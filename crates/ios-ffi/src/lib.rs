//! C FFI shim for [`tg_ws_proxy_rs`], used by the iOS app.
//!
//! Mirrors `crates/android-jni`: parse the same CLI string the binary accepts,
//! run [`tg_ws_proxy_rs::server`] on a background Tokio runtime, and push log
//! lines plus the `tg://` link back to the host app through plain C callbacks.
//! Start/stop is cooperative: completing the watch channel breaks the accept
//! loop the same way Ctrl+C would.

use std::ffi::{CStr, CString, c_char, c_void};
use std::io::{self, Write};
use std::ptr;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use tokio::sync::watch;
use tracing_subscriber::layer::SubscriberExt as _;
use tracing_subscriber::util::SubscriberInitExt as _;
use tracing_subscriber::{EnvFilter, Registry, fmt::MakeWriter, reload};

use tg_ws_proxy_rs::config::Config;
use tg_ws_proxy_rs::server;

pub type StrCallback = Option<unsafe extern "C" fn(*const c_char, *mut c_void)>;
pub type VoidCallback = Option<unsafe extern "C" fn(*mut c_void)>;

#[derive(Clone, Copy)]
struct Callbacks {
    on_log: StrCallback,
    on_error: StrCallback,
    on_listening: StrCallback,
    on_stopped: VoidCallback,
    user: *mut c_void,
}

// The raw `user` pointer is opaque to us and only ever handed back to the
// callbacks the host registered together with it.
unsafe impl Send for Callbacks {}

static CALLBACKS: Mutex<Option<Callbacks>> = Mutex::new(None);

/// Reload handle for the `EnvFilter`: a global subscriber can only be installed
/// once per process, so every Start after the first swaps the filter instead.
static LOG_FILTER: OnceLock<reload::Handle<EnvFilter, Registry>> = OnceLock::new();

struct ProxyState {
    shutdown: Option<watch::Sender<bool>>,
    thread: Option<std::thread::JoinHandle<()>>,
    /// Set by `tgws_stop`, cleared by the next start. `tgws_is_running` must
    /// report false the moment Stop is pressed, while `start_proxy` keeps
    /// refusing until the old runtime has actually finished winding down.
    stopping: bool,
}

static STATE: Mutex<ProxyState> = Mutex::new(ProxyState {
    shutdown: None,
    thread: None,
    stopping: false,
});

// ---------------------------------------------------------------------------
// C API
// ---------------------------------------------------------------------------

/// Register the callbacks. Call once before `tgws_start`. All callbacks may be
/// invoked from arbitrary background threads, so the host must hop to its own
/// main thread/queue before touching UI state.
#[unsafe(no_mangle)]
pub extern "C" fn tgws_set_callbacks(
    on_log: StrCallback,
    on_error: StrCallback,
    on_listening: StrCallback,
    on_stopped: VoidCallback,
    user: *mut c_void,
) {
    if let Ok(mut guard) = CALLBACKS.lock() {
        *guard = Some(Callbacks {
            on_log,
            on_error,
            on_listening,
            on_stopped,
            user,
        });
    }
}

/// Start the proxy with a CLI-style argument string (e.g. `--port 1443 --quiet`).
/// Returns NULL on success, or a heap-allocated error message that the caller
/// must release with `tgws_free_string`.
///
/// # Safety
/// `args` must be NULL or a valid NUL-terminated C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tgws_start(args: *const c_char) -> *mut c_char {
    let args = if args.is_null() {
        String::new()
    } else {
        // SAFETY: documented precondition above.
        match unsafe { CStr::from_ptr(args) }.to_str() {
            Ok(s) => s.to_owned(),
            Err(e) => return into_c_string(format!("invalid arguments: {e}")),
        }
    };
    match start_proxy(&args) {
        Ok(()) => ptr::null_mut(),
        Err(e) => into_c_string(e),
    }
}

/// Ask the proxy to stop. Returns immediately; `on_stopped` fires once the
/// worker has wound down.
#[unsafe(no_mangle)]
pub extern "C" fn tgws_stop() {
    stop_proxy();
}

#[unsafe(no_mangle)]
pub extern "C" fn tgws_is_running() -> bool {
    match STATE.lock() {
        Ok(state) => !state.stopping && state.thread.as_ref().is_some_and(|t| !t.is_finished()),
        Err(_) => false,
    }
}

/// Release a string returned by `tgws_start`.
///
/// # Safety
/// `s` must be NULL or a pointer previously returned by `tgws_start`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tgws_free_string(s: *mut c_char) {
    if !s.is_null() {
        // SAFETY: documented precondition above.
        drop(unsafe { CString::from_raw(s) });
    }
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

fn into_c_string(s: String) -> *mut c_char {
    CString::new(s.replace('\0', ""))
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

fn callbacks() -> Option<Callbacks> {
    CALLBACKS.lock().ok().and_then(|guard| *guard)
}

fn call_str(pick: impl Fn(&Callbacks) -> StrCallback, text: &str) {
    let Some(cbs) = callbacks() else { return };
    let Some(cb) = pick(&cbs) else { return };
    let Ok(c) = CString::new(text.replace('\0', "")) else {
        return;
    };
    // SAFETY: the host registered this function pointer together with `user`,
    // and `c` outlives the call.
    unsafe { cb(c.as_ptr(), cbs.user) };
}

fn emit_log(line: &str) {
    call_str(|c| c.on_log, line);
}

fn emit_error(line: &str) {
    eprintln!("{line}");
    call_str(|c| c.on_error, line);
}

fn emit_listening(link: &str) {
    call_str(|c| c.on_listening, link);
}

fn emit_stopped() {
    let Some(cbs) = callbacks() else { return };
    if let Some(cb) = cbs.on_stopped {
        // SAFETY: see `call_str`.
        unsafe { cb(cbs.user) };
    }
}

fn start_proxy(args: &str) -> Result<(), String> {
    let mut state = STATE
        .lock()
        .map_err(|_| "proxy state lock poisoned".to_string())?;
    // Reap a worker that already exited (a `--check` run, a startup failure, or
    // a Stop whose runtime has finished winding down).
    if state.thread.as_ref().is_some_and(|t| t.is_finished()) {
        state.thread = None;
        state.stopping = false;
    }
    if state.thread.is_some() {
        return Err(if state.stopping {
            "proxy is still stopping, try again in a moment".into()
        } else {
            "proxy is already running".into()
        });
    }

    let config = Config::try_from_cli_line(args)?;
    install_logging(&config);
    server::install_crypto_provider();

    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    let thread = std::thread::Builder::new()
        .name("tg-ws-proxy".into())
        .spawn(move || {
            let rt = match tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                // Two workers are plenty for an accept loop on a phone.
                .worker_threads(2)
                .thread_name("tg-ws-worker")
                .build()
            {
                Ok(rt) => rt,
                Err(e) => {
                    emit_error(&format!("failed to start runtime: {e}"));
                    return;
                }
            };

            let result = rt.block_on(async move {
                let shutdown = async move {
                    let mut rx = shutdown_rx;
                    loop {
                        if *rx.borrow() {
                            break;
                        }
                        if rx.changed().await.is_err() {
                            break;
                        }
                    }
                };
                server::run_with_listen(config, shutdown, |info| {
                    emit_listening(&info.tg_link);
                })
                .await
            });

            // Wind down first, report second: a reported stop has to mean
            // "startable again".
            rt.shutdown_timeout(Duration::from_secs(2));

            match result {
                Ok(()) => emit_stopped(),
                Err(e) => emit_error(&format!("proxy failed: {e}")),
            }
        })
        .map_err(|e| format!("failed to spawn proxy thread: {e}"))?;

    state.shutdown = Some(shutdown_tx);
    state.thread = Some(thread);
    state.stopping = false;
    Ok(())
}

fn stop_proxy() {
    let mut state = match STATE.lock() {
        Ok(s) => s,
        Err(_) => return,
    };
    if let Some(tx) = state.shutdown.take() {
        let _ = tx.send(true);
    }
    // Deliberately no `join()`: this is called from the UI thread.
    state.stopping = true;
}

fn install_logging(config: &Config) {
    let log_level = if config.quiet {
        "off"
    } else if config.verbose {
        "debug"
    } else {
        "info"
    };

    let env_filter =
        tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| log_level.into());

    if let Some(handle) = LOG_FILTER.get() {
        let _ = handle.reload(env_filter);
        return;
    }

    let (filter, handle) = reload::Layer::new(env_filter);
    let installed = Registry::default()
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_ansi(false)
                .with_target(false)
                .with_writer(IosMakeWriter),
        )
        .try_init()
        .is_ok();
    if installed {
        let _ = LOG_FILTER.set(handle);
    }
}

struct IosMakeWriter;

impl<'a> MakeWriter<'a> for IosMakeWriter {
    type Writer = IosWriter;

    fn make_writer(&'a self) -> Self::Writer {
        IosWriter { buf: Vec::new() }
    }
}

struct IosWriter {
    buf: Vec<u8>,
}

impl Write for IosWriter {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        self.buf.extend_from_slice(data);
        drain_lines(&mut self.buf);
        Ok(data.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        if !self.buf.is_empty() {
            let line = String::from_utf8_lossy(&self.buf).into_owned();
            self.buf.clear();
            forward_line(&line);
        }
        Ok(())
    }
}

impl Drop for IosWriter {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

fn drain_lines(buf: &mut Vec<u8>) {
    while let Some(pos) = buf.iter().position(|&b| b == b'\n') {
        let mut line: Vec<u8> = buf.drain(..=pos).collect();
        line.pop();
        if line.last() == Some(&b'\r') {
            line.pop();
        }
        if !line.is_empty() {
            forward_line(&String::from_utf8_lossy(&line));
        }
    }
}

fn forward_line(line: &str) {
    // Visible in the Xcode console / Console.app, plus the in-app log panel.
    eprintln!("{line}");
    emit_log(line);
}

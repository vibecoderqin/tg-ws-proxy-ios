#!/usr/bin/env bash
# Build the Rust core and C FFI shim for physical iOS devices.
set -euo pipefail
cd "$(dirname "$0")/.."

export IPHONEOS_DEPLOYMENT_TARGET=15.0
rustup target add aarch64-apple-ios
cargo build --release -p tg-ws-proxy-ios --target aarch64-apple-ios

mkdir -p ios/Libs
cp target/aarch64-apple-ios/release/libtg_ws_proxy_ios.a ios/Libs/
echo "OK: ios/Libs/libtg_ws_proxy_ios.a"

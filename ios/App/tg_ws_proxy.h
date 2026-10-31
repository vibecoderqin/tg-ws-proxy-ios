#ifndef TG_WS_PROXY_H
#define TG_WS_PROXY_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*tgws_str_cb)(const char *text, void *user);
typedef void (*tgws_void_cb)(void *user);

void tgws_set_callbacks(tgws_str_cb on_log,
                        tgws_str_cb on_error,
                        tgws_str_cb on_listening,
                        tgws_void_cb on_stopped,
                        void *user);

char *tgws_start(const char *args);
void tgws_stop(void);
bool tgws_is_running(void);
void tgws_free_string(char *s);

#ifdef __cplusplus
}
#endif

#endif

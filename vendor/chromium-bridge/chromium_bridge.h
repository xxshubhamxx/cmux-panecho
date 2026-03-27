// Chromium bridge: raw content API with CALayerHost rendering.
//
// Runs Chromium's browser process out-of-process. The GPU compositor
// renders to a CAContext whose ID is sent to our app. We create a
// CALayerHost with that ID for zero-copy compositing.
//
// Input events translated from NSEvent in Swift and forwarded via
// content::RenderWidgetHost::Forward*Event.
#ifndef CHROMIUM_BRIDGE_H
#define CHROMIUM_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

#define CHROMIUM_OK             0
#define CHROMIUM_ERR_NOT_INIT  -1
#define CHROMIUM_ERR_INVALID   -2
#define CHROMIUM_ERR_FAILED    -3

typedef void* chromium_browser_t;

// -------------------------------------------------------------------
// Callbacks
// -------------------------------------------------------------------

/// Called when the compositor provides a new CAContext ID for rendering.
/// Create a CALayerHost with this ID to display the web content.
typedef void (*chromium_ca_context_callback)(
    chromium_browser_t browser,
    uint32_t ca_context_id,
    void* user_data
);

/// Title changed.
typedef void (*chromium_title_callback)(
    chromium_browser_t browser,
    const char* title,
    void* user_data
);

/// URL changed.
typedef void (*chromium_url_callback)(
    chromium_browser_t browser,
    const char* url,
    void* user_data
);

/// Loading state changed.
typedef void (*chromium_loading_state_callback)(
    chromium_browser_t browser,
    bool is_loading,
    bool can_go_back,
    bool can_go_forward,
    void* user_data
);

typedef struct {
    chromium_ca_context_callback   on_ca_context;
    chromium_title_callback        on_title_change;
    chromium_url_callback          on_url_change;
    chromium_loading_state_callback on_loading_state_change;
    void*                          user_data;
} chromium_client_callbacks;

// -------------------------------------------------------------------
// Lifecycle
// -------------------------------------------------------------------

/// Initialize the Chromium browser process.
/// `chromium_framework_path` is the path to the built content_shell framework.
/// `helper_path` is the path to the helper subprocess executable.
int chromium_initialize(
    const char* chromium_framework_path,
    const char* helper_path,
    const char* cache_root
);

/// Pump the browser message loop. Call from main thread at 60fps.
void chromium_do_message_loop_work(void);

/// Shut down Chromium.
void chromium_shutdown(void);

bool chromium_is_initialized(void);

// -------------------------------------------------------------------
// Browser
// -------------------------------------------------------------------

/// Create a new browser (web contents).
/// The compositor will call on_ca_context with the CAContext ID for rendering.
chromium_browser_t chromium_browser_create(
    const char* initial_url,
    int width, int height,
    const chromium_client_callbacks* callbacks
);

void chromium_browser_destroy(chromium_browser_t browser);

// Navigation
int chromium_browser_load_url(chromium_browser_t browser, const char* url);
int chromium_browser_go_back(chromium_browser_t browser);
int chromium_browser_go_forward(chromium_browser_t browser);
int chromium_browser_reload(chromium_browser_t browser);
int chromium_browser_stop(chromium_browser_t browser);

// Resize
void chromium_browser_resize(chromium_browser_t browser, int width, int height);

// Visibility
void chromium_browser_set_visible(chromium_browser_t browser, bool visible);

// -------------------------------------------------------------------
// Input forwarding (NSEvent → Chromium WebInputEvent)
// -------------------------------------------------------------------

void chromium_browser_send_mouse_click(
    chromium_browser_t browser,
    int x, int y,
    int button,      // 0=left, 1=middle, 2=right
    bool mouse_up,
    int click_count,
    uint32_t modifiers
);

void chromium_browser_send_mouse_move(
    chromium_browser_t browser,
    int x, int y,
    uint32_t modifiers
);

void chromium_browser_send_mouse_wheel(
    chromium_browser_t browser,
    int x, int y,
    float delta_x, float delta_y,
    uint32_t modifiers
);

void chromium_browser_send_key_event(
    chromium_browser_t browser,
    int type,              // 0=RawKeyDown, 1=KeyUp, 2=Char
    int windows_key_code,
    int native_key_code,
    uint32_t modifiers,
    uint16_t character
);

// -------------------------------------------------------------------
// Utility
// -------------------------------------------------------------------

const char* chromium_get_version(void);

#ifdef __cplusplus
}
#endif
#endif // CHROMIUM_BRIDGE_H

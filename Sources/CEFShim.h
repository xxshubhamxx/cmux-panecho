#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef __cplusplus
typedef uint_least16_t char16_t;
#endif

typedef struct _cef_string_t {
    char16_t *str;
    size_t length;
    void (*dtor)(char16_t *str);
} cef_string_t;

typedef cef_string_t *cef_string_userfree_t;

typedef struct _cef_basetime_t {
    int64_t val;
} cef_basetime_t;

typedef struct _cef_base_ref_counted_t {
    size_t size;
    void (*add_ref)(struct _cef_base_ref_counted_t *self);
    int (*release)(struct _cef_base_ref_counted_t *self);
    int (*has_one_ref)(struct _cef_base_ref_counted_t *self);
    int (*has_at_least_one_ref)(struct _cef_base_ref_counted_t *self);
} cef_base_ref_counted_t;

typedef struct _cef_main_args_t {
    int argc;
    char **argv;
} cef_main_args_t;

typedef uint32_t cef_color_t;
typedef void *cef_cursor_handle_t;

typedef void *cef_window_handle_t;

typedef struct _cef_point_t {
    int x;
    int y;
} cef_point_t;

typedef struct _cef_rect_t {
    int x;
    int y;
    int width;
    int height;
} cef_rect_t;

typedef struct _cef_size_t {
    int width;
    int height;
} cef_size_t;

typedef enum {
    CT_POINTER,
    CT_CROSS,
    CT_HAND,
    CT_IBEAM,
    CT_WAIT,
    CT_HELP,
    CT_EASTRESIZE,
    CT_NORTHRESIZE,
    CT_NORTHEASTRESIZE,
    CT_NORTHWESTRESIZE,
    CT_SOUTHRESIZE,
    CT_SOUTHEASTRESIZE,
    CT_SOUTHWESTRESIZE,
    CT_WESTRESIZE,
    CT_NORTHSOUTHRESIZE,
    CT_EASTWESTRESIZE,
    CT_NORTHEASTSOUTHWESTRESIZE,
    CT_NORTHWESTSOUTHEASTRESIZE,
    CT_COLUMNRESIZE,
    CT_ROWRESIZE,
    CT_MIDDLEPANNING,
    CT_EASTPANNING,
    CT_NORTHPANNING,
    CT_NORTHEASTPANNING,
    CT_NORTHWESTPANNING,
    CT_SOUTHPANNING,
    CT_SOUTHEASTPANNING,
    CT_SOUTHWESTPANNING,
    CT_WESTPANNING,
    CT_MOVE,
    CT_VERTICALTEXT,
    CT_CELL,
    CT_CONTEXTMENU,
    CT_ALIAS,
    CT_PROGRESS,
    CT_NODROP,
    CT_COPY,
    CT_NONE,
    CT_NOTALLOWED,
    CT_ZOOMIN,
    CT_ZOOMOUT,
    CT_GRAB,
    CT_GRABBING,
    CT_MIDDLE_PANNING_VERTICAL,
    CT_MIDDLE_PANNING_HORIZONTAL,
    CT_CUSTOM,
    CT_DND_NONE,
    CT_DND_MOVE,
    CT_DND_COPY,
    CT_DND_LINK,
    CT_NUM_VALUES,
} cef_cursor_type_t;

typedef struct _cef_cursor_info_t {
    cef_point_t hotspot;
    float image_scale_factor;
    void *buffer;
    cef_size_t size;
} cef_cursor_info_t;

typedef struct _cef_window_info_t {
    size_t size;
    cef_string_t window_name;
    cef_rect_t bounds;
    int hidden;
    cef_window_handle_t parent_view;
    int windowless_rendering_enabled;
    int shared_texture_enabled;
    int external_begin_frame_enabled;
    cef_window_handle_t view;
    int runtime_style;
} cef_window_info_t;

typedef struct _cef_request_context_settings_t {
    size_t size;
    cef_string_t cache_path;
    int persist_session_cookies;
    cef_string_t accept_language_list;
    cef_string_t cookieable_schemes_list;
    int cookieable_schemes_exclude_defaults;
} cef_request_context_settings_t;

typedef enum {
    CEF_COOKIE_PRIORITY_LOW = -1,
    CEF_COOKIE_PRIORITY_MEDIUM = 0,
    CEF_COOKIE_PRIORITY_HIGH = 1,
} cef_cookie_priority_t;

typedef enum {
    CEF_COOKIE_SAME_SITE_UNSPECIFIED,
    CEF_COOKIE_SAME_SITE_NO_RESTRICTION,
    CEF_COOKIE_SAME_SITE_LAX_MODE,
    CEF_COOKIE_SAME_SITE_STRICT_MODE,
    CEF_COOKIE_SAME_SITE_NUM_VALUES,
} cef_cookie_same_site_t;

typedef struct _cef_cookie_t {
    size_t size;
    cef_string_t name;
    cef_string_t value;
    cef_string_t domain;
    cef_string_t path;
    int secure;
    int httponly;
    cef_basetime_t creation;
    cef_basetime_t last_access;
    int has_expires;
    cef_basetime_t expires;
    cef_cookie_same_site_t same_site;
    cef_cookie_priority_t priority;
} cef_cookie_t;

typedef struct _cef_browser_settings_t {
    size_t size;
    int windowless_frame_rate;
    cef_string_t standard_font_family;
    cef_string_t fixed_font_family;
    cef_string_t serif_font_family;
    cef_string_t sans_serif_font_family;
    cef_string_t cursive_font_family;
    cef_string_t fantasy_font_family;
    int default_font_size;
    int default_fixed_font_size;
    int minimum_font_size;
    int minimum_logical_font_size;
    cef_string_t default_encoding;
    int remote_fonts;
    int javascript;
    int javascript_close_windows;
    int javascript_access_clipboard;
    int javascript_dom_paste;
    int image_loading;
    int image_shrink_standalone_to_fit;
    int text_area_resize;
    int tab_to_links;
    int local_storage;
    int databases_deprecated;
    int webgl;
    cef_color_t background_color;
    int chrome_status_bubble;
    int chrome_zoom_bubble;
} cef_browser_settings_t;

typedef struct _cef_value_t cef_value_t;
typedef struct _cef_dictionary_value_t cef_dictionary_value_t;
typedef struct _cef_request_context_t cef_request_context_t;
typedef struct _cef_request_context_handler_t cef_request_context_handler_t;
typedef struct _cef_browser_t cef_browser_t;
typedef struct _cef_browser_host_t cef_browser_host_t;
typedef struct _cef_frame_t cef_frame_t;
typedef struct _cef_client_t cef_client_t;
typedef struct _cef_browser_process_handler_t cef_browser_process_handler_t;
typedef struct _cef_app_t cef_app_t;
typedef struct _cef_display_handler_t cef_display_handler_t;
typedef struct _cef_load_handler_t cef_load_handler_t;
typedef struct _cef_life_span_handler_t cef_life_span_handler_t;
typedef struct _cef_find_handler_t cef_find_handler_t;
typedef struct _cef_completion_callback_t cef_completion_callback_t;
typedef struct _cef_cookie_visitor_t cef_cookie_visitor_t;
typedef struct _cef_set_cookie_callback_t cef_set_cookie_callback_t;
typedef struct _cef_delete_cookies_callback_t cef_delete_cookies_callback_t;
typedef struct _cef_cookie_manager_t cef_cookie_manager_t;
typedef struct _cef_dialog_handler_t cef_dialog_handler_t;
typedef struct _cef_file_dialog_callback_t cef_file_dialog_callback_t;
typedef struct _cef_jsdialog_callback_t cef_jsdialog_callback_t;
typedef struct _cef_jsdialog_handler_t cef_jsdialog_handler_t;
typedef struct _cef_download_handler_t cef_download_handler_t;
typedef struct _cef_before_download_callback_t cef_before_download_callback_t;
typedef struct _cef_download_item_callback_t cef_download_item_callback_t;
typedef struct _cef_download_item_t cef_download_item_t;
typedef struct _cef_request_t cef_request_t;
typedef struct _cef_resource_request_handler_t cef_resource_request_handler_t;
typedef struct _cef_request_handler_t cef_request_handler_t;
typedef struct _cef_callback_t cef_callback_t;
typedef struct _cef_auth_callback_t cef_auth_callback_t;
typedef struct _cef_sslinfo_t cef_sslinfo_t;
typedef struct _cef_x509_certificate_t cef_x509_certificate_t;
typedef struct _cef_select_client_certificate_callback_t cef_select_client_certificate_callback_t;
typedef struct _cef_unresponsive_process_callback_t cef_unresponsive_process_callback_t;
typedef struct _cef_preference_observer_t cef_preference_observer_t;
typedef struct _cef_registration_t cef_registration_t;
typedef struct _cef_string_list_t *cef_string_list_t;

typedef enum {
    LOGSEVERITY_DEFAULT = 0,
    LOGSEVERITY_VERBOSE,
    LOGSEVERITY_DEBUG = LOGSEVERITY_VERBOSE,
    LOGSEVERITY_INFO,
    LOGSEVERITY_WARNING,
    LOGSEVERITY_ERROR,
    LOGSEVERITY_FATAL,
    LOGSEVERITY_DISABLE = 99
} cef_log_severity_t;

typedef enum {
    LOG_ITEMS_DEFAULT = 0,
    LOG_ITEMS_NONE = 1,
    LOG_ITEMS_FLAG_PROCESS_ID = 1 << 1,
    LOG_ITEMS_FLAG_THREAD_ID = 1 << 2,
    LOG_ITEMS_FLAG_TIME_STAMP = 1 << 3,
    LOG_ITEMS_FLAG_TICK_COUNT = 1 << 4,
} cef_log_items_t;

typedef struct _cef_settings_t {
    size_t size;
    int no_sandbox;
    cef_string_t browser_subprocess_path;
    cef_string_t framework_dir_path;
    cef_string_t main_bundle_path;
    int multi_threaded_message_loop;
    int external_message_pump;
    int windowless_rendering_enabled;
    int command_line_args_disabled;
    cef_string_t cache_path;
    cef_string_t root_cache_path;
    int persist_session_cookies;
    cef_string_t user_agent;
    cef_string_t user_agent_product;
    cef_string_t locale;
    cef_string_t log_file;
    cef_log_severity_t log_severity;
    cef_log_items_t log_items;
    cef_string_t javascript_flags;
    cef_string_t resources_dir_path;
    cef_string_t locales_dir_path;
    int remote_debugging_port;
    int uncaught_exception_stack_size;
    cef_color_t background_color;
    cef_string_t accept_language_list;
    cef_string_t cookieable_schemes_list;
    int cookieable_schemes_exclude_defaults;
    cef_string_t chrome_policy_id;
    int chrome_app_icon_id;
    int disable_signal_handlers;
    int use_views_default_popup;
} cef_settings_t;

typedef enum {
    CEF_ERR_NONE = 0,
    CEF_ERR_ABORTED = -3,
} cef_errorcode_t;

typedef enum {
    TS_ABNORMAL_TERMINATION,
    TS_PROCESS_WAS_KILLED,
    TS_PROCESS_CRASHED,
    TS_PROCESS_OOM,
    TS_LAUNCH_FAILED,
    TS_INTEGRITY_FAILURE,
} cef_termination_status_t;

typedef enum {
    JSDIALOGTYPE_ALERT,
    JSDIALOGTYPE_CONFIRM,
    JSDIALOGTYPE_PROMPT,
    JSDIALOGTYPE_NUM_VALUES,
} cef_jsdialog_type_t;

typedef enum {
    FILE_DIALOG_OPEN,
    FILE_DIALOG_OPEN_MULTIPLE,
    FILE_DIALOG_OPEN_FOLDER,
    FILE_DIALOG_SAVE,
    FILE_DIALOG_NUM_VALUES,
} cef_file_dialog_mode_t;

struct _cef_value_t {
    cef_base_ref_counted_t base;
    int (*is_valid)(cef_value_t *self);
    int (*is_owned)(cef_value_t *self);
    int (*is_read_only)(cef_value_t *self);
    int (*is_same)(cef_value_t *self, cef_value_t *that);
    int (*is_equal)(cef_value_t *self, cef_value_t *that);
    cef_value_t *(*copy)(cef_value_t *self);
    int (*get_type)(cef_value_t *self);
    int (*get_bool)(cef_value_t *self);
    int (*get_int)(cef_value_t *self);
    double (*get_double)(cef_value_t *self);
    cef_string_userfree_t (*get_string)(cef_value_t *self);
    void *(*get_binary)(cef_value_t *self);
    cef_dictionary_value_t *(*get_dictionary)(cef_value_t *self);
    void *(*get_list)(cef_value_t *self);
    int (*set_null)(cef_value_t *self);
    int (*set_bool)(cef_value_t *self, int value);
    int (*set_int)(cef_value_t *self, int value);
    int (*set_double)(cef_value_t *self, double value);
    int (*set_string)(cef_value_t *self, const cef_string_t *value);
    int (*set_binary)(cef_value_t *self, void *value);
    int (*set_dictionary)(cef_value_t *self, cef_dictionary_value_t *value);
    int (*set_list)(cef_value_t *self, void *value);
};

struct _cef_dictionary_value_t {
    cef_base_ref_counted_t base;
    int (*is_valid)(cef_dictionary_value_t *self);
    int (*is_owned)(cef_dictionary_value_t *self);
    int (*is_read_only)(cef_dictionary_value_t *self);
    int (*is_same)(cef_dictionary_value_t *self, cef_dictionary_value_t *that);
    int (*is_equal)(cef_dictionary_value_t *self, cef_dictionary_value_t *that);
    cef_dictionary_value_t *(*copy)(cef_dictionary_value_t *self, int excludeEmptyChildren);
    size_t (*get_size)(cef_dictionary_value_t *self);
    int (*clear)(cef_dictionary_value_t *self);
    int (*has_key)(cef_dictionary_value_t *self, const cef_string_t *key);
    int (*get_keys)(cef_dictionary_value_t *self, void *keys);
    int (*remove)(cef_dictionary_value_t *self, const cef_string_t *key);
    int (*get_type)(cef_dictionary_value_t *self, const cef_string_t *key);
    cef_value_t *(*get_value)(cef_dictionary_value_t *self, const cef_string_t *key);
    int (*get_bool)(cef_dictionary_value_t *self, const cef_string_t *key);
    int (*get_int)(cef_dictionary_value_t *self, const cef_string_t *key);
    double (*get_double)(cef_dictionary_value_t *self, const cef_string_t *key);
    cef_string_userfree_t (*get_string)(cef_dictionary_value_t *self, const cef_string_t *key);
    void *(*get_binary)(cef_dictionary_value_t *self, const cef_string_t *key);
    cef_dictionary_value_t *(*get_dictionary)(cef_dictionary_value_t *self, const cef_string_t *key);
    void *(*get_list)(cef_dictionary_value_t *self, const cef_string_t *key);
    int (*set_value)(cef_dictionary_value_t *self, const cef_string_t *key, cef_value_t *value);
    int (*set_null)(cef_dictionary_value_t *self, const cef_string_t *key);
    int (*set_bool)(cef_dictionary_value_t *self, const cef_string_t *key, int value);
    int (*set_int)(cef_dictionary_value_t *self, const cef_string_t *key, int value);
    int (*set_double)(cef_dictionary_value_t *self, const cef_string_t *key, double value);
    int (*set_string)(cef_dictionary_value_t *self, const cef_string_t *key, const cef_string_t *value);
    int (*set_binary)(cef_dictionary_value_t *self, const cef_string_t *key, void *value);
    int (*set_dictionary)(cef_dictionary_value_t *self, const cef_string_t *key, cef_dictionary_value_t *value);
    int (*set_list)(cef_dictionary_value_t *self, const cef_string_t *key, void *value);
};

typedef struct _cef_preference_manager_t {
    cef_base_ref_counted_t base;
    int (*has_preference)(struct _cef_preference_manager_t *self, const cef_string_t *name);
    cef_value_t *(*get_preference)(struct _cef_preference_manager_t *self, const cef_string_t *name);
    cef_dictionary_value_t *(*get_all_preferences)(struct _cef_preference_manager_t *self, int includeDefaults);
    int (*can_set_preference)(struct _cef_preference_manager_t *self, const cef_string_t *name);
    int (*set_preference)(struct _cef_preference_manager_t *self, const cef_string_t *name, cef_value_t *value, cef_string_t *error);
    cef_registration_t *(*add_preference_observer)(
        struct _cef_preference_manager_t *self,
        const cef_string_t *name,
        cef_preference_observer_t *observer
    );
} cef_preference_manager_t;

struct _cef_request_context_handler_t {
    cef_base_ref_counted_t base;
    void (*on_request_context_initialized)(cef_request_context_handler_t *self, cef_request_context_t *request_context);
    cef_resource_request_handler_t *(*get_resource_request_handler)(
        cef_request_context_handler_t *self,
        cef_browser_t *browser,
        cef_frame_t *frame,
        cef_request_t *request,
        int is_navigation,
        int is_download,
        const cef_string_t *request_initiator,
        int *disable_default_handling
    );
};

struct _cef_request_context_t {
    cef_preference_manager_t base;
    int (*is_same)(cef_request_context_t *self, cef_request_context_t *other);
    int (*is_sharing_with)(cef_request_context_t *self, cef_request_context_t *other);
    int (*is_global)(cef_request_context_t *self);
    cef_request_context_handler_t *(*get_handler)(cef_request_context_t *self);
    cef_string_userfree_t (*get_cache_path)(cef_request_context_t *self);
    cef_cookie_manager_t *(*get_cookie_manager)(cef_request_context_t *self, cef_completion_callback_t *callback);
};

struct _cef_cookie_manager_t {
    cef_base_ref_counted_t base;
    int (*visit_all_cookies)(cef_cookie_manager_t *self, cef_cookie_visitor_t *visitor);
    int (*visit_url_cookies)(cef_cookie_manager_t *self, const cef_string_t *url, int includeHttpOnly, cef_cookie_visitor_t *visitor);
    int (*set_cookie)(cef_cookie_manager_t *self, const cef_string_t *url, const cef_cookie_t *cookie, cef_set_cookie_callback_t *callback);
    int (*delete_cookies)(cef_cookie_manager_t *self, const cef_string_t *url, const cef_string_t *cookie_name, cef_delete_cookies_callback_t *callback);
    int (*flush_store)(cef_cookie_manager_t *self, cef_completion_callback_t *callback);
};

struct _cef_completion_callback_t {
    cef_base_ref_counted_t base;
    void (*on_complete)(cef_completion_callback_t *self);
};

struct _cef_cookie_visitor_t {
    cef_base_ref_counted_t base;
    int (*visit)(cef_cookie_visitor_t *self, const cef_cookie_t *cookie, int count, int total, int *deleteCookie);
};

struct _cef_set_cookie_callback_t {
    cef_base_ref_counted_t base;
    void (*on_complete)(cef_set_cookie_callback_t *self, int success);
};

struct _cef_delete_cookies_callback_t {
    cef_base_ref_counted_t base;
    void (*on_complete)(cef_delete_cookies_callback_t *self, int num_deleted);
};

struct _cef_file_dialog_callback_t {
    cef_base_ref_counted_t base;
    void (*cont)(cef_file_dialog_callback_t *self, cef_string_list_t file_paths);
    void (*cancel)(cef_file_dialog_callback_t *self);
};

struct _cef_jsdialog_callback_t {
    cef_base_ref_counted_t base;
    void (*cont)(cef_jsdialog_callback_t *self, int success, const cef_string_t *user_input);
};

struct _cef_frame_t {
    cef_base_ref_counted_t base;
    int (*is_valid)(cef_frame_t *self);
    void (*undo)(cef_frame_t *self);
    void (*redo)(cef_frame_t *self);
    void (*cut)(cef_frame_t *self);
    void (*copy)(cef_frame_t *self);
    void (*paste)(cef_frame_t *self);
    void (*paste_and_match_style)(cef_frame_t *self);
    void (*del)(cef_frame_t *self);
    void (*select_all)(cef_frame_t *self);
    void (*view_source)(cef_frame_t *self);
    void (*get_source)(cef_frame_t *self, void *visitor);
    void (*get_text)(cef_frame_t *self, void *visitor);
    void (*load_request)(cef_frame_t *self, void *request);
    void (*load_url)(cef_frame_t *self, const cef_string_t *url);
    void (*execute_java_script)(cef_frame_t *self, const cef_string_t *code, const cef_string_t *scriptURL, int startLine);
    int (*is_main)(cef_frame_t *self);
    int (*is_focused)(cef_frame_t *self);
    cef_string_userfree_t (*get_name)(cef_frame_t *self);
    cef_string_userfree_t (*get_identifier)(cef_frame_t *self);
    cef_frame_t *(*get_parent)(cef_frame_t *self);
    cef_string_userfree_t (*get_url)(cef_frame_t *self);
    cef_browser_t *(*get_browser)(cef_frame_t *self);
};

struct _cef_browser_t {
    cef_base_ref_counted_t base;
    int (*is_valid)(cef_browser_t *self);
    cef_browser_host_t *(*get_host)(cef_browser_t *self);
    int (*can_go_back)(cef_browser_t *self);
    void (*go_back)(cef_browser_t *self);
    int (*can_go_forward)(cef_browser_t *self);
    void (*go_forward)(cef_browser_t *self);
    int (*is_loading)(cef_browser_t *self);
    void (*reload)(cef_browser_t *self);
    void (*reload_ignore_cache)(cef_browser_t *self);
    void (*stop_load)(cef_browser_t *self);
    int (*get_identifier)(cef_browser_t *self);
    int (*is_same)(cef_browser_t *self, cef_browser_t *that);
    int (*is_popup)(cef_browser_t *self);
    int (*has_document)(cef_browser_t *self);
    cef_frame_t *(*get_main_frame)(cef_browser_t *self);
    cef_frame_t *(*get_focused_frame)(cef_browser_t *self);
};

struct _cef_browser_host_t {
    cef_base_ref_counted_t base;
    cef_browser_t *(*get_browser)(cef_browser_host_t *self);
    void (*close_browser)(cef_browser_host_t *self, int forceClose);
    int (*try_close_browser)(cef_browser_host_t *self);
    int (*is_ready_to_be_closed)(cef_browser_host_t *self);
    void (*set_focus)(cef_browser_host_t *self, int focus);
    cef_window_handle_t (*get_window_handle)(cef_browser_host_t *self);
    cef_window_handle_t (*get_opener_window_handle)(cef_browser_host_t *self);
    int (*get_opener_identifier)(cef_browser_host_t *self);
    int (*has_view)(cef_browser_host_t *self);
    cef_client_t *(*get_client)(cef_browser_host_t *self);
    cef_request_context_t *(*get_request_context)(cef_browser_host_t *self);
    int (*can_zoom)(cef_browser_host_t *self, int command);
    void (*zoom)(cef_browser_host_t *self, int command);
    double (*get_default_zoom_level)(cef_browser_host_t *self);
    double (*get_zoom_level)(cef_browser_host_t *self);
    void (*set_zoom_level)(cef_browser_host_t *self, double zoomLevel);
    void (*run_file_dialog)(cef_browser_host_t *self, int mode, const cef_string_t *title, const cef_string_t *defaultFilePath, void *acceptFilters, void *callback);
    void (*start_download)(cef_browser_host_t *self, const cef_string_t *url);
    void (*download_image)(cef_browser_host_t *self, const cef_string_t *imageURL, int isFavicon, uint32_t maxImageSize, int bypassCache, void *callback);
    void (*print)(cef_browser_host_t *self);
    void (*print_to_pdf)(cef_browser_host_t *self, const cef_string_t *path, void *settings, void *callback);
    void (*find)(cef_browser_host_t *self, int identifier, const cef_string_t *searchText, int forward, int matchCase, int findNext);
    void (*stop_finding)(cef_browser_host_t *self, int clearSelection);
    void (*show_dev_tools)(cef_browser_host_t *self, const cef_window_info_t *windowInfo, cef_client_t *client, const cef_browser_settings_t *settings, const void *inspectElementAt);
    void (*close_dev_tools)(cef_browser_host_t *self);
    int (*has_dev_tools)(cef_browser_host_t *self);
    void (*send_dev_tools_message)(cef_browser_host_t *self, const void *message, size_t messageSize);
    void (*execute_dev_tools_method)(cef_browser_host_t *self, int messageId, const cef_string_t *method, cef_dictionary_value_t *params);
    int (*add_dev_tools_message_observer)(cef_browser_host_t *self, void *observer);
    int (*get_navigation_entries)(cef_browser_host_t *self, void *visitor, int currentOnly);
    void (*replace_misspelling)(cef_browser_host_t *self, const cef_string_t *word);
    void (*add_word_to_dictionary)(cef_browser_host_t *self, const cef_string_t *word);
    int (*is_window_rendering_disabled)(cef_browser_host_t *self);
    void (*was_resized)(cef_browser_host_t *self);
    void (*was_hidden)(cef_browser_host_t *self, int hidden);
    void (*notify_screen_info_changed)(cef_browser_host_t *self);
};

struct _cef_browser_process_handler_t {
    cef_base_ref_counted_t base;
    void (*on_register_custom_preferences)(cef_browser_process_handler_t *self, int type, void *registrar);
    void (*on_context_initialized)(cef_browser_process_handler_t *self);
    void (*on_before_child_process_launch)(cef_browser_process_handler_t *self, void *command_line);
    int (*on_already_running_app_relaunch)(cef_browser_process_handler_t *self, void *command_line, const cef_string_t *current_directory);
    void (*on_schedule_message_pump_work)(cef_browser_process_handler_t *self, int64_t delay_ms);
    cef_client_t *(*get_default_client)(cef_browser_process_handler_t *self);
    void *(*get_default_request_context_handler)(cef_browser_process_handler_t *self);
};

struct _cef_app_t {
    cef_base_ref_counted_t base;
    void (*on_before_command_line_processing)(cef_app_t *self, const cef_string_t *process_type, void *command_line);
    void (*on_register_custom_schemes)(cef_app_t *self, void *registrar);
    void *(*get_resource_bundle_handler)(cef_app_t *self);
    cef_browser_process_handler_t *(*get_browser_process_handler)(cef_app_t *self);
    void *(*get_render_process_handler)(cef_app_t *self);
};

struct _cef_display_handler_t {
    cef_base_ref_counted_t base;
    void (*on_address_change)(cef_display_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, const cef_string_t *url);
    void (*on_title_change)(cef_display_handler_t *self, cef_browser_t *browser, const cef_string_t *title);
    void (*on_favicon_urlchange)(cef_display_handler_t *self, cef_browser_t *browser, cef_string_list_t iconURLs);
    void (*on_fullscreen_mode_change)(cef_display_handler_t *self, cef_browser_t *browser, int fullscreen);
    int (*on_tooltip)(cef_display_handler_t *self, cef_browser_t *browser, cef_string_t *text);
    void (*on_status_message)(cef_display_handler_t *self, cef_browser_t *browser, const cef_string_t *value);
    int (*on_console_message)(cef_display_handler_t *self, cef_browser_t *browser, cef_log_severity_t level, const cef_string_t *message, const cef_string_t *source, int line);
    int (*on_auto_resize)(cef_display_handler_t *self, cef_browser_t *browser, const cef_size_t *newSize);
    void (*on_loading_progress_change)(cef_display_handler_t *self, cef_browser_t *browser, double progress);
    int (*on_cursor_change)(cef_display_handler_t *self, cef_browser_t *browser, cef_cursor_handle_t cursor, cef_cursor_type_t type, const cef_cursor_info_t *customCursorInfo);
    void (*on_media_access_change)(cef_display_handler_t *self, cef_browser_t *browser, int hasVideoAccess, int hasAudioAccess);
    int (*on_contents_bounds_change)(cef_display_handler_t *self, cef_browser_t *browser, const cef_rect_t *newBounds);
    int (*get_root_window_screen_rect)(cef_display_handler_t *self, cef_browser_t *browser, cef_rect_t *rect);
};

struct _cef_load_handler_t {
    cef_base_ref_counted_t base;
    void (*on_loading_state_change)(cef_load_handler_t *self, cef_browser_t *browser, int isLoading, int canGoBack, int canGoForward);
    void (*on_load_start)(cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, int transitionType);
    void (*on_load_end)(cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, int httpStatusCode);
    void (*on_load_error)(cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, cef_errorcode_t errorCode, const cef_string_t *errorText, const cef_string_t *failedURL);
};

struct _cef_life_span_handler_t {
    cef_base_ref_counted_t base;
    int (*on_before_popup)(cef_life_span_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, int popupID, const cef_string_t *targetURL, const cef_string_t *targetFrameName, int targetDisposition, int userGesture, const void *popupFeatures, cef_window_info_t *windowInfo, cef_client_t **client, cef_browser_settings_t *settings, cef_dictionary_value_t **extraInfo, int *noJavaScriptAccess);
    void (*on_before_popup_aborted)(cef_life_span_handler_t *self, cef_browser_t *browser, int popupID);
    void (*on_before_dev_tools_popup)(cef_life_span_handler_t *self, cef_browser_t *browser, cef_window_info_t *windowInfo, cef_client_t **client, cef_browser_settings_t *settings, cef_dictionary_value_t **extraInfo, int *useDefaultWindow);
    void (*on_after_created)(cef_life_span_handler_t *self, cef_browser_t *browser);
    int (*do_close)(cef_life_span_handler_t *self, cef_browser_t *browser);
    void (*on_before_close)(cef_life_span_handler_t *self, cef_browser_t *browser);
};

struct _cef_find_handler_t {
    cef_base_ref_counted_t base;
    void (*on_find_result)(cef_find_handler_t *self, cef_browser_t *browser, int identifier, int count, const cef_rect_t *selectionRect, int activeMatchOrdinal, int finalUpdate);
};

struct _cef_dialog_handler_t {
    cef_base_ref_counted_t base;
    int (*on_file_dialog)(cef_dialog_handler_t *self,
                          cef_browser_t *browser,
                          cef_file_dialog_mode_t mode,
                          const cef_string_t *title,
                          const cef_string_t *default_file_path,
                          cef_string_list_t accept_filters,
                          cef_string_list_t accept_extensions,
                          cef_string_list_t accept_descriptions,
                          cef_file_dialog_callback_t *callback);
};

struct _cef_jsdialog_handler_t {
    cef_base_ref_counted_t base;
    int (*on_jsdialog)(cef_jsdialog_handler_t *self,
                       cef_browser_t *browser,
                       const cef_string_t *origin_url,
                       cef_jsdialog_type_t dialog_type,
                       const cef_string_t *message_text,
                       const cef_string_t *default_prompt_text,
                       cef_jsdialog_callback_t *callback,
                       int *suppress_message);
    int (*on_before_unload_dialog)(cef_jsdialog_handler_t *self,
                                   cef_browser_t *browser,
                                   const cef_string_t *message_text,
                                   int is_reload,
                                   cef_jsdialog_callback_t *callback);
    void (*on_reset_dialog_state)(cef_jsdialog_handler_t *self, cef_browser_t *browser);
    void (*on_dialog_closed)(cef_jsdialog_handler_t *self, cef_browser_t *browser);
};

struct _cef_before_download_callback_t {
    cef_base_ref_counted_t base;
    void (*cont)(cef_before_download_callback_t *self, const cef_string_t *download_path, int show_dialog);
};

struct _cef_download_item_callback_t {
    cef_base_ref_counted_t base;
    void (*cancel)(cef_download_item_callback_t *self);
    void (*pause)(cef_download_item_callback_t *self);
    void (*resume)(cef_download_item_callback_t *self);
};

struct _cef_download_item_t {
    cef_base_ref_counted_t base;
    int (*is_valid)(cef_download_item_t *self);
    int (*is_in_progress)(cef_download_item_t *self);
    int (*is_complete)(cef_download_item_t *self);
    int (*is_canceled)(cef_download_item_t *self);
    int (*is_interrupted)(cef_download_item_t *self);
    int (*get_percent_complete)(cef_download_item_t *self);
    int64_t (*get_total_bytes)(cef_download_item_t *self);
    int64_t (*get_received_bytes)(cef_download_item_t *self);
    cef_string_userfree_t (*get_full_path)(cef_download_item_t *self);
    uint32_t (*get_id)(cef_download_item_t *self);
    cef_string_userfree_t (*get_url)(cef_download_item_t *self);
    cef_string_userfree_t (*get_original_url)(cef_download_item_t *self);
    cef_string_userfree_t (*get_suggested_file_name)(cef_download_item_t *self);
    cef_string_userfree_t (*get_content_disposition)(cef_download_item_t *self);
    cef_string_userfree_t (*get_mime_type)(cef_download_item_t *self);
};

struct _cef_download_handler_t {
    cef_base_ref_counted_t base;
    int (*can_download)(cef_download_handler_t *self, cef_browser_t *browser, const cef_string_t *url, const cef_string_t *request_method);
    int (*on_before_download)(cef_download_handler_t *self, cef_browser_t *browser, cef_download_item_t *download_item, const cef_string_t *suggested_name, cef_before_download_callback_t *callback);
    void (*on_download_updated)(cef_download_handler_t *self, cef_browser_t *browser, cef_download_item_t *download_item, cef_download_item_callback_t *callback);
};

struct _cef_request_handler_t {
    cef_base_ref_counted_t base;
    int (*on_before_browse)(cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, cef_request_t *request, int user_gesture, int is_redirect);
    int (*on_open_urlfrom_tab)(cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, const cef_string_t *target_url, int target_disposition, int user_gesture);
    cef_resource_request_handler_t *(*get_resource_request_handler)(cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, cef_request_t *request, int is_navigation, int is_download, const cef_string_t *request_initiator, int *disable_default_handling);
    int (*get_auth_credentials)(cef_request_handler_t *self, cef_browser_t *browser, const cef_string_t *origin_url, int isProxy, const cef_string_t *host, int port, const cef_string_t *realm, const cef_string_t *scheme, cef_auth_callback_t *callback);
    int (*on_certificate_error)(cef_request_handler_t *self, cef_browser_t *browser, cef_errorcode_t cert_error, const cef_string_t *request_url, cef_sslinfo_t *ssl_info, cef_callback_t *callback);
    int (*on_select_client_certificate)(cef_request_handler_t *self, cef_browser_t *browser, int isProxy, const cef_string_t *host, int port, size_t certificatesCount, cef_x509_certificate_t *const *certificates, cef_select_client_certificate_callback_t *callback);
    void (*on_render_view_ready)(cef_request_handler_t *self, cef_browser_t *browser);
    int (*on_render_process_unresponsive)(cef_request_handler_t *self, cef_browser_t *browser, cef_unresponsive_process_callback_t *callback);
    void (*on_render_process_responsive)(cef_request_handler_t *self, cef_browser_t *browser);
    void (*on_render_process_terminated)(cef_request_handler_t *self, cef_browser_t *browser, cef_termination_status_t status, int error_code, const cef_string_t *error_string);
    void (*on_document_available_in_main_frame)(cef_request_handler_t *self, cef_browser_t *browser);
};

struct _cef_client_t {
    cef_base_ref_counted_t base;
    void *(*get_audio_handler)(cef_client_t *self);
    void *(*get_command_handler)(cef_client_t *self);
    void *(*get_context_menu_handler)(cef_client_t *self);
    cef_dialog_handler_t *(*get_dialog_handler)(cef_client_t *self);
    cef_display_handler_t *(*get_display_handler)(cef_client_t *self);
    cef_download_handler_t *(*get_download_handler)(cef_client_t *self);
    void *(*get_drag_handler)(cef_client_t *self);
    cef_find_handler_t *(*get_find_handler)(cef_client_t *self);
    void *(*get_focus_handler)(cef_client_t *self);
    void *(*get_frame_handler)(cef_client_t *self);
    void *(*get_permission_handler)(cef_client_t *self);
    cef_jsdialog_handler_t *(*get_jsdialog_handler)(cef_client_t *self);
    void *(*get_keyboard_handler)(cef_client_t *self);
    cef_life_span_handler_t *(*get_life_span_handler)(cef_client_t *self);
    cef_load_handler_t *(*get_load_handler)(cef_client_t *self);
    void *(*get_print_handler)(cef_client_t *self);
    void *(*get_render_handler)(cef_client_t *self);
    cef_request_handler_t *(*get_request_handler)(cef_client_t *self);
    int (*on_process_message_received)(cef_client_t *self, cef_browser_t *browser, cef_frame_t *frame, int sourceProcess, void *message);
};

typedef int (*CMUXCEFStringUTF16SetFn)(const char16_t *src, size_t srcLen, cef_string_t *output, int copy);
typedef void (*CMUXCEFStringUserfreeFreeFn)(cef_string_userfree_t str);
typedef cef_string_list_t (*CMUXCEFStringListAllocFn)(void);
typedef size_t (*CMUXCEFStringListSizeFn)(cef_string_list_t list);
typedef int (*CMUXCEFStringListValueFn)(cef_string_list_t list, size_t index, cef_string_t *value);
typedef void (*CMUXCEFStringListAppendFn)(cef_string_list_t list, const cef_string_t *value);
typedef void (*CMUXCEFStringListFreeFn)(cef_string_list_t list);
typedef cef_request_context_t *(*CMUXCEFRequestContextCreateContextFn)(const cef_request_context_settings_t *settings, void *handler);
typedef cef_value_t *(*CMUXCEFValueCreateFn)(void);
typedef cef_dictionary_value_t *(*CMUXCEFDictionaryValueCreateFn)(void);
typedef cef_browser_t *(*CMUXCEFBrowserCreateBrowserSyncFn)(const cef_window_info_t *windowInfo, cef_client_t *client, const cef_string_t *url, const cef_browser_settings_t *settings, cef_dictionary_value_t *extraInfo, cef_request_context_t *requestContext);

#ifdef __cplusplus
}
#endif

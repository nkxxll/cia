pub const GtkApplication = opaque {};
pub const GtkEventController = opaque {};
pub const GtkGesture = opaque {};
pub const GtkGestureClick = opaque {};
pub const GtkGestureSingle = opaque {};
pub const GtkGLArea = opaque {};
pub const GtkWidget = opaque {};
pub const GtkWindow = opaque {};
pub const GdkGLContext = opaque {};

pub const gboolean = c_int;
pub const guint = c_uint;
pub const gpointer = ?*anyopaque;
pub const GCallback = *const fn () callconv(.c) void;

pub const G_APPLICATION_DEFAULT_FLAGS: c_uint = 0;
pub const G_CONNECT_DEFAULT: c_uint = 0;
pub const GTK_EVENT_CONTROLLER_SCROLL_VERTICAL: c_uint = 1;

pub const GDK_KEY_Escape: c_uint = 0xff1b;
pub const GDK_KEY_Left: c_uint = 0xff51;
pub const GDK_KEY_Up: c_uint = 0xff52;
pub const GDK_KEY_Right: c_uint = 0xff53;
pub const GDK_KEY_Down: c_uint = 0xff54;
pub const GDK_KEY_space: c_uint = 0x020;
pub const GDK_KEY_a: c_uint = 0x061;
pub const GDK_KEY_d: c_uint = 0x064;
pub const GDK_KEY_r: c_uint = 0x072;
pub const GDK_KEY_s: c_uint = 0x073;
pub const GDK_KEY_w: c_uint = 0x077;

pub extern fn gtk_application_new(application_id: [*:0]const u8, flags: c_uint) ?*GtkApplication;
pub extern fn gtk_application_window_new(application: *GtkApplication) *GtkWidget;
pub extern fn gtk_event_controller_key_new() *GtkEventController;
pub extern fn gtk_event_controller_motion_new() *GtkEventController;
pub extern fn gtk_event_controller_scroll_new(flags: c_uint) *GtkEventController;
pub extern fn gtk_gesture_click_new() *GtkGesture;
pub extern fn gtk_gesture_single_set_button(gesture: *GtkGestureSingle, button: guint) void;
pub extern fn gtk_gl_area_make_current(area: *GtkGLArea) void;
pub extern fn gtk_gl_area_new() *GtkWidget;
pub extern fn gtk_gl_area_queue_render(area: *GtkGLArea) void;
pub extern fn gtk_gl_area_set_required_version(area: *GtkGLArea, major: c_int, minor: c_int) void;
pub extern fn gtk_widget_add_controller(widget: *GtkWidget, controller: *GtkEventController) void;
pub extern fn gtk_widget_get_height(widget: *GtkWidget) c_int;
pub extern fn gtk_widget_get_scale_factor(widget: *GtkWidget) c_int;
pub extern fn gtk_widget_get_width(widget: *GtkWidget) c_int;
pub extern fn gtk_widget_grab_focus(widget: *GtkWidget) gboolean;
pub extern fn gtk_widget_set_focusable(widget: *GtkWidget, focusable: gboolean) void;
pub extern fn gtk_window_present(window: *GtkWindow) void;
pub extern fn gtk_window_set_child(window: *GtkWindow, child: *GtkWidget) void;
pub extern fn gtk_window_set_default_size(window: *GtkWindow, width: c_int, height: c_int) void;
pub extern fn gtk_window_set_title(window: *GtkWindow, title: [*:0]const u8) void;

pub extern fn g_application_quit(application: *anyopaque) void;
pub extern fn g_application_run(application: *anyopaque, argc: c_int, argv: ?[*][*:0]u8) c_int;
pub extern fn g_object_unref(object: *anyopaque) void;
pub extern fn g_signal_connect_data(
    instance: *anyopaque,
    detailed_signal: [*:0]const u8,
    callback: GCallback,
    data: gpointer,
    destroy_data: ?*const fn (gpointer, *anyopaque) callconv(.c) void,
    connect_flags: c_uint,
) c_ulong;

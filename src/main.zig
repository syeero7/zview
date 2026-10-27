const std = @import("std");
const sdl3 = @import("sdl3");

// Use main callbacks.
comptime {
    _ = sdl3.main_callbacks;
}

// Disable main hack.
pub const _start = void;
pub const WinMainCRTStartup = void;

const my_image = @embedFile("trees.jpeg");

const fps = 60;
const window_width = 640;
const window_height = 480;
const init_flags = sdl3.InitFlags{ .video = true };

const logger = sdl3.log.Category.application;

const AppState = struct {
    frame_capper: sdl3.extras.FramerateCapper(f32),
    window: sdl3.video.Window,
    renderer: sdl3.render.Renderer,
    texture: sdl3.render.Texture,
};

pub fn init(init_data: sdl3.Init) !struct { AppState, sdl3.AppResult } {
    _ = try sdl3.setMemoryFunctionsByAllocator(init_data.gpa);
    sdl3.log.setAllPriorities(.info);
    sdl3.log.setLogOutputFunction(void, &sdl3.extras.loggers.zigLog, null);
    try sdl3.init(init_flags);

    try logger.logInfo("Starting application...", .{});

    const window, const renderer = try sdl3.render.Renderer.initWithWindow(
        "Hello SDL3",
        window_width,
        window_height,
        .{},
    );
    errdefer renderer.deinit();
    errdefer window.deinit();
    var frame_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .unlimited = {} } };
    renderer.setVSync(.{ .on_each_num_refresh = 1 }) catch {
        frame_capper.mode = .{ .limited = fps };
    };
    const texture = try sdl3.image.loadTextureIo(
        renderer,
        try sdl3.io_stream.Stream.initFromConstMem(my_image),
        true,
    );
    errdefer texture.deinit();

    try logger.logInfo("Finished initializing", .{});
    return .{
        .{
            .frame_capper = frame_capper,
            .window = window,
            .renderer = renderer,
            .texture = texture,
        },
        .run,
    };
}

pub fn iterate(app_state: *AppState) !sdl3.AppResult {
    const dt = app_state.frame_capper.delay();
    _ = dt;

    try app_state.renderer.setDrawColor(.{ .r = 128, .g = 30, .b = 255, .a = 255 });
    try app_state.renderer.clear();
    const border = 10;
    try app_state.renderer.renderTexture(app_state.texture, null, .{
        .x = border,
        .y = border,
        .w = window_width - border * 2,
        .h = window_height - border * 2,
    });
    try app_state.renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    var fps_text_buf: [32]u8 = undefined;
    const fps_text = std.fmt.bufPrintSentinel(&fps_text_buf, "FPS: {d}", .{app_state.frame_capper.getObservedFps()}, 0) catch "[Err]";
    try app_state.renderer.renderDebugText(.{ .x = 0, .y = 0 }, fps_text);

    try app_state.renderer.present();
    return .run;
}

pub fn event(app_state: *AppState, current_event: sdl3.events.Event) !sdl3.AppResult {
    _ = app_state;
    switch (current_event) {
        .terminating, .quit => return .success,
        else => {},
    }
    return .run;
}

pub fn quit(app_state: ?*AppState, result: sdl3.AppResult) void {
    _ = result;
    if (app_state) |state| {
        state.texture.deinit();
        state.renderer.deinit();
        state.window.deinit();
    }

    sdl3.quit(init_flags);
    sdl3.shutdown();
}

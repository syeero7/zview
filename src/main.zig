const std = @import("std");
const sdl3 = @import("sdl3");

const Display = sdl3.video.Display;
const Renderer = sdl3.render.Renderer;

const AppState = struct {
    frame_limiter: sdl3.extras.FramerateCapper(f32),
    window: sdl3.video.Window,
    renderer: sdl3.render.Renderer,
    texture: sdl3.render.Texture,
};

// Use main callbacks.
comptime {
    _ = sdl3.main_callbacks;
}

// Disable main hack.
pub const _start = void;
pub const WinMainCRTStartup = void;

const fps = 60;
const init_flags = sdl3.InitFlags{ .video = true };

const logger = sdl3.log.Category.application;

pub fn init(init_data: sdl3.Init) !struct { AppState, sdl3.AppResult } {
    const gpa = init_data.gpa;

    const filepath: [:0]u8 = fp: {
        if (init_data.args.len < 2) return error.ImgPathRequired;
        break :fp std.mem.span(init_data.args[1]);
    };

    _ = try sdl3.setMemoryFunctionsByAllocator(gpa);
    sdl3.log.setAllPriorities(.info);
    sdl3.log.setLogOutputFunction(void, &sdl3.extras.loggers.zigLog, null);

    try sdl3.init(init_flags);
    try logger.logInfo("Starting application...", .{});

    const display = try Display.getPrimaryDisplay();
    const mode = try display.getDesktopMode();
    const window, const renderer = try Renderer.initWithWindow("zview", mode.width, mode.height, .{ .fullscreen = true });
    errdefer renderer.deinit();
    errdefer window.deinit();

    var frame_limiter = sdl3.extras.FramerateCapper(f32){ .mode = .{ .unlimited = {} } };
    renderer.setVSync(.{ .on_each_num_refresh = 1 }) catch {
        frame_limiter.mode = .{ .limited = fps };
    };

    const texture = try sdl3.image.loadTexture(renderer, filepath);
    errdefer texture.deinit();

    try logger.logInfo("Finished initializing", .{});
    return .{
        .{
            .frame_limiter = frame_limiter,
            .window = window,
            .renderer = renderer,
            .texture = texture,
        },
        .run,
    };
}

pub fn iterate(state: *AppState) !sdl3.AppResult {
    _ = state.frame_limiter.delay();

    try state.renderer.setDrawColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
    try state.renderer.clear();

    const img_width, const img_height = try state.texture.getSize();
    try state.renderer.setLogicalPresentation(@intFromFloat(img_width), @intFromFloat(img_height), .letter_box);
    try state.renderer.renderTexture(state.texture, null, null);
    try state.renderer.present();
    return .run;
}

pub fn event(state: *AppState, current_event: sdl3.events.Event) !sdl3.AppResult {
    _ = state;
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

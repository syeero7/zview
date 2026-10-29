const std = @import("std");
const sdl3 = @import("sdl3");

const Display = sdl3.video.Display;
const Renderer = sdl3.render.Renderer;
const FpsLimiter = sdl3.extras.FramerateCapper(f32);

const AppState = struct {
    fps_limiter: FpsLimiter,
    window: sdl3.video.Window,
    renderer: Renderer,
    texture: sdl3.render.Texture,
    rotate_angle: f32 = 0,
    zoom_level: f32 = 1,
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

    try renderer.setLogicalPresentation(mode.width, mode.height, .letter_box);
    var fps_limiter = FpsLimiter{ .mode = .unlimited };
    renderer.setVSync(.{ .on_each_num_refresh = 1 }) catch {
        fps_limiter.mode = .{ .limited = fps };
    };

    const texture = try sdl3.image.loadTexture(renderer, filepath);
    errdefer texture.deinit();

    try logger.logInfo("Finished initializing", .{});
    return .{
        .{
            .fps_limiter = fps_limiter,
            .window = window,
            .renderer = renderer,
            .texture = texture,
        },
        .run,
    };
}

pub fn iterate(state: *AppState) !sdl3.AppResult {
    _ = state.fps_limiter.delay();
    try state.renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
    try state.renderer.clear();

    const texture_width, const texture_height = try state.texture.getSize();
    const window_size = try state.window.getSize();
    const window_width: f32 = @floatFromInt(window_size.@"0");
    const window_height: f32 = @floatFromInt(window_size.@"1");

    const scale = @min(window_width / texture_width, window_height / texture_height) * state.zoom_level;
    var dest_rect: sdl3.rect.FRect = undefined;
    dest_rect.w = texture_width * scale;
    dest_rect.h = texture_height * scale;
    dest_rect.x = (window_width - dest_rect.w) / 2;
    dest_rect.y = (window_height - dest_rect.h) / 2;

    try state.renderer.renderTextureRotated(state.texture, null, dest_rect, state.rotate_angle, null, .{});
    try state.renderer.present();
    return .run;
}

pub fn event(state: *AppState, current_event: sdl3.events.Event) !sdl3.AppResult {
    switch (current_event) {
        .terminating, .quit => return .success,
        .key_down => |keyboard| {
            if (keyboard.key == null) return .run;
            switch (keyboard.key.?) {
                .q => return .success,
                .l => state.rotate_angle = rotate(state.rotate_angle, .clockwise),
                .h => state.rotate_angle = rotate(state.rotate_angle, .counter_clockwise),
                .z => state.zoom_level = @min(2, state.zoom_level + 0.25),
                .x => state.zoom_level = @max(0.25, state.zoom_level - 0.25),
                else => {},
            }
        },
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

fn rotate(angle: f32, direction: enum { clockwise, counter_clockwise }) f32 {
    return switch (direction) {
        .clockwise => if (angle == 270) 0 else @min(270, angle + 90),
        .counter_clockwise => if (angle == 0) 90 else @max(0, angle - 90),
    };
}

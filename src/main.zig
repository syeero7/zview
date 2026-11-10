const std = @import("std");
const sdl3 = @import("sdl3");
const img = @import("images.zig");
const Transform = @import("Transform.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Display = sdl3.video.Display;
const Renderer = sdl3.render.Renderer;
const Texture = sdl3.render.Texture;
const FpsLimiter = sdl3.extras.FramerateCapper(f32);

const fps = 60;
const init_flags = sdl3.InitFlags{ .video = true };

const logger = sdl3.log.Category.application;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    _ = try sdl3.setMemoryFunctionsByAllocator(allocator);
    defer sdl3.shutdown();
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    sdl3.log.setAllPriorities(.info);
    sdl3.log.setLogOutputFunction(void, &sdl3.extras.loggers.zigLog, null);

    const display = try Display.getPrimaryDisplay();
    const mode = try display.getDesktopMode();
    const window, const renderer = try Renderer.initWithWindow("zview", mode.width, mode.height, .{ .fullscreen = true });
    defer renderer.deinit();
    defer window.deinit();

    try renderer.setLogicalPresentation(mode.width, mode.height, .letter_box);
    var fps_limiter = FpsLimiter{ .mode = .unlimited };
    renderer.setVSync(.{ .on_each_num_refresh = 1 }) catch {
        fps_limiter.mode = .{ .limited = fps };
    };

    var arg_iterator = try init.minimal.args.iterateAllocator(allocator);
    defer arg_iterator.deinit();

    _ = arg_iterator.next();
    const path = arg_iterator.next() orelse return error.PathRequied;

    var images = try img.Images.init(io, allocator, path);
    defer images.deinit(io, allocator);

    images.cache.current = .{
        .texture = try images.source.getTexture(allocator, 0, renderer),
    };

    var transform: Transform = .{};
    if (images.source != .image) {
        const thread = try std.Thread.spawn(.{}, img.loadAdjacentImages, .{ io, allocator, &images });
        thread.detach();
    }

    var quit = false;
    while (!quit) {
        _ = fps_limiter.delay();
        try renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        try renderer.clear();

        const window_size = try window.getSize();
        const texture = blk: {
            if (try images.getCurrentTexture(io, renderer)) |tex| break :blk tex;
            const fallback = try renderer.createTexture(.packed_rgba_8_8_8_8, .target, window_size.@"0", window_size.@"1");
            break :blk fallback;
        };

        const texture_width, const texture_height = try texture.getSize();
        const window_width: f32 = @floatFromInt(window_size.@"0");
        const window_height: f32 = @floatFromInt(window_size.@"1");
        const scale = @min(window_width / texture_width, window_height / texture_height) * transform.scale_factor;
        var dest_rect: sdl3.rect.FRect = undefined;
        dest_rect.w = texture_width * scale;
        dest_rect.h = texture_height * scale;
        dest_rect.x = (window_width - dest_rect.w) / 2;
        dest_rect.y = (window_height - dest_rect.h) / 2;

        try renderer.renderTextureRotated(texture, null, dest_rect, transform.rotate_angle, null, .{});
        try renderer.present();

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => quit = true,
                .key_down => |keyboard| {
                    if (keyboard.key == null) continue;
                    switch (keyboard.key.?) {
                        .q => quit = true,
                        .l => transform.rotate(.clockwise),
                        .h => transform.rotate(.counter_clockwise),
                        .z => transform.scaleUp(),
                        .x => transform.scaleDown(),
                        .right => try images.next(io),
                        .left => try images.previous(io),
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
}

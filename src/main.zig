const std = @import("std");
const c = @import("c");
const Io = std.Io;

const Error = error{SdlFailure};

pub fn main(init: std.process.Init) !void {
    _ = Io;
    const gpa = std.heap.c_allocator;

    const filepath = fp: {
        var iterator = try init.minimal.args.iterateAllocator(gpa);
        defer iterator.deinit();
        _ = iterator.next() orelse return;
        break :fp iterator.next() orelse return;
    };

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("Failed to initialize SDL: {s}", .{c.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer c.SDL_Quit();

    const display_id = c.SDL_GetPrimaryDisplay();
    const mode = c.SDL_GetDesktopDisplayMode(display_id);
    if (mode == null) {
        std.log.err("Failed to get display mode: {s}", .{c.SDL_GetError()});
        return Error.SdlFailure;
    }

    const window = c.SDL_CreateWindow("zview", mode.*.w, mode.*.h, c.SDL_WINDOW_FULLSCREEN);
    if (window == null) {
        std.log.err("Failed to create window: {s}", .{c.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null);
    if (renderer == null) {
        std.log.err("Failed to create render: {s}", .{c.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer c.SDL_DestroyRenderer(renderer);

    const texture = c.IMG_LoadTexture(renderer, filepath);
    if (texture == null) {
        std.log.err("Failed to create texture: {s}", .{c.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer c.SDL_DestroyTexture(texture);

    _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderClear(renderer);

    var img_width: f32 = undefined;
    var img_height: f32 = undefined;
    if (!c.SDL_GetTextureSize(texture, &img_width, &img_height)) {
        std.log.err("Failed to get texture size {s}", .{c.SDL_GetError()});
        return Error.SdlFailure;
    }

    _ = c.SDL_SetRenderLogicalPresentation(renderer, @intFromFloat(img_width), @intFromFloat(img_height), c.SDL_LOGICAL_PRESENTATION_LETTERBOX);
    _ = c.SDL_RenderTexture(renderer, texture, null, null);
    _ = c.SDL_RenderPresent(renderer);
    c.SDL_Delay(2000);
}

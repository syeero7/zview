const std = @import("std");
const sdl = @import("sdl");
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

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.log.err("Failed to initialize SDL: {s}", .{sdl.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("zview", 800, 600, sdl.SDL_WINDOW_FULLSCREEN);
    if (window == null) {
        std.log.err("Failed to create window: {s}", .{sdl.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, null);
    if (renderer == null) {
        std.log.err("Failed to create render: {s}", .{sdl.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.IMG_LoadTexture(renderer, filepath);
    if (texture == null) {
        std.log.err("Failed to create texture: {s}", .{sdl.SDL_GetError()});
        return Error.SdlFailure;
    }
    defer sdl.SDL_DestroyTexture(texture);

    _ = sdl.SDL_RenderClear(renderer);
    _ = sdl.SDL_RenderTexture(renderer, texture, null, null);
    _ = sdl.SDL_RenderPresent(renderer);
    sdl.SDL_Delay(2000);
}

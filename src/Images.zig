const std = @import("std");
const sdl3 = @import("sdl3");
const zip_lib = @import("zip.zig");
const img_src = @import("image_source.zig");
const Cache = @import("Cache.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Texture = sdl3.render.Texture;
const Surface = sdl3.surface.Surface;
const Renderer = sdl3.render.Renderer;

const Images = @This();

source: img_src.Source,
current_index: usize = 0,
cache: Cache = .{},
mutex: Io.Mutex,
condition: Io.Condition,
active: bool = true,
ready: bool = true,

pub fn init(io: Io, allocator: Allocator, path: [:0]const u8) !@This() {
    return .{
        .source = try .init(io, allocator, path),
        .mutex = .init,
        .condition = .init,
    };
}

pub fn deinit(self: *@This(), io: Io, allocator: Allocator) void {
    self.source.deinit(io, allocator);
    self.active = false;
    self.cache.deinit();
}

pub fn next(self: *@This(), io: Io) !void {
    const src_length = switch (self.source) {
        .directory => |dir_src| dir_src.sub_paths.len,
        .zip => |zip_src| zip_src.entries.len,
        .image => return,
    };
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    if (self.current_index == src_length - 1) return;
    self.current_index += 1;

    self.cache.loadNext();
    self.ready = true;
    self.condition.signal(io);
}

pub fn previous(self: *@This(), io: Io) !void {
    if (self.source == .image) return;
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    if (self.current_index == 0) return;
    self.current_index -= 1;

    self.cache.loadPrevious();
    self.ready = true;
    self.condition.signal(io);
}

pub fn getCurrentTexture(self: *@This(), io: Io, renderer: Renderer) !?Texture {
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    const current = self.cache.current orelse return null;
    if (current.texture) |texture| return texture;
    if (current.surface) |surface| {
        const texture = try renderer.createTextureFromSurface(surface);
        surface.deinit();
        self.cache.current = .{ .texture = texture, .surface = null };
        return texture;
    }

    unreachable;
}

pub fn loadAdjacentImages(io: Io, allocator: Allocator, images: *Images) !void {
    const src_length = switch (images.source) {
        .directory => |dir| dir.sub_paths.len,
        .zip => |zip| zip.entries.len,
        else => unreachable,
    };

    while (true) {
        try images.mutex.lock(io);
        defer images.mutex.unlock(io);
        if (!images.active) break;

        while (!images.ready) try images.condition.wait(io, &images.mutex);
        defer images.ready = false;

        const prev_index = if (images.current_index > 0) images.current_index - 1 else 0;
        const next_index = images.current_index + 1;

        if (next_index < src_length and !images.cache.hasNext()) {
            images.cache.next = .{
                .surface = try images.source.getSurface(allocator, next_index),
            };
        }

        if (images.current_index > 0 and prev_index >= 0 and !images.cache.hasPrevious()) {
            images.cache.previous = .{
                .surface = try images.source.getSurface(allocator, prev_index),
            };
        }
    }
}

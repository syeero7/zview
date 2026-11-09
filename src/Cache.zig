const std = @import("std");
const sdl3 = @import("sdl3");
const zip_lib = @import("zip.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Texture = sdl3.render.Texture;
const Surface = sdl3.surface.Surface;

const CacheItem = struct {
    surface: ?Surface = null,
    texture: ?Texture = null,

    pub fn deinit(self: *@This()) void {
        if (self.surface) |surface| surface.deinit();
        if (self.texture) |texture| texture.deinit();
    }

    pub fn isEmpty(self: @This()) bool {
        return self.texture == null and self.surface == null;
    }
};

const Cache = @This();

previous: ?CacheItem = null,
current: ?CacheItem = null,
next: ?CacheItem = null,

pub fn deinit(self: *@This()) void {
    if (self.previous != null) self.previous.?.deinit();
    if (self.current != null) self.current.?.deinit();
    if (self.next != null) self.next.?.deinit();
}

pub fn loadNext(self: *@This()) void {
    if (self.previous != null) self.previous.?.deinit();
    self.previous = self.current;
    self.current = self.next;
    self.next = null;
}

pub fn loadPrevious(self: *@This()) void {
    if (self.next != null) self.next.?.deinit();
    self.next = self.current;
    self.current = self.previous;
    self.previous = null;
}

pub fn hasNext(self: @This()) bool {
    return self.next != null and !self.next.?.isEmpty();
}

pub fn hasPrevious(self: @This()) bool {
    return self.previous != null and !self.previous.?.isEmpty();
}

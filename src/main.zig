const std = @import("std");
const sdl = @import("sdl");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    _ = init;
    _ = Io;
    _ = sdl;
    std.debug.print("hello \n", .{});
}

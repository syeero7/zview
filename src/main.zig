const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    _ = init;
    _ = Io;
    std.debug.print("hello \n", .{});
}

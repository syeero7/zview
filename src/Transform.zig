const std = @import("std");

const Transform = @This();

rotate_angle: f32 = 0,
scale_factor: f32 = 1,

pub fn rotate(self: *@This(), direction: enum { clockwise, counter_clockwise }) void {
    const angle = self.rotate_angle;
    self.rotate_angle = switch (direction) {
        .clockwise => if (angle == 270) 0 else @min(270, angle + 90),
        .counter_clockwise => if (angle == 0) 90 else @max(0, angle - 90),
    };
}

pub fn scaleUp(self: *@This()) void {
    self.scale_factor = @min(2, self.scale_factor + 0.05);
}
pub fn scaleDown(self: *@This()) void {
    self.scale_factor = @max(0.1, self.scale_factor - 0.05);
}

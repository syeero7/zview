const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include <SDL3/SDL.h>
            \\#include <SDL3_image/SDL_image.h>
        ),
        .optimize = optimize,
        .target = target,
    });

    main_module.addImport("c", translate_c.createModule());
    main_module.linkSystemLibrary("SDL3", .{});
    main_module.linkSystemLibrary("SDL3_image", .{});

    const exe = b.addExecutable(.{
        .name = "zview",
        .root_module = main_module,
    });

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

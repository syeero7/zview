const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

const targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    // .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *std.Build) !void {
    const should_build_multi_targets = b.option(bool, "multi-targets", "Build for multiple targets");
    const optimize = b.standardOptimizeOption(.{});

    if (should_build_multi_targets) |_| {
        for (targets) |query| {
            const target = b.resolveTargetQuery(query);
            const main_module = getModule(b, target, optimize);
            const suffix = try query.zigTriple(b.allocator);
            const exe = b.addExecutable(.{
                .name = b.fmt("zview-{s}", .{suffix}),
                .root_module = main_module,
            });

            b.installArtifact(exe);
        }

        return;
    }

    const target = b.standardTargetOptions(.{});
    const main_module = getModule(b, target, optimize);
    _ = b.systemIntegrationOption("sdl", .{ .default = true });
    main_module.linkSystemLibrary("SDL3_image", .{});

    const exe = b.addExecutable(.{
        .name = "zview",
        .root_module = main_module,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{ .root_module = main_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn getModule(b: *Build, target: ResolvedTarget, optimize: OptimizeMode) *Build.Module {
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = true,
    });

    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    main_module.addImport("sdl3", sdl3.module("sdl3"));
    return main_module;
}

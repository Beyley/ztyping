const std = @import("std");
const zaudio = @import("libs/zaudio/build.zig");
const sdl = @import("libs/SDL/build.zig");
const fontstash = @import("libs/fontstash/build.zig");
const wgpu = @import("wgpu.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ztyping",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    //Link libc and libc++, libc++ for wgpu
    exe.linkLibC();
    exe.linkLibCpp();

    { //zaudio
        const zaudio_pkg = zaudio.package(b, target, optimize, .{});
        zaudio_pkg.link(exe);
    } //zaudio

    { //fontstash
        var fontstash_lib = fontstash.buildFontstash(b, target, optimize, false);
        exe.linkLibrary(fontstash_lib);
        exe.addIncludePath("libs/fontstash/src");
    } //fontstash

    { //SDL
        const sdl_pkg = try sdl.createSDL(b, target, optimize, sdl.getDefaultOptionsForTarget(target));
        exe.linkLibrary(sdl_pkg);
        exe.addIncludePath("libs/SDL/include");

        //Add the C macros to the exe
        try exe.c_macros.appendSlice(sdl_pkg.c_macros.items);
    } //SDL

    { //wgpu
        exe.addObjectFile(try wgpu.create_wgpu(b, target, optimize));

        if (target.getOsTag() == .windows) {
            exe.linkSystemLibrary("ws2_32");
            exe.linkSystemLibrary("userenv");
            exe.linkSystemLibrary("bcrypt");
            exe.linkSystemLibrary("d3dcompiler_47");
        }

        exe.addIncludePath("libs/wgpu-native/ffi");
    } //wgpu

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";

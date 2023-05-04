const std = @import("std");
const zaudio = @import("libs/zaudio/build.zig");
const sdl = @import("libs/SDL/build.zig");
const fontstash = @import("libs/fontstash/build.zig");

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
        const wgpu_native_path = root_path ++ "libs/wgpu-native/";

        //Get the users name
        var username = std.os.getenv("USER") orelse return error.UserVariableNotSet;

        //TODO: install the proper toolchains

        //Get the possible path to `cross`
        //TODO: make this logic much smarter
        var cross_path = try std.mem.concat(b.allocator, u8, &.{ "/home/", username, "/.cargo/bin/cross" });

        //Array list will store our target name
        var cross_target = std.ArrayList(u8).init(b.allocator);

        //Add cpu arch
        try cross_target.appendSlice(@tagName(target.getCpuArch()));
        try cross_target.append('-');
        //Add special thing
        switch (target.getOsTag()) {
            .windows => try cross_target.appendSlice("pc"),
            .linux => try cross_target.appendSlice("unknown"),
            else => {
                //if theres no special thing, pop the last hyphen
                _ = cross_target.pop();
            },
        }
        try cross_target.append('-');
        //Add OS
        try cross_target.appendSlice(@tagName(target.getOsTag()));
        try cross_target.append('-');
        //Add ABI
        try cross_target.appendSlice(@tagName(target.getAbi()));

        var build_result = try std.ChildProcess.exec(.{
            .allocator = b.allocator,
            .argv = &.{ cross_path, "build", "--target", cross_target.items, if (optimize == std.builtin.OptimizeMode.Debug) "" else "--release" },
            .cwd = wgpu_native_path,
        });
        defer b.allocator.free(build_result.stdout);
        defer b.allocator.free(build_result.stderr);

        // std.debug.print("cross output: {s}\n", .{build_result.stderr});

        exe.addLibraryPath(try std.mem.concat(b.allocator, u8, &.{ root_path, "libs/wgpu-native/target/", cross_target.items, "/", if (optimize == std.builtin.OptimizeMode.Debug) "debug" else "release" }));
        exe.linkSystemLibrary("wgpu_native");

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

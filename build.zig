const std = @import("std");
const zaudio = @import("libs/zaudio/build.zig");
const zmath = @import("libs/zmath/build.zig");
const sdl = @import("libs/SDL/build.zig");
const fontstash = @import("libs/fontstash/build.zig");
const wgpu = @import("wgpu.zig");
const cimgui = @import("libs/cimgui/build.zig");
const iconv = @import("libs/iconv-zig/build.zig");
const ImageProcessor = @import("image_processor.zig");

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

    { //zmath
        const zmath_pkg = zmath.package(b, target, optimize, .{
            .options = .{ .enable_cross_platform_determinism = true },
        });
        zmath_pkg.link(exe);
    } //zmath

    { //fontstash
        var fontstash_lib = fontstash.buildFontstash(b, target, optimize, false);
        exe.linkLibrary(fontstash_lib);
        exe.addIncludePath("libs/fontstash/src");
    } //fontstash

    { //SDL
        var sdl_options = sdl.getDefaultOptionsForTarget(target);

        if (target.getOsTag() == .windows) {
            sdl_options.shared = true;
        }

        const sdl_pkg = try sdl.createSDL(b, target, optimize, sdl_options);
        exe.linkLibrary(sdl_pkg);
        exe.addIncludePath("libs/SDL/include");

        try sdl.applyLinkerArgs(b.allocator, target, exe);

        //Add the C macros to the exe
        try exe.c_macros.appendSlice(sdl_pkg.c_macros.items);
    } //SDL

    { //wgpu
        var wgpu_from_source = b.option(bool, "wgpu_from_source", "Compile WGPU from source") orelse false;

        if (wgpu_from_source) {
            exe.addObjectFile(try wgpu.create_wgpu(b, target, optimize));
        } else {
            var wgpu_bin_path = std.ArrayList(u8).init(b.allocator);

            try wgpu_bin_path.appendSlice(root_path ++ "libs/wgpu-native-bin/");

            try wgpu_bin_path.appendSlice(@tagName(target.getOsTag()));
            try wgpu_bin_path.append('-');
            try wgpu_bin_path.appendSlice(@tagName(target.getCpuArch()));

            exe.addLibraryPath(try wgpu_bin_path.toOwnedSlice());
            exe.linkSystemLibrary("wgpu_native");
        }

        if (target.getOsTag() == .windows) {
            exe.linkSystemLibrary("ws2_32");
            exe.linkSystemLibrary("userenv");
            exe.linkSystemLibrary("bcrypt");
            exe.linkSystemLibrary("d3dcompiler_47");
        }

        exe.addIncludePath("libs/wgpu-native/ffi");
    } //wgpu

    { //cimgui
        const cimgui_lib = try cimgui.create_cimgui(b, target, optimize);

        exe.linkLibrary(cimgui_lib);

        exe.addIncludePath("libs/cimgui/");
    } //cimgui

    { //zigimg
        var module = b.addModule("zigimg", .{
            .source_file = .{ .path = root_path ++ "libs/zigimg/zigimg.zig" },
        });

        exe.addModule("zigimg", module);
    } //zigimg

    { //iconv
        var iconv_lib = iconv.createIconv(b, target, optimize);

        exe.linkLibrary(iconv_lib);
    } //iconv

    { //process assets
        const process_images_step = b.step("Process images", "Process image files into a QOI texture atlas");

        process_images_step.makeFn = ImageProcessor.processImages;

        exe.step.dependOn(process_images_step);
    } //process assets

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

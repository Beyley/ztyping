const std = @import("std");
const zmath = @import("libs/zmath/build.zig");
const bass = @import("libs/zig-bass/build.zig");
const wgpu = @import("wgpu.zig");
const cimgui = @import("libs/cimgui/build.zig");
const iconv = @import("libs/iconv-zig/build.zig");
const ImageProcessor = @import("image_processor.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ztyping",
        .root_source_file = .{ .path = "game/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    //Link libc and libc++, libc++ for wgpu
    exe.linkLibC();
    exe.linkLibCpp();

    if (target.isDarwin()) {
        exe.addIncludePath(root_path ++ "libs/system-sdk/macos12/usr/include");
        exe.addFrameworkPath(root_path ++ "libs/system-sdk/macos12/System/Library/Frameworks");
        exe.addLibraryPath(root_path ++ "libs/system-sdk/macos12/usr/lib");

        exe.addIncludePath(root_path ++ "game/osx");
        exe.addCSourceFile(root_path ++ "game/osx/osx_helper.mm", &.{"-fobjc-arc"});

        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Foundation");

        exe.linkSystemLibrary("objc");
    }

    exe.addCSourceFile(root_path ++ "libs/stb/impl_stb_truetype.c", &.{});
    exe.addIncludePath(root_path ++ "libs/stb");

    if (target.isLinux() and !target.isNative()) {
        exe.addIncludePath(root_path ++ "libs/system-sdk/linux/include");
        exe.addLibraryPath(b.fmt(root_path ++ "libs/system-sdk/linux/lib/{s}", .{try target.linuxTriple(b.allocator)}));
    }

    { //zig-bass
        const zig_bass = b.addModule("bass", .{ .source_file = .{ .path = root_path ++ "libs/zig-bass/src/bass.zig" } });
        exe.addModule("bass", zig_bass);

        bass.linkBass(exe);
        bass.installBass(b, target);

        exe.addIncludePath(root_path ++ "libs/zig-bass/src");
    } //zig-bass

    { //zmath
        const zmath_pkg = zmath.package(b, target, optimize, .{
            .options = .{ .enable_cross_platform_determinism = true },
        });

        zmath_pkg.link(exe);
    } //zmath

    //SDL

    const sdl_pkg = b.dependency("SDL2", .{
        .target = target,
        .optimize = optimize,
        .osx_sdk_path = @as([]const u8, root_path ++ "libs/system-sdk/macos12"),
        .linux_sdk_path = @as([]const u8, root_path ++ "libs/system-sdk/linux"),
    });
    const sdl_lib = sdl_pkg.artifact("SDL2");

    //Link SDL
    exe.linkLibrary(sdl_lib);
    //Install the SDL headers
    exe.installLibraryHeaders(sdl_lib);

    //Add all the SDL C macros to our executable too
    try exe.c_macros.appendSlice(sdl_lib.c_macros.items);

    //SDL

    { //wgpu
        var wgpu_from_source = b.option(bool, "wgpu_from_source", "Compile WGPU from source") orelse false;

        if (wgpu_from_source) {
            var wgpu_lib = try wgpu.create_wgpu(b, target, optimize);

            if (target.getOsTag() == .windows) {
                @panic("TODO"); //we need to force dynamic linking here.
            } else {
                exe.addObjectFile(wgpu_lib);
            }
        } else {
            var wgpu_bin_path = std.ArrayList(u8).init(b.allocator);

            try wgpu_bin_path.appendSlice(root_path ++ "libs/wgpu-native-bin/");

            try wgpu_bin_path.appendSlice(@tagName(target.getOsTag()));
            try wgpu_bin_path.append('-');
            try wgpu_bin_path.appendSlice(@tagName(target.getCpuArch()));

            var wgpu_bin_path_slice = try wgpu_bin_path.toOwnedSlice();

            exe.addLibraryPath(wgpu_bin_path_slice);
            exe.linkSystemLibrary("wgpu_native");

            if (target.isWindows()) {
                b.installFile(try std.mem.concat(b.allocator, u8, &.{ wgpu_bin_path_slice, "/wgpu_native.dll" }), "bin/wgpu_native.dll");
            }
        }

        //On windows we need to link these libraries for wgpu to work
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

        cimgui_lib.installLibraryHeaders(sdl_lib);
        cimgui_lib.linkLibrary(sdl_lib);
        exe.addIncludePath("libs/cimgui/");

        exe.linkLibrary(cimgui_lib);
    } //cimgui

    //zigimg
    const zigimg_pkg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_module = zigimg_pkg.module("zigimg");
    exe.addModule("zigimg", zigimg_module);
    //zigimg

    { //iconv
        var iconv_lib = iconv.createIconv(b, target, optimize);

        exe.linkLibrary(iconv_lib);

        //On MacOS, we need to link iconv manually, on other platforms its part of libc (Linux) or by ourselves through win_iconv (Windows)
        if (target.getOsTag() == .macos) {
            exe.linkSystemLibrary("iconv");
        }
    } //iconv

    { //process assets
        var process_assets_exe = b.addExecutable(.{
            .name = "asset_processor",
            .root_source_file = .{ .path = root_path ++ "image_processor.zig" },
        });
        process_assets_exe.linkLibC();
        process_assets_exe.addModule("zigimg", zigimg_module);
        var run_process_assets = b.addRunArtifact(process_assets_exe);
        run_process_assets.addArg(root_path);

        const process_images_step = b.step("Process images", "Process image files into a QOI texture atlas");
        process_images_step.dependOn(&run_process_assets.step);

        exe.step.dependOn(process_images_step);
    } //process assets

    const tempo = b.addExecutable(.{
        .name = "tempo",
        .root_source_file = .{ .path = root_path ++ "util/tempo.zig" },
    });
    b.installArtifact(tempo);

    const tempo_cmd = b.addRunArtifact(tempo);
    tempo_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        tempo_cmd.addArgs(args);
    }
    const tempo_step = b.step("tempo", "");
    tempo_step.dependOn(&tempo_cmd.step);

    const run_game_cmd = b.addRunArtifact(exe);
    run_game_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_game_cmd.addArgs(args);
    }
    const run_game_step = b.step("run", "Run the app");
    run_game_step.dependOn(&run_game_cmd.step);
}

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";

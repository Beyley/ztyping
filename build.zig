const std = @import("std");
const bass = @import("libs/zig-bass/build.zig");
const cimgui = @import("libs/cimgui/build.zig");
const iconv = @import("libs/iconv-zig/build.zig");
const ImageProcessor = @import("image_processor.zig");
const builtin = @import("builtin");
const mach_core = @import("mach_core");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_core_dep = b.dependency("mach_core", .{
        .target = target,
        .optimize = optimize,
    });

    const zig_bass = b.addModule("bass", .{
        .root_source_file = .{ .path = root_path ++ "libs/zig-bass/src/bass.zig" },
    });

    const stb_truetype = b.addModule("stb_truetype", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = .{ .path = "game/stb_truetype.zig" },
    });

    stb_truetype.addCSourceFile(.{ .file = .{ .path = root_path ++ "libs/stb/impl_stb_truetype.c" }, .flags = &.{} });
    stb_truetype.addIncludePath(.{ .path = root_path ++ "libs/stb" });

    const zigimg_module = b.dependency("zigimg", .{}).module("zigimg");
    const app = try mach_core.App.init(b, mach_core_dep.builder, .{
        .name = "ztyping",
        .src = "game/app.zig",
        .target = target,
        .optimize = optimize,
        .deps = &[_]std.Build.Module.Import{
            .{
                .name = "mach",
                .module = b.dependency("mach", .{
                    .target = target,
                    .optimize = optimize,
                }).module("mach"),
            },
            .{
                .name = "zigimg",
                .module = zigimg_module,
            },
            .{
                .name = "bass",
                .module = zig_bass,
            },
            .{
                .name = "stb_truetype",
                .module = stb_truetype,
            },
        },
    });
    const app_module = app.compile.root_module.import_table.get("app").?;

    app_module.resolved_target = target;

    bass.linkBass(app_module);
    bass.installBass(b, target.result);

    app.compile.addIncludePath(.{ .path = root_path ++ "libs/zig-bass/src" });

    // if (target.isDarwin()) {
    //     exe.addIncludePath(.{ .path = root_path ++ "libs/system-sdk/macos12/usr/include" });
    //     exe.addFrameworkPath(.{ .path = root_path ++ "libs/system-sdk/macos12/System/Library/Frameworks" });
    //     exe.addLibraryPath(.{ .path = root_path ++ "libs/system-sdk/macos12/usr/lib" });

    //     if (!builtin.target.isDarwin()) {
    //         b.sysroot = root_path ++ "libs/system-sdk/macos12";
    //     }

    //     exe.linkFramework("Metal");
    //     exe.linkFramework("QuartzCore");
    //     exe.linkFramework("Foundation");

    //     exe.linkSystemLibrary("objc");
    // }

    // if (target.isLinux() and !target.isNative()) {
    //     exe.addIncludePath(.{ .path = root_path ++ "libs/system-sdk/linux/include" });
    //     exe.addLibraryPath(.{ .path = b.fmt(root_path ++ "libs/system-sdk/linux/lib/{s}", .{try target.linuxTriple(b.allocator)}) });
    // }

    { //zig-bass
    } //zig-bass

    // { //cimgui
    //     const cimgui_lib = try cimgui.create_cimgui(b, target, optimize);

    //     cimgui_lib.installLibraryHeaders(sdl_lib);
    //     cimgui_lib.linkLibrary(sdl_lib);
    //     try cimgui_lib.lib_paths.appendSlice(sdl_lib.lib_paths.items);
    //     try cimgui_lib.include_dirs.appendSlice(sdl_lib.include_dirs.items);

    //     exe.addIncludePath(.{ .path = "libs/cimgui/" });

    //     exe.linkLibrary(cimgui_lib);
    // } //cimgui

    { //iconv
        const iconv_lib = iconv.createIconv(b, target, optimize);

        app_module.linkLibrary(iconv_lib);

        //On MacOS, we need to link iconv manually, on other platforms its part of libc (Linux) or by ourselves through win_iconv (Windows)
        if (target.result.os.tag == .macos) {
            app_module.linkSystemLibrary("iconv", .{});
        }
    } //iconv

    { //process assets
        var process_assets_exe = b.addExecutable(.{
            .name = "asset_processor",
            .root_source_file = .{ .path = root_path ++ "image_processor.zig" },
            .target = b.host,
        });

        process_assets_exe.root_module.addImport("zigimg", zigimg_module);
        var run_process_assets = b.addRunArtifact(process_assets_exe);
        run_process_assets.addArg(root_path);

        const process_images_step = b.step("Process images", "Process image files into a QOI texture atlas");
        process_images_step.dependOn(&run_process_assets.step);

        app.compile.step.dependOn(process_images_step);
    } //process assets

    const tempo = b.addExecutable(.{
        .name = "tempo",
        .root_source_file = .{ .path = root_path ++ "util/tempo.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tempo);

    // const clap = b.dependency("clap", .{});
    // const fumen_compile = b.addExecutable(.{
    //     .name = "fumen_compile",
    //     .root_source_file = .{ .path = root_path ++ "util/fumen_compile.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // fumen_compile.root_module.addImport("clap", clap.module("clap"));
    // b.installArtifact(fumen_compile);

    app.compile.root_module.addImport(
        "fumen_compiler",
        b.addModule(
            "fumen_compiler",
            .{
                .root_source_file = .{ .path = root_path ++ "util/fumen_compile.zig" },
            },
        ),
    );

    // const fumen_compile_cmd = b.addRunArtifact(fumen_compile);
    // fumen_compile_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     fumen_compile_cmd.addArgs(args);
    // }
    // const fumen_compile_step = b.step("fumen_compile", "Run the fumen compiler");
    // fumen_compile_step.dependOn(&fumen_compile_cmd.step);

    const tempo_cmd = b.addRunArtifact(tempo);
    tempo_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        tempo_cmd.addArgs(args);
    }
    const tempo_step = b.step("tempo", "");
    tempo_step.dependOn(&tempo_cmd.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";

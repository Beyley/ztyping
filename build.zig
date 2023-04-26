const std = @import("std");
const SoLoud = @import("libs/soloud/build.zig");
const Fontstash = @import("libs/fontstash/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ztyping",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath("libs/fontstash/src");
    exe.addIncludePath("libs/soloud/include");

    var build_options = SoLoud.SoloudBuildOptions{};

    { //soloud
        build_options.with_sdl1 = false;
        build_options.with_sdl2 = true;
        build_options.with_sdl1_static = false;
        build_options.with_sdl2_static = false;
        build_options.with_portaudio = true;
        build_options.with_openal = true;
        build_options.with_xaudio2 = false;
        build_options.with_winmm = false;
        build_options.with_wasapi = false;
        build_options.with_oss = true;
        build_options.with_nosound = true;
        build_options.with_miniaudio = false;

        if (target.isWindows()) {
            build_options.with_xaudio2 = false;
            build_options.with_wasapi = true;
            build_options.with_winmm = true;
            build_options.with_oss = false;
        }

        if (target.isDarwin()) {
            build_options.with_oss = false;
        }

        var soloud = try SoLoud.buildSoloud(b, target, optimize, build_options);
        exe.linkLibrary(soloud);
    } //soloud

    { //fontstash
        var fontstash = Fontstash.buildFontstash(b, target, optimize, false);
        exe.linkLibrary(fontstash);
    } //fontstash

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

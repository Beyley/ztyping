const std = @import("std");

///Tries to compile and prepare wgpu, returning the path to a static library to add with addObjectFile()
pub fn create_wgpu(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) ![]const u8 {
    const wgpu_native_path = root_path ++ "libs/wgpu-native/";

    //Get the users name
    var username = try std.process.getEnvVarOwned(b.allocator, "USER");

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

    var args = std.ArrayList([]const u8).init(b.allocator);
    defer args.deinit();

    var env_map = try std.process.getEnvMap(b.allocator);
    // try env_map.put("CROSS_CONTAINER_ENGINE_NO_BUILDKIT", "1");

    try args.append(cross_path);
    try args.append("build");
    try args.append("--target");
    try args.append(cross_target.items);
    if (optimize != .Debug) {
        try args.append("--release");
    }

    var build_result = try std.ChildProcess.exec(.{
        .allocator = b.allocator,
        .argv = args.items,
        .cwd = wgpu_native_path,
        .env_map = &env_map,
    });
    defer b.allocator.free(build_result.stdout);
    defer b.allocator.free(build_result.stderr);

    if (build_result.term.Exited != 0) {
        std.debug.print("exitied with code: {d}\n{s}\n", .{ build_result.term.Exited, build_result.stderr });
        return error.UnableToCompileWgpu;
    }

    var target_path = try std.mem.concat(b.allocator, u8, &.{ root_path, "libs/wgpu-native/target/", cross_target.items, "/", if (optimize == std.builtin.OptimizeMode.Debug) "debug" else "release" });

    return (try std.mem.concat(b.allocator, u8, &.{ target_path, "/libwgpu_native.a" }));
}

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";

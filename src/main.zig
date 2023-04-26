const std = @import("std");
const SoLoud = @cImport(@cInclude("soloud_c.h"));

pub fn main() !void {
    std.debug.print("Creating SoLoud object\n", .{});
    var soloud = SoLoud.Soloud_create();
    defer SoLoud.Soloud_destroy(soloud);

    std.debug.print("Initializing SoLoud\n", .{});
    var err = SoLoud.Soloud_init(soloud);
    if (err != 0) {
        std.debug.print("SoLoud init failed, error {d}\n", .{err});
        return error.SoloudInitFailed;
    }
    defer SoLoud.Soloud_deinit(soloud);
}

const std = @import("std");

pub const SoLoud = struct {
    soloud: *c.Soloud,

    pub const c = @cImport(@cInclude("soloud_c.h"));

    pub fn init() !SoLoud {
        var soloud = c.Soloud_create();

        var err = c.Soloud_init(soloud);
        if (err != 0) {
            std.debug.print("SoLoud init failed, error {d}\n", .{err});
            return error.SoLoudInitFailed;
        }

        return .{ .soloud = soloud };
    }

    pub fn deinit(self: *const SoLoud) void {
        c.Soloud_deinit(self.soloud);
        c.Soloud_destroy(self.soloud);
    }
};

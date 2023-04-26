const std = @import("std");
const SoLoud = @import("soloud/soloud.zig").SoLoud;

pub fn main() !void {
    //Create the allocator to be used in the lifetime of the app
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("Memory leak!");

    //Initialize SoLoud
    var soloud = try SoLoud.init();
    defer soloud.deinit();
}

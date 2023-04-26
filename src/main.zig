const std = @import("std");
const SoLoud = @import("soloud/soloud.zig").SoLoud;

const c = @cImport({
    @cInclude("fontstash.h");
});

pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub var soloud: SoLoud = undefined;

pub fn main() !void {
    //Create the allocator to be used in the lifetime of the app
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("Memory leak!");

    //Initialize SoLoud
    soloud = try SoLoud.init();
    defer soloud.deinit();
}

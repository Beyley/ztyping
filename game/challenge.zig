const std = @import("std");

const RenderState = @import("screen.zig").RenderState;
const Gfx = @import("gfx.zig");

pub const ChallengeInfo = struct {
    hidden: bool = false,
    sudden: bool = false,
    stealth: bool = false,
    lyrics_stealth: bool = false,
    /// Whether or not the notes follow a sin(x) pattern for their Y position
    sin: bool = false,
    /// Whether or not the notes follow a cos(x) pattern for their Y position
    cos: bool = false,
    /// Whether or not the notes follow a tan(x) pattern for their Y position
    tan: bool = false,
    /// The speed of the map
    speed: f64 = 1,
    key: i32 = 0,
    /// A time added to the current time to "offset" the visuals/timing from the actual audio time,
    /// this is used to fix audio delay caused by the OS, hardware, and poor map timing
    audio_offset: i16 = 0,

    /// Whether or not the challenge is valid
    valid: bool = true,

    const Self = @This();

    pub fn format(self: Self, render_state: *RenderState, writer: anytype) !void {
        _ = render_state;
        //If its not valid,
        if (!self.valid) {
            //Write some hyphens
            try writer.writeAll("----");
            //Break out
            return;
        }

        //Write the speed
        try writer.writeByte('x');
        try std.fmt.formatFloatDecimal(self.speed, .{
            .precision = 1,
        }, writer);

        if (self.sudden) try writer.writeByte('S');
        if (self.hidden) try writer.writeByte('H');
        if (self.stealth) try writer.writeByte('C');
        if (self.lyrics_stealth) try writer.writeByte('L');
        if (self.key != 0) try std.fmt.formatInt(self.key, 10, .lower, .{}, writer);
        if (self.sin) try writer.writeByte('s');
        if (self.cos) try writer.writeByte('c');
        if (self.tan) try writer.writeByte('t');
    }
};

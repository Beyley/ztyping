const std = @import("std");

fn getTime() f64 {
    return @as(f64, @floatFromInt(std.time.nanoTimestamp())) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("Press enter to start\n");

    _ = try stdin.readByte();

    var a: f64 = 0;
    var b: f64 = 0;

    const start: f64 = getTime();

    var count: f64 = 0;
    while (true) {
        const char = try stdin.readByte();

        if (char == 'q') {
            return;
        }

        if (char != '\n') {
            continue;
        }

        const time = getTime() - start;

        a -= b;
        a += time * count;
        b += time;
        count += 1;

        const delta = a / ((count - 1) * count * (count + 1) / 6);
        try std.fmt.format(stdout, "tempo: {d}s\n", .{delta});
        try std.fmt.format(stdout, "bpm: {d}\n", .{60 / delta});
    }
}

const std = @import("std");

const Ini = @import("ini.zig").Ini(std.fs.File.Reader, 256, 0);

const Self = @This();

volume: f64,
window_scale: f32,

pub fn readConfig() !Self {
    var file = try std.fs.cwd().openFile("UTyping_config.txt", .{});
    defer file.close();

    var ini_reader = Ini.init(file.reader());

    var self: Self = .{
        .volume = 0.25,
        .window_scale = 1.0,
    };

    while (try ini_reader.next()) |item| {
        if (item.section == null) {
            if (std.mem.eql(u8, item.key, "Volume") and !std.mem.eql(u8, item.value, "default")) {
                self.volume = try std.fmt.parseFloat(f64, item.value);
            } else if (std.mem.eql(u8, item.key, "WindowScale")) {
                self.window_scale = try std.fmt.parseFloat(f32, item.value);
            } else {
                std.debug.print("Unknown config option \"{s}\" with value \"{s}\"\n", .{ item.key, item.value });
            }
        }
    }

    return self;
}

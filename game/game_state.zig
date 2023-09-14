const std = @import("std");

const Music = @import("music.zig");
const AudioTracker = @import("audio_tracker.zig");
const Convert = @import("convert.zig");
const Config = @import("config.zig");

const Self = @This();

is_running: bool,
audio_tracker: AudioTracker,
map_list: []Music,
current_map: ?Music,
convert: Convert,
delta_time: f64,
counter_freq: f64,
counter_curr: u64,
config: Config,
random: std.rand.DefaultPrng = std.rand.DefaultPrng.init(35798752),
///The name of the user, this is owned by the main menu instance at the bottom of the screen stack
name: []const u8,

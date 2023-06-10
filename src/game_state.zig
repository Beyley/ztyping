const std = @import("std");

const Music = @import("music.zig");
const AudioTracker = @import("audio_tracker.zig");
const Convert = @import("convert.zig");

const Self = @This();

is_running: bool,
audio_tracker: AudioTracker,
map_list: []Music,
current_map: ?Music,
convert: Convert,
delta_time: f64,
counter_freq: f64,
counter_curr: u64,

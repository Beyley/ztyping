const std = @import("std");

const Music = @import("music.zig");

const AudioTracker = @import("audio_tracker.zig");

const Self = @This();

is_running: bool,
audio_tracker: AudioTracker,
map_list: []Music,

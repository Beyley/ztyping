const std = @import("std");
const zaudio = @import("zaudio");

const Engine = zaudio.Engine;

engine: *Engine,
music: ?*zaudio.Sound = null,

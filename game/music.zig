const std = @import("std");

const IConv = @import("iconv.zig");
const Fumen = @import("fumen.zig");

const Gfx = @import("gfx.zig");
const Screen = @import("screen.zig");
const Fontstash = @import("fontstash.zig");

const Self = @This();

title: [:0]const u8,
artist: [:0]const u8,
author: [:0]const u8,
level: u3,
fumen_file_name: [:0]const u8,
ranking_file_name: [:0]const u8,
comment: []const [:0]const u8,

fumen: Fumen,

allocator: std.mem.Allocator,

pub fn deinit(self: *Self) void {
    self.allocator.free(self.title);
    self.allocator.free(self.artist);
    self.allocator.free(self.author);
    self.allocator.free(self.fumen_file_name);
    self.allocator.free(self.ranking_file_name);

    for (self.comment) |comment| {
        self.allocator.free(comment);
    }

    self.allocator.free(self.comment);
    self.fumen.deinit();
}

pub fn readFromFile(allocator: std.mem.Allocator, path: std.fs.Dir, file: *std.fs.File) !Self {
    var self: Self = undefined;
    self.allocator = allocator;

    var iconv = IConv.ziconv_open("Shift_JIS", "UTF-8");
    defer IConv.ziconv_close(iconv);

    var comments = std.ArrayList([:0]const u8).init(allocator);
    errdefer {
        for (comments.items) |comment| {
            allocator.free(comment);
        }
        comments.deinit();
    }

    //Set to 12 to match COMMENT_N_LINES in UTyping.cpp
    try comments.ensureTotalCapacity(12);

    var title: ?[:0]const u8 = null;
    var artist: ?[:0]const u8 = null;
    var author: ?[:0]const u8 = null;
    var fumen_file_name: ?[:0]const u8 = null;
    var ranking_file_name: ?[:0]const u8 = null;

    errdefer if (title) |title_ptr| allocator.free(title_ptr);
    errdefer if (artist) |artist_ptr| allocator.free(artist_ptr);
    errdefer if (author) |author_ptr| allocator.free(author_ptr);
    errdefer if (fumen_file_name) |fumen_file_name_ptr| allocator.free(fumen_file_name_ptr);
    errdefer if (ranking_file_name) |ranking_file_name_ptr| allocator.free(ranking_file_name_ptr);

    var i: usize = 0;
    while (true) {
        var orig_line = try file.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u32)) orelse break;
        defer allocator.free(orig_line);

        var returnless = if (orig_line[orig_line.len - 1] == '\r') orig_line[0 .. orig_line.len - 1] else orig_line;

        var line = try iconv.convert(allocator, returnless);
        defer allocator.free(line);

        //If the last char is \r, strip it out
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0..(line.len - 1)];
        }

        if (i == 0) {
            title = try allocator.dupeZ(u8, line);
        } else if (i == 1) {
            artist = try allocator.dupeZ(u8, line);
        } else if (i == 2) {
            author = try allocator.dupeZ(u8, line);
        } else if (i == 3) {
            self.level = try std.fmt.parseUnsigned(u3, line, 0);

            //While i dont like this behaviour, it matches UTyping
            if (self.level == 0) {
                return error.MusicInvalidLevel;
            }
        } else if (i == 4) {
            fumen_file_name = try allocator.dupeZ(u8, line);
        } else if (i == 5) {
            ranking_file_name = try allocator.dupeZ(u8, line);
        } else {
            try comments.append(try allocator.dupeZ(u8, line));
        }

        i += 1;
    }

    self.title = title.?;
    self.artist = artist.?;
    self.author = author.?;
    self.fumen_file_name = fumen_file_name.?;
    self.ranking_file_name = ranking_file_name.?;

    //i hate the look of this so much
    errdefer {
        for (self.comment) |comment| {
            allocator.free(comment);
        }

        allocator.free(self.comment);
    }

    self.comment = try comments.toOwnedSlice();

    var fumen_path = try path.realpathAlloc(allocator, self.fumen_file_name);
    defer allocator.free(fumen_path);

    var fumen_file = try std.fs.openFileAbsolute(fumen_path, .{});
    defer fumen_file.close();

    self.fumen = try Fumen.readFromFile(allocator, &fumen_file, path);
    errdefer self.fumen.deinit();

    return self;
}

pub fn readUTypingList(allocator: std.mem.Allocator) ![]Self {
    var list_file = try std.fs.cwd().openFile("UTyping_list.txt", .{});
    defer list_file.close();

    var reader = list_file.reader();

    var music_list = std.ArrayList(Self).init(allocator);
    errdefer {
        for (0..music_list.items.len) |i| {
            music_list.items[i].deinit();
        }
        music_list.deinit();
    }

    while (true) {
        var line = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 100) orelse break;
        defer allocator.free(line);

        //Normalize, aka remove \r and change `\` to `/`
        var normalized = try std.mem.replaceOwned(u8, allocator, if (line[line.len - 1] == '\r') line[0 .. line.len - 1] else line, &.{'\\'}, &.{'/'});
        defer allocator.free(normalized);

        var music_file = try std.fs.cwd().openFile(normalized, .{});
        defer music_file.close();

        var music_dir = try std.fs.cwd().openDir(std.fs.path.dirname(normalized) orelse "", .{});
        defer music_dir.close();

        var music = try readFromFile(allocator, music_dir, &music_file);

        try music_list.append(music);
    }

    return try music_list.toOwnedSlice();
}

const title_x = 40;
const title_y = (30 - 30 / 2);
const num_x = (Screen.display_width - 25);
const num_y = (60 - 44);
const artist_y = num_y;
const level_x = (Screen.display_width - 270);
const level_y = (60 - 22);
const author_x_f = (Screen.display_width - 30);
const author_y_f = level_y;

const achievement_x = (title_x - 25);
const achievement_y = (30 - 24 / 2);

pub fn draw(
    self: Self,
    render_state: Screen.RenderState,
    y: f32,
    brightness: f32,
    music_idx: usize,
    music_count: usize,
) !void {
    const title_state = Fontstash.Fontstash.State{
        .font = Fontstash.Mincho,
        .size = Fontstash.ptToPx(30),
        .alignment = .{
            .vertical = .top,
        },
    };

    const scaleVec = @as(Gfx.Vector2, @splat(render_state.gfx.scale));

    const color = Gfx.ColorF{ brightness, brightness, brightness, 1 };
    const title_width = (try render_state.fontstash.textBounds(self.title, title_state)).x2;

    const width_num: f32 = blk: { //draw right-aligned text for the index
        var context = Fontstash.Fontstash.WriterContext{
            .draw = false,
            .draw_position = .{ 0, 0 },
            .state = Fontstash.Normal,
        };
        context.state.size *= render_state.gfx.scale;

        var writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "{d}/{d}", .{ music_idx + 1, music_count });
        var bounds = context.bounds;
        //Adjust for resolution
        bounds.br /= @splat(render_state.gfx.scale);
        bounds.tl /= @splat(render_state.gfx.scale);
        context.draw_position = Gfx.Vector2{ num_x - bounds.br[0], num_y + y } * scaleVec;
        context.draw = true;
        context.state.color = color;
        writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "{d}/{d}", .{ music_idx + 1, music_count });
        break :blk bounds.br[0];
    };

    { //artist
        const width = (try render_state.fontstash.textBounds(self.artist, Fontstash.Normal)).x2;
        var x = (Screen.display_width - 150) - width * 2 / 3;

        var width_l = x - (title_x + title_width);
        var width_r = (num_x - width_num) - (x + width);

        if (width_l <= 20 or width_r <= 20) {
            x += (width_r - width_l) / 4;
        }

        if (width_l < 0 or width_l + width_r <= 0) {
            x = title_x + title_width;
        } else if (width_r < 0) {
            x += width_r;
        }

        var state = Fontstash.Normal;
        state.color = color;
        _ = try render_state.fontstash.drawText(.{ x, y + artist_y }, self.artist, state);
    }

    { //fumen author
        var fumen_author_color = color * @as(Gfx.ColorF, @splat(2)) / @as(Gfx.ColorF, @splat(3));
        fumen_author_color[3] = 1;

        var context = Fontstash.Fontstash.WriterContext{
            .draw = false,
            .draw_position = .{ 0, 0 },
            .state = Fontstash.Normal,
        };
        context.state.size *= render_state.gfx.scale;

        var writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "(譜面作成　{s})", .{self.author});
        var bounds = context.bounds;
        //Adjust for resolution
        bounds.br /= @splat(render_state.gfx.scale);
        bounds.tl /= @splat(render_state.gfx.scale);
        context.draw_position = Gfx.Vector2{ author_x_f - bounds.br[0], author_y_f + y } * scaleVec;
        context.draw = true;
        context.state.color = fumen_author_color;
        writer = try render_state.fontstash.context.writer(&context);
        try std.fmt.format(writer, "(譜面作成　{s})", .{self.author});
    }

    { //difficulty
        for (0..5) |i| {
            const star_color = if (self.level <= i) blk: {
                var tmp = color / @as(Gfx.ColorF, @splat(2));
                tmp[3] = 1;
                break :blk tmp;
            } else Gfx.ColorF{ brightness, brightness, 0, 1 };
            const str = if (self.level <= i) "☆" else "★";

            var state = Fontstash.Normal;
            state.color = star_color;
            _ = try render_state.fontstash.drawText(
                .{ level_x + 16 * @as(f32, @floatFromInt(i)), level_y + y },
                str,
                state,
            );
        }
    }

    { //achievement
        //TODO
    }

    var state = title_state;
    state.color = color;
    _ = try render_state.fontstash.drawText(.{ title_x, title_y + y }, self.title, state);
}

pub fn drawRanking(
    music: Self,
    render_state: Screen.RenderState,
    pos: Gfx.Vector2,
    ranking_pos: usize,
    rank_len: usize,
) !void {
    _ = music;
    _ = rank_len;
    _ = ranking_pos;
    _ = pos;
    _ = render_state;
}

pub fn drawComment(music: Self, render_state: Screen.RenderState, pos: Gfx.Vector2) !void {
    _ = music;
    _ = pos;
    _ = render_state;
}

pub fn drawPlayData(music: Self, render_state: Screen.RenderState, pos: Gfx.Vector2) !void {
    _ = music;
    _ = pos;
    _ = render_state;
}

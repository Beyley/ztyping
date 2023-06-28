//Copyright (c) 2023 Beyley Thomas <ep1cm1n10n123@gmail.com>
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.

const std = @import("std");
const builtin = @import("builtin");

const Gfx = @import("gfx.zig");

const Self = @This();

const c = @cImport({
    // @cDefine("STBTT_STATIC", "");
    @cInclude("stb_truetype.h");
});

pub const Rectangle = struct {
    tl: Gfx.Vector2u,
    br: Gfx.Vector2u,
};

pub const Rectanglei = struct {
    tl: Gfx.Vector2i,
    br: Gfx.Vector2i,
};

pub const RectangleF = struct {
    tl: Gfx.Vector2,
    br: Gfx.Vector2,
};

const CreateTextureFn = *const fn (
    user_ptr: ?*anyopaque,
    width: usize,
    height: usize,
) anyerror!void;
const UpdateTextureFn = *const fn (
    user_ptr: ?*anyopaque,
    rect: Rectangle,
    data: []const u8,
) anyerror!void;
const DrawFn = *const fn (
    user_ptr: ?*anyopaque,
    positions: []const Gfx.Vector2,
    tex_coords: []const Gfx.Vector2,
    colors: []const Gfx.ColorF,
) anyerror!void;
const DeleteFn = *const fn (user_ptr: ?*anyopaque) void;
const ResizeFn = *const fn (
    user_ptr: ?*anyopaque,
    width: usize,
    height: usize,
) anyerror!void;
const HandleErrorFn = *const fn (
    user_ptr: ?*anyopaque,
    err: anyerror,
) anyerror!void;

pub const Parameters = struct {
    pub const ZeroPosition = enum {
        top_left,
        bottom_left,
    };

    width: usize,
    height: usize,
    zero_position: ZeroPosition,
    user_ptr: ?*anyopaque,
    impl_create_texture: CreateTextureFn,
    impl_update_texture: UpdateTextureFn,
    impl_draw: DrawFn,
    impl_delete: DeleteFn,
    impl_resize: ResizeFn,
    impl_handle_error: HandleErrorFn,
};

pub const Atlas = struct {
    pub const AtlasNode = struct {
        x: usize,
        y: usize,
        width: usize,
    };

    pub const AtlasErrors = error{
        AtlasFull,
    };

    const SkylineNode = struct {
        pos: Gfx.Vector2u,
        width: usize,
    };

    width: usize,
    height: usize,
    ///A list of skyline nodes
    nodes: std.ArrayList(SkylineNode),
    ///The surface area that has been used
    used_surface_area: u64,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, width: usize, height: usize) !Atlas {
        var atlas = Atlas{
            .width = width,
            .height = height,
            .nodes = std.ArrayList(SkylineNode).init(allocator),
            .used_surface_area = 0,
            .allocator = allocator,
        };

        //Ensure that we have a reasonable amount of space already allocated
        try atlas.nodes.ensureUnusedCapacity(atlas_init_capacity);

        try atlas.nodes.append(.{
            .pos = .{ 0, 0 },
            .width = width,
        });

        return atlas;
    }

    ///Requests a new rect from the atlas
    pub fn getRect(self: *Atlas, width: usize, height: usize) !Gfx.Vector2u {
        std.debug.assert(width != 0);
        std.debug.assert(height != 0);

        var best_height: usize = std.math.maxInt(usize);
        var best_wasted_area: usize = std.math.maxInt(usize);

        var best_index: ?usize = null;

        var new_node: ?Rectangle = null;

        for (0..self.nodes.items.len) |i| {
            switch (self.rectangleFits(width, height, i)) {
                .no_fit => {},
                .fits => |fit| {
                    best_height = fit.y + height;
                    best_wasted_area = fit.wasted_area;
                    best_index = i;

                    new_node = Rectangle{
                        .tl = .{ self.nodes.items[i].pos[0], fit.y },
                        .br = .{ width, height },
                    };
                },
            }
        }

        //If no new node was found, return an AtlasFull error
        if (new_node) |node| {
            try self.addSkylineLevel(best_index.?, node);

            self.used_surface_area += width * height;

            //Return the top left position of the node
            return node.tl;
        } else {
            return AtlasErrors.AtlasFull;
        }
    }

    fn addSkylineLevel(self: *Atlas, index: usize, rect: Rectangle) !void {
        var new_node = SkylineNode{
            .pos = .{
                rect.tl[0],
                rect.tl[1] + rect.br[1],
            },
            .width = rect.br[0],
        };

        try self.nodes.insert(index, new_node);

        std.debug.assert(new_node.pos[0] + new_node.width <= self.width);
        std.debug.assert(new_node.pos[1] <= self.height);

        var i = index + 1;
        while (i < self.nodes.items.len) {
            var curr_node: *SkylineNode = &self.nodes.items[i];
            const last_node: SkylineNode = self.nodes.items[i - 1];

            std.debug.assert(last_node.pos[0] <= curr_node.pos[0]);

            if (curr_node.pos[0] < last_node.pos[0] + last_node.width) {
                const shrink = last_node.pos[0] + last_node.width - curr_node.pos[0];

                curr_node.pos[0] += shrink;
                //NOTE: the @min here is to prevent the number from going negative
                curr_node.width -= @min(curr_node.width, shrink);

                if (curr_node.width <= 0) {
                    _ = self.nodes.orderedRemove(i);
                    i -= 1;
                } else {
                    break;
                }
            } else {
                break;
            }

            i += 1;
        }

        self.mergeSkylines();
    }

    inline fn mergeSkylines(self: *Atlas) void {
        var i: usize = 0;
        while (i < self.nodes.items.len - 1) : (i += 1) {
            var curr_node: *SkylineNode = &self.nodes.items[i];
            var next_node: SkylineNode = self.nodes.items[i + 1];

            if (curr_node.pos[1] == next_node.pos[1]) {
                curr_node.width += next_node.width;

                _ = self.nodes.orderedRemove(i + 1);

                i -= 1;
            }
        }
    }

    pub fn reset(self: *Atlas, width: usize, height: usize) void {
        self.width = width;
        self.height = height;

        //Reset the node list
        self.nodes.clearRetainingCapacity();

        self.nodes.append(.{
            .pos = .{ 0, 0 },
            .width = width,
        }) catch unreachable;
    }

    fn rectangleFits(self: *Atlas, width: usize, height: usize, idx: usize) union(enum) {
        fits: struct {
            y: usize,
            wasted_area: u64,
        },
        no_fit: void,
    } {
        const node_idx = self.nodes.items[idx];

        //Get the X position of the item rectangle
        const x = node_idx.pos[0];

        //If the position of the node + width of the rect is wider than the altas width, it no fit
        if (x + width > self.width) {
            return .{ .no_fit = {} };
        }

        var width_left = width;

        var i = idx;

        var y = node_idx.pos[1];
        while (width_left > 0) {
            y = @max(y, self.nodes.items[i].pos[1]);
            if (y + height > self.height) {
                return .{ .no_fit = {} };
            }

            //NOTE: the @min here is to prevent the number from going negative
            width_left -= @min(self.nodes.items[i].width, width_left);

            i += 1;

            //Assert that we are still behind the end of the list, or that the width is less than or equal to 0
            std.debug.assert(i < self.nodes.items.len or width_left <= 0);
        }

        var wasted_area: u64 = 0;

        const rect_left = node_idx.pos[0];
        const rect_right = node_idx.pos[0] + node_idx.width;

        i = idx;
        while (i < self.nodes.items.len and self.nodes.items[i].pos[0] < rect_right) {
            var curr_node = self.nodes.items[i];

            //If the current node is outside of the rect,
            if (curr_node.pos[0] >= rect_right or curr_node.pos[0] + curr_node.width <= rect_left) {
                break;
            }

            var left_side = curr_node.pos[0];
            var right_side = @min(rect_right, left_side + curr_node.width);

            std.debug.assert(y >= curr_node.pos[1]);

            wasted_area += (right_side - left_side) * (y - curr_node.pos[1]);

            i += 1;
        }

        return .{
            .fits = .{
                .y = y,
                .wasted_area = wasted_area,
            },
        };
    }

    pub fn deinit(self: *Atlas) void {
        self.nodes.deinit();

        //Mark the underlying object as undefined
        self.* = undefined;
    }
};

pub const Alignment = struct {
    pub const Horizontal = enum {
        left,
        right,
        center,
    };

    pub const Vertical = enum {
        top,
        middle,
        bottom,
        baseline,
    };

    horizontal: Horizontal = .left,
    vertical: Vertical = .baseline,
};

pub const State = struct {
    font: []const u8,
    alignment: Alignment = .{},
    size: f32,
    color: Gfx.ColorF = Gfx.WhiteF,
    blur: f32 = 0,
    spacing: f32 = 0,
};

pub const Font = struct {
    pub const Glyph = struct {
        codepoint: u21,
        index: usize,
        next: ?usize,
        size: f32,
        blur: f32,
        rectangle: Rectangle,
        x_advance: f32,
        x_offset: f32,
        y_offset: f32,
    };

    font: c.stbtt_fontinfo,
    ascender: f32,
    descender: f32,
    lineh: f32,
    glyphs: std.ArrayList(Glyph),
    glyph_count: usize,
    fallbacks: std.ArrayList(*Font),
    lut: [hash_lut_size]?usize,
};

const scratch_buffer_size = 64000;
const atlas_init_capacity = 256;
const hash_lut_size = 256;
const vertex_count = 1024;

allocator: std.mem.Allocator,
fonts: std.StringHashMap(*Font),
parameters: Parameters,
scratch_buffer: []u8,
atlas: Atlas,
tex_cache: []u8,
dirty_rect: Rectangle,
width_texel: f32,
height_texel: f32,
vertices: [vertex_count]Gfx.Vector2,
tex_coords: [vertex_count]Gfx.Vector2,
colors: [vertex_count]Gfx.ColorF,
vertex_count: usize,

///Creates a new Fontstash context
pub fn create(allocator: std.mem.Allocator, params: Parameters) !*Self {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.* = .{
        .allocator = allocator,
        .fonts = std.StringHashMap(*Font).init(allocator),
        .parameters = params,
        .scratch_buffer = undefined,
        .atlas = undefined,
        .tex_cache = undefined,
        .dirty_rect = .{
            .tl = .{ params.width, params.height },
            .br = .{ 0, 0 },
        },
        .width_texel = 1 / @as(f32, @floatFromInt(params.width)),
        .height_texel = 1 / @as(f32, @floatFromInt(params.height)),
        .vertices = undefined,
        .tex_coords = undefined,
        .colors = undefined,
        .vertex_count = 0,
    };
    //Create our scratch buffer
    self.scratch_buffer = try allocator.alloc(u8, scratch_buffer_size);
    errdefer allocator.free(self.scratch_buffer);
    //Create our atlas object
    self.atlas = try Atlas.create(allocator, params.width, params.height);
    errdefer self.atlas.deinit();

    //Tell the implementation to create its texture
    try params.impl_create_texture(params.user_ptr, params.width, params.height);
    errdefer params.impl_delete(params.user_ptr);

    //Allocate the texture cache (aka the CPU texture stb_truetype writes to)
    self.tex_cache = try allocator.alloc(u8, params.width * params.height);
    errdefer allocator.free(self.tex_cache);

    //Clear the whole texture cache to `0`
    @memset(self.tex_cache, 0);

    //Add a 2x2 white rect at 0,0 for debug drawing
    try self.addWhiteRect(2, 2);

    return self;
}

fn getVerticalAlignment(self: *Self, font: Font, state: State) f32 {
    return switch (self.parameters.zero_position) {
        .top_left => switch (state.alignment.vertical) {
            .top => font.ascender * state.size,
            .middle => (font.ascender + font.descender) / 2 * state.size,
            .baseline => 0,
            .bottom => font.descender * state.size,
        },
        .bottom_left => switch (state.alignment.vertical) {
            .top => -font.ascender * state.size,
            .middle => -(font.ascender + font.descender) / 2 * state.size,
            .baseline => 0,
            .bottom => -font.descender * state.size,
        },
    };
}

fn hashInt(int: anytype) @TypeOf(int) {
    var a = int;
    @setRuntimeSafety(false);
    a += ~(a << 15);
    a ^= (a >> 10);
    a += (a << 3);
    a ^= (a >> 6);
    a += ~(a << 11);
    a ^= (a >> 16);
    @setRuntimeSafety(true);
    return a;
}

fn getGlyphIndex(font: *Font, codepoint: u21) usize {
    return @intCast(c.stbtt_FindGlyphIndex(&font.font, @intCast(codepoint)));
}

fn getGlyph(self: *Self, font: *Font, codepoint: u21, state: State) !*Font.Glyph {
    std.debug.assert(state.size >= 0.2);
    std.debug.assert(state.blur <= 20);

    var render_font = font;

    //Convert the blur into a pixel padding, 1blur = 10px
    var pad = @as(isize, @intFromFloat(state.blur * 10)) + 2;

    //Reset the scratch buffer usage
    self.scratch_buffer.len = 0;

    //Hash the codepoint
    var hash = hashInt(codepoint) & (hash_lut_size - 1);
    //Get the index of the codepoint from the hash
    var i = font.lut[hash];

    while (i != null) {
        //Get the glyph
        var glyph = &font.glyphs.items[i.?];

        //If the codepoint, size, and blur matches, return the cached glyph
        if (glyph.codepoint == codepoint and glyph.size == state.size and glyph.blur == state.blur) {
            return glyph;
        }

        //Check the next glyph
        i = glyph.next;
    }

    //If we could find find the glyph, create it
    var glyph_index = getGlyphIndex(font, codepoint);

    //Try to find the glyph in the fallback fonts if there was none in the main font
    if (glyph_index == 0) {
        for (font.fallbacks.items) |fallback_font| {
            var fallback_index = getGlyphIndex(fallback_font, codepoint);

            //If the fallback font has the glyph, render that index and font instead
            if (fallback_index != 0) {
                glyph_index = fallback_index;
                render_font = fallback_font;
                break;
            }
        }
    }

    var scale = c.stbtt_ScaleForPixelHeight(&render_font.font, state.size);

    var advance: c_int = undefined;
    var left_side_bearing: c_int = undefined;
    c.stbtt_GetGlyphHMetrics(
        &render_font.font,
        @intCast(glyph_index),
        &advance,
        &left_side_bearing,
    );
    var x0c: c_int = undefined;
    var y0c: c_int = undefined;
    var x1c: c_int = undefined;
    var y1c: c_int = undefined;
    c.stbtt_GetGlyphBitmapBox(
        &render_font.font,
        @intCast(glyph_index),
        scale,
        scale,
        &x0c,
        &y0c,
        &x1c,
        &y1c,
    );

    var x0: isize = @intCast(x0c);
    var y0: isize = @intCast(y0c);
    var x1: isize = @intCast(x1c);
    var y1: isize = @intCast(y1c);

    var glyph_width: usize = @intCast(x1 - x0 + @as(isize, @intCast(pad)) * 2);
    var glyph_height: usize = @intCast(y1 - y0 + @as(isize, @intCast(pad)) * 2);

    var glyph_position = self.atlas.getRect(glyph_width, glyph_height) catch |err| blk: {
        if (err == Atlas.AtlasErrors.AtlasFull) {
            try self.parameters.impl_handle_error(self.parameters.user_ptr, err);
            break :blk try self.atlas.getRect(glyph_width, glyph_height);
        } else {
            return err;
        }
    };

    var glyph = Font.Glyph{
        .blur = state.blur,
        .codepoint = codepoint,
        .index = glyph_index,
        .rectangle = Rectangle{
            .tl = glyph_position,
            .br = glyph_position + Gfx.Vector2u{ glyph_width, glyph_height },
        },
        .size = state.size,
        .x_advance = scale * @as(f32, @floatFromInt(advance)),
        .x_offset = @floatFromInt(x0 - pad),
        .y_offset = @floatFromInt(y0 - pad),
        .next = font.lut[hash],
    };
    try render_font.glyphs.append(glyph);

    //Insert the char into the hash lookup
    font.lut[hash] = font.glyphs.items.len - 1;

    //Rasterize
    var dst_ptr = &self.tex_cache[(glyph.rectangle.tl[0] + @as(usize, @intCast(pad))) + (glyph.rectangle.tl[1] + @as(usize, @intCast(pad))) * self.parameters.width];
    c.stbtt_MakeGlyphBitmap(
        &render_font.font,
        dst_ptr,
        @intCast(@as(isize, @intCast(glyph_width)) - pad * 2),
        @intCast(@as(isize, @intCast(glyph_height)) - pad * 2),
        @intCast(self.parameters.width),
        scale,
        scale,
        @intCast(glyph_index),
    );

    //Make sure there is a 1 pixel empty border
    // const glyph_tl_byte_offset = glyph.rectangle.tl[0] + (glyph.rectangle.tl[1]) * self.parameters.width;
    // const glyph_bl_byte_offset = glyph.rectangle.tl[0] + (glyph.rectangle.br[1] - 1) * self.parameters.width;
    //Set the top row to 0
    // @memset(self.tex_cache[glyph_tl_byte_offset .. glyph_tl_byte_offset + glyph_width - 1], 0);
    //Set the bottom row to 0
    // @memset(self.tex_cache[glyph_bl_byte_offset .. glyph_bl_byte_offset + glyph_width - 1], 0);

    // for (0..glyph_height - 2) |j| {
    //     var y = j + 1;

    //     //Set the left pixel
    //     self.tex_cache[y * self.parameters.width + glyph.rectangle.tl[0]] = 0;
    //     self.tex_cache[y * self.parameters.width + glyph.rectangle.tl[0] + glyph_width - 1] = 0;
    // }

    //Blur
    if (state.blur > 0) {
        self.scratch_buffer.len = 0;
        var blur_dst_offset: usize = @intCast(glyph.rectangle.tl[0] + glyph.rectangle.tl[1] * self.parameters.width);
        _ = blur_dst_offset;

        // TODO
        // self.blur(blur_dst_offset, glyph_width, glyph_height, self.parameters.width, state.blur);
    }

    //Update the dirty rect
    self.dirty_rect.tl = @min(self.dirty_rect.tl, glyph.rectangle.tl);
    self.dirty_rect.br = @max(self.dirty_rect.br, glyph.rectangle.br);

    //Return a reference to the last item that was just added to the glyph list
    return &render_font.glyphs.items[render_font.glyphs.items.len - 1];
}

const Quad = struct {
    rect: RectangleF,
    tex: RectangleF,
};

fn getQuad(
    self: *Self,
    font: *Font,
    prev_glyph_index: ?usize,
    glyph: *Font.Glyph,
    scale: f32,
    spacing: f32,
    x: *f32,
    y: *f32,
) Quad {
    //If the previous glyph is specified,
    if (prev_glyph_index) |previous_glyph_index| {
        //Get the kern advnace from the previous glyph to the current glyph
        const advance = @as(f32, @floatFromInt(c.stbtt_GetGlyphKernAdvance(
            &font.font,
            @intCast(previous_glyph_index),
            @intCast(glyph.index),
        ))) * scale;
        //Apply the advance to the x coord
        //TODO: make a way to disable the rounding here
        x.* += @round(advance + spacing + 0.5);
    }

    // Each glyph has a 2px border to allow good interpolation,
    // one pixel to prevent leaking, and one to allow good interpolation for rendering.
    // Inset the texture region by one pixel for correct interpolation.
    var x_offset = glyph.x_offset + 1;
    var y_offset = glyph.y_offset + 1;
    //Inset the rect
    var rect = RectangleF{
        .tl = Gfx.vector2UToF(glyph.rectangle.tl) + Gfx.Vector2{ 1, 1 },
        .br = Gfx.vector2UToF(glyph.rectangle.br) - Gfx.Vector2{ 1, 1 },
    };

    var quad = switch (self.parameters.zero_position) {
        .top_left => blk: {
            //TODO: make a way to disable rounding here
            var rounded_x = @round(x.* + x_offset);
            var rounded_y = @round(y.* + y_offset);

            break :blk Quad{
                .rect = RectangleF{
                    .tl = Gfx.Vector2{ rounded_x, rounded_y },
                    .br = Gfx.Vector2{ rounded_x, rounded_y } + rect.br - rect.tl,
                },
                .tex = RectangleF{
                    .tl = rect.tl * Gfx.Vector2{ self.width_texel, self.height_texel },
                    .br = rect.br * Gfx.Vector2{ self.width_texel, self.height_texel },
                },
            };
        },
        .bottom_left => blk: {
            var rounded_x = @round(x.* + x_offset);
            var rounded_y = @round(y.* - y_offset);

            break :blk Quad{
                .rect = RectangleF{
                    .tl = .{ rounded_x, rounded_y },
                    .br = .{
                        rounded_x + rect.tl[0] - rect.br[0],
                        rounded_y - rect.br[1] + rect.tl[1],
                    },
                },
                .tex = RectangleF{
                    .tl = rect.tl * Gfx.Vector2{ self.width_texel, self.height_texel },
                    .br = rect.br * Gfx.Vector2{ self.width_texel, self.height_texel },
                },
            };
        },
    };

    //TODO: make a way to disable rounding here
    x.* += @round(glyph.x_advance + 0.5);

    return quad;
}

///Returns the bounds and advance of the text
pub fn textBounds(
    self: *Self,
    position: Gfx.Vector2,
    text: []const u8,
    state: State,
) !struct {
    advance: f32,
    bounds: RectangleF,
} {
    var draw_position = position;

    var advance: f32 = 0;

    var font = self.fonts.get(state.font) orelse return error.MissingFont;

    var scale = c.stbtt_ScaleForPixelHeight(&font.font, state.size);

    //Align vertically
    draw_position[1] += self.getVerticalAlignment(font.*, state);

    var min = draw_position;
    var max = draw_position;

    var x_start = draw_position[0];

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    var previous_glyph_index: ?usize = null;
    var next = iter.nextCodepoint();
    while (next != null) : (next = iter.nextCodepoint()) {
        var codepoint: u21 = next.?;

        var glyph = try self.getGlyph(font, codepoint, state);

        var quad = self.getQuad(
            font,
            previous_glyph_index,
            glyph,
            scale,
            state.spacing,
            &draw_position[0],
            &draw_position[1],
        );

        if (quad.rect.tl[0] < min[0]) min[0] = quad.rect.tl[0];
        if (quad.rect.br[0] > max[0]) max[0] = quad.rect.br[0];
        switch (self.parameters.zero_position) {
            .top_left => {
                if (quad.rect.tl[1] < min[1]) min[1] = quad.rect.tl[1];
                if (quad.rect.br[1] > max[1]) max[1] = quad.rect.br[1];
            },
            .bottom_left => {
                if (quad.rect.br[1] < min[1]) min[1] = quad.rect.br[1];
                if (quad.rect.tl[1] > max[1]) max[1] = quad.rect.tl[1];
            },
        }

        previous_glyph_index = glyph.index;
    }

    advance = draw_position[0] - x_start;

    //Align horizontally
    switch (state.alignment.horizontal) {
        .left => {
            //do nothing in this case
        },
        .right => {
            min[0] -= advance;
            max[0] -= advance;
        },
        .center => {
            min[0] -= advance * 0.5;
            max[0] -= advance * 0.5;
        },
    }

    //Update the font in the dictionary
    try self.fonts.put(state.font, font);

    return .{
        .advance = advance,
        .bounds = RectangleF{
            .tl = min,
            .br = max,
        },
    };
}

///Draws the specified text with the specified state
pub fn drawText(self: *Self, position: Gfx.Vector2, text: []const u8, state: State) !Gfx.Vector2 {
    var draw_position = position;

    var font = self.fonts.get(state.font) orelse return error.MissingFont;

    var scale = c.stbtt_ScaleForPixelHeight(&font.font, state.size);

    //Align horizontally
    switch (state.alignment.horizontal) {
        .left => {
            //do nothing in this case
        },
        .right => {
            const width = (try self.textBounds(draw_position, text, state)).advance;
            draw_position[0] -= width;
        },
        .center => {
            const width = (try self.textBounds(draw_position, text, state)).advance;
            draw_position[0] -= width * 0.5;
        },
    }
    //Align vertically
    draw_position[1] += self.getVerticalAlignment(font.*, state);

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    var previous_glyph_index: ?usize = null;
    var next: ?u21 = iter.nextCodepoint();
    while (next != null) : (next = iter.nextCodepoint()) {
        var codepoint = next.?;

        var glyph = try self.getGlyph(font, codepoint, state);

        var quad = self.getQuad(font, previous_glyph_index, glyph, scale, state.spacing, &draw_position[0], &draw_position[1]);

        if (self.vertex_count + 6 > vertex_count) {
            try self.flush();
        }

        self.addVertex(quad.rect.tl, quad.tex.tl, state.color);
        self.addVertex(quad.rect.br, quad.tex.br, state.color);
        self.addVertex(.{ quad.rect.br[0], quad.rect.tl[1] }, .{ quad.tex.br[0], quad.tex.tl[1] }, state.color);

        self.addVertex(quad.rect.tl, quad.tex.tl, state.color);
        self.addVertex(.{ quad.rect.tl[0], quad.rect.br[1] }, .{ quad.tex.tl[0], quad.tex.br[1] }, state.color);
        self.addVertex(quad.rect.br, quad.tex.br, state.color);
    }

    try self.flush();

    return draw_position;
}

inline fn addVertex(self: *Self, pos: Gfx.Vector2, tex: Gfx.Vector2, col: Gfx.ColorF) void {
    std.debug.assert(self.vertex_count < vertex_count);

    self.vertices[self.vertex_count] = pos;
    self.tex_coords[self.vertex_count] = tex;
    self.colors[self.vertex_count] = col;

    self.vertex_count += 1;
}

fn flush(self: *Self) !void {
    if (self.dirty_rect.tl[0] < self.dirty_rect.br[0] and self.dirty_rect.tl[1] < self.dirty_rect.br[1]) {
        try self.parameters.impl_update_texture(
            self.parameters.user_ptr,
            self.dirty_rect,
            self.tex_cache,
        );

        self.dirty_rect.tl = .{
            self.parameters.width,
            self.parameters.height,
        };
        self.dirty_rect.br = .{ 0, 0 };
    }

    try self.parameters.impl_draw(
        self.parameters.user_ptr,
        self.vertices[0..self.vertex_count],
        self.tex_coords[0..self.vertex_count],
        self.colors[0..self.vertex_count],
    );

    self.vertex_count = 0;

    //In safe modes, we should set these to undefined, so valgrind can catch undefined accesses
    if (std.debug.runtime_safety) {
        @memset(&self.vertices, undefined);
        @memset(&self.tex_coords, undefined);
        @memset(&self.colors, undefined);
    }
}

///Adds a white rectangle to the atlas
fn addWhiteRect(self: *Self, width: usize, height: usize) !void {
    var rect_pos = try self.atlas.getRect(width, height);

    for (0..height) |y| {
        const start_pos = rect_pos[0] + y * self.parameters.width;

        var row = self.tex_cache[start_pos .. start_pos + width];
        @memset(row, 0);
    }

    self.dirty_rect.tl = @min(self.dirty_rect.tl, rect_pos);
    self.dirty_rect.br = @max(self.dirty_rect.br, rect_pos + Gfx.Vector2u{ width, height });
}

///Gets the vertical metrics relating to the current state
pub fn verticalMetrics(self: *Self, state: State) struct {
    ascender: f32,
    descender: f32,
    lineh: f32,
} {
    var font: *Font = self.fonts.get(state.font) orelse unreachable;

    return .{
        .ascender = font.ascender * state.size,
        .descender = font.descender * state.size,
        .lineh = font.lineh * state.size,
    };
}

pub fn resetAtlas(self: *Self, width: usize, height: usize) !void {
    try self.flush();

    if (width != self.parameters.width or height != self.parameters.height) {
        try self.parameters.impl_resize(self.parameters.user_ptr, width, height);

        //Set the new width/height of the atlas
        self.parameters.width = width;
        self.parameters.height = height;
        //Set the new width/height texel size
        self.width_texel = 1.0 / @as(f32, @floatFromInt(width));
        self.height_texel = 1.0 / @as(f32, @floatFromInt(height));

        self.atlas.width = width;
        self.atlas.height = height;

        self.tex_cache = try self.allocator.realloc(self.tex_cache, width * height);
    }

    self.atlas.reset(width, height);

    //Set the CPU texture cache to 0
    @memset(self.tex_cache, 0);

    self.dirty_rect.tl = .{ width, height };
    self.dirty_rect.br = .{ 0, 0 };

    var fon_iter = self.fonts.valueIterator();
    var next: ?**Font = fon_iter.next();
    while (next != null) : (next = fon_iter.next()) {
        var font = next.?.*;

        //Clear the glyph array
        font.glyphs.clearRetainingCapacity();

        //Clear the LUT
        @memset(&font.lut, null);
    }

    try self.addWhiteRect(2, 2);
}

///Adds a new font from a slice of data containing a TTF font.
///
///Caller is responsible for freeing `data`.
pub fn addFontMem(
    self: *Self,
    comptime name: []const u8,
    data: [:0]const u8,
) !*Font {
    var font = try self.allocator.create(Font);
    errdefer self.allocator.destroy(font);
    font.* = Font{
        .lut = undefined,
        .ascender = undefined,
        .descender = undefined,
        .fallbacks = std.ArrayList(*Font).init(self.allocator),
        .font = std.mem.zeroes(c.stbtt_fontinfo),
        .lineh = undefined,
        .glyphs = std.ArrayList(Font.Glyph).init(self.allocator),
        .glyph_count = 0,
    };

    //memset the lookup table to null
    @memset(&font.lut, null);

    if (c.stbtt_InitFont(&font.font, data.ptr, 0) == 0) {
        return error.StbInitFontFailed;
    }

    var ascent: c_int = undefined;
    var descent: c_int = undefined;
    var line_gap: c_int = undefined;
    c.stbtt_GetFontVMetrics(
        &font.font,
        &ascent,
        &descent,
        &line_gap,
    );

    var fh = ascent - descent;

    font.ascender = @as(f32, @floatFromInt(ascent)) / @as(f32, @floatFromInt(fh));
    font.descender = @as(f32, @floatFromInt(descent)) / @as(f32, @floatFromInt(fh));
    font.lineh = @as(f32, @floatFromInt(fh + line_gap)) / @as(f32, @floatFromInt(fh));

    try self.fonts.put(name, font);

    return font;
}

///Destroys a fontstash context
pub fn deinit(self: *Self) void {
    self.parameters.impl_delete(self.parameters.user_ptr);

    var iter = self.fonts.valueIterator();
    var next: ?**Font = iter.next();

    while (next != null) : (next = iter.next()) {
        var font = next.?;

        font.*.glyphs.deinit();

        self.allocator.destroy(font.*);
    }

    self.fonts.deinit();

    self.scratch_buffer.len = scratch_buffer_size;

    //Free the scratch buffer
    self.allocator.free(self.scratch_buffer);

    self.atlas.deinit();

    self.allocator.free(self.tex_cache);

    const allocator = self.allocator;

    //Free the contents
    self.* = undefined;

    //Destroy the underlying item
    allocator.destroy(self);
}

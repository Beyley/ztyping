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

    width: usize,
    height: usize,
    nodes: []AtlasNode,
    node_count: usize,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, width: usize, height: usize) !Atlas {
        var atlas = Atlas{
            .width = width,
            .height = height,
            .nodes = try allocator.alloc(AtlasNode, atlas_init_nodes),
            .node_count = atlas_init_nodes,
            .allocator = allocator,
        };

        //Set that we are using 1 node
        atlas.nodes.len = 1;

        //Init root node
        atlas.nodes[0] = .{
            .x = 0,
            .y = 0,
            .width = width,
        };

        return atlas;
    }

    pub fn rectFits(self: *Atlas, idx: usize, width: usize, height: usize) ?usize {
        var i = idx;

        const node = self.nodes[i];

        var x = node.x;
        var y = node.y;

        //If the node X pos + rect width goes past the end of the atlas, it does not fit, return null
        if (x + width > self.width) {
            return null;
        }

        var space_left: isize = @intCast(isize, width);

        while (space_left > 0) : (i += 1) {
            //If there are no more nodes to check, it does not fit, return null
            if (i == self.nodes.len) {
                return null;
            }

            const curr_node = self.nodes[i];

            y = @max(y, curr_node.y);

            //If the node Y position + height exceeds the atlas height, it does not fit, return null
            if (y + height > self.height) {
                return null;
            }

            //Subtract the space left by the width of the current node
            space_left -= @intCast(isize, curr_node.width);
        }

        return y;
    }

    pub fn insertNode(self: *Atlas, idx: usize, x: usize, y: usize, width: usize) !void {
        if (self.nodes.len + 1 > self.node_count) {
            //Store the variable here, so we can restore it later
            var used_nodes = self.nodes.len;

            //Set the length of the slice to the amount of nodes, this is to satisfy the allocator
            self.nodes.len = self.node_count;

            //Double the amount of nodes
            self.node_count *= 2;

            //Assert that we are going to create *some* amount of nodes
            std.debug.assert(self.node_count != 0);

            //Realloc the nodes to the new size
            self.nodes = try self.allocator.realloc(self.nodes, self.node_count);

            //Restore the length to the real used count
            self.nodes.len = used_nodes;
        }

        var i = self.nodes.len;

        //Increment the amount of used nodes
        self.nodes.len += 1;

        //Move all the nodes in front of this index forward, to make room
        while (i > idx) : (i -= 1) {
            self.nodes[i] = self.nodes[i - 1];
        }

        //Set the node to the values
        self.nodes[idx] = .{
            .x = x,
            .y = y,
            .width = width,
        };
    }

    pub fn removeNode(self: *Atlas, idx: usize) void {
        std.debug.assert(self.nodes.len > 0);

        var i = idx;
        //Move all the nodes in front of the index backward, to fill the empty space
        while (i < self.nodes.len - 1) : (i += 1) {
            self.nodes[i] = self.nodes[i + 1];
        }

        //Mark the now-unused node as undefined
        self.nodes[self.nodes.len - 1] = undefined;

        //Decrement the amount of used nodes
        self.nodes.len -= 1;
    }

    pub fn addSkylineLevel(self: *Atlas, idx: usize, x: usize, y: usize, width: usize, height: usize) !void {
        //Insert a new node
        try self.insertNode(idx, x, y + height, width);

        var i: usize = idx + 1;
        //Delete the skyline segments that fall under the shadow of the new segment
        while (i < self.nodes.len) : (i += 1) {
            var curr_node = &self.nodes[i];
            const last_node = self.nodes[i - 1];

            //If the current node is to the left left or is inside of the last node (horizontally)
            if (curr_node.x < last_node.x + last_node.width) {
                //Get the amount to shrink the current node's width
                var shrink = last_node.x + last_node.width - curr_node.x;

                //Move the node to the right,
                curr_node.x += shrink;
                //Shrink the node
                if (shrink > curr_node.width) {
                    curr_node.width = 0;
                } else {
                    curr_node.width -= shrink;
                }
                // curr_node.width -= @min(shrink, curr_node.width);

                //If the node's width becomes 0, then get it outta here!
                if (curr_node.width <= 0) {
                    self.removeNode(i);
                    i -= 1;
                }
                //If the node's width is greater than 0, then break out
                else {
                    break;
                }
            }
            //If the current node is to the right of the last node, break out
            else {
                break;
            }
        }

        i = 0;
        //Merge same height skyline segments that are next to each other.
        while (i < self.nodes.len - 1) : (i += 1) {
            var curr_node = &self.nodes[i];
            var next_node = self.nodes[i + 1];

            //If the y positions match,
            if (curr_node.y == next_node.y) {
                //Add the next node's width to the current node
                curr_node.width += next_node.width;

                //Remove the next node, as it has been merged into the current node
                self.removeNode(i + 1);
                i -= 1;
            }
        }
    }

    pub fn addRect(self: *Atlas, width: usize, height: usize) !Gfx.Vector2u {
        var bestw: usize = self.width;
        var besth: usize = self.height;
        var besti: ?usize = null;

        var bestx: usize = undefined;
        var besty: usize = undefined;
        var i: usize = 0;

        for (self.nodes) |node| {
            var fits = self.rectFits(i, width, height);

            if (fits) |y| {
                if (y + width < besth or (y + width == besth and node.width < bestw)) {
                    besti = i;
                    bestw = node.width;
                    besth = y + height;
                    bestx = node.x;
                    besty = y;
                }
            }
        }

        if (besti == null) {
            return AtlasErrors.AtlasFull;
        }

        try self.addSkylineLevel(besti.?, bestx, besty, width, height);

        //Return the best x and y
        return .{ bestx, besty };
    }

    pub fn deinit(self: *Atlas, allocator: std.mem.Allocator) void {
        self.nodes.len = self.node_count;

        //Free the list of nodes
        allocator.free(self.nodes);

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
const atlas_init_nodes = 256;
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
        .width_texel = 1 / @floatFromInt(f32, params.width),
        .height_texel = 1 / @floatFromInt(f32, params.height),
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
    errdefer self.atlas.deinit(allocator);

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
    return @intCast(usize, c.stbtt_FindGlyphIndex(&font.font, @intCast(c_int, codepoint)));
}

fn getGlyph(self: *Self, font: *Font, codepoint: u21, state: State) !*Font.Glyph {
    std.debug.assert(state.size >= 0.2);
    std.debug.assert(state.blur <= 20);

    var render_font = font;

    //Convert the blur into a pixel padding, 1blur = 10px
    var pad = @intFromFloat(isize, state.blur * 10) + 2;

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
        @intCast(c_int, glyph_index),
        &advance,
        &left_side_bearing,
    );
    var x0c: c_int = undefined;
    var y0c: c_int = undefined;
    var x1c: c_int = undefined;
    var y1c: c_int = undefined;
    c.stbtt_GetGlyphBitmapBox(
        &render_font.font,
        @intCast(c_int, glyph_index),
        scale,
        scale,
        &x0c,
        &y0c,
        &x1c,
        &y1c,
    );

    var x0 = @intCast(isize, x0c);
    var y0 = @intCast(isize, y0c);
    var x1 = @intCast(isize, x1c);
    var y1 = @intCast(isize, y1c);

    var glyph_width = @intCast(usize, x1 - x0 + @intCast(isize, pad) * 2);
    var glyph_height = @intCast(usize, y1 - y0 + @intCast(isize, pad) * 2);

    var glyph_position = self.atlas.addRect(glyph_width, glyph_height) catch |err| blk: {
        if (err == Atlas.AtlasErrors.AtlasFull) {
            // self.handleError(); //TODO
            break :blk try self.atlas.addRect(glyph_width, glyph_height);
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
        .x_advance = scale * @floatFromInt(f32, advance),
        .x_offset = @floatFromInt(f32, x0 - pad),
        .y_offset = @floatFromInt(f32, y0 - pad),
        .next = font.lut[hash],
    };
    try render_font.glyphs.append(glyph);

    //Insert the char into the hash lookup
    font.lut[hash] = font.glyphs.items.len - 1;

    //Rasterize
    var dst_ptr = &self.tex_cache[(glyph.rectangle.tl[0] + @intCast(usize, pad)) + glyph.rectangle.tl[1] * self.parameters.width];
    c.stbtt_MakeGlyphBitmap(
        &render_font.font,
        dst_ptr,
        @intCast(c_int, @intCast(isize, glyph_width) - pad * 2),
        @intCast(c_int, @intCast(isize, glyph_height) - pad * 2),
        @intCast(c_int, self.parameters.width),
        scale,
        scale,
        @intCast(c_int, glyph_index),
    );

    //Make sure there is a 1 pixel empty border
    const offset = glyph.rectangle.tl[0] + glyph.rectangle.tl[1] * self.parameters.width;
    for (0..glyph_height) |y| {
        self.tex_cache[offset + (y * self.parameters.width)] = 0;
        self.tex_cache[offset + (glyph_width - 1 + y * self.parameters.width)] = 0;
    }
    for (0..glyph_width) |x| {
        self.tex_cache[offset + x] = 0;
        self.tex_cache[offset + (x + (glyph_width - 1) * self.parameters.width)] = 0;
    }

    //Blur
    if (state.blur > 0) {
        self.scratch_buffer.len = 0;
        var blur_dst_offset = @intCast(usize, glyph.rectangle.tl[0] + glyph.rectangle.tl[1] * self.parameters.width);
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
        const advance = @floatFromInt(f32, c.stbtt_GetGlyphKernAdvance(
            &font.font,
            @intCast(c_int, previous_glyph_index),
            @intCast(c_int, glyph.index),
        )) * scale;
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
    var rect_pos = try self.atlas.addRect(width, height);

    for (0..height) |y| {
        const start_pos = rect_pos[0] + y * self.parameters.width;

        var row = self.tex_cache[start_pos .. start_pos + width];
        @memset(row, 0);
    }

    self.dirty_rect.tl = @min(self.dirty_rect.tl, rect_pos);
    self.dirty_rect.br = @max(self.dirty_rect.br, rect_pos + Gfx.Vector2u{ width, height });
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
    _ = fh;

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

    self.atlas.deinit(self.allocator);

    self.allocator.free(self.tex_cache);

    const allocator = self.allocator;

    //Free the contents
    self.* = undefined;

    //Destroy the underlying item
    allocator.destroy(self);
}

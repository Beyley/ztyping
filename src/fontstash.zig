const std = @import("std");

const c = @import("main.zig").c;

const Gfx = @import("gfx.zig");
const Renderer = @import("renderer.zig");

const Self = @This();

pub const Fontstash = @import("fontstash_impl.zig");

pub const Mincho = "mincho";
pub const Gothic = "gothic";

gfx: *Gfx,
renderer: Renderer,
context: *Fontstash,
gothic: *Fontstash.Font,
mincho: *Fontstash.Font,
texture: ?Gfx.Texture = null,
allocator: std.mem.Allocator,
font_size: f32 = 0,

pub fn init(self: *Self, gfx: *Gfx, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;
    self.gfx = gfx;

    self.context = try Fontstash.create(allocator, Fontstash.Parameters{
        .zero_position = .top_left,
        .width = 4096,
        .height = 4096,
        .user_ptr = self,
        .impl_create_texture = create,
        .impl_update_texture = update,
        .impl_draw = draw,
        .impl_delete = delete,
        .impl_resize = resize,
        .impl_handle_error = handleError,
    });
    errdefer self.context.deinit();

    self.renderer = try Renderer.init(allocator, gfx, self.texture.?);
    errdefer self.renderer.deinit();

    var gothic_data = @embedFile("fonts/gothic.ttf");
    var mincho_data = @embedFile("fonts/mincho.ttf");

    self.gothic = try self.context.addFontMem("gothic", gothic_data);
    self.mincho = try self.context.addFontMem("mincho", mincho_data);
}

pub fn verticalMetrics(self: *Self, state: Fontstash.State) struct { ascender: f32, descender: f32, line_height: f32 } {
    var internal_state = state;
    internal_state.size *= self.gfx.scale;

    var metrics = self.context.verticalMetrics(internal_state);

    return .{
        .ascender = metrics.ascender / self.gfx.scale,
        .descender = metrics.descender / self.gfx.scale,
        //NOTE: fontstash seems to give us double the line height that is correct,
        //      so lets just divide by 2 to get an actually useful number...
        .line_height = metrics.lineh / 2 / self.gfx.scale,
    };
}

pub fn drawText(self: *Self, position: Gfx.Vector2, text: []const u8, state: Fontstash.State) !void {
    var internal_state = state;
    internal_state.size *= self.gfx.scale;

    _ = try self.context.drawText(
        position * Gfx.Vector2{
            self.gfx.scale,
            self.gfx.scale,
        },
        text,
        internal_state,
    );
}

pub fn ptToPx(pt: f32) f32 {
    return pt / (4.0 / 3.0);
}

const Bounds = extern struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
};

pub fn textBounds(self: *Self, text: []const u8, state: Fontstash.State) !Bounds {
    var bounds = try self.context.textBounds(.{ 0, 0 }, text, state);

    return .{
        .x1 = bounds.bounds.tl[0],
        .y1 = bounds.bounds.tl[1],
        .x2 = bounds.bounds.br[0],
        .y2 = bounds.bounds.br[1],
    };
}

pub fn deinit(self: *Self) void {
    self.renderer.deinit();
    self.context.deinit();
}

fn toSelf(ptr: *anyopaque) *Self {
    return @ptrCast(@alignCast(ptr));
}

fn create(self_ptr: ?*anyopaque, width: usize, height: usize) anyerror!void {
    var self = toSelf(self_ptr.?);

    self.texture = try self.gfx.device.createBlankTexture(@intCast(width), @intCast(height));
    try self.texture.?.createBindGroup(self.gfx.device, self.gfx.sampler, self.gfx.bind_group_layouts);
}

fn resize(self_ptr: ?*anyopaque, width: usize, height: usize) anyerror!void {
    var self = toSelf(self_ptr.?);

    if (self.texture == null) {
        unreachable;
    }

    std.debug.print("resizing texture to {d}/{d}...\n", .{ width, height });

    //Recreate the texture with the new width
    self.texture = try self.gfx.device.createBlankTexture(@intCast(width), @intCast(height));
    //Recreate the texture with the new height
    try self.texture.?.createBindGroup(self.gfx.device, self.gfx.sampler, self.gfx.bind_group_layouts);

    self.renderer.texture = self.texture.?;
}

fn handleError(self_ptr: ?*anyopaque, err: anyerror) anyerror!void {
    var self = toSelf(self_ptr.?);

    std.debug.print("atlas error!\n", .{});

    //TODO: when at atlas error happens, end the current draw call, and begin a new one, somehow

    //If the atlas is full,
    if (err == Fontstash.Atlas.AtlasErrors.AtlasFull) {
        //Reset the atlas with the same size, as the default size is already *way* big enough, so just resetting it will work
        try self.context.resetAtlas(@min(self.context.parameters.width * 2, 16384), @min(self.context.parameters.height * 2, 16384));

        return;
    }
}

fn update(self_ptr: ?*anyopaque, rect: Fontstash.Rectangle, data: []const u8) anyerror!void {
    var self = toSelf(self_ptr.?);

    var rect_x = rect.tl[0];
    var rect_y = rect.tl[1];
    var rect_wh = rect.br - rect.tl;
    var w = rect_wh[0];
    var h = rect_wh[1];

    var full = try self.allocator.alloc(Gfx.ColorB, @intCast(w * h));
    defer self.allocator.free(full);

    //TODO: can we SIMD this?
    // for (0..w * h) |i| {
    //     full[i] = .{ 255, 255, 255, data[i] };
    // }

    for (0..h) |y| {
        for (0..w) |x| {
            full[y * w + x] = .{ 255, 255, 255, data[(rect_y + y) * self.texture.?.width + x + rect_x] };
        }
    }

    self.gfx.queue.writeTexture(
        self.texture.?,
        Gfx.ColorB,
        full,
        c.WGPUOrigin3D{
            .x = @intCast(rect_x),
            .y = @intCast(rect_y),
            .z = 0,
        },
        c.WGPUExtent3D{
            .width = @intCast(w),
            .height = @intCast(h),
            .depthOrArrayLayers = 1,
        },
    );
}

fn draw(
    self_ptr: ?*anyopaque,
    positions: []const Gfx.Vector2,
    tex_coords: []const Gfx.Vector2,
    colors: []const Gfx.ColorF,
) anyerror!void {
    var self = toSelf(self_ptr.?);

    //Assert these lengths are all the same
    std.debug.assert(positions.len == tex_coords.len and tex_coords.len == colors.len);

    var reserved = try self.renderer.reserve(@intCast(positions.len), @intCast(positions.len));

    var scale = Gfx.Vector2{
        self.gfx.scale,
        self.gfx.scale,
    };

    for (0..positions.len) |i| {
        reserved.vtx[i] = Gfx.Vertex{
            .position = positions[i] / scale,
            .tex_coord = tex_coords[i],
            .vertex_col = colors[i],
        };

        reserved.idx[@intCast(i)] = @intCast(i + reserved.idx_offset);
    }
}

fn delete(self_ptr: ?*anyopaque) void {
    var self = toSelf(self_ptr.?);

    if (self.texture != null) {
        self.texture.?.deinit();
    }
}

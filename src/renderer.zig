const std = @import("std");

const c = @import("main.zig").c;

const Gfx = @import("gfx.zig");

const Self = @This();

gfx: Gfx,
arena_allocator: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,
///The main texture of the renderer, aka the atlas
texture: Gfx.Texture,
vtx_buf: Gfx.Buffer,
idx_buf: Gfx.Buffer,

pub fn init(allocator: std.mem.Allocator, gfx: Gfx, texture: Gfx.Texture) !Self {
    var self: Self = Self{
        .gfx = gfx,
        .allocator = undefined,
        .arena_allocator = std.heap.ArenaAllocator.init(allocator),
        .texture = texture,
        .vtx_buf = try gfx.device.createBuffer(Gfx.Vertex, 4, .vertex),
        .idx_buf = try gfx.device.createBuffer(u16, 6, .index),
    };
    self.allocator = self.arena_allocator.allocator();

    return self;
}

pub fn clearState(self: *Self) void {
    _ = self;
}

pub fn begin(self: *Self) void {
    _ = self;
}

pub fn end(self: *Self) void {
    _ = self;
}

pub fn draw(self: *Self, encoder: *Gfx.RenderPassEncoder) !void {
    self.gfx.queue.writeBuffer(self.vtx_buf, 0, Gfx.Vertex, &.{
        Gfx.Vertex{
            .position = .{ 0, 0 },
            .tex_coord = .{ 0, 0 },
            .vertex_col = .{ 0, 1, 0, 1 },
        },
        Gfx.Vertex{
            .position = .{ 500, 0 },
            .tex_coord = .{ 1, 0 },
            .vertex_col = .{ 1, 0, 0, 1 },
        },
        Gfx.Vertex{
            .position = .{ 0, 500 },
            .tex_coord = .{ 0, 1 },
            .vertex_col = .{ 0, 0, 1, 1 },
        },
        Gfx.Vertex{
            .position = .{ 500, 500 },
            .tex_coord = .{ 1, 1 },
            .vertex_col = .{ 1, 0, 1, 1 },
        },
    });

    self.gfx.queue.writeBuffer(self.idx_buf, 0, u16, &.{ 0, 2, 1, 1, 2, 3 });

    //Set the pipeline
    encoder.setPipeline(self.gfx.render_pipeline);
    encoder.setBindGroup(0, self.gfx.projection_matrix_bind_group, &.{});
    encoder.setBindGroup(1, self.texture.bind_group.?, &.{});

    encoder.setVertexBuffer(0, self.vtx_buf, 0, self.vtx_buf.size);
    encoder.setIndexBuffer(self.idx_buf, .uint16, 0, self.idx_buf.size);
    encoder.drawIndexed(6, 1, 0, 0, 0);
}

pub fn deinit(self: *Self) void {
    self.arena_allocator.deinit();
}

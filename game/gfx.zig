const std = @import("std");
const builtin = @import("builtin");
const core = @import("mach").core;
const math = @import("mach").math;
const img = @import("zigimg");

const Config = @import("config.zig");

const Self = @This();

pub const Vector2 = @Vector(2, f32);
pub const Vector2u = @Vector(2, usize);
pub const Vector2i = @Vector(2, isize);
///RGBA f32 color
pub const ColorF = @Vector(4, f32);
///RGBA u8 color
pub const ColorB = @Vector(4, u8);
///A rectangle with its bounds specified as u32
pub const RectU = @Vector(4, u32);
pub const RectF = @Vector(4, f32);

pub const Vector2One: Vector2 = @splat(@as(f32, 1));
pub const Vector2Zero: Vector2 = @splat(@as(f32, 0));

pub fn vector2FToU(orig: Vector2) Vector2u {
    return .{
        @intFromFloat(orig[0]),
        @intFromFloat(orig[1]),
    };
}

pub fn vector2UToF(orig: Vector2u) Vector2 {
    return .{
        @floatFromInt(orig[0]),
        @floatFromInt(orig[1]),
    };
}

pub fn vector2IToF(orig: Vector2i) Vector2 {
    return .{
        @floatFromInt(orig[0]),
        @floatFromInt(orig[1]),
    };
}

pub fn vector2UToI(orig: Vector2u) Vector2i {
    return .{
        @intCast(orig[0]),
        @intCast(orig[1]),
    };
}

pub fn vector2IToU(orig: Vector2i) Vector2u {
    return .{
        @intCast(orig[0]),
        @intCast(orig[1]),
    };
}

pub const WhiteF = ColorF{ 1, 1, 1, 1 };
pub const RedF = ColorF{ 1, 0, 0, 1 };
pub const GreenF = ColorF{ 0, 1, 0, 1 };
pub const BlueF = ColorF{ 0, 0, 1, 1 };

pub const WhiteB = ColorB{ 255, 255, 255, 255 };
pub const RedB = ColorB{ 255, 0, 0, 255 };
pub const GreenB = ColorB{ 0, 255, 0, 255 };
pub const BlueB = ColorB{ 0, 0, 255, 255 };

pub fn colorBToF(orig: ColorB) ColorF {
    var f = ColorF{
        @floatFromInt(orig[0]),
        @floatFromInt(orig[1]),
        @floatFromInt(orig[2]),
        @floatFromInt(orig[3]),
    };

    f /= @splat(@as(f32, 255));

    return f;
}

pub const Error = error{
    UnableToCreateTextureBindGroup,
    UnableToCreateSampler,
    UnableToCreateBindGroupForTexture,
    UnableToFinishCommandEncoder,
    UnableToBeginRenderPass,
    UnableToGetSwapChainTextureView,
    UnableToRetrieveWindowWMInfo,
    MissingSDLX11,
    MissingSDLWayland,
    MissingSDLWindows,
    MissingSDLCocoa,
    UnknownWindowSubsystem,
    SurfaceCreationError,
    UnableToRequestAdapter,
    UnableToRequestDevice,
    UnableToCreateSwapChain,
    UnableToGetDeviceQueue,
    UnableToCreateShaderModule,
    UnableToCreateTextureSamplerBindGroupLayout,
    UnableToCreateProjectionMatrixBindGroupLayout,
    UnableToCreateRenderPipeline,
    UnableToCreateCommandEncoder,
    UnableToCreateDeviceTexture,
    UnableToCreateTextureView,
    UnableToCreateBuffer,
    InstanceCreationError,
};

shader: *core.gpu.ShaderModule = undefined,
bind_group_layouts: BindGroupLayouts = undefined,
render_pipeline_layout: *core.gpu.PipelineLayout = undefined,
render_pipeline: *core.gpu.RenderPipeline = undefined,
projection_matrix_buffer: *core.gpu.Buffer = undefined,
projection_matrix_bind_group: *core.gpu.BindGroup = undefined,
sampler: *core.gpu.Sampler = undefined,
scale: f32 = 1.0,
viewport: RectU = undefined,

pub fn init(config: Config) !Self {
    var self: Self = Self{
        .scale = config.window_scale,
    };

    const width: u32 = @intFromFloat(640 * config.window_scale);
    const height: u32 = @intFromFloat(480 * config.window_scale);

    core.setSizeLimit(.{
        .min = .{ .width = width, .height = height },
        .max = .{ .width = width, .height = height },
    });

    //Update the viewport
    self.viewport = RectU{ 0, 0, @intCast(width), @intCast(height) };

    //Setup the error callbacks
    self.setErrorCallbacks();

    //Create our shader module
    self.shader = try createShaderModule();

    //Create the bind group layouts
    self.bind_group_layouts = try createBindGroupLayouts();

    //Create the render pipeline layout
    self.render_pipeline_layout = createPipelineLayout(self.bind_group_layouts);

    //Create the render pipeline
    self.render_pipeline = createRenderPipeline(self.render_pipeline_layout, self.shader);

    //Create the projection matrix buffer
    self.projection_matrix_buffer = try createBuffer(math.Mat4x4, 1, .{ .uniform = true, .copy_dst = true });
    std.debug.print("got proj matrix buffer {*}\n", .{self.projection_matrix_buffer});

    //Create the projection matrix bind group
    self.projection_matrix_bind_group = core.device.createBindGroup(&core.gpu.BindGroup.Descriptor.init(.{
        .label = "Projection Matrix Bind Group",
        .layout = self.bind_group_layouts.projection_matrix,
        .entries = &.{
            core.gpu.BindGroup.Entry.buffer(
                0,
                self.projection_matrix_buffer,
                0,
                @sizeOf(math.Mat4x4),
                // REENABLE THIS TO FIX SYSGPU
                // @sizeOf(math.Mat4x4),
            ),
        },
    }));
    std.debug.print("got projection matrix bind group {*}\n", .{self.projection_matrix_bind_group});

    self.sampler = core.device.createSampler(&core.gpu.Sampler.Descriptor{
        .label = "Sampler",
        .compare = .undefined,
        .mipmap_filter = .linear,
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .lod_max_clamp = 0,
        .lod_min_clamp = 0,
        .max_anisotropy = 1,
    });

    std.debug.print("got sampler {*}\n", .{self.sampler});

    return self;
}

pub fn deinit(self: *Self) void {
    self.projection_matrix_buffer.release();
    self.bind_group_layouts.deinit();
    self.render_pipeline.release();
    self.render_pipeline_layout.release();
    self.shader.release();

    self.shader = undefined;
    self.render_pipeline_layout = undefined;
}

pub const Texture = struct {
    tex: *core.gpu.Texture,
    view: *core.gpu.TextureView,
    width: u32,
    height: u32,
    bind_group: ?*core.gpu.BindGroup = null,

    ///De-inits the texture, freeing its resources
    pub fn deinit(self: *Texture) void {
        self.view.release();
        self.tex.release();
        if (self.bind_group) |_| {
            self.bind_group.?.release();
        }

        self.tex = undefined;
        self.view = undefined;
    }

    ///Creates the bind group for the texture, not called implicitly as textures may be used for other purposes
    pub fn createBindGroup(self: *Texture, sampler: *core.gpu.Sampler, bind_group_layouts: BindGroupLayouts) !void {
        self.bind_group = core.device.createBindGroup(&core.gpu.BindGroup.Descriptor.init(.{
            .label = "Texture bind group",
            .entries = &.{
                .{
                    .binding = 0,
                    .texture_view = self.view,
                    .size = 0,
                },
                .{
                    .binding = 1,
                    .sampler = sampler,
                    .size = 0,
                },
            },
            .layout = bind_group_layouts.texture_sampler,
        }));

        std.debug.print("got texture bind group {*}\n", .{self.bind_group});
    }
};

pub const BindGroupLayouts = struct {
    texture_sampler: *core.gpu.BindGroupLayout,
    projection_matrix: *core.gpu.BindGroupLayout,

    pub fn deinit(self: *BindGroupLayouts) void {
        self.texture_sampler.release();
        self.projection_matrix.release();
    }
};

pub fn createShaderModule() !*core.gpu.ShaderModule {
    const module = core.device.createShaderModuleWGSL("Shader", @embedFile("shader.wgsl"));

    std.debug.print("got shader module {*}\n", .{module});

    return module;
}
pub fn createBindGroupLayouts() !BindGroupLayouts {
    var layouts: BindGroupLayouts = undefined;

    layouts.texture_sampler = core.device.createBindGroupLayout(&core.gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Texture/Sampler bind group layout",
        .entries = &.{
            core.gpu.BindGroupLayout.Entry.texture(
                0,
                .{ .fragment = true },
                .float,
                .dimension_2d,
                false,
            ),
            core.gpu.BindGroupLayout.Entry.sampler(
                1,
                .{ .fragment = true },
                .filtering,
            ),
        },
    }));
    layouts.projection_matrix = core.device.createBindGroupLayout(&core.gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Projection matrix bind group layout",
        .entries = &.{
            core.gpu.BindGroupLayout.Entry.buffer(
                0,
                .{ .vertex = true },
                .uniform,
                false,
                @sizeOf(math.Mat4x4),
            ),
        },
    }));

    std.debug.print("got texture/sampler bind group layout {*}\n", .{layouts.texture_sampler});
    std.debug.print("got projection matrix bind group layout {*}\n", .{layouts.projection_matrix});

    return layouts;
}

pub fn createPipelineLayout(bind_group_layouts: BindGroupLayouts) *core.gpu.PipelineLayout {
    const layout = core.device.createPipelineLayout(&core.gpu.PipelineLayout.Descriptor.init(.{
        .label = "Pipeline Layout",
        .bind_group_layouts = &.{
            bind_group_layouts.projection_matrix,
            bind_group_layouts.texture_sampler,
        },
    }));

    std.debug.print("got pipeline layout {*}\n", .{layout});

    return layout;
}

pub fn createRenderPipeline(layout: *core.gpu.PipelineLayout, shader: *core.gpu.ShaderModule) *core.gpu.RenderPipeline {
    const pipeline = core.device.createRenderPipeline(&core.gpu.RenderPipeline.Descriptor{
        .label = "Render Pipeline",
        .layout = layout,
        .vertex = .{
            .module = shader,
            .entry_point = "vs_main",
            .buffer_count = 3,
            .buffers = @as([]const core.gpu.VertexBufferLayout, &.{
                core.gpu.VertexBufferLayout.init(.{
                    .array_stride = @sizeOf(Vector2),
                    .step_mode = .vertex,
                    .attributes = &.{
                        .{
                            .format = .float32x2,
                            .offset = 0,
                            .shader_location = 0,
                        },
                    },
                }),
                core.gpu.VertexBufferLayout.init(.{
                    .array_stride = @sizeOf(Vector2),
                    .step_mode = .vertex,
                    .attributes = &.{
                        .{
                            .format = .float32x2,
                            .offset = 0,
                            .shader_location = 1,
                        },
                    },
                }),
                core.gpu.VertexBufferLayout.init(.{
                    .array_stride = @sizeOf(ColorF),
                    .step_mode = .vertex,
                    .attributes = &.{
                        .{
                            .format = .float32x4,
                            .offset = 0,
                            .shader_location = 2,
                        },
                    },
                }),
            }).ptr,
        },
        .fragment = &core.gpu.FragmentState.init(.{
            .module = shader,
            .targets = &.{
                core.gpu.ColorTargetState{
                    .blend = &.{
                        .color = .{
                            .src_factor = .src_alpha,
                            .dst_factor = .one_minus_src_alpha,
                            .operation = .add,
                        },
                        .alpha = .{
                            .src_factor = .one,
                            .dst_factor = .one_minus_src_alpha,
                            .operation = .add,
                        },
                    },
                    .format = core.descriptor.format,
                    .write_mask = core.gpu.ColorWriteMaskFlags.all,
                },
            },
            .entry_point = "fs_main",
        }),
        .primitive = .{
            .cull_mode = .back,
            .topology = .triangle_list,
            .front_face = .ccw,
        },
    });

    std.debug.print("got render pipeline {*}\n", .{pipeline});

    return pipeline;
}

pub fn createTexture(allocator: std.mem.Allocator, data: []const u8) !Texture {
    var stream: img.Image.Stream = .{ .const_buffer = std.io.fixedBufferStream(data) };

    var image = try img.qoi.QOI.readImage(allocator, &stream);
    defer image.deinit();

    const tex_format = core.gpu.Texture.Format.rgba8_unorm_srgb;

    const tex = core.device.createTexture(&core.gpu.Texture.Descriptor.init(.{
        .label = "Texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .dimension = .dimension_2d,
        .size = .{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .depth_or_array_layers = 1,
        },
        .format = tex_format,
        .mip_level_count = 1,
        .sample_count = 1,
        .view_formats = &.{tex_format},
    }));

    const view = tex.createView(&core.gpu.TextureView.Descriptor{
        .label = "Texture View",
        .format = tex_format,
        .dimension = .dimension_2d,
        .base_mip_level = 0,
        .base_array_layer = 0,
        .mip_level_count = 1,
        .array_layer_count = 1,
        .aspect = .all,
    });

    core.queue.writeTexture(&.{
        .texture = tex,
        .mip_level = 0,
        .origin = .{},
        .aspect = .all,
    }, &.{
        .bytes_per_row = @intCast(image.width * @sizeOf(img.color.Rgba32)),
        .rows_per_image = @intCast(image.height),
    }, &.{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .depth_or_array_layers = 1,
    }, image.pixels.rgba32);

    const texture = Texture{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .tex = tex,
        .view = view,
    };

    return texture;
}

pub fn createBlankTexture(width: u32, height: u32) !Texture {
    const tex_format = core.gpu.Texture.Format.rgba8_unorm_srgb;

    const tex = core.device.createTexture(&core.gpu.Texture.Descriptor.init(.{
        .label = "Texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .dimension = .dimension_2d,
        .size = .{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        },
        .format = tex_format,
        .mip_level_count = 1,
        .sample_count = 1,
        .view_formats = &.{tex_format},
    }));

    const view = tex.createView(&core.gpu.TextureView.Descriptor{
        .label = "Texture View",
        .format = tex_format,
        .dimension = .dimension_2d,
        .base_mip_level = 0,
        .base_array_layer = 0,
        .mip_level_count = 1,
        .array_layer_count = 1,
        .aspect = .all,
    });

    const texture = Texture{
        .width = width,
        .height = height,
        .tex = tex,
        .view = view,
    };

    return texture;
}

pub fn createBuffer(comptime contents_type: type, count: u64, buffer_type: core.gpu.Buffer.UsageFlags) !*core.gpu.Buffer {
    const size: u64 = @intCast(@sizeOf(contents_type) * count);

    var usage = buffer_type;
    usage.copy_dst = true;

    const buffer = core.device.createBuffer(&core.gpu.Buffer.Descriptor{
        .label = "Buffer",
        .usage = usage,
        .mapped_at_creation = .false,
        .size = size,
    });

    std.debug.print("got buffer {*}\n", .{buffer});

    return buffer;
}

pub fn setErrorCallbacks(self: *Self) void {
    _ = self; // autofix
    core.device.setUncapturedErrorCallback({}, uncapturedError);

    std.debug.print("setup wgpu device callbacks\n", .{});
}

inline fn uncapturedError(ctx: void, error_type: core.gpu.ErrorType, message: [*:0]const u8) void {
    _ = ctx; // autofix

    std.debug.print("Got uncaptured error {s} with message {s}\n", .{ @tagName(error_type), std.mem.span(message) });
    // @panic("uncaptured wgpu error");
}

// fn deviceLost(reason: c.WGPUDeviceLostReason, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
//     _ = user_data;

//     std.debug.print("Device lost! reason {d} with message {s}\n", .{ reason, std.mem.span(message) });
//     @panic("device lost");
// }

pub fn updateProjectionMatrixBuffer(self: *Self) void {
    var w: c_int = 0;
    var h: c_int = 0;

    w = 640;
    h = 480;

    const mat = orthographicOffCenter(
        0,
        @floatFromInt(w),
        0,
        @floatFromInt(h),
        0,
        1,
    );

    core.queue.writeBuffer(self.projection_matrix_buffer, 0, &[_]math.Mat4x4{mat});
}

pub fn orthographicOffCenter(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) math.Mat4x4 {
    std.debug.assert(!std.math.approxEqAbs(f32, far, near, 0.001));

    const r = 1 / (far - near);

    return math.mat4x4(
        &math.vec4(2 / (right - left), 0.0, 0.0, 0.0),
        &math.vec4(0.0, 2 / (top - bottom), 0.0, 0.0),
        &math.vec4(0.0, 0.0, r, 0.0),
        &math.vec4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), -r * near, 1.0),
    );
}

pub const UVs = struct {
    tl: Vector2,
    tr: Vector2,
    bl: Vector2,
    br: Vector2,
};

const Atlas = @import("content/atlas.zig");
pub fn getTexUVsFromAtlas(comptime name: []const u8) UVs {
    return getTexUVsFromAtlasPadding(name, 0);
}

pub fn getTexUVsFromAtlasPadding(comptime name: []const u8, comptime padding: comptime_float) UVs {
    var info = @field(Atlas, name);

    info.x += padding;
    info.y += padding;
    info.w -= padding * 2;
    info.h -= padding * 2;

    return .{
        .tl = .{
            info.x / Atlas.atlas_width,
            info.y / Atlas.atlas_height,
        },
        .tr = .{
            (info.x + info.w) / Atlas.atlas_width,
            info.y / Atlas.atlas_height,
        },
        .bl = .{
            info.x / Atlas.atlas_width,
            (info.y + info.h) / Atlas.atlas_height,
        },
        .br = .{
            (info.x + info.w) / Atlas.atlas_width,
            (info.y + info.h) / Atlas.atlas_height,
        },
    };
}

pub fn getTexSizeFromAtlas(comptime name: []const u8) Vector2 {
    const info = @field(Atlas, name);

    return .{ info.w, info.h };
}

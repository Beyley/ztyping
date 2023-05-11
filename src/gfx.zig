const std = @import("std");
const builtin = @import("builtin");
const c = @import("main.zig").c;
const zmath = @import("zmath");
const img = @import("zigimg");

const Self = @This();

instance: Instance = undefined,
surface: Surface = undefined,
adapter: Adapter = undefined,
device: Device = undefined,
queue: Queue = undefined,
shader: c.WGPUShaderModule = null,
bind_group_layouts: BindGroupLayouts = undefined,
render_pipeline_layout: c.WGPUPipelineLayout = null,
render_pipeline: c.WGPURenderPipeline = null,
swap_chain: ?SwapChain = undefined,
//TODO: wrap this into a `UniformBuffer` object
projection_matrix_buffer: Buffer = undefined,
projection_matrix_bind_group: c.WGPUBindGroup = null,
sampler: c.WGPUSampler = null,

pub fn init(window: *c.SDL_Window) !Self {
    var self: Self = Self{};

    //Create the webgpu instance
    self.instance = try createInstance();

    //Create the webgpu surface
    self.surface = try self.instance.createSurface(window);

    //Request an adapter
    self.adapter = try self.instance.requestAdapter(self.surface);

    //Request a device
    self.device = try self.adapter.requestDevice();

    //Get the queue
    self.queue = try self.device.getQueue();

    //Setup the error callbacks
    self.setErrorCallbacks();

    //Create our shader module
    self.shader = try self.device.createShaderModule();

    //Get the surface format
    var preferred_surface_format = self.surface.getPreferredFormat(self.adapter);

    //Create the bind group layouts
    self.bind_group_layouts = try self.device.createBindGroupLayouts();

    //Create the render pipeline layout
    self.render_pipeline_layout = try self.device.createPipelineLayout(self.bind_group_layouts);

    //Create the render pipeline
    self.render_pipeline = try self.device.createRenderPipeline(self.render_pipeline_layout, self.shader, preferred_surface_format);

    //Create the swapchain
    self.swap_chain = try self.device.createSwapChainOptimal(self.adapter, self.surface, window);

    //Create the projection matrix buffer
    self.projection_matrix_buffer = try self.device.createBuffer(@sizeOf(zmath.Mat), .uniform);
    // self.projection_matrix_buffer = try self.device.createUniformBuffer(@sizeOf(zmath.Mat), "Projection Matrix Buffer");

    //Create the projection matrix bind group
    self.projection_matrix_bind_group = c.wgpuDeviceCreateBindGroup(self.device.c, &c.WGPUBindGroupDescriptor{
        .nextInChain = null,
        .label = "Projection Matrix BindGroup",
        .layout = self.bind_group_layouts.projection_matrix,
        .entryCount = 1,
        .entries = &c.WGPUBindGroupEntry{
            .nextInChain = null,
            .binding = 0,
            .buffer = self.projection_matrix_buffer.c,
            .size = @sizeOf(zmath.Mat),
            .offset = 0,
            .sampler = null,
            .textureView = null,
        },
    }) orelse return error.UnableToCreateTextureBindGroup;
    std.debug.print("got projection matrix bind group 0x{x}\n", .{@ptrToInt(self.projection_matrix_bind_group.?)});

    self.sampler = c.wgpuDeviceCreateSampler(self.device.c, &c.WGPUSamplerDescriptor{
        .nextInChain = null,
        .label = "Sampler",
        .compare = c.WGPUCompareFunction_Undefined,
        .mipmapFilter = c.WGPUMipmapFilterMode_Linear,
        .magFilter = c.WGPUFilterMode_Linear,
        .minFilter = c.WGPUFilterMode_Linear,
        .addressModeU = c.WGPUAddressMode_ClampToEdge,
        .addressModeV = c.WGPUAddressMode_ClampToEdge,
        .addressModeW = c.WGPUAddressMode_ClampToEdge,
        .lodMaxClamp = 0,
        .lodMinClamp = 0,
        .maxAnisotropy = 1,
    }) orelse return error.UnableToCreateSampler;
    std.debug.print("got sampler 0x{x}\n", .{@ptrToInt(self.sampler.?)});

    return self;
}

pub fn deinit(self: *Self) void {
    self.projection_matrix_buffer.deinit();
    self.bind_group_layouts.deinit();
    c.wgpuPipelineLayoutDrop(self.render_pipeline_layout);
    c.wgpuRenderPipelineDrop(self.render_pipeline);
    if (self.swap_chain) |swap_chain| {
        swap_chain.deinit();
    }
    c.wgpuShaderModuleDrop(self.shader);
    self.device.deinit();
    self.adapter.deinit();
    self.surface.deinit();
    self.instance.deinit();

    self.shader = null;
    self.render_pipeline = null;
    self.render_pipeline_layout = null;
}

pub const RenderPassEncoder = struct {
    c: c.WGPURenderPassEncoder,

    pub fn setPipeline(self: RenderPassEncoder, pipeline: c.WGPURenderPipeline) void {
        c.wgpuRenderPassEncoderSetPipeline(self.c, pipeline);
    }

    pub fn end(self: RenderPassEncoder) void {
        c.wgpuRenderPassEncoderEnd(self.c);
    }

    pub fn setBindGroup(self: *RenderPassEncoder, groupIndex: u32, group: c.WGPUBindGroup, dynamic_offsets: []const u32) void {
        c.wgpuRenderPassEncoderSetBindGroup(self.c, groupIndex, group, @intCast(u32, dynamic_offsets.len), dynamic_offsets.ptr);
    }
};

pub const Texture = struct {
    tex: c.WGPUTexture,
    view: c.WGPUTextureView,
    bind_group: ?c.WGPUBindGroup,

    pub fn deinit(self: Texture) void {
        c.wgpuTextureViewDrop(self.view);
        c.wgpuTextureDrop(self.tex);
        if (self.bind_group) |bind_group| {
            c.wgpuBindGroupDrop(bind_group);
        }
    }
    pub fn createBindGroup(self: *Texture, device: Device, sampler: c.WGPUSampler, bind_group_layouts: BindGroupLayouts) !void {
        self.bind_group = c.wgpuDeviceCreateBindGroup(device.c, &c.WGPUBindGroupDescriptor{
            .label = "Texture Bind Group",
            .nextInChain = 0,
            .entries = @as([]const c.WGPUBindGroupEntry, &.{
                c.WGPUBindGroupEntry{
                    .nextInChain = null,
                    .binding = 0,
                    .textureView = self.view,
                    .buffer = null,
                    .offset = 0,
                    .size = 0,
                    .sampler = null,
                },
                c.WGPUBindGroupEntry{
                    .nextInChain = null,
                    .binding = 1,
                    .textureView = null,
                    .buffer = null,
                    .offset = 0,
                    .size = 0,
                    .sampler = sampler,
                },
            }).ptr,
            .entryCount = 2,
            .layout = bind_group_layouts.texture_sampler,
        }) orelse return error.UnableToCreateBindGroupForTexture;

        std.debug.print("got texture bind group 0x{x}\n", .{@ptrToInt(self.bind_group.?)});
    }
};

pub const BindGroupLayouts = struct {
    texture_sampler: c.WGPUBindGroupLayout,
    projection_matrix: c.WGPUBindGroupLayout,
    pub fn deinit(self: *BindGroupLayouts) void {
        c.wgpuBindGroupLayoutDrop(self.texture_sampler);
        c.wgpuBindGroupLayoutDrop(self.projection_matrix);

        //Clear them to null, so a proper error gets thrown wgpu side if they are re-used
        self.texture_sampler = null;
        self.projection_matrix = null;
    }
};

pub const CommandEncoder = struct {
    c: c.WGPUCommandEncoder,

    pub fn finish(self: CommandEncoder, descriptor: *const c.WGPUCommandBufferDescriptor) !c.WGPUCommandBuffer {
        return c.wgpuCommandEncoderFinish(self.c, descriptor) orelse error.UnableToFinishCommandEncoder;
    }

    pub fn beginRenderPass(self: *CommandEncoder, color_attachment: c.WGPUTextureView) !RenderPassEncoder {
        return .{
            .c = c.wgpuCommandEncoderBeginRenderPass(self.c, &c.WGPURenderPassDescriptor{
                .label = "Render Pass Encoder",
                .colorAttachmentCount = 1,
                .colorAttachments = &c.WGPURenderPassColorAttachment{
                    .view = color_attachment,
                    .loadOp = c.WGPULoadOp_Clear,
                    .storeOp = c.WGPUStoreOp_Store,
                    .clearValue = c.WGPUColor{
                        .r = 0,
                        .g = 1,
                        .b = 0,
                        .a = 1,
                    },
                    .resolveTarget = null,
                },
                .depthStencilAttachment = null,
                .occlusionQuerySet = null,
                .timestampWriteCount = 0,
                .timestampWrites = null,
                .nextInChain = null,
            }) orelse return error.UnableToBeginRenderPass,
        };
    }
};

pub const SwapChain = struct {
    c: c.WGPUSwapChain,

    pub fn deinit(self: SwapChain) void {
        c.wgpuSwapChainDrop(self.c);
    }

    pub fn swapChainPresent(self: SwapChain) void {
        c.wgpuSwapChainPresent(self.c);
    }

    pub fn getCurrentSwapChainTexture(self: SwapChain) !c.WGPUTextureView {
        return c.wgpuSwapChainGetCurrentTextureView(self.c) orelse error.UnableToGetSwapChainTextureView;
    }
};

pub const Surface = struct {
    c: c.WGPUSurface,

    pub fn deinit(self: *Surface) void {
        c.wgpuSurfaceDrop(self.c);

        self.c = null;
    }

    pub fn getPreferredFormat(self: Surface, adapter: Adapter) c.WGPUTextureFormat {
        return c.wgpuSurfaceGetPreferredFormat(self.c, adapter.c);
    }
};

pub const Instance = struct {
    c: c.WGPUInstance,

    pub fn deinit(self: *Instance) void {
        c.wgpuInstanceDrop(self.c);

        self.c = null;
    }

    pub fn createSurface(self: Instance, window: *c.SDL_Window) !Surface {
        var info: c.SDL_SysWMinfo = undefined;
        c.SDL_GetVersion(&info.version);
        var result = c.SDL_GetWindowWMInfo(window, &info);

        if (result == c.SDL_FALSE) {
            return error.UnableToRetrieveWindowWMInfo;
        }

        var descriptor: c.WGPUSurfaceDescriptor = .{
            .nextInChain = null,
            .label = "Surface",
        };
        if (info.subsystem == c.SDL_SYSWM_X11) {
            if (@hasDecl(c, "SDL_VIDEO_DRIVER_X11")) {
                descriptor.nextInChain = @ptrCast([*c]c.WGPUChainedStruct, &c.WGPUSurfaceDescriptorFromXlibWindow{
                    .chain = .{
                        .sType = c.WGPUSType_SurfaceDescriptorFromXlibWindow,
                        .next = null,
                    },
                    .display = info.info.x11.display,
                    .window = @intCast(u32, info.info.x11.window),
                });
            } else {
                return error.MissingSDLX11;
            }
        } else if (info.subsystem == c.SDL_SYSWM_WAYLAND) {
            if (@hasDecl(c, "SDL_VIDEO_DRIVER_WAYLAND")) {
                descriptor.nextInChain = @ptrCast([*c]c.WGPUChainedStruct, &c.WGPUSurfaceDescriptorFromWaylandSurface{
                    .chain = .{
                        .sType = c.WGPUSType_SurfaceDescriptorFromWaylandSurface,
                        .next = null,
                    },
                    .display = info.info.wayland.display,
                    .surface = info.info.wayland.surface,
                });
            } else {
                return error.MissingSDLWayland;
            }
        } else {
            return error.UnknownWindowSubsystem;
        }

        var surface = c.wgpuInstanceCreateSurface(self.c, &descriptor);

        std.debug.print("got surface 0x{x}\n", .{@ptrToInt(surface.?)});

        return .{ .c = surface orelse return error.SurfaceCreationError };
    }

    pub fn requestAdapter(self: Instance, surface: Surface) !Adapter {
        var adapter: c.WGPUAdapter = undefined;

        c.wgpuInstanceRequestAdapter(self.c, &c.WGPURequestAdapterOptions{
            .compatibleSurface = surface.c,
            .nextInChain = null,
            .powerPreference = c.WGPUPowerPreference_HighPerformance,
            .forceFallbackAdapter = false,
        }, handleAdapterCallback, @ptrCast(*anyopaque, &adapter));

        std.debug.print("got adapter 0x{x}\n", .{@ptrToInt(adapter.?)});

        return .{ .c = adapter orelse return error.UnableToRequestAdapter };
    }
};

pub const Adapter = struct {
    c: c.WGPUAdapter,

    pub fn deinit(self: *Adapter) void {
        c.wgpuAdapterDrop(self.c);

        self.c = null;
    }

    pub fn requestDevice(self: Adapter) !Device {
        var device: c.WGPUDevice = undefined;

        c.wgpuAdapterRequestDevice(self.c, &c.WGPUDeviceDescriptor{
            .label = "Device",
            .requiredFeaturesCount = 0,
            .requiredFeatures = null,
            .requiredLimits = null,
            .defaultQueue = c.WGPUQueueDescriptor{
                .nextInChain = null,
                .label = "Default Queue",
            },
            .nextInChain = null,
        }, handleDeviceCallback, @ptrCast(*anyopaque, &device));

        std.debug.print("got device 0x{x}\n", .{@ptrToInt(device.?)});

        return .{ .c = device orelse return error.UnableToRequestDevice };
    }
};

pub const Queue = struct {
    c: c.WGPUQueue,

    pub fn writeBuffer(self: Queue, buffer: Buffer, offset: u64, data: *anyopaque, size: usize) void {
        c.wgpuQueueWriteBuffer(self.c, buffer.c, offset, data, size);
    }

    pub fn submit(self: Queue, buffers: []const c.WGPUCommandBuffer) void {
        c.wgpuQueueSubmit(self.c, @intCast(u32, buffers.len), buffers.ptr);
    }
};

pub const Device = struct {
    c: c.WGPUDevice,

    pub fn deinit(self: *Device) void {
        c.wgpuDeviceDrop(self.c);

        self.c = null;
    }

    pub fn createSwapChainOptimal(self: Device, adapter: Adapter, surface: Surface, window: *c.SDL_Window) !SwapChain {
        //Try to create a swapchain with mailbox
        return self.createSwapChain(adapter, surface, window, true) catch {
            //If that fails, try to create one with standard VSync
            return try self.createSwapChain(adapter, surface, window, false);
        };
    }

    pub fn createSwapChain(self: Device, adapter: Adapter, surface: Surface, window: *c.SDL_Window, mailbox: bool) !SwapChain {
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.SDL_GL_GetDrawableSize(window, &width, &height);

        var swap_chain = c.wgpuDeviceCreateSwapChain(self.c, surface.c, &c.WGPUSwapChainDescriptor{
            .usage = c.WGPUTextureUsage_RenderAttachment,
            .format = surface.getPreferredFormat(adapter),
            .presentMode = if (mailbox) c.WGPUPresentMode_Mailbox else c.WGPUPresentMode_Fifo,
            .nextInChain = null,
            .width = @intCast(u32, width),
            .height = @intCast(u32, height),
            .label = "Swapchain",
        });

        std.debug.print("got swap chain 0x{x} with size {d}x{d}\n", .{ @ptrToInt(swap_chain.?), width, height });

        return .{ .c = swap_chain orelse return error.UnableToCreateSwapChain };
    }

    pub fn getQueue(self: Device) !Queue {
        return .{ .c = c.wgpuDeviceGetQueue(self.c) orelse return error.UnableToGetDeviceQueue };
    }

    pub fn createShaderModule(self: Device) !c.WGPUShaderModule {
        var module = c.wgpuDeviceCreateShaderModule(self.c, &c.WGPUShaderModuleDescriptor{
            .label = "Shader",
            .nextInChain = @ptrCast(
                [*c]c.WGPUChainedStruct,
                @constCast(&c.WGPUShaderModuleWGSLDescriptor{
                    .chain = c.WGPUChainedStruct{
                        .sType = c.WGPUSType_ShaderModuleWGSLDescriptor,
                        .next = null,
                    },
                    .code = @embedFile("shader.wgsl"),
                }),
            ),
            .hints = null,
            .hintCount = 0,
        });

        std.debug.print("got shader module 0x{x}\n", .{@ptrToInt(module.?)});

        return module orelse error.UnableToCreateShaderModule;
    }

    pub fn createBindGroupLayouts(self: Device) !BindGroupLayouts {
        var layouts: BindGroupLayouts = undefined;

        layouts.texture_sampler = c.wgpuDeviceCreateBindGroupLayout(self.c, &c.WGPUBindGroupLayoutDescriptor{
            .nextInChain = null,
            .label = "Texture/Sampler bind group layout",
            .entryCount = 2,
            .entries = @as([]const c.WGPUBindGroupLayoutEntry, &.{
                c.WGPUBindGroupLayoutEntry{
                    .nextInChain = null,
                    .binding = 0,
                    .texture = c.WGPUTextureBindingLayout{
                        .nextInChain = null,
                        .multisampled = false,
                        .sampleType = c.WGPUTextureSampleType_Float,
                        .viewDimension = c.WGPUTextureViewDimension_2D,
                    },
                    .buffer = undefined,
                    .sampler = undefined,
                    .storageTexture = undefined,
                    .visibility = c.WGPUShaderStage_Fragment,
                },
                c.WGPUBindGroupLayoutEntry{
                    .nextInChain = null,
                    .binding = 1,
                    .sampler = c.WGPUSamplerBindingLayout{
                        .nextInChain = null,
                        .type = c.WGPUSamplerBindingType_Filtering,
                    },
                    .buffer = undefined,
                    .texture = undefined,
                    .storageTexture = undefined,
                    .visibility = c.WGPUShaderStage_Fragment,
                },
            }).ptr,
        });
        layouts.projection_matrix = c.wgpuDeviceCreateBindGroupLayout(self.c, &c.WGPUBindGroupLayoutDescriptor{
            .nextInChain = null,
            .label = "Projection matrix bind group layout",
            .entryCount = 1,
            .entries = &c.WGPUBindGroupLayoutEntry{
                .nextInChain = null,
                .binding = 0,
                .texture = undefined,
                .buffer = c.WGPUBufferBindingLayout{
                    .nextInChain = null,
                    .type = c.WGPUBufferBindingType_Uniform,
                    .minBindingSize = @sizeOf(zmath.Mat),
                    .hasDynamicOffset = false,
                },
                .sampler = undefined,
                .storageTexture = undefined,
                .visibility = c.WGPUShaderStage_Vertex,
            },
        });

        std.debug.print("got texture/sampler bind group layout 0x{x}\n", .{@ptrToInt(layouts.texture_sampler.?)});
        std.debug.print("got projection matrix bind group layout 0x{x}\n", .{@ptrToInt(layouts.projection_matrix.?)});

        return layouts;
    }

    pub fn createPipelineLayout(self: Device, bind_group_layouts: BindGroupLayouts) !c.WGPUPipelineLayout {
        var layout = c.wgpuDeviceCreatePipelineLayout(self.c, &c.WGPUPipelineLayoutDescriptor{
            .label = "Pipeline Layout",
            .bindGroupLayoutCount = 2,
            .bindGroupLayouts = @as([]const c.WGPUBindGroupLayout, &.{
                bind_group_layouts.texture_sampler,
                bind_group_layouts.projection_matrix,
            }).ptr,
            .nextInChain = null,
        });

        std.debug.print("got pipeline layout 0x{x}\n", .{@ptrToInt(layout.?)});

        return layout;
    }

    pub fn createRenderPipeline(self: Device, layout: c.WGPUPipelineLayout, shader: c.WGPUShaderModule, surface_format: c.WGPUTextureFormat) !c.WGPURenderPipeline {
        var pipeline = c.wgpuDeviceCreateRenderPipeline(self.c, &c.WGPURenderPipelineDescriptor{
            .nextInChain = null,
            .label = "Render Pipeline",
            .layout = layout,
            .vertex = c.WGPUVertexState{
                .nextInChain = null,
                .module = shader,
                .entryPoint = "vs_main",
                .constantCount = 0,
                .constants = null,
                .bufferCount = 1,
                .buffers = &c.WGPUVertexBufferLayout{
                    .arrayStride = @sizeOf(Vertex),
                    .stepMode = c.WGPUVertexStepMode_Vertex,
                    .attributeCount = 3,
                    .attributes = @as([]const c.WGPUVertexAttribute, &.{
                        c.WGPUVertexAttribute{
                            .format = c.WGPUVertexFormat_Float32x2,
                            .offset = @offsetOf(Vertex, "position"),
                            .shaderLocation = 0,
                        },
                        c.WGPUVertexAttribute{
                            .format = c.WGPUVertexFormat_Float32x2,
                            .offset = @offsetOf(Vertex, "tex_coord"),
                            .shaderLocation = 1,
                        },
                        c.WGPUVertexAttribute{
                            .format = c.WGPUVertexFormat_Float32x4,
                            .offset = @offsetOf(Vertex, "vertex_col"),
                            .shaderLocation = 2,
                        },
                    }).ptr,
                },
            },
            .fragment = &c.WGPUFragmentState{
                .module = shader,
                .targets = &c.WGPUColorTargetState{
                    .blend = &c.WGPUBlendState{
                        .color = c.WGPUBlendComponent{
                            .srcFactor = c.WGPUBlendFactor_SrcAlpha,
                            .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha,
                            .operation = c.WGPUBlendOperation_Add,
                        },
                        .alpha = c.WGPUBlendComponent{
                            .srcFactor = c.WGPUBlendFactor_One,
                            .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha,
                            .operation = c.WGPUBlendOperation_Add,
                        },
                    },
                    .nextInChain = null,
                    .format = surface_format,
                    .writeMask = c.WGPUColorWriteMask_All,
                },
                .targetCount = 1,
                .constants = null,
                .constantCount = 0,
                .entryPoint = "fs_main",
                .nextInChain = null,
            },
            .primitive = c.WGPUPrimitiveState{
                .cullMode = c.WGPUCullMode_Back,
                .topology = c.WGPUPrimitiveTopology_TriangleList,
                .frontFace = c.WGPUFrontFace_CCW,
                .nextInChain = null,
                .stripIndexFormat = c.WGPUIndexFormat_Undefined,
            },
            .depthStencil = null,
            .multisample = c.WGPUMultisampleState{
                .count = 1,
                .mask = ~@as(u32, 0),
                .alphaToCoverageEnabled = false,
                .nextInChain = null,
            },
        });

        std.debug.print("got render pipeline 0x{x}\n", .{@ptrToInt(pipeline.?)});

        return pipeline orelse error.UnableToCreateRenderPipeline;
    }

    pub fn createCommandEncoder(self: Device, descriptor: *const c.WGPUCommandEncoderDescriptor) !CommandEncoder {
        return .{
            .c = c.wgpuDeviceCreateCommandEncoder(self.c, descriptor) orelse return error.UnableToCreateCommandEncoder,
        };
    }

    pub fn createUniformBuffer(self: Device, size: usize, name: [*c]const u8) !c.WGPUBuffer {
        var buffer = c.wgpuDeviceCreateBuffer(self.c, &c.WGPUBufferDescriptor{
            .nextInChain = null,
            .label = name,
            .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
            .size = @intCast(u64, size),
            .mappedAtCreation = false,
        });

        std.debug.print("got buffer 0x{x} ({s}) with size {d}\n", .{ @ptrToInt(buffer.?), name, size });

        return buffer orelse error.UnableToCreateBuffer;
    }

    pub fn createTexture(self: Device, queue: Queue, allocator: std.mem.Allocator, data: []const u8) !Texture {
        var stream: img.Image.Stream = .{ .const_buffer = std.io.fixedBufferStream(data) };

        var image = try img.qoi.QOI.readImage(allocator, &stream);
        defer image.deinit();

        var texFormat: c_uint = c.WGPUTextureFormat_RGBA8UnormSrgb;

        var tex = c.wgpuDeviceCreateTexture(self.c, &c.WGPUTextureDescriptor{
            .nextInChain = null,
            .label = "Texture",
            .usage = c.WGPUTextureUsage_CopyDst | c.WGPUTextureUsage_TextureBinding,
            .dimension = c.WGPUTextureDimension_2D,
            .size = c.WGPUExtent3D{
                .width = @intCast(u32, image.width),
                .height = @intCast(u32, image.height),
                .depthOrArrayLayers = 1,
            },
            .format = texFormat,
            .mipLevelCount = 1,
            .sampleCount = 1,
            .viewFormatCount = 1,
            .viewFormats = &texFormat,
        }) orelse return error.UnableToCreateDeviceTexture;

        var view = c.wgpuTextureCreateView(tex, &c.WGPUTextureViewDescriptor{
            .nextInChain = null,
            .label = "Texture View",
            .format = texFormat,
            .dimension = c.WGPUTextureViewDimension_2D,
            .baseMipLevel = 0,
            .baseArrayLayer = 0,
            .mipLevelCount = 1,
            .arrayLayerCount = 1,
            .aspect = c.WGPUTextureAspect_All,
        }) orelse return error.UnableToCreateTextureView;

        c.wgpuQueueWriteTexture(
            queue.c,
            &c.WGPUImageCopyTexture{
                .nextInChain = null,
                .texture = tex,
                .mipLevel = 0,
                .origin = c.WGPUOrigin3D{
                    .x = 0,
                    .y = 0,
                    .z = 0,
                },
                .aspect = c.WGPUTextureAspect_All,
            },
            image.pixels.rgba32.ptr,
            image.pixels.rgba32.len * @sizeOf(img.color.Rgba32),
            &c.WGPUTextureDataLayout{
                .nextInChain = null,
                .bytesPerRow = @intCast(u32, image.width * @sizeOf(img.color.Rgba32)),
                .offset = 0,
                .rowsPerImage = @intCast(u32, image.height),
            },
            &c.WGPUExtent3D{
                .width = @intCast(u32, image.width),
                .height = @intCast(u32, image.height),
                .depthOrArrayLayers = 1,
            },
        );

        var texture = Texture{
            .tex = tex,
            .view = view,
            .bind_group = null,
        };

        return texture;
    }

    pub fn createBuffer(self: Device, size: u64, comptime buffer_type: BufferType) !Buffer {
        var buffer = c.wgpuDeviceCreateBuffer(self.c, &c.WGPUBufferDescriptor{
            .nextInChain = null,
            .size = size,
            .mappedAtCreation = false,
            .usage = @enumToInt(buffer_type) | c.WGPUBufferUsage_CopyDst,
            .label = "Buffer (" ++ @tagName(buffer_type) ++ ")",
        });

        std.debug.print("got buffer 0x{x}\n", .{@ptrToInt(buffer.?)});

        return .{
            .c = buffer orelse return error.UnableToCreateBuffer,
            .type = buffer_type,
            .size = size,
        };
    }
};

pub const BufferType = enum(c_int) {
    index = 0x00000010,
    vertex = 0x00000020,
    uniform = 0x00000040,
    storage = 0x00000080,
    indirect = 0x00000100,
    query_resolve = 0x00000200,
};
pub const Buffer = struct {
    c: c.WGPUBuffer,
    type: BufferType,
    size: u64,

    pub fn deinit(self: Buffer) void {
        c.wgpuBufferDrop(self.c);
    }
};

pub const Vertex = extern struct {
    position: @Vector(2, f32),
    tex_coord: @Vector(2, f32),
    vertex_col: @Vector(4, f32),
};

pub fn createInstance() !Instance {
    var instance = c.wgpuCreateInstance(&c.WGPUInstanceDescriptor{
        .nextInChain = null,
    });

    std.debug.print("got instance 0x{x}\n", .{@ptrToInt(instance.?)});

    return .{ .c = instance orelse return error.InstanceCreationError };
}

pub fn setErrorCallbacks(self: *Self) void {
    c.wgpuDeviceSetUncapturedErrorCallback(self.device.c, uncapturedError, null);
    c.wgpuDeviceSetDeviceLostCallback(self.device.c, deviceLost, null);

    std.debug.print("setup wgpu device callbacks\n", .{});
}

fn uncapturedError(error_type: c.WGPUErrorType, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;

    std.debug.print("Got uncaptured error {d} with message {s}\n", .{ error_type, std.mem.span(message) });
    @panic("uncaptured wgpu error");
}

fn deviceLost(reason: c.WGPUDeviceLostReason, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;

    std.debug.print("Device lost! reason {d} with message {s}\n", .{ reason, std.mem.span(message) });
    @panic("device lost");
}

pub fn handleDeviceCallback(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, message: [*c]const u8, userdata: ?*anyopaque) callconv(.C) void {
    var device_ptr: *c.WGPUDevice = @ptrCast(*c.WGPUDevice, @alignCast(@alignOf(c.WGPUDevice), userdata));

    if (status != c.WGPURequestDeviceStatus_Success) {
        std.debug.print("Failed to get wgpu adapter, status: {d}, message {s}", .{ status, std.mem.span(message) });
        @panic("Unable to aquire wgpu adapter!");
    }

    device_ptr.* = device;
}

pub fn handleAdapterCallback(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message: [*c]const u8, userdata: ?*anyopaque) callconv(.C) void {
    var adapter_ptr: *c.WGPUAdapter = @ptrCast(*c.WGPUAdapter, @alignCast(@alignOf(c.WGPUAdapter), userdata));

    if (status != c.WGPURequestAdapterStatus_Success) {
        std.debug.print("Failed to get wgpu adapter, status: {d}, message {s}", .{ status, std.mem.span(message) });
        @panic("Unable to aquire wgpu adapter!");
    }

    adapter_ptr.* = adapter;
}

pub fn updateProjectionMatrixBuffer(self: *Self, queue: Queue, window: *c.SDL_Window) void {
    var w: c_int = 0;
    var h: c_int = 0;
    c.SDL_GL_GetDrawableSize(window, &w, &h);

    var mat = zmath.orthographicOffCenterLh(0, @intToFloat(f32, w), 0, @intToFloat(f32, h), 0, 1);

    queue.writeBuffer(self.projection_matrix_buffer, 0, &mat, @sizeOf(zmath.Mat));
}

pub fn recreateSwapChain(self: *Self, window: *c.SDL_Window) !void {
    if (self.swap_chain) |swap_chain| {
        swap_chain.deinit();
    }

    self.swap_chain = try self.device.createSwapChainOptimal(self.adapter, self.surface, window);
}

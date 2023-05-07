const std = @import("std");
const builtin = @import("builtin");
const c = @import("main.zig").c;
const zmath = @import("zmath");
const img = @import("zigimg");

pub const Vertex = extern struct {
    position: @Vector(2, f32),
    tex_coord: @Vector(2, f32),
    vertex_col: @Vector(4, f32),
};

pub fn createInstance() !c.WGPUInstance {
    var instance = c.wgpuCreateInstance(&c.WGPUInstanceDescriptor{
        .nextInChain = null,
    });

    std.debug.print("got instance 0x{x}\n", .{@ptrToInt(instance.?)});

    return instance orelse error.InstanceCreationError;
}

pub fn requestAdapter(instance: c.WGPUInstance, surface: c.WGPUSurface) !c.WGPUAdapter {
    var adapter: c.WGPUAdapter = undefined;

    c.wgpuInstanceRequestAdapter(instance, &c.WGPURequestAdapterOptions{
        .compatibleSurface = surface,
        .nextInChain = null,
        .powerPreference = c.WGPUPowerPreference_HighPerformance,
        .forceFallbackAdapter = false,
    }, handleAdapterCallback, @ptrCast(*anyopaque, &adapter));

    std.debug.print("got adapter 0x{x}\n", .{@ptrToInt(adapter.?)});

    return adapter;
}

pub fn setErrorCallbacks(device: c.WGPUDevice) void {
    c.wgpuDeviceSetUncapturedErrorCallback(device, uncapturedError, null);
    c.wgpuDeviceSetDeviceLostCallback(device, deviceLost, null);

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

pub fn requestDevice(adapter: c.WGPUAdapter) !c.WGPUDevice {
    var device: c.WGPUDevice = undefined;

    c.wgpuAdapterRequestDevice(adapter, &c.WGPUDeviceDescriptor{
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

    std.debug.print("got device 0x{x}\n", .{@ptrToInt(adapter.?)});

    return device;
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

pub fn createSurface(instance: c.WGPUInstance, window: *c.SDL_Window) !c.WGPUSurface {
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

    var surface = c.wgpuInstanceCreateSurface(instance, &descriptor);

    std.debug.print("got surface 0x{x}\n", .{@ptrToInt(surface.?)});

    return surface orelse error.SurfaceCreationError;
}

pub const BindGroupLayouts = struct {
    texture_sampler: c.WGPUBindGroupLayout,
    projection_matrix: c.WGPUBindGroupLayout,
    pub fn deinit(self: BindGroupLayouts) void {
        c.wgpuBindGroupLayoutDrop(self.texture_sampler);
        c.wgpuBindGroupLayoutDrop(self.projection_matrix);
    }
};

pub fn createBindGroupLayouts(device: c.WGPUDevice) !BindGroupLayouts {
    var layouts: BindGroupLayouts = undefined;

    layouts.texture_sampler = c.wgpuDeviceCreateBindGroupLayout(device, &c.WGPUBindGroupLayoutDescriptor{
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
    layouts.projection_matrix = c.wgpuDeviceCreateBindGroupLayout(device, &c.WGPUBindGroupLayoutDescriptor{
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

pub fn createPipelineLayout(device: c.WGPUDevice, bind_group_layouts: BindGroupLayouts) !c.WGPUPipelineLayout {
    var layout = c.wgpuDeviceCreatePipelineLayout(device, &c.WGPUPipelineLayoutDescriptor{
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

pub fn createShaderModule(device: c.WGPUDevice) !c.WGPUShaderModule {
    var module = c.wgpuDeviceCreateShaderModule(device, &c.WGPUShaderModuleDescriptor{
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

pub fn createRenderPipeline(device: c.WGPUDevice, layout: c.WGPUPipelineLayout, shader: c.WGPUShaderModule, surface_format: c.WGPUTextureFormat) !c.WGPURenderPipeline {
    var pipeline = c.wgpuDeviceCreateRenderPipeline(device, &c.WGPURenderPipelineDescriptor{
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

pub fn createSwapChain(device: c.WGPUDevice, surface: c.WGPUSurface, format: c.WGPUTextureFormat, window: *c.SDL_Window) !c.WGPUSwapChain {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.SDL_GL_GetDrawableSize(window, &width, &height);

    var swap_chain = c.wgpuDeviceCreateSwapChain(device, surface, &c.WGPUSwapChainDescriptor{
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .format = format,
        .presentMode = c.WGPUPresentMode_Fifo,
        .nextInChain = null,
        .width = @intCast(u32, width),
        .height = @intCast(u32, height),
        .label = "Swapchain",
    });

    std.debug.print("got swap chain 0x{x} with size {d}x{d}\n", .{ @ptrToInt(swap_chain.?), width, height });

    return swap_chain orelse error.UnableToCreateSwapChain;
}

pub const Texture = struct {
    tex: c.WGPUTexture,
    view: c.WGPUTextureView,
    pub fn deinit(self: Texture) void {
        c.wgpuTextureViewDrop(self.view);
        c.wgpuTextureDrop(self.tex);
    }
};

pub fn createTexture(allocator: std.mem.Allocator, device: c.WGPUDevice, queue: c.WGPUQueue, data: []const u8) !Texture {
    var stream: img.Image.Stream = .{ .const_buffer = std.io.fixedBufferStream(data) };

    var image = try img.qoi.QOI.readImage(allocator, &stream);
    defer image.deinit();

    var texFormat: c_uint = c.WGPUTextureFormat_RGBA8UnormSrgb;

    var tex = c.wgpuDeviceCreateTexture(device, &c.WGPUTextureDescriptor{
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
        queue,
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

    return .{
        .tex = tex,
        .view = view,
    };
}

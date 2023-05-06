const std = @import("std");
const builtin = @import("builtin");
const c = @import("main.zig").c;
const zmath = @import("zmath");

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

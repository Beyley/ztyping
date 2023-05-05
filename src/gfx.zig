const std = @import("std");
const builtin = @import("builtin");
const c = @import("main.zig").c;

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

pub fn requestDevice(adapter: c.WGPUAdapter) !c.WGPUDevice {
    var device: c.WGPUDevice = undefined;

    c.wgpuAdapterRequestDevice(adapter, &c.WGPUDeviceDescriptor{
        .label = null,
        .requiredFeaturesCount = 0,
        .requiredFeatures = null,
        .requiredLimits = null,
        .defaultQueue = c.WGPUQueueDescriptor{
            .nextInChain = null,
            .label = null,
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
        .label = null,
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

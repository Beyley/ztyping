const std = @import("std");
const builtin = @import("builtin");
const c = @import("main.zig").c;

pub fn create_instance() !c.WGPUInstance {
    return c.wgpuCreateInstance(&c.WGPUInstanceDescriptor{
        .nextInChain = null,
    }) orelse error.InstanceCreationError;
}

pub fn request_adapter(instance: c.WGPUInstance, surface: c.WGPUSurface) !c.WGPUAdapter {
    var adapter: c.WGPUAdapter = undefined;

    c.wgpuInstanceRequestAdapter(instance, &c.WGPURequestAdapterOptions{
        .compatibleSurface = surface,
        .nextInChain = null,
        .powerPreference = c.WGPUPowerPreference_HighPerformance,
        .forceFallbackAdapter = false,
    }, handle_adapter_callback, @ptrCast(*anyopaque, &adapter));

    return adapter;
}

pub fn handle_adapter_callback(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message: [*c]const u8, userdata: ?*anyopaque) callconv(.C) void {
    var adapter_ptr: *c.WGPUAdapter = @ptrCast(*c.WGPUAdapter, @alignCast(@alignOf(c.WGPUAdapter), userdata));

    if (status != c.WGPURequestAdapterStatus_Success) {
        std.debug.print("Failed to get wgpu adapter, status: {d}, message {s}", .{ status, std.mem.span(message) });
        @panic("Unable to aquire wgpu adapter!");
    }

    adapter_ptr.* = adapter;
}

pub fn create_surface(instance: c.WGPUInstance, window: *c.SDL_Window) !c.WGPUSurface {
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

    return c.wgpuInstanceCreateSurface(instance, &descriptor) orelse error.SurfaceCreationError;
}

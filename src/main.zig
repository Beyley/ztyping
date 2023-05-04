const std = @import("std");
const zaudio = @import("zaudio");

const c = @cImport({
    @cInclude("fontstash.h");
    @cInclude("SDL.h");
});

pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub var allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    //Create the allocator to be used in the lifetime of the app
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("Memory leak!");
    allocator = gpa.allocator();

    //Initialize zaudio
    zaudio.init(allocator);
    defer zaudio.deinit();

    //Initialize our audio engine
    const engine = try zaudio.Engine.create(null);
    defer engine.destroy();

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL init failed! err:{s}\n", .{c.SDL_GetError()});
        return error.InitSdlFailure;
    }
    defer c.SDL_Quit();
    std.debug.print("Initialized SDL\n", .{});

    const window = c.SDL_CreateWindow("ztyping", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN);
    if (window == null) {
        std.debug.print("SDL window creation failed! err:{s}\n", .{c.SDL_GetError()});
        return error.CreateWindowFailure;
    }
    defer c.SDL_DestroyWindow(window);
    std.debug.print("Created SDL window\n", .{});

    var isRunning = true;
    while (isRunning) {
        var ev: c.SDL_Event = undefined;

        if (c.SDL_PollEvent(&ev) != 0) {
            if (ev.type == c.SDL_QUIT) {
                isRunning = false;
            }
        }
    }
}

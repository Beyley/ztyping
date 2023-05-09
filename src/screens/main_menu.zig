const Screen = @import("../screen.zig");
const Gfx = @import("../gfx.zig");

pub const MainMenu = Screen{
    .render = renderScreen,
};

pub fn renderScreen(gfx: Gfx, render_pass_encoder: Gfx.RenderPassEncoder, texture: Gfx.Texture) void {
    _ = render_pass_encoder;
    _ = gfx;
    _ = texture;
}

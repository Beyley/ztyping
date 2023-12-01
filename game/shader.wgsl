struct VertexOutputs {
    //The position of the vertex
    @builtin(position) position: vec4<f32>,
    //The texture cooridnate of the vertex
    @location(0) tex_coord: vec2<f32>,
    //The color of the vertex
    @location(1) vertex_col: vec4<f32>
}

struct FragmentInputs {
    //Texture coordinate
    @location(0) tex_coord: vec2<f32>,
    //The Vertex color
    @location(1) vertex_col: vec4<f32>
}

@group(0) @binding(0) var<uniform> projection_matrix: mat4x4<f32>;

@vertex
fn vs_main(
    @location(0) pos: vec2<f32>,
    @location(1) tex_coord: vec2<f32>,
    @location(2) vertex_col: vec4<f32>,
) -> VertexOutputs {
    var output: VertexOutputs;

    output.position = projection_matrix * vec4<f32>(pos, 0.0, 1.0);
    output.tex_coord = tex_coord;
    output.vertex_col = vertex_col;

    return output;
}

//TODO: keep an eye on the spec, once we are able to support texture and sampler arrays, PLEASE USE THEM
//The texture we're sampling
@group(1) @binding(0) var t: texture_2d<f32>;
//The sampler we're using to sample the texture
@group(1) @binding(1) var s: sampler;

@fragment
fn fs_main(input: FragmentInputs) -> @location(0) vec4<f32> {
    return toLinear(textureSample(t, s, input.tex_coord) * input.vertex_col);
}

fn toLinear(sRGB: vec4<f32>) -> vec4<f32>
{
    var cutoff: vec4<f32> = vec4<f32>(0.0);

    if(sRGB.r < 0.04045) {
        cutoff.r = 1.0;
    }
    if(sRGB.g < 0.04045) {
        cutoff.g = 1.0;
    }
    if(sRGB.b < 0.04045) {
        cutoff.b = 1.0;
    }
    if(sRGB.a < 0.04045) {
        cutoff.a = 1.0;
    }

	var higher: vec4<f32> = pow((sRGB + vec4<f32>(0.055))/vec4<f32>(1.055), vec4<f32>(2.4));
	var lower: vec4<f32> = sRGB/vec4<f32>(12.92);

	return mix(higher, lower, cutoff);
}

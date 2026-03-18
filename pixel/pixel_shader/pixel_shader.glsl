#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  float pixel_size;
  float reserved;
} params;

layout (set = 0, binding = 1) uniform sampler2D input_buffer;
layout (rgba16f, set = 0, binding = 2) uniform image2D output_buffer;

vec4 pixelate(sampler2D tex, vec2 uv) {
  float width = params.raster_size.x / params.pixel_size;
  float height = params.raster_size.y / params.pixel_size;
  vec2 coord = vec2(ceil(uv.x * width) / width, ceil(uv.y * height) / height);
  return texture(tex, coord);
}

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  if (uv.x >= size.x || uv.y >= size.y) return;

  float pixel_size = params.pixel_size;
  vec4 colour = pixelate(input_buffer, uv_normalised);
  imageStore(output_buffer, uv, colour);
}

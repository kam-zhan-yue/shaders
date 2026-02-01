#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
  float pixel_size;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;
layout (set = 0, binding = 2) uniform sampler2D fragment_buffer;

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  if (uv.x >= size.x || uv.y >= size.y) return;

  float pixel_size = params.pixel_size;

  vec2 pixel = uv_normalised;
  pixel.x -= mod(pixel.x, 1.0 / pixel_size);
  pixel.y -= mod(pixel.y, 1.0 / pixel_size);
  vec4 colour = texture(fragment_buffer, pixel);
  imageStore(colour_buffer, uv, colour);
}

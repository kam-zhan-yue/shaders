#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  vec2 texel_size = 1.0 / size.xy;
  if (uv.x >= size.x || uv.y >= size.y) return;
  
  vec4 colour = imageLoad(colour_buffer, uv);
  float grayscale = (colour.x + colour.y + colour.z) / 3;
  vec4 gray = vec4(vec3(grayscale), 1.0);
  imageStore(colour_buffer, uv, gray);
}

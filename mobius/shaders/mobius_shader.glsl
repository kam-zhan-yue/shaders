#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (rgba16f, set = 0, binding = 0) uniform image2D colour_image;

layout (push_constant, std430) uniform Params {
  vec2 raster_size;
  vec2 reserved;
} params;

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  ivec2 size = ivec2(params.raster_size);

  // Prevent reading / writing out of bounds
  if (uv.x >= size.x || uv.y >= size.y) {
    return;
  }

  // Read from the colour buffer
  vec4 colour = imageLoad(colour_image, uv);

  float gray = (colour.r + colour.g + colour.g) / 3;
  colour.rgb = vec3(gray);

  // Write back to the colour buffer
  imageStore(colour_image, uv, colour);
}

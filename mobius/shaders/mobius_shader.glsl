#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
  mat4 inv_projection_mat;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;
layout (set = 0, binding = 2) uniform sampler2D depth_buffer;

vec2 offsets[9] = vec2[](
  vec2(-1, 1),    // top left
  vec2(0, 1),       // top center
  vec2(1, 1),     // top right
  vec2(-1, 0),      // center left
  vec2(0, 0),         // center center
  vec2(1, 0),       // center right
  vec2(-1, -1),   // bottom left
  vec2(0, -1),      // bottom center
  vec2(1, -1)    // bottom right
);

int sobel_vertical_kernel[9] = int[](
    1, 0, -1,
    2, 0, -2,
    1, 0, -1
);

int sobel_horizontal_kernel[9] = int[](
    1, 2, 1,
    0, 0, 0,
    -1, -2, -1
);

// Unproject


void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  vec2 texel_size = 1.0 / size.xy;

  // Prevent reading / writing out of bounds
  if (uv.x >= size.x || uv.y >= size.y) {
    return;
  }

  vec4 sampleTex[9];
  for (int i = 0; i < 9; ++i) {
    sampleTex[i] = texture(depth_buffer, uv_normalised + offsets[i] * texel_size);
  }

  vec4 colour = vec4(0);
  for (int i = 0; i < 9; ++i) {
    colour += sampleTex[i] * sobel_vertical_kernel[i];
    colour += sampleTex[i] * sobel_horizontal_kernel[i];
  }
  // vec4 colour = texture(depth_buffer, uv_normalised);

  // Write back to the colour buffer
  imageStore(colour_buffer, uv, colour);
}

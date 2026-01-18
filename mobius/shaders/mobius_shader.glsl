#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
  mat4 inv_proj_mat;
  mat4 inv_view_mat;
  float depth_threshold;
  float depth_thickness;
  float depth_strength;
  float normal_threshold;
  float normal_thickness;
  float normal_strength;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;
layout (set = 0, binding = 2) uniform sampler2D depth_buffer;
layout (set = 0, binding = 3) uniform sampler2D normal_buffer;

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
const vec2 offset = vec2(0.0001);

int vertical_kernel[9] = int[](
    1, 0, -1,
    2, 0, -2,
    1, 0, -1
);

int horizontal_kernel[9] = int[](
    1, 2, 1,
    0, 0, 0,
    -1, -2, -1
);

// Implementation of Unity's Remap Node: https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Remap-Node.html
// E.g. remap(screen.x, 0, 800, 0, 1)
float remap(float value, float in_min, float in_max, float out_min, float out_max) {
    return out_min + (value - in_min) * (out_max - out_min) / (in_max - in_min);
}

float normal_sobel(vec2 uv, vec2 thickness) {
  float gx = 0.0;
  float gy = 0.0;
  for (int i = 0; i < 9; ++i) {
    vec4 normal = params.inv_view_mat * texture(normal_buffer, uv + offsets[i] * thickness);
    float weight = (normal.x + normal.y + normal.z) / 3;
    gx += horizontal_kernel[i] * weight;
    gy += vertical_kernel[i] * weight;
  }
  return sqrt(gx * gx + gy * gy);
}

float depth_sobel(vec2 uv, vec2 thickness) {
  float gx = 0.0;
  float gy = 0.0;
  for (int i = 0; i < 9; ++i) {
    float depth = texture(depth_buffer, uv + offsets[i] * thickness).r;
    gx += horizontal_kernel[i] * depth;
    gy += vertical_kernel[i] * depth;
  }
  return sqrt(gx * gx + gy * gy);
}

float post_sobel(float sobel, float threshold, float thickness, float strength) {
  float step = smoothstep(0, threshold, sobel);
  float power = pow(step, thickness);
  float result = power * strength;
  return result;
}

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  vec2 texel_size = 1.0 / size.xy;

  // Prevent reading / writing out of bounds
  if (uv.x >= size.x || uv.y >= size.y) {
    return;
  }

  // Implementation 2
  float depth_value = depth_sobel(uv_normalised, texel_size);
  float depth_post = post_sobel(depth_value, params.depth_threshold, params.depth_thickness, params.depth_strength);
  float depth_step = step(0.01, depth_post);

  float normal_value = normal_sobel(uv_normalised, texel_size);
  float normal_post = post_sobel(normal_value, params.normal_threshold, params.normal_thickness, params.normal_strength);
  float normal_step = step(0.01, normal_post);

  float sobel = max(depth_step, normal_step);

  vec4 colour = vec4(vec3(sobel), 1.0);

  // Write back to the colour buffer
  imageStore(colour_buffer, uv, colour);
}

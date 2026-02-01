#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 shadow_tiling;
  float shadow_horizontal;
  float shadow_vertical;
  float shadow_diagonal;
  float shadow_reserved;
  vec4 outline_colour;
  float outline_amplitude;
  float outline_frequency;
  float depth_thickness;
  float normal_thickness;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;
layout (set = 0, binding = 2) uniform sampler2D depth_buffer;
layout (set = 0, binding = 3) uniform sampler2D normal_buffer;
layout (set = 0, binding = 4) uniform sampler2D noise_texture;
layout (set = 0, binding = 5) uniform sampler2D crosshatch_texture;

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

float luma(vec3 colour) {
  const vec3 magic = vec3(0.2125, 0.7154, 0.0721);
  return dot(magic, colour);
}

float normal_sobel(vec2 uv, vec2 texel, float thickness, vec2 displacement, vec2 size) {
  float gx = 0.0;
  float gy = 0.0;
  for (int i = 0; i < 9; ++i) {
    vec2 UV = uv + offsets[i] * texel * thickness + displacement;
    if (UV.x >= size.x || UV.y >= size.y) continue;
    vec4 normal = texture(normal_buffer, UV);
    float weight = luma(normal.xyz);
    gx += horizontal_kernel[i] * weight;
    gy += vertical_kernel[i] * weight;
  }
  return sqrt(gx * gx + gy * gy);
}

float depth_sobel(vec2 uv, vec2 texel, float thickness, vec2 displacement, vec2 size) {
  float gx = 0.0;
  float gy = 0.0;
  for (int i = 0; i < 9; ++i) {
    vec2 UV = uv + offsets[i] * texel * thickness + displacement;
    if (UV.x >= size.x || UV.y >= size.y) continue;

    float depth = texture(depth_buffer, UV).r;
    gx += horizontal_kernel[i] * depth;
    gy += vertical_kernel[i] * depth;
  }
  return sqrt(gx * gx + gy * gy);
}

vec2 rotate_uv(vec2 uv, float rotation, vec2 mid) {
    return vec2(
      cos(rotation) * (uv.x - mid.x) + sin(rotation) * (uv.y - mid.y) + mid.x,
      cos(rotation) * (uv.y - mid.y) - sin(rotation) * (uv.x - mid.x) + mid.y
    );
}

// Taken from: https://gist.github.com/983/e170a24ae8eba2cd174f
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 full_brightness(vec3 colour) {
  vec3 hsv = rgb2hsv(colour);
  hsv.z = 1.0;
  vec3 rgb = hsv2rgb(hsv);
  return rgb;
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

  // Add noise displacement for hand-drawn style
  float noise = texture(noise_texture, uv_normalised).r;
  vec2 displacement = vec2(
    noise * sin(uv.y * params.outline_frequency),
    noise * cos(uv.x * params.outline_frequency)
  ) * params.outline_amplitude / size.xy;

  // Convolution filters for depth and normal maps
  float depth_value = depth_sobel(uv_normalised, texel_size, params.depth_thickness, displacement, size) * 5;
  float normal_value = normal_sobel(uv_normalised, texel_size, params.normal_thickness, displacement, size);
  float sobel = max(depth_value, normal_value);

  // Debug Sobel Filter
  // imageStore(colour_buffer, uv, vec4(vec3(sobel), 0.0))

  // Crosshatch shadows
  vec4 pixel_normal = texture(normal_buffer, uv_normalised);
  vec4 pixel_colour = imageLoad(colour_buffer, uv);
  float pixel_depth = texture(depth_buffer, uv_normalised).r;

  // Retrieve diffuse lighting from normal buffer and hack it into luma
  float diffuse_light = pixel_normal.a;
  float pixel_luma = luma(pixel_colour.rgb + diffuse_light * 0.1);

  float rotation_amount = 90.0;
  vec2 rotation_centre = vec2(0.5, 0.5);
  vec2 rotated_uv = rotate_uv(uv_normalised, rotation_amount, rotation_centre);
  vec4 crosshatch = texture(crosshatch_texture, rotated_uv * params.shadow_tiling);

  // If the luma of a given pixel falls under a specific luma value, we change its colour to a darker shade.
  // To avoid capturing the background colour, we can reuse the depth buffer to apply shadow patterns that are close enough to the camera
  if (pixel_depth >= 0.00001) {
    float shadow_value = 1 - pixel_luma;
    float horizontal = step(params.shadow_horizontal, shadow_value) * crosshatch.r;
    float vertical = step(params.shadow_vertical, shadow_value) * crosshatch.g;
    float diagonal = step(params.shadow_diagonal, shadow_value) * crosshatch.b;
    float shadow = step(0.1, max(max(horizontal, vertical), diagonal));
    float final = max(sobel, shadow);

    // Debug Crosshatch Shadows
    // imageStore(colour_buffer, uv, vec4(vec3(shadow), 0.0));

    // Override for normal specular
    if (pixel_normal.r >= 1.0 && pixel_normal.g >= 1.0 && pixel_normal.b >= 1.0) {
      imageStore(colour_buffer, uv, vec4(1.0));
    } else {
      vec4 final_colour = vec4(full_brightness(pixel_colour.rgb), 1.0);
      vec4 colour = mix(final_colour, params.outline_colour, final);
      imageStore(colour_buffer, uv, colour);
    }
  } else {
    imageStore(colour_buffer, uv, pixel_colour);
  }
}


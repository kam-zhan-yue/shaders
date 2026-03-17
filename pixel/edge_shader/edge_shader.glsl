#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
  mat4 inv_proj_mat;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;
layout (set = 0, binding = 2) uniform sampler2D screen_buffer;
layout (set = 0, binding = 3) uniform sampler2D depth_buffer;
layout (set = 0, binding = 4) uniform sampler2D normal_buffer;

const vec2 offset = vec2(0.0001);

// Taken from https://github.com/godotengine/godot-docs/issues/9591
vec4 normal_roughness_compatibility(vec4 p_normal_roughness) {
	float roughness = p_normal_roughness.w;
	if (roughness > 0.5) {
		roughness = 1.0 - roughness;
	}
	roughness /= (127.0 / 255.0);
	vec4 compatibility = vec4(normalize(p_normal_roughness.xyz * 2.0 - 1.0) * 0.5 + 0.5, roughness);
  return normalize(compatibility * 2.0 - 1.0);
}

float linearise_depth(vec2 uv) {
  float depth = texture(depth_buffer, uv).r;
  vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
  vec4 view = params.inv_proj_mat * vec4(ndc, 1.0);
  view.xyz /= view.w;
  return -view.z;
}

vec4 get_normal(vec2 uv) {
  vec4 normal = texture(normal_buffer, uv);
  normal = normal * 2.0 - 1.0;
  return normal;
}

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  vec2 texel_size = 1.0 / size.xy;
  if (uv.x >= size.x || uv.y >= size.y) return;

  vec2 uv_offsets[4];
  uv_offsets[0] = uv_normalised + vec2(0.0, -1.0) * texel_size + offset; // up
  uv_offsets[1] = uv_normalised + vec2(0.0, 1.0) * texel_size + offset;  // down
  uv_offsets[2] = uv_normalised + vec2(1.0, 0.0) * texel_size + offset;  // right
  uv_offsets[3] = uv_normalised + vec2(-1.0, 0.0) * texel_size + offset; // left

  
  // vec4 colour = texture(screen_buffer, uv_normalised);
  // float grayscale = (colour.x + colour.y + colour.z) / 3;
  // vec4 gray = vec4(vec3(grayscale), 1.0);
  // imageStore(colour_buffer, uv, colour);

  float depth = linearise_depth(uv_normalised + offset);
  float depth_difference = 0.0;
  for (int i = 0; i < uv_offsets.length(); ++i) {
    float depth_offset = linearise_depth(uv_offsets[i]);
    depth_difference += clamp(depth_offset - depth, 0.0, 1.0);
  }
  depth_difference = smoothstep(0.25, 0.3, depth_difference);

  vec3 normal = normal_roughness_compatibility(get_normal(uv_normalised + offset)).rgb;
  float normal_difference = 0.0;
  for (int i = 0; i < uv_offsets.length(); ++i) {
    vec3 normal_offset = normal_roughness_compatibility(get_normal(uv_offsets[i])).rgb;
    normal_difference += 1.0 - dot(normal, normal_offset);
  }
  normal_difference = smoothstep(0.2, 0.2, normal_difference);

  // float depth = texture(depth_buffer, uv_normalised).r;
  imageStore(colour_buffer, uv, vec4(vec3(depth_difference), 1.0));

  // float depth = texture(depth_buffer, uv_normalised).r;
  // imageStore(colour_buffer, uv, vec4(vec3(depth), 1.0));

  // vec4 normal = texture(normal_buffer, uv_normalised);
  // normal = normal_roughness_compatibility(normal);
  // imageStore(colour_buffer, uv, normal);
}

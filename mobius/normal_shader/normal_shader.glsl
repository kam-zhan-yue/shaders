#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
  vec4 camera_pos;
  vec4 light_direction;
  mat4 inv_proj_mat;
  mat4 inv_view_mat;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D output_buffer;
layout (set = 0, binding = 2) uniform sampler2D normal_buffer;
layout (set = 0, binding = 3) uniform sampler2D depth_buffer;

vec3 reconstruct_world_pos(vec2 uv, float depth) {
  vec2 ndc = uv * 2.0 - 1.0;
  float z = depth * 2.0 - 1.0;

  vec4 clip = vec4(ndc, z, 1.0);
  vec4 view = params.inv_proj_mat * clip;
  view /= view.w;
  vec4 world = params.inv_view_mat * view;
  return world.xyz;
}

// Taken from https://github.com/godotengine/godot-docs/issues/9591
vec4 normal_roughness_compatibility(vec4 p_normal_roughness) {
	float roughness = p_normal_roughness.w;
	if (roughness > 0.5) {
		roughness = 1.0 - roughness;
	}
	roughness /= (127.0 / 255.0);
	return vec4(normalize(p_normal_roughness.xyz * 2.0 - 1.0) * 0.5 + 0.5, roughness);
}

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;

  // Prevent reading / writing out of bounds
  if (uv.x >= size.x || uv.y >= size.y) {
    return;
  }

  vec4 sampled = texture(normal_buffer, uv_normalised);
  vec4 compatible = normal_roughness_compatibility(sampled);
  vec3 normal = compatible.rgb;
  normal = normalize(normal * 2.0 - 1.0);
  float depth = texture(depth_buffer, uv_normalised).r;

  vec3 lightDir = normalize(params.light_direction.xyz);
  vec3 cameraPos = params.camera_pos.xyz;
  vec3 worldPos = reconstruct_world_pos(uv_normalised, depth);

  // vec3 lightDir = normalize(lightPos - worldPos);
  vec3 viewDir = normalize(cameraPos - worldPos);

  // Diffuse
  float diff = max(dot(lightDir, normal), 0.0);

  vec3 halfwayDir = normalize(lightDir + viewDir);
  float spec = pow(max(dot(normal, halfwayDir), 0.0), 2.0);

  if (spec >= 0.98) {
    normal = vec3(1.0, 1.0, 1.0);
  }

  imageStore(output_buffer, uv, vec4(normal, diff));
}


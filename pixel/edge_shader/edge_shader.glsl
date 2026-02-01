#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0, std430) readonly buffer Params {
  vec2 raster_size;
  vec2 reserved;
} params;

layout (rgba16f, set = 0, binding = 1) uniform image2D colour_buffer;
layout (set = 0, binding = 2) uniform sampler2D screen_buffer;
layout (set = 0, binding = 3) uniform sampler2D depth_buffer;
layout (set = 0, binding = 4) uniform sampler2D normal_buffer;

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

void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  vec2 size = vec2(params.raster_size);
  vec2 uv_normalised = uv / size;
  vec2 texel_size = 1.0 / size.xy;
  if (uv.x >= size.x || uv.y >= size.y) return;
  
  vec4 colour = texture(screen_buffer, uv_normalised);
  float grayscale = (colour.x + colour.y + colour.z) / 3;
  vec4 gray = vec4(vec3(grayscale), 1.0);
  imageStore(colour_buffer, uv, gray);

  // float depth = texture(depth_buffer, uv_normalised).r;
  // imageStore(colour_buffer, uv, vec4(vec3(depth), 1.0));

  // vec4 normal = texture(normal_buffer, uv_normalised);
  // normal = normal_roughness_compatibility(normal);
  // imageStore(colour_buffer, uv, normal);
}

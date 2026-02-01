shader_type sky;
render_mode use_half_res_pass;

uniform vec3 sky_top : source_color;
uniform vec3 sky_horizon : source_color;

void sky() {
  float colour_gradient = clamp(EYEDIR.y, 0.0, 1.0);
  vec3 sky_colour = mix(sky_horizon, sky_top, colour_gradient);
  COLOR = sky_colour;
}


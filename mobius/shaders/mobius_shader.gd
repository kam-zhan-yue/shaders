@tool
class_name MobiusShader
extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var nearest_sampler: RID
var parameter_storage_buffer: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_initialise_compute)
	var data := PackedFloat32Array()
	data.resize(20)
	data.fill(0)
	var parameter_data := data.to_byte_array()
	parameter_storage_buffer = rd.storage_buffer_create(parameter_data.size(), parameter_data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			RenderingServer.free_rid(shader)
		if nearest_sampler.is_valid():
			rd.free_rid(nearest_sampler)
		if parameter_storage_buffer.is_valid():
			rd.free_rid(parameter_storage_buffer)


func _initialise_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return

	var shader_file := load("res://shaders/mobius_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if not(rd and p_effect_callback_type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT and pipeline.is_valid()):
		return

	var render_scene_buffers := p_render_data.get_render_scene_buffers()
	var scene_data := p_render_data.get_render_scene_data()
	if render_scene_buffers and scene_data:
		var size: Vector2i = render_scene_buffers.get_internal_size()
		if size.x == 0 and size.y == 0:
			return
		# We can use a compute shader here.
		@warning_ignore("integer_division")
		var x_groups := (size.x - 1) / 8 + 1
		@warning_ignore("integer_division")
		var y_groups := (size.y - 1) / 8 + 1
		var z_groups := 1

		# Make sure we have a sampler
		if not nearest_sampler.is_valid():
			var sampler_state := RDSamplerState.new()
			sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
			sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
			nearest_sampler = rd.sampler_create(sampler_state)

		var view_count: int = render_scene_buffers.get_view_count()
		for view in view_count:
			var colour_buffer: RID = render_scene_buffers.get_color_layer(view)
			var depth_buffer: RID = render_scene_buffers.get_depth_layer(view)

			var parameters := PackedFloat32Array([size.x, size.y, 0.0, 0.0])
			var inv_proj_mat := scene_data.get_cam_projection().inverse()
			var inv_proj_mat_array := PackedVector4Array([inv_proj_mat.x, inv_proj_mat.y, inv_proj_mat.z, inv_proj_mat.w])

			var parameter_data = parameters.to_byte_array()
			parameter_data.append_array(inv_proj_mat_array.to_byte_array())
			rd.buffer_update(parameter_storage_buffer, 0, parameter_data.size(), parameter_data)

			# Uniform Buffer
			var storage_buffer := RDUniform.new()
			storage_buffer.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			storage_buffer.binding = 0
			storage_buffer.add_id(parameter_storage_buffer)

			# Colour Image
			var uniform_colour := RDUniform.new()
			uniform_colour.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_colour.binding = 1
			uniform_colour.add_id(colour_buffer)

			# Depth Buffer
			var uniform_depth := RDUniform.new()
			uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform_depth.binding = 2
			uniform_depth.add_id(nearest_sampler)
			uniform_depth.add_id(depth_buffer)

			var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [storage_buffer, uniform_colour, uniform_depth])

			# Run the compute shader
			var compute_list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
			rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
			# rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
			rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
			rd.compute_list_end()


@tool
class_name EdgeShader
extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var parameter_rid: RID
var sampler_rid: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	RenderingServer.call_on_render_thread(_initialise_compute)
	var parameter_data := get_empty_data()
	parameter_rid = rd.storage_buffer_create(parameter_data.size(), parameter_data)


func get_empty_data() -> PackedByteArray:
	# size + reserved: 4 floats
	# inv view matrix: 16 floats
	var matrices := PackedFloat32Array()
	matrices.resize(20)
	matrices.fill(0)
	var parameter_data = matrices.to_byte_array()
	return parameter_data

func _initialise_compute() -> void:
	if not rd: return

	var shader_file := load("res://pixel/edge_shader/edge_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	if not shader.is_valid(): return
	pipeline = rd.compute_pipeline_create(shader)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			rd.free_rid(shader)
		if sampler_rid.is_valid():
			rd.free_rid(sampler_rid)
		if parameter_rid.is_valid():
			rd.free_rid(parameter_rid)


func get_uniform(rids: Array[RID], type: RenderingDevice.UniformType, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in rids:
		uniform.add_id(rid)
	return uniform


func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if not rd: return
	if p_effect_callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT: return
	if not pipeline.is_valid(): return

	var render_scene_buffers = p_render_data.get_render_scene_buffers()
	var scene_data = p_render_data.get_render_scene_data()
	if not render_scene_buffers or not scene_data: return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 and size.y == 0: return

	@warning_ignore("integer_division")
	var x_groups := (size.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var y_groups := (size.y - 1) / 8 + 1
	var z_groups := 1

	# Make sure we have a sampler
	if not sampler_rid.is_valid():
		var sampler_state := RDSamplerState.new()
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_rid = rd.sampler_create(sampler_state)


	var view_count: int = render_scene_buffers.get_view_count()
	for view in view_count:
		var colour_buffer: RID = render_scene_buffers.get_color_layer(view)
		var depth_buffer: RID = render_scene_buffers.get_depth_layer(view)
		var normal_buffer: RID = render_scene_buffers.get_texture("forward_clustered", "normal_roughness")

		var parameters := PackedFloat32Array([size.x, size.y, 0.0, 0.0])
		var inv_proj_mat := scene_data.get_cam_projection().inverse()
		var inv_proj_mat_arr := PackedVector4Array([inv_proj_mat.x, inv_proj_mat.y, inv_proj_mat.z, inv_proj_mat.w])
		var parameter_data = parameters.to_byte_array()
		parameter_data.append_array(inv_proj_mat_arr.to_byte_array())
		rd.buffer_update(parameter_rid, 0, parameter_data.size(), parameter_data)

		# Uniform Buffer
		var storage_buffer := get_uniform(
			[parameter_rid],
			RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,
			0,
		)
		# Input the Colour Buffer
		var uniform_input := get_uniform(
			[colour_buffer],
			RenderingDevice.UNIFORM_TYPE_IMAGE,
			1,
		)
		# Depth Buffer
		var uniform_depth := get_uniform(
			[sampler_rid, depth_buffer],
			RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
			2,
		)
		# Normal Buffer
		var uniform_normal := get_uniform(
			[sampler_rid, normal_buffer],
			RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
			3,
		)
		var uniform_set := UniformSetCacheRD.get_cache(
			shader, 0, 
			[storage_buffer, uniform_input, uniform_depth, uniform_normal]
		)

		# Run the compute shader
		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
		rd.compute_list_end()

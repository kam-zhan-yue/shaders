@tool
class_name NormalShader
extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler_rid: RID
var parameter_rid: RID
var normal_output: RID
var light: DirectionalLight3D

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd:
		RenderingServer.call_on_render_thread(_initialise_compute)

		var parameter_data := get_empty_data()
		parameter_rid = rd.storage_buffer_create(parameter_data.size(), parameter_data)


func get_empty_data() -> PackedByteArray:
	# size and padding: 4 floats
	# camera position: 4 floats
	# light position: 4 floats
	# inv projection matrix: 12 floats
	# inv view matrix: 12 floats
	var matrices := PackedFloat32Array()
	matrices.resize(144)
	matrices.fill(0)

	var parameter_data = matrices.to_byte_array()
	return parameter_data


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			RenderingServer.free_rid(shader)
		if sampler_rid.is_valid():
			rd.free_rid(sampler_rid)
		if parameter_rid.is_valid():
			rd.free_rid(parameter_rid)
		if normal_output.is_valid():
			rd.free_rid(normal_output)


func _initialise_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return

	var shader_file := load("res://mobius/normal_shader/normal_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)


func get_uniform(rids: Array[RID], type: RenderingDevice.UniformType, binding: int) -> RDUniform: 
	var uniform := RDUniform.new() 
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in rids:
		uniform.add_id(rid)
	return uniform


func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if not(rd and p_effect_callback_type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT and pipeline.is_valid()):
		return
	if not normal_output.is_valid() or not light:
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
		if not sampler_rid.is_valid():
			var sampler_state := RDSamplerState.new()
			sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
			sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
			sampler_rid = rd.sampler_create(sampler_state)

		var view_count: int = render_scene_buffers.get_view_count()
		for view in view_count:
			var parameters := PackedFloat32Array([size.x, size.y, 0.0, 0.0])
			var camera_pos := scene_data.get_cam_transform().origin
			var camera_pos_array := PackedFloat32Array([camera_pos.x, camera_pos.y, camera_pos.z, 1.0])

			var light_dir := light.rotation
			var light_dir_array := PackedFloat32Array([light_dir.x, light_dir.y, light_dir.z, 1.0])

			var inv_proj_mat := scene_data.get_cam_projection().inverse()
			var inv_proj_mat_array := PackedVector4Array([inv_proj_mat.x, inv_proj_mat.y, inv_proj_mat.z, inv_proj_mat.w])

			var inv_view_mat := scene_data.get_view_projection(view).inverse()
			var inv_view_mat_array := PackedVector4Array([inv_view_mat.x, inv_view_mat.y, inv_view_mat.z, inv_view_mat.w])

			var parameter_data = parameters.to_byte_array()
			parameter_data.append_array(camera_pos_array.to_byte_array())
			parameter_data.append_array(light_dir_array.to_byte_array())
			parameter_data.append_array(inv_proj_mat_array.to_byte_array())
			parameter_data.append_array(inv_view_mat_array.to_byte_array())
			rd.buffer_update(parameter_rid, 0, parameter_data.size(), parameter_data)

			# Storage Buffer
			var storage_buffer := get_uniform(
				[parameter_rid],
				RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,
				0,
			)
			# Output Image
			var uniform_output := get_uniform(
				[normal_output],
				RenderingDevice.UNIFORM_TYPE_IMAGE,
				1,
			)
			# Normal Buffer
			var normal_buffer: RID = render_scene_buffers.get_texture("forward_clustered", "normal_roughness")
			var uniform_normal := get_uniform(
				[sampler_rid, normal_buffer],
				RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
				2,
			)
			# Depth Buffer
			var depth_buffer: RID = render_scene_buffers.get_depth_layer(view)

			var uniform_depth := get_uniform(
				[sampler_rid, depth_buffer],
				RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
				3,
			)

			var uniform_set := UniformSetCacheRD.get_cache(
				shader, 0, 
				[storage_buffer, uniform_output, uniform_normal, uniform_depth]
			)

			# Run the compute shader
			var compute_list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
			rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
			# rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
			rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
			rd.compute_list_end()

@tool
class_name MobiusShader
extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler_rid: RID
var normal_input: RID
var image_sampler_rid: RID
var parameter_rid: RID
var noise_rid: RID
var crosshatch_rid: RID
var active: bool

@export_category("Noise")
@export var noise_texture: Texture2D
@export var crosshatch: Texture2D

@export_category("Shadow")
@export var shadow_tiling := Vector2.ONE
@export var shadow_horizontal := 0.4
@export var shadow_vertical := 0.6
@export var shadow_diagonal := 0.8

@export_category("Outline")
@export var outline_colour := Color.WHITE
@export var outline_frequency := 2.0
@export var outline_amplitude := 2.0
@export var depth_thickness := 1.0
@export var normal_thickness := 1.0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd:
		RenderingServer.call_on_render_thread(_initialise_compute)

		var parameter_data := get_empty_data()
		parameter_rid = rd.storage_buffer_create(parameter_data.size(), parameter_data)


func get_empty_data() -> PackedByteArray:
	# size + reserved: 4 floats
	# inv view matrix: 12 floats
	var matrices := PackedFloat32Array()
	matrices.resize(16)
	matrices.fill(0)

	var sobel_data = get_sobel_parameters()
	var parameter_data = matrices.to_byte_array()
	parameter_data.append_array(sobel_data)
	return parameter_data

func get_sobel_parameters() -> PackedByteArray:
	var shadow_data := PackedFloat32Array([shadow_tiling.x, shadow_tiling.y, shadow_horizontal, shadow_vertical, shadow_diagonal, 0.0])
	var outline_colour_data := PackedFloat32Array([outline_colour.r, outline_colour.b, outline_colour.g, outline_colour.a])
	var outline_parameters := PackedFloat32Array([outline_amplitude, outline_frequency, depth_thickness, normal_thickness])
	var parameter_data := shadow_data.to_byte_array()
	parameter_data.append_array(outline_colour_data.to_byte_array())
	parameter_data.append_array(outline_parameters.to_byte_array())
	return parameter_data


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			RenderingServer.free_rid(shader)
		if sampler_rid.is_valid():
			rd.free_rid(sampler_rid)
		if image_sampler_rid.is_valid():
			rd.free_rid(image_sampler_rid)
		if parameter_rid.is_valid():
			rd.free_rid(parameter_rid)
		if noise_rid.is_valid():
			rd.free_rid(noise_rid)
		if crosshatch_rid.is_valid():
			rd.free_rid(crosshatch_rid)


func get_uniform(rids: Array[RID], type: RenderingDevice.UniformType, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in rids:
		uniform.add_id(rid)
	return uniform


func _initialise_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return

	var shader_file := load("res://mobius/mobius_shader/mobius_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)


func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	# hack to not get the shader to run while in scene mode
	if not active:
		return
	if not(rd and p_effect_callback_type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT and pipeline.is_valid()):
		return
	if not normal_input.is_valid():
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

		# Make sure we have an image sampler
		if not image_sampler_rid.is_valid():
			var image_sampler_state := RDSamplerState.new()
			image_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
			image_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
			image_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
			image_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
			image_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
			image_sampler_rid = rd.sampler_create(image_sampler_state)

		var view_count: int = render_scene_buffers.get_view_count()
		for view in view_count:
			var colour_buffer: RID = render_scene_buffers.get_color_layer(view)
			var depth_buffer: RID = render_scene_buffers.get_depth_layer(view)

			var parameters := PackedFloat32Array([size.x, size.y])
			var sobel_parameters := get_sobel_parameters()

			var parameter_data = parameters.to_byte_array()
			parameter_data.append_array(sobel_parameters)
			rd.buffer_update(parameter_rid, 0, parameter_data.size(), parameter_data)

			# Uniform Buffer
			var storage_buffer := get_uniform(
				[parameter_rid],
				RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,
				0,
			)

			# Colour Image
			var uniform_colour := get_uniform(
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
				[sampler_rid, normal_input],
				RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
				3,
			)

			# Noise Buffer
			if not noise_rid:
				var noise_image: Image = noise_texture.get_image()
				noise_image.convert(Image.FORMAT_RF)
				var noise_format := RDTextureFormat.new()
				noise_format.width = noise_image.get_width()
				noise_format.height = noise_image.get_height()
				noise_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
				noise_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
				noise_rid = rd.texture_create(noise_format, RDTextureView.new(), [noise_image.get_data()])

			if not noise_rid.is_valid():
				return

			var uniform_noise := get_uniform(
				[sampler_rid, noise_rid],
				RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
				4,
			)

			# Crosshatch Buffer
			if not crosshatch_rid:
				var crosshatch_image: Image = crosshatch.get_image()
				crosshatch_image.clear_mipmaps()
				crosshatch_image.convert(Image.FORMAT_RGBA8)
				crosshatch_image.decompress()
				var crosshatch_format := RDTextureFormat.new()
				crosshatch_format.width = crosshatch.get_width()
				crosshatch_format.height = crosshatch.get_height()
				crosshatch_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB
				crosshatch_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
				crosshatch_rid = rd.texture_create(crosshatch_format, RDTextureView.new(), [crosshatch_image.get_data()])

			if not crosshatch_rid.is_valid():
				return

			var uniform_crosshatch := get_uniform(
				[image_sampler_rid, crosshatch_rid],
				RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,
				5,
			)

			var uniform_set := UniformSetCacheRD.get_cache(
				shader, 0, 
				[storage_buffer, uniform_colour, uniform_depth, uniform_normal, uniform_noise, uniform_crosshatch]
			)

			# Run the compute shader
			var compute_list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
			rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
			rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
			rd.compute_list_end()

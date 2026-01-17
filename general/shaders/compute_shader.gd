class_name ComputeShader

func _init() -> void:
	# Create a local RenderingDevice and init the shader
	var rd := RenderingServer.create_local_rendering_device()
	var shader_file = load("res://shaders/compute_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var shader := rd.shader_create_from_spirv(shader_spirv)

	# Create an input buffer
	var input := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var input_bytes := input.to_byte_array()
	var buffer := rd.storage_buffer_create(input_bytes.size(), input_bytes)

	# Create a uniform to assign the buffer to the rendering device
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer)
	var uniform_set := rd.uniform_set_create([uniform], shader, 0)

	# Define the compute shader pipeline
	var pipeline := rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 5, 1, 1)
	rd.compute_list_end()

	# Execute the compute shader
	rd.submit()
	rd.sync()

	# Retrieve the results
	var output_bytes := rd.buffer_get_data(buffer)
	var output := output_bytes.to_float32_array()

	print("Input: ", input)
	print("Output: ", output)

	rd.free_rid(buffer)
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)

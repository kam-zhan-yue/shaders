@tool
class_name Pixel
extends Node3D

@export var environment: Node

var texture_rid: RID

var last_window_size : Vector2i

func _ready() -> void:
	last_window_size = DisplayServer.window_get_size()
	create_texture()


func _process(_delta) -> void:
	var new_size = DisplayServer.window_get_size()

	if new_size != last_window_size:
		last_window_size = new_size
		create_texture()


func is_valid() -> bool:
	var rd := RenderingServer.get_rendering_device()
	return rd != null

func create_texture() -> void:
	if not is_valid(): return
	var rd := RenderingServer.get_rendering_device()

	# Ensure we free the previously created texture
	if texture_rid.is_valid():
		rd.free_rid(texture_rid)

	var stretch_transform := get_viewport().get_stretch_transform()
	var viewport := get_viewport().get_visible_rect().size
	var fmt := RDTextureFormat.new()
	fmt.width = int(viewport.x * stretch_transform.x.x)
	fmt.height = int(viewport.y * stretch_transform.y.y)
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	texture_rid = rd.texture_create(fmt, RDTextureView.new())
	var pixel_shader := environment.compositor.compositor_effects[0] as PixelShader
	var edge_shader := environment.compositor.compositor_effects[1] as EdgeShader
	pixel_shader.screen_texture = texture_rid
	edge_shader.screen_texture = texture_rid

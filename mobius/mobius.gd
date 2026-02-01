@tool
class_name Mobius
extends Node

@export var environment: Node
@export var directional_light: DirectionalLight3D

var active := false
var normal_map: RID

var last_window_size : Vector2i

func _ready() -> void:
	last_window_size = DisplayServer.window_get_size()
	active = true
	create_normal_texture()


func _process(_delta) -> void:
	var new_size = DisplayServer.window_get_size()

	if new_size != last_window_size:
		last_window_size = new_size
		create_normal_texture()


func is_valid() -> bool:
	var rd := RenderingServer.get_rendering_device()
	return rd and environment and directional_light


func create_normal_texture() -> void:
	if not is_valid(): return
	var rd := RenderingServer.get_rendering_device()


	# Ensure we free the previously created texture
	if normal_map.is_valid():
		rd.free_rid(normal_map)

	var stretch_transform := get_viewport().get_stretch_transform()
	var viewport := get_viewport().get_visible_rect().size
	var fmt := RDTextureFormat.new()
	fmt.width = int(viewport.x * stretch_transform.x.x)
	fmt.height = int(viewport.y * stretch_transform.y.y)
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	normal_map = rd.texture_create(fmt, RDTextureView.new())
	environment.compositor.compositor_effects[0].light = directional_light
	environment.compositor.compositor_effects[0].normal_output = normal_map
	environment.compositor.compositor_effects[1].normal_input = normal_map
	environment.compositor.compositor_effects[1].active = active

class_name CameraControls
extends Camera3D

const TILT_LOWER_LIMIT := deg_to_rad(-80.0)
const TILT_UPPER_LIMIT := deg_to_rad(80.0)

@export var speed := 10.0
@export var mouse_sensitivity := 5.0

var _rotation_input: float
var _tilt_input: float
var _movement_input: Vector2

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	_update_position(delta)
	_update_rotation(delta)


func _update_position(delta: float) -> void:
	position += basis.z * _movement_input.y * delta * speed
	position += basis.x * _movement_input.x * delta * speed

func _update_rotation(delta: float) -> void:
	var next_rotation := transform.basis.get_euler()
	next_rotation.x += _tilt_input * delta
	next_rotation.x = clamp(next_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	next_rotation.y += _rotation_input * delta
	
	transform.basis = Basis.from_euler(next_rotation)
	
	rotation.z = 0.0
	_rotation_input = 0.0
	_tilt_input = 0.0

func _unhandled_input(event: InputEvent) -> void:
	var is_mouse_input := event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if is_mouse_input:
		_rotation_input = -event.relative.x * mouse_sensitivity
		_tilt_input = -event.relative.y * mouse_sensitivity

func _input(_event: InputEvent) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_movement_input = input


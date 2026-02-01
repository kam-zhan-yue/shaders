extends Camera3D

@export var speed := 10.0

var direction: Vector3

func _process(delta: float) -> void:
	var velocity := self.speed * self.direction * delta
	var change := Vector3(velocity.x, velocity.y, 0.0)
	global_position += change

func _input(_event: InputEvent) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	self.direction = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()


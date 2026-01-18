extends Camera3D

@export var speed := 10.0

var direction: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var velocity := self.speed * self.direction * delta
	var change := Vector3(velocity.x, velocity.y, 0.0)
	global_position += change

func _input(_event: InputEvent) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	self.direction = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()


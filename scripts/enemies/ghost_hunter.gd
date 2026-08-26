extends CharacterBody2D

@export var patrol_speed: float = 120.0
@export var patrol_distance: float = 500.0

const GRAVITY := 900.0
const MAX_FALL_SPEED := 500.0

var start_position: Vector2
var direction: int = 1


func _ready() -> void:
	start_position = position


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_patrol()

	move_and_slide()

	_update_facing()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)
	else:
		velocity.y = 0.0


func _handle_patrol() -> void:
	var left_boundary := start_position.x - patrol_distance
	var right_boundary := start_position.x + patrol_distance

	if position.x <= left_boundary:
		direction = 1
	elif position.x >= right_boundary:
		direction = -1

	velocity.x = direction * patrol_speed


func _update_facing() -> void:
	$Visuals.scale.x = abs($Visuals.scale.x) * direction

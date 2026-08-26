extends CharacterBody2D

@export var move_speed: float = 320.0
@export var acceleration: float = 1800.0
@export var deceleration: float = 1200.0
@export var jump_velocity: float = -420.0
@export var gravity: float = 900.0
@export var max_fall_speed: float = 500.0

const MAX_JUMPS := 2

var jump_count := 0


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal_movement(delta)

	move_and_slide()

	if is_on_floor():
		jump_count = 0


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
		velocity.y = min(velocity.y, max_fall_speed)


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and jump_count < MAX_JUMPS:
		velocity.y = jump_velocity
		jump_count += 1


func _handle_horizontal_movement(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)

extends CharacterBody2D

signal soul_changed(current_soul: int, max_soul: int)
signal soul_depleted

@export var move_speed: float = 320.0
@export var acceleration: float = 1800.0
@export var deceleration: float = 1200.0
@export var jump_velocity: float = -420.0
@export var gravity: float = 900.0
@export var max_fall_speed: float = 500.0
@export var hit_immunity_duration: float = 1.0

const MAX_JUMPS := 2
const MAX_SOUL := 3

var jump_count := 0
var soul: int = MAX_SOUL
var is_immune: bool = false


func _ready() -> void:
	$ImmunityTimer.wait_time = hit_immunity_duration
	$ImmunityTimer.timeout.connect(_on_immunity_timer_timeout)
	$HitFlashTimer.timeout.connect(_on_hit_flash_timer_timeout)


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


# Central entry point for any hazard that should corrupt the player's SOUL.
# Ignored while immune or once SOUL has already reached zero.
func take_corruption(amount: int = 1) -> void:
	if is_immune or soul <= 0:
		return

	soul = max(soul - amount, 0)
	soul_changed.emit(soul, MAX_SOUL)

	if soul <= 0:
		soul_depleted.emit()
		# TEMPORARY DEBUG: remove once Evil Ghost transformation / game over exists.
		print("SOUL depleted — Little Ghost has become an Evil Ghost (debug placeholder).")

	_start_immunity()


# Central entry point for anything that should restore the player's SOUL.
# Clamped to MAX_SOUL; only emits soul_changed if SOUL actually changed.
func restore_soul(amount: int = 1) -> void:
	var new_soul: int = min(soul + amount, MAX_SOUL)
	if new_soul == soul:
		return

	soul = new_soul
	soul_changed.emit(soul, MAX_SOUL)


func _start_immunity() -> void:
	is_immune = true
	$HitFlashTimer.start()
	$ImmunityTimer.start()


func _on_immunity_timer_timeout() -> void:
	is_immune = false
	$HitFlashTimer.stop()
	$Body.modulate.a = 1.0


# Temporary hit feedback: blinks the player semi-transparent while immune.
func _on_hit_flash_timer_timeout() -> void:
	$Body.modulate.a = 0.4 if $Body.modulate.a >= 1.0 else 1.0

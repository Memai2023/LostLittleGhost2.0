extends CharacterBody2D

signal player_spotted
signal player_lost

@export var patrol_speed: float = 120.0
@export var patrol_distance: float = 500.0
@export var cone_length: float = 260.0
@export var cone_width: float = 160.0
# Brief stop at each patrol boundary before reversing, so the facing flip
# reads as a deliberate turn rather than an instant reversal.
@export var patrol_pause_duration: float = 0.5

const GRAVITY := 900.0
const MAX_FALL_SPEED := 500.0

# TEMPORARY DEBUG FEEDBACK — these two colors only exist to make detection
# visible during development. Remove once real gameplay feedback (SOUL /
# damage) replaces them in a later step.
const DEBUG_CONE_COLOR_IDLE := Color(1.0, 0.95, 0.6, 0.75)
const DEBUG_CONE_COLOR_DETECTED := Color(1.0, 0.2, 0.2, 0.55)

# Per-frame lantern position, in Visuals-local space, measured from each
# source frame's own lit-flame pixel cluster (all 6 frames hold the lantern
# in the same hand, so these stay closely clustered rather than flipping
# sides like the old 3-frame set did).
const LANTERN_OFFSET_IDLE_A := Vector2(19.7, -20.3)
const LANTERN_OFFSET_IDLE_B := Vector2(26.8, -20.5)
const LANTERN_OFFSET_WALK_A := Vector2(28.0, -21.5)
const LANTERN_OFFSET_WALK_B := Vector2(26.7, -19.9)
const LANTERN_OFFSET_WALK_C := Vector2(30.6, -20.2)
const LANTERN_OFFSET_WALK_D := Vector2(29.2, -19.7)

var start_position: Vector2
var direction: int = 1
var player_in_cone: bool = false
var is_paused: bool = false
var _pause_timer: float = 0.0


func _ready() -> void:
	start_position = position
	_build_flashlight_cone()
	$Visuals/FlashlightPivot/DetectionArea.body_entered.connect(_on_detection_area_body_entered)
	$Visuals/FlashlightPivot/DetectionArea.body_exited.connect(_on_detection_area_body_exited)
	$Hurtbox.body_entered.connect(_on_hurtbox_body_entered)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_patrol(delta)

	move_and_slide()

	_update_facing()
	_update_animation()
	_update_lantern_position()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)
	else:
		velocity.y = 0.0


func _handle_patrol(delta: float) -> void:
	if is_paused:
		_pause_timer -= delta
		velocity.x = 0.0
		if _pause_timer <= 0.0:
			is_paused = false
			direction *= -1
		return

	var left_boundary := start_position.x - patrol_distance
	var right_boundary := start_position.x + patrol_distance

	var reached_end := (direction == 1 and position.x >= right_boundary) \
		or (direction == -1 and position.x <= left_boundary)
	if reached_end:
		is_paused = true
		_pause_timer = patrol_pause_duration
		velocity.x = 0.0
		return

	velocity.x = direction * patrol_speed


# direction only ever changes at the end of a patrol-boundary pause above
# (never from a per-frame velocity read), so facing can't flicker -- it
# stays fixed on the last real heading for the whole pause, then flips once.
func _update_facing() -> void:
	$Visuals.scale.x = abs($Visuals.scale.x) * direction


# Reuses the existing patrol-driven velocity -- no separate movement/idle
# state exists (or is needed) beyond what _handle_patrol() already sets.
# While paused at a patrol boundary, velocity.x is 0, so this naturally
# shows "idle" during the pause.
func _update_animation() -> void:
	var target_animation: StringName = &"walk" if absf(velocity.x) > 0.1 else &"idle"
	if $Visuals/AnimatedSprite2D.animation != target_animation:
		$Visuals/AnimatedSprite2D.play(target_animation)


# Moves the (shared) flashlight pivot and lantern glow to match the
# lantern's drawn position in whichever frame is currently showing. Both
# are children of Visuals, so the existing facing-flip (_update_facing)
# mirrors them correctly along with the rest of the art.
func _update_lantern_position() -> void:
	var sprite: AnimatedSprite2D = $Visuals/AnimatedSprite2D
	var offset: Vector2
	if sprite.animation == &"walk":
		match sprite.frame:
			0: offset = LANTERN_OFFSET_WALK_A
			1: offset = LANTERN_OFFSET_WALK_B
			2: offset = LANTERN_OFFSET_WALK_C
			_: offset = LANTERN_OFFSET_WALK_D
	else:
		offset = LANTERN_OFFSET_IDLE_B if sprite.frame == 1 else LANTERN_OFFSET_IDLE_A
	$Visuals/FlashlightPivot.position = offset
	$Visuals/LanternGlow.position = offset


func _build_flashlight_cone() -> void:
	var cone_points := PackedVector2Array([
		Vector2.ZERO,
		Vector2(cone_length, -cone_width / 2.0),
		Vector2(cone_length, cone_width / 2.0),
	])
	$Visuals/FlashlightPivot/Cone.polygon = cone_points
	$Visuals/FlashlightPivot/DetectionArea/CollisionPolygon2D.polygon = cone_points

	var cone_material: ShaderMaterial = $Visuals/FlashlightPivot/Cone.material
	cone_material.set_shader_parameter("cone_length", cone_length)
	cone_material.set_shader_parameter("cone_width", cone_width)


func _on_detection_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_cone = true
	player_spotted.emit()
	_set_debug_cone_color(true)
	if body.has_method("take_corruption"):
		body.take_corruption()


func _on_detection_area_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_cone = false
	player_lost.emit()
	_set_debug_cone_color(false)


func _on_hurtbox_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("take_corruption"):
		body.take_corruption()


# ---------------------------------------------------------------------------
# TEMPORARY DEBUG FEEDBACK
# Changes the cone's color while the player is inside it, purely so
# detection can be verified visually during development. Safe to delete
# once real gameplay feedback exists.
# ---------------------------------------------------------------------------
func _set_debug_cone_color(is_player_detected: bool) -> void:
	var cone_material: ShaderMaterial = $Visuals/FlashlightPivot/Cone.material
	cone_material.set_shader_parameter(
		"warm_color", DEBUG_CONE_COLOR_DETECTED if is_player_detected else DEBUG_CONE_COLOR_IDLE
	)

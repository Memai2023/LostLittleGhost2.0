extends CharacterBody2D

signal player_spotted
signal player_lost

@export var patrol_speed: float = 120.0
@export var patrol_distance: float = 500.0
@export var cone_length: float = 260.0
@export var cone_width: float = 160.0

const GRAVITY := 900.0
const MAX_FALL_SPEED := 500.0

# TEMPORARY DEBUG FEEDBACK — these two colors only exist to make detection
# visible during development. Remove once real gameplay feedback (SOUL /
# damage) replaces them in a later step.
const DEBUG_CONE_COLOR_IDLE := Color(1.0, 0.95, 0.6, 0.35)
const DEBUG_CONE_COLOR_DETECTED := Color(1.0, 0.2, 0.2, 0.55)

var start_position: Vector2
var direction: int = 1
var player_in_cone: bool = false


func _ready() -> void:
	start_position = position
	_build_flashlight_cone()
	$Visuals/FlashlightPivot/DetectionArea.body_entered.connect(_on_detection_area_body_entered)
	$Visuals/FlashlightPivot/DetectionArea.body_exited.connect(_on_detection_area_body_exited)


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


func _build_flashlight_cone() -> void:
	var cone_points := PackedVector2Array([
		Vector2.ZERO,
		Vector2(cone_length, -cone_width / 2.0),
		Vector2(cone_length, cone_width / 2.0),
	])
	$Visuals/FlashlightPivot/Cone.polygon = cone_points
	$Visuals/FlashlightPivot/DetectionArea/CollisionPolygon2D.polygon = cone_points


func _on_detection_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_cone = true
	player_spotted.emit()
	_set_debug_cone_color(true)


func _on_detection_area_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_cone = false
	player_lost.emit()
	_set_debug_cone_color(false)


# ---------------------------------------------------------------------------
# TEMPORARY DEBUG FEEDBACK
# Changes the cone's color while the player is inside it, purely so
# detection can be verified visually during development. Safe to delete
# once real gameplay feedback exists.
# ---------------------------------------------------------------------------
func _set_debug_cone_color(is_player_detected: bool) -> void:
	$Visuals/FlashlightPivot/Cone.color = DEBUG_CONE_COLOR_DETECTED if is_player_detected else DEBUG_CONE_COLOR_IDLE

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
@export var respawn_delay: float = 1.0
@export var idle_pose_delay: float = 0.5
@export var good_orb_reaction_duration: float = 0.7
@export var side_texture: Texture2D
@export var front_texture: Texture2D
@export var holding_orb_texture: Texture2D

const MAX_JUMPS := 2
const MAX_SOUL := 3
const PLAYER_COLLISION_LAYER := 2

const NORMAL_TINT := Color(1, 1, 1, 1)
const RESPAWN_TINT := Color(0.45, 0.12, 0.55, 0.6)

# Per-pose visual alignment so each PNG's own transparent padding lines up
# with the same collision-shape bottom (y=19) and horizontal center (x=0).
const SIDE_SCALE := Vector2(0.31, 0.31)
const SIDE_POSITION := Vector2(0, -9.3)
const FRONT_SCALE := Vector2(0.297, 0.297)
const FRONT_POSITION := Vector2(-0.15, -11.0)
const HOLDING_ORB_SCALE := Vector2(0.29, 0.29)
const HOLDING_ORB_POSITION := Vector2(-1.3, -10.0)

const POSE_SIDE := "side"
const POSE_FRONT := "front"
const POSE_HOLDING_ORB := "holding_orb"

var jump_count := 0
var soul: int = MAX_SOUL
var is_immune: bool = false
var is_respawning: bool = false
var respawn_position: Vector2
var facing_direction: int = 1
var idle_timer: float = 0.0
var current_pose: String = POSE_SIDE
var is_showing_good_orb_reaction: bool = false


func _ready() -> void:
	respawn_position = global_position

	$ImmunityTimer.wait_time = hit_immunity_duration
	$ImmunityTimer.timeout.connect(_on_immunity_timer_timeout)
	$HitFlashTimer.timeout.connect(_on_hit_flash_timer_timeout)

	$RespawnTimer.wait_time = respawn_delay
	$RespawnTimer.timeout.connect(_on_respawn_timer_timeout)

	$GoodOrbReactionTimer.wait_time = good_orb_reaction_duration
	$GoodOrbReactionTimer.timeout.connect(_on_good_orb_reaction_timer_timeout)


func _physics_process(delta: float) -> void:
	if is_respawning:
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal_movement(delta)

	move_and_slide()

	if is_on_floor():
		jump_count = 0

	_update_visual_pose(delta)


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
		facing_direction = 1 if direction > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)


# Chooses between the side (moving/airborne) and front (idle-on-ground) poses.
# Idle time only accumulates while grounded and not moving, so brief pauses
# while changing direction never reach the delay and never flicker.
# Skipped entirely while the Good Orb reaction pose is active, so the
# ordinary idle logic can never replace it before its timer finishes.
func _update_visual_pose(delta: float) -> void:
	if is_showing_good_orb_reaction:
		return

	var moving_horizontally := Input.get_axis("move_left", "move_right") != 0.0
	var airborne := not is_on_floor()

	if moving_horizontally or airborne:
		idle_timer = 0.0
		_apply_side_pose()
	else:
		idle_timer += delta
		if idle_timer >= idle_pose_delay:
			_apply_front_pose()
		else:
			_apply_side_pose()


func _apply_side_pose() -> void:
	if current_pose != POSE_SIDE:
		current_pose = POSE_SIDE
		$GoodGhostSprite.texture = side_texture
		$GoodGhostSprite.scale = SIDE_SCALE
		$GoodGhostSprite.position = SIDE_POSITION
	$GoodGhostSprite.flip_h = facing_direction < 0


func _apply_front_pose() -> void:
	if current_pose != POSE_FRONT:
		current_pose = POSE_FRONT
		$GoodGhostSprite.texture = front_texture
		$GoodGhostSprite.scale = FRONT_SCALE
		$GoodGhostSprite.position = FRONT_POSITION
	$GoodGhostSprite.flip_h = false


# Called by Good Spirit Orbs on collection, regardless of whether SOUL was
# actually restored. Temporarily overrides the idle pose without touching
# movement; collecting another orb mid-reaction simply restarts the timer.
func show_good_orb_reaction() -> void:
	if is_respawning:
		return

	is_showing_good_orb_reaction = true
	current_pose = POSE_HOLDING_ORB
	$GoodGhostSprite.texture = holding_orb_texture
	$GoodGhostSprite.scale = HOLDING_ORB_SCALE
	$GoodGhostSprite.position = HOLDING_ORB_POSITION
	$GoodGhostSprite.flip_h = false

	$GoodOrbReactionTimer.start()


func _on_good_orb_reaction_timer_timeout() -> void:
	is_showing_good_orb_reaction = false

	var moving_horizontally := Input.get_axis("move_left", "move_right") != 0.0
	var airborne := not is_on_floor()

	if moving_horizontally or airborne:
		idle_timer = 0.0
		_apply_side_pose()
	else:
		# Already past the idle threshold: show the front pose immediately
		# rather than waiting through another idle delay.
		idle_timer = idle_pose_delay
		_apply_front_pose()


# Called by checkpoints to update where the player will respawn.
func set_respawn_position(new_respawn_position: Vector2) -> void:
	respawn_position = new_respawn_position


# Central entry point for any hazard that should corrupt the player's SOUL.
# Ignored while immune, already depleted, or already respawning.
func take_corruption(amount: int = 1) -> void:
	if is_respawning or is_immune or soul <= 0:
		return

	soul = max(soul - amount, 0)
	soul_changed.emit(soul, MAX_SOUL)

	if soul <= 0:
		soul_depleted.emit()
		_begin_respawn_sequence()
		return

	_start_immunity()


# Called by fall-detection hazards. Reuses the same respawn sequence as
# SOUL depletion, without treating falling as corruption damage.
func fall_reset() -> void:
	if is_respawning:
		return
	_begin_respawn_sequence()


# Central entry point for anything that should restore the player's SOUL.
# Clamped to MAX_SOUL; only emits soul_changed if SOUL actually changed.
func restore_soul(amount: int = 1) -> void:
	if is_respawning:
		return

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
	$GoodGhostSprite.modulate.a = 1.0


# Temporary hit feedback: blinks the player semi-transparent while immune.
func _on_hit_flash_timer_timeout() -> void:
	$GoodGhostSprite.modulate.a = 0.4 if $GoodGhostSprite.modulate.a >= 1.0 else 1.0


# Begins the short Evil Ghost / respawn sequence once SOUL reaches zero.
# Freezes movement, hides the player from hazard/orb detection, and plays a
# simple placeholder corruption effect until the respawn timer fires.
func _begin_respawn_sequence() -> void:
	if is_respawning:
		return

	is_respawning = true
	is_immune = true
	$HitFlashTimer.stop()

	is_showing_good_orb_reaction = false
	$GoodOrbReactionTimer.stop()

	velocity = Vector2.ZERO
	collision_layer = 0

	$GoodGhostSprite.modulate = RESPAWN_TINT

	$RespawnTimer.start()


func _on_respawn_timer_timeout() -> void:
	global_position = respawn_position
	velocity = Vector2.ZERO
	jump_count = 0

	soul = MAX_SOUL
	soul_changed.emit(soul, MAX_SOUL)

	$GoodGhostSprite.modulate = NORMAL_TINT
	collision_layer = PLAYER_COLLISION_LAYER
	is_immune = false
	is_respawning = false

	idle_timer = 0.0
	_apply_side_pose()

	$Camera2D.reset_smoothing()

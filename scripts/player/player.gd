extends CharacterBody2D

signal soul_changed(current_soul: int, max_soul: int)
signal soul_depleted

enum RespawnCause { SOUL_CORRUPTION, FALL_DEATH }

@export var move_speed: float = 320.0
@export var acceleration: float = 1800.0
@export var deceleration: float = 1200.0
@export var jump_velocity: float = -420.0
@export var gravity: float = 900.0
@export var max_fall_speed: float = 500.0
@export var hit_immunity_duration: float = 1.0
# Death-pose display duration for FALL_DEATH only.
@export var respawn_delay: float = 0.8
@export var idle_pose_delay: float = 0.5
@export var good_orb_reaction_duration: float = 0.7
# Evil Ghost display duration for SOUL_CORRUPTION only.
@export var evil_pose_duration: float = 3.0
@export var crying_pose_duration: float = 0.5
# How long a Transparent Caster pickup's stealth effect lasts.
@export var stealth_duration: float = 4.5
@export var side_texture: Texture2D
@export var front_texture: Texture2D
@export var holding_orb_texture: Texture2D
@export var dead_texture: Texture2D
@export var evil_texture: Texture2D
@export var surprise_texture: Texture2D
@export var crying_texture: Texture2D

const MAX_JUMPS := 2
const MAX_SOUL := 3
const PLAYER_COLLISION_LAYER := 2

# This is primarily a horizontal platformer: the camera should track the
# player's X position but stay at one deliberate vertical framing at all
# times, rather than following normal jump/fall/elevation-change movement.
# Chosen so the player sits comfortably below center at the graveyard spawn
# (Y=850), while the level's full ground-height range (~580-950) stays
# framed with margin at both ends.
const CAMERA_FIXED_Y := 740.0

const NORMAL_TINT := Color(1, 1, 1, 1)
const RESPAWN_TINT := Color(0.45, 0.12, 0.55, 0.6)
const STEALTH_TINT := Color(0.6, 0.85, 1.0, 0.4)

# Per-pose visual alignment so each PNG's own transparent padding lines up
# with the same collision-shape bottom (y=19) and horizontal center (x=0).
# Y values carry a deliberate -7 hover (vs. the original alpha-bbox
# "touching" alignment, y=19): the ghost is meant to float above whatever
# it's standing on, unlike the ground-hugging Ghost Hunter, but sit close
# enough to read as grounded rather than floaty (reduced from an earlier
# -10 hover). Collision (CollisionShape2D, still bottom at y=19) is
# untouched -- this is visual only.
const SIDE_SCALE := Vector2(0.31, 0.31)
const SIDE_POSITION := Vector2(0, -16.3)
const FRONT_SCALE := Vector2(0.297, 0.297)
const FRONT_POSITION := Vector2(-0.15, -18.0)
const HOLDING_ORB_SCALE := Vector2(0.29, 0.29)
const HOLDING_ORB_POSITION := Vector2(-1.3, -17.0)
const DEAD_SCALE := Vector2(0.323, 0.323)
const DEAD_POSITION := Vector2(0.97, -18.65)
const EVIL_SCALE := Vector2(0.234, 0.234)
const EVIL_POSITION := Vector2(1.52, -18.0)
const SURPRISE_SCALE := Vector2(0.302, 0.302)
const SURPRISE_POSITION := Vector2(-0.15, -16.95)
const CRYING_SCALE := Vector2(0.151, 0.151)
const CRYING_POSITION := Vector2(-0.6, -19.06)

const POSE_SIDE := "side"
const POSE_FRONT := "front"
const POSE_HOLDING_ORB := "holding_orb"
const POSE_DEAD := "dead"
const POSE_EVIL := "evil"
const POSE_SURPRISE := "surprise"
const POSE_CRYING := "crying"

var jump_count := 0
var soul: int = MAX_SOUL
var is_immune: bool = false
var is_respawning: bool = false
var respawn_cause: RespawnCause = RespawnCause.FALL_DEATH
var respawn_position: Vector2
var facing_direction: int = 1
var idle_timer: float = 0.0
var current_pose: String = POSE_SIDE
var is_showing_good_orb_reaction: bool = false
var is_showing_crying: bool = false
var is_stealthed: bool = false
var is_ending: bool = false
var _ending_camera_frozen_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	respawn_position = global_position

	$ImmunityTimer.wait_time = hit_immunity_duration
	$ImmunityTimer.timeout.connect(_on_immunity_timer_timeout)
	$HitFlashTimer.timeout.connect(_on_hit_flash_timer_timeout)

	$RespawnTimer.wait_time = respawn_delay
	$RespawnTimer.timeout.connect(_on_respawn_timer_timeout)

	$GoodOrbReactionTimer.wait_time = good_orb_reaction_duration
	$GoodOrbReactionTimer.timeout.connect(_on_good_orb_reaction_timer_timeout)

	$EvilGhostTimer.wait_time = evil_pose_duration
	$EvilGhostTimer.timeout.connect(_on_evil_ghost_timer_timeout)

	$CryingTimer.wait_time = crying_pose_duration
	$CryingTimer.timeout.connect(_on_crying_timer_timeout)

	$StealthTimer.wait_time = stealth_duration
	$StealthTimer.timeout.connect(_on_stealth_timer_timeout)


func _physics_process(delta: float) -> void:
	if is_ending:
		_lock_camera_for_ending()
		return

	if is_respawning:
		_lock_camera_vertical()
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal_movement(delta)

	move_and_slide()

	if is_on_floor():
		jump_count = 0

	_lock_camera_vertical()
	_update_visual_pose(delta)


# Holds the camera's global Y at CAMERA_FIXED_Y by offsetting its local
# position against the player's current Y each frame, regardless of jumping,
# falling, or ground-height changes across the level. Horizontal following
# is untouched -- the camera's local X stays at 0 and inherits normal
# parent-following + smoothing, exactly as before.
func _lock_camera_vertical() -> void:
	$Camera2D.position.y = CAMERA_FIXED_Y - global_position.y


# Holds the camera at exactly the world position it had the moment the
# ending started (see stop_for_ending()), regardless of any subsequent
# player movement -- e.g. the portal-entry tween in game_controller.gd
# animating global_position toward PortalEntryTarget. Camera2D is a child of
# the player, so its global_position has to be re-asserted every frame to
# counteract the parent transform change; this keeps the ending framing
# completely still instead of drifting the background/foreground alignment
# players already saw when the portal activated.
func _lock_camera_for_ending() -> void:
	$Camera2D.global_position = _ending_camera_frozen_position


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


# Chooses the player's visual pose every frame. Idle time only accumulates
# while grounded and not moving, so brief pauses while changing direction
# never reach the delay and never flicker.
#
# Priority order (highest to lowest):
#   1. Evil Ghost / Dead Ghost   -- enforced above this function, via the
#      is_respawning gate in _physics_process, which skips this call entirely.
#   2. Crying (valid Ghost Hunter / Bad Orb hit) -- is_showing_crying
#   3. Good Orb holding reaction                 -- is_showing_good_orb_reaction
#   4. Surprise while jumping or falling         -- airborne
#   5. Directional side pose while moving on the ground
#   6. Front-facing idle pose
func _update_visual_pose(delta: float) -> void:
	if is_showing_crying or is_showing_good_orb_reaction:
		return

	var moving_horizontally := Input.get_axis("move_left", "move_right") != 0.0
	var airborne := not is_on_floor()

	if airborne:
		idle_timer = 0.0
		_apply_surprise_pose()
	elif moving_horizontally:
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


# The airborne (jump/fall) pose. Directional like the side pose: flips to
# match facing_direction so a jump/double-jump made while moving (or last
# moved) left visibly faces left instead of always facing right.
func _apply_surprise_pose() -> void:
	if current_pose != POSE_SURPRISE:
		current_pose = POSE_SURPRISE
		$GoodGhostSprite.texture = surprise_texture
		$GoodGhostSprite.scale = SURPRISE_SCALE
		$GoodGhostSprite.position = SURPRISE_POSITION
	$GoodGhostSprite.flip_h = facing_direction < 0


# Called by Good Spirit Orbs on collection, regardless of whether SOUL was
# actually restored. Ranks below Crying (a hit reaction should not be
# interrupted by a pickup) but above Surprise, so collecting an orb while
# airborne still shows the holding-orb reaction.
func show_good_orb_reaction() -> void:
	if is_respawning or is_showing_crying:
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
	_restore_pose_for_current_state()


# Called from take_corruption() for a hit that actually removes a Spirit
# Heart without depleting SOUL (Ghost Hunter body/flashlight, or a Bad
# Spirit Orb -- the game design treats Bad Orb contact as "the same hit
# feedback as other hazards"). Cancels any Good Orb reaction in progress
# and outranks ordinary movement/idle/jump pose updates until its timer
# ends. Does not touch movement, immunity, or flashing -- those are
# handled separately by the caller.
func show_crying_reaction() -> void:
	if is_respawning:
		return

	is_showing_good_orb_reaction = false
	$GoodOrbReactionTimer.stop()

	is_showing_crying = true
	current_pose = POSE_CRYING
	$GoodGhostSprite.texture = crying_texture
	$GoodGhostSprite.scale = CRYING_SCALE
	$GoodGhostSprite.position = CRYING_POSITION
	$GoodGhostSprite.flip_h = false

	$CryingTimer.start()


func _on_crying_timer_timeout() -> void:
	is_showing_crying = false
	_restore_pose_for_current_state()


# Shared by both the Good Orb reaction and the Crying reaction when their
# timers end: pick the correct pose immediately based on the player's
# state at that instant (airborne -> Surprise, moving -> side, still ->
# front) rather than waiting through another idle delay.
func _restore_pose_for_current_state() -> void:
	var moving_horizontally := Input.get_axis("move_left", "move_right") != 0.0
	var airborne := not is_on_floor()

	if airborne:
		idle_timer = 0.0
		_apply_surprise_pose()
	elif moving_horizontally:
		idle_timer = 0.0
		_apply_side_pose()
	else:
		idle_timer = idle_pose_delay
		_apply_front_pose()


# Called by checkpoints to update where the player will respawn.
func set_respawn_position(new_respawn_position: Vector2) -> void:
	respawn_position = new_respawn_position


# Called once by game_controller.gd when the door goal is reached. Freezes
# movement/input the same way is_respawning already does (see
# _physics_process), without touching any respawn/death state -- this is a
# one-way stop for the rest of the session, not a reusable freeze.
func stop_for_ending() -> void:
	is_ending = true
	velocity = Vector2.ZERO
	_ending_camera_frozen_position = $Camera2D.global_position


# Called by Transparent Caster pickups. Makes the ghost undetectable to
# Ghost Hunters (and, as a side effect, to orbs/checkpoints/fall death, the
# same way the existing respawn-immunity window already works) by reusing
# that same collision_layer = 0 pattern -- no Ghost Hunter script is
# touched. Picking up a second caster while already stealthed simply
# restarts the timer rather than stacking.
func activate_stealth() -> void:
	if is_respawning:
		return

	is_stealthed = true
	collision_layer = 0
	$GoodGhostSprite.modulate = STEALTH_TINT
	$StealthTimer.start()


func _on_stealth_timer_timeout() -> void:
	is_stealthed = false
	collision_layer = PLAYER_COLLISION_LAYER
	$GoodGhostSprite.modulate = NORMAL_TINT


# Central entry point for any hazard that should corrupt the player's SOUL.
# Ignored while immune, already depleted, or already respawning.
func take_corruption(amount: int = 1) -> void:
	if is_respawning or is_immune or soul <= 0:
		return

	soul = max(soul - amount, 0)
	soul_changed.emit(soul, MAX_SOUL)

	if soul <= 0:
		# The third heart: skip Crying entirely and go straight to the
		# Evil Ghost sequence, which takes priority over everything else.
		soul_depleted.emit()
		_begin_corruption_respawn_sequence()
		return

	show_crying_reaction()
	_start_immunity()


# Called by fall-detection hazards: always the FALL_DEATH sequence
# (Good -> Dead -> Respawn), never Evil Ghost.
func fall_reset() -> void:
	if is_respawning:
		return

	respawn_cause = RespawnCause.FALL_DEATH
	_apply_fall_corruption()
	_freeze_for_respawn()
	_show_dead_pose()
	$RespawnTimer.start()


# Falling applies the same SOUL consequence as a hazard hit, reusing
# take_corruption()'s soul bookkeeping and soul_changed emission (so the HUD
# updates the same way) -- but always keeps the FALL_DEATH pose/respawn path
# above rather than take_corruption()'s own Crying/Evil Ghost reactions.
func _apply_fall_corruption() -> void:
	if soul <= 0:
		return

	soul = max(soul - 1, 0)
	soul_changed.emit(soul, MAX_SOUL)


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
# Applies to whichever texture is currently active, including Crying.
func _on_hit_flash_timer_timeout() -> void:
	$GoodGhostSprite.modulate.a = 0.4 if $GoodGhostSprite.modulate.a >= 1.0 else 1.0


# Shared setup for both respawn causes: freezes movement, disables further
# damage, hides the player from hazard/orb detection, and cancels any
# in-progress Good Orb or Crying reaction. Does not choose a pose or
# start a timer -- callers do that afterward, since SOUL_CORRUPTION and
# FALL_DEATH show different pre-respawn sequences.
func _freeze_for_respawn() -> void:
	is_respawning = true
	is_immune = true
	$HitFlashTimer.stop()

	is_showing_good_orb_reaction = false
	$GoodOrbReactionTimer.stop()

	is_showing_crying = false
	$CryingTimer.stop()

	velocity = Vector2.ZERO
	collision_layer = 0


# SOUL reaching zero through corruption: Good Ghost -> Evil Ghost -> Respawn
# -> Good Ghost. The dead pose is never shown for this cause. Evil Ghost is
# shown at full color/opacity so it stays clearly visible (no dead-pose tint),
# and goes straight to the final reset once its timer ends -- no extra delay.
func _begin_corruption_respawn_sequence() -> void:
	if is_respawning:
		return

	respawn_cause = RespawnCause.SOUL_CORRUPTION
	_freeze_for_respawn()

	current_pose = POSE_EVIL
	$GoodGhostSprite.texture = evil_texture
	$GoodGhostSprite.scale = EVIL_SCALE
	$GoodGhostSprite.position = EVIL_POSITION
	$GoodGhostSprite.flip_h = false
	$GoodGhostSprite.modulate = NORMAL_TINT

	$EvilGhostTimer.start()


func _on_evil_ghost_timer_timeout() -> void:
	_finish_respawn()


func _show_dead_pose() -> void:
	current_pose = POSE_DEAD
	$GoodGhostSprite.texture = dead_texture
	$GoodGhostSprite.scale = DEAD_SCALE
	$GoodGhostSprite.position = DEAD_POSITION
	$GoodGhostSprite.flip_h = false
	$GoodGhostSprite.modulate = RESPAWN_TINT


func _on_respawn_timer_timeout() -> void:
	_finish_respawn()


# Final reset shared by both respawn causes: teleport to the latest
# checkpoint, restore SOUL, update the HUD (via soul_changed), and restore
# normal visuals, movement and pose selection.
func _finish_respawn() -> void:
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

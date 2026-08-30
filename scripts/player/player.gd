extends CharacterBody2D

signal soul_changed(current_soul: int, max_soul: int)
signal soul_depleted
signal superpower_activated
signal superpower_deactivated

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
# Evil Ghost display duration for SOUL_CORRUPTION only: the fatal-corruption
# sequence is Evil (held full-size for this long) -> shrinks/fades away to
# nothing -> respawn. There is no Dead pose in this sequence -- Dead is
# FALL_DEATH-only (see respawn_delay/$RespawnTimer/_show_dead_pose() below).
@export var evil_pose_duration: float = 1.0
@export var crying_pose_duration: float = 0.5
# How long a Transparent Caster pickup's stealth effect lasts.
@export var stealth_duration: float = 4.5
# How long the checkpoint-activation portal reaction is displayed.
@export var portal_pose_duration: float = 1.1
@export var side_texture: Texture2D
@export var front_texture: Texture2D
@export var holding_orb_texture: Texture2D
@export var dead_texture: Texture2D
@export var evil_texture: Texture2D
@export var surprise_texture: Texture2D
@export var crying_texture: Texture2D
@export var portal_texture: Texture2D
@export var caster_transition_texture: Texture2D

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
# DEAD_SCALE/EVIL_SCALE below are derived from each PNG's *solid-body* alpha
# bounding box (alpha >= 128, i.e. ~50%+ opacity) rather than the full
# alpha>0 canvas bbox used for the other poses -- ghost_evil.png in
# particular has a soft smoky aura reaching almost to the canvas edges, and
# including that faint halo in the bbox would read the ghost's actual body
# as far larger than it looks, undershooting its rendered scale. side/dead
# barely change between thresholds (clean, mostly-hard edges), so this
# threshold doesn't shift their measurements meaningfully, keeping all
# three comparable on the same basis.
#   ghost_good_idle_right.png: canvas 156x220, bbox(a>=128)=(9,9,145,199), size 136x190
#   ghost_evil.png:             canvas 248x257, bbox(a>=128)=(11,19,223,246), size 212x227
#   ghost_good_dead.png:        canvas 192x202, bbox(a>=128)=(7,12,179,195), size 172x183
# Target rendered height = side's own current rendered height
# (190 * SIDE_SCALE.y=0.31 = 58.9px) -- "approximately the same visible
# height as the normal good ghost" means matching side_texture specifically,
# not the ~60px convention used when the other pose sources were sized.
#   DEAD_SCALE.y  = 58.9 / 183 = 0.3219  (was 0.323 -- already nearly right)
#   EVIL_SCALE.y  = 58.9 / 227 = 0.2595  (was 0.234 -- ~10% too small, the
#                                         reported "much smaller" bug)
# Position: content bbox center-x aligned to world x=0, bbox bottom aligned
# to the same y=12 hover anchor (collision bottom 19, minus the shared -7
# hover) every other pose uses -- see the block comment above SIDE_SCALE.
#   dead: center_x=(7+179)/2=93, canvas_cx=96 -> offset -3px * 0.3219 = 0.97
#         bottom=195, canvas_cy=101 -> 12 - (195-101)*0.3219 = -18.26
#   evil: center_x=(11+223)/2=117, canvas_cx=124 -> offset -7px
#
# EVIL_SCALE is a deliberate exception to "match side_texture's height":
# evil_texture's narrower, darker silhouette still reads as visually
# smaller than the normal ghost even at an equal measured pixel height, so
# it's intentionally scaled up further -- to ~75px rendered (vs the shared
# ~59px every other pose uses) -- so it reads as clearly larger and more
# threatening. Position uses the same bottom-anchor/center-x formula as
# every other pose, just re-solved for this larger scale so the increase
# grows upward from the same hover anchor rather than sinking into the
# platform:
#   EVIL_SCALE.y = 0.33 (was 0.2595) -> rendered height = 227*0.33 = 74.91px
#   position.x = 7px * 0.33 = 2.31
#   position.y = 12 - (246-128.5)*0.33 = 12 - 38.775 = -26.78
const DEAD_SCALE := Vector2(0.3219, 0.3219)
const DEAD_POSITION := Vector2(0.97, -18.26)
const EVIL_SCALE := Vector2(0.33, 0.33)
const EVIL_POSITION := Vector2(2.31, -26.78)
const SURPRISE_SCALE := Vector2(0.302, 0.302)
const SURPRISE_POSITION := Vector2(-0.15, -16.95)
const CRYING_SCALE := Vector2(0.151, 0.151)
const CRYING_POSITION := Vector2(-0.6, -19.06)
# ghost_happy.png is a much larger, centered-but-not-exact canvas (700x733)
# than the other pose sources, calibrated the same way as every other pose:
# scale chosen so the alpha (>=128) content renders at the same height as
# side_texture's own rendered content (58.9px = 190px bbox * SIDE_SCALE.y
# 0.31), position from the same bottom-anchor/center-x formula (bottom at
# collision y=19 minus the shared -7 hover, horizontal center at world x=0).
#   ghost_happy.png: canvas 700x733, bbox(a>=128)=(215,214,492,522), size 278x309
#   PORTAL_SCALE.y = 58.9 / 309 = 0.1906
#   center_x=(215+492)/2=353.5, canvas_cx=350 -> offset -3.5px * 0.1906 = -0.67
#   bottom=522, canvas_cy=366.5 -> 12 - (522-366.5)*0.1906 = -17.64
const PORTAL_SCALE := Vector2(0.1906, 0.1906)
const PORTAL_POSITION := Vector2(-0.67, -17.64)

# Warm outline (see assets/shaders/ghost_portal_outline.gdshader), applied
# only while the portal pose is active -- ghost_happy.png's warm tones would
# otherwise blend into the checkpoint's own blue glow. outline_width_px is
# derived from a target on-screen thickness divided by the portal pose's own
# scale, so the ring reads as a consistent ~2.5 screen pixels regardless of
# how PORTAL_SCALE is tuned later.
const PORTAL_OUTLINE_SHADER := preload("res://assets/shaders/ghost_portal_outline.gdshader")
const PORTAL_OUTLINE_COLOR := Color(1.0, 0.82, 0.45, 1.0)
const PORTAL_OUTLINE_TARGET_SCREEN_PX := 2.5

# Scale "pop" played once when the portal pose begins: quickly overshoots to
# 120%, eases back to a slightly-enlarged 108% resting size for the rest of
# the reaction, then _restore_pose_for_current_state() snaps back to
# whatever pose's own real scale applies once the reaction ends.
const PORTAL_POP_SCALE_FACTOR := 1.2
const PORTAL_SETTLE_SCALE_FACTOR := 1.08
const PORTAL_POP_GROW_DURATION := 0.12
const PORTAL_POP_SETTLE_DURATION := 0.18

# Evil disappearance (corruption death only -- FALL_DEATH shows Dead
# instantly and unrelated to any of this). After evil_pose_duration's full
# hold, $GoodGhostSprite itself shrinks and fades directly to nothing -- no
# texture switch, no Dead pose anywhere in this sequence. Position is
# solved from the same bottom-anchor formula as EVIL_POSITION/DEAD_POSITION,
# just for this much smaller scale, so Evil collapses toward its own feet
# (the shared hover anchor) rather than sinking, floating, or drifting
# sideways as it shrinks:
#   x = 7px * 0.06 = 0.42
#   y = 12 - (246-128.5)*0.06 = 12 - 7.05 = 4.95
const EVIL_DISAPPEAR_DURATION := 0.45
const EVIL_DISAPPEAR_SCALE := Vector2(0.06, 0.06)
const EVIL_DISAPPEAR_POSITION := Vector2(0.42, 4.95)

# Transparent Caster pickup transition (separate from the checkpoint's happy
# pose above -- ghost-portal.png here, ghost_happy.png there, never shared).
# Uses ghost-portal.png's own previously-verified calibration: canvas
# 968x902, alpha content ~612px tall and already centered, target rendered
# height ~60px (the same convention used before ghost_happy.png replaced it
# for checkpoints):
#   scale = 60 / 612 = 0.098, position already centered at content-bottom
#   bottom-anchor y=12 hover -> (0, -18.0)
# Held fully visible for CASTER_TRANSITION_HOLD_DURATION, then modulate
# tweens straight to STEALTH_TINT (the existing invisibility look, color and
# alpha both) over CASTER_TRANSITION_FADE_DURATION -- no texture switch
# during either step. See activate_stealth()/_play_caster_transition().
const CASTER_TRANSITION_SCALE := Vector2(0.098, 0.098)
const CASTER_TRANSITION_POSITION := Vector2(0.0, -18.0)
const CASTER_TRANSITION_HOLD_DURATION := 0.45
const CASTER_TRANSITION_FADE_DURATION := 0.30

const POSE_SIDE := "side"
const POSE_FRONT := "front"
const POSE_HOLDING_ORB := "holding_orb"
const POSE_DEAD := "dead"
const POSE_EVIL := "evil"
const POSE_SURPRISE := "surprise"
const POSE_CRYING := "crying"
const POSE_PORTAL := "portal"
const POSE_CASTER_TRANSITION := "caster_transition"

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
var is_showing_portal_pose: bool = false
var is_showing_caster_transition: bool = false
var is_stealthed: bool = false
var is_ending: bool = false
var _ending_camera_frozen_position: Vector2 = Vector2.ZERO
var _portal_outline_material: ShaderMaterial
var _sprite_original_material: Material = null
var _portal_reaction_tween: Tween = null
# The single tween driving the Transparent Caster's brief ghost-portal.png
# hold-then-fade-to-invisible transition (see _play_caster_transition()).
var _caster_transition_tween: Tween = null
# Facing direction captured at the instant a fatal sequence begins (before
# movement freezes), so Evil and Dead both consistently face whichever way
# the player was actually moving/facing when they died -- never affected by
# input afterward, since nothing updates this again until the next death.
var _death_facing_direction: int = 1
# The single tween driving Evil's shrink-and-fade-to-nothing (see
# _play_evil_disappear_tween()).
var _evil_disappear_tween: Tween = null


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

	$PortalPoseTimer.wait_time = portal_pose_duration
	$PortalPoseTimer.timeout.connect(_on_portal_pose_timer_timeout)

	# Captured before this material is ever touched, so clearing the portal
	# pose always restores whatever the sprite actually started with (null
	# today) rather than assuming null.
	_sprite_original_material = $GoodGhostSprite.material
	_portal_outline_material = ShaderMaterial.new()
	_portal_outline_material.shader = PORTAL_OUTLINE_SHADER
	_portal_outline_material.set_shader_parameter("outline_color", PORTAL_OUTLINE_COLOR)
	_portal_outline_material.set_shader_parameter(
		"outline_width_px", PORTAL_OUTLINE_TARGET_SCREEN_PX / PORTAL_SCALE.x
	)


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
		if jump_count == 0:
			$JumpSFX.play()
		else:
			$DoubleJumpSFX.play()
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
#   0. Portal pose (checkpoint activation reaction) -- is_showing_portal_pose,
#      for portal_pose_duration seconds. Unlike the other reactions below,
#      this one runs while the player can still be moving/jumping, so the
#      guard here is what actually keeps movement/jump poses from
#      overwriting it every frame -- not an is_ending/is_respawning gate.
#      Transparent Caster transition -- is_showing_caster_transition, for its
#      own short hold-then-fade -- shares this same top priority and the same
#      reasoning (movement/jump stays live during it, so the guard here is
#      what keeps its ghost-portal.png hold from being overwritten).
#   1. Evil Ghost / Dead Ghost   -- enforced above this function, via the
#      is_respawning gate in _physics_process, which skips this call entirely.
#   2. Crying (valid Ghost Hunter / Bad Orb hit) -- is_showing_crying
#   3. Good Orb holding reaction                 -- is_showing_good_orb_reaction
#   4. Surprise while jumping or falling         -- airborne
#   5. Directional side pose while moving on the ground
#   6. Front-facing idle pose
func _update_visual_pose(delta: float) -> void:
	if (
		is_showing_portal_pose
		or is_showing_caster_transition
		or is_showing_crying
		or is_showing_good_orb_reaction
	):
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


# Checkpoint-activation reaction only -- see show_portal_pose()/
# clear_portal_pose(). ghost_happy.png is front-facing art and is never
# mirrored, unlike the directional side/surprise poses.
func _apply_portal_pose() -> void:
	if current_pose != POSE_PORTAL:
		current_pose = POSE_PORTAL
		$GoodGhostSprite.texture = portal_texture
		$GoodGhostSprite.scale = PORTAL_SCALE
		$GoodGhostSprite.position = PORTAL_POSITION
	$GoodGhostSprite.flip_h = false


# Transparent Caster transition only -- see activate_stealth()/
# _play_caster_transition(). ghost-portal.png is front-facing art here too,
# never mirrored.
func _apply_caster_transition_pose() -> void:
	if current_pose != POSE_CASTER_TRANSITION:
		current_pose = POSE_CASTER_TRANSITION
		$GoodGhostSprite.texture = caster_transition_texture
		$GoodGhostSprite.scale = CASTER_TRANSITION_SCALE
		$GoodGhostSprite.position = CASTER_TRANSITION_POSITION
	$GoodGhostSprite.flip_h = false


# Called by checkpoint.gd (on the body that actually entered its Area2D)
# the moment an ordinary checkpoint first activates and changes its own
# appearance. Takes priority over every other pose -- see the guard at the
# top of _update_visual_pose() -- for portal_pose_duration seconds, so
# normal movement/jump pose updates can't overwrite it while the player
# keeps moving. Self-clearing via PortalPoseTimer; does not freeze movement
# or touch collision, and never touches the Player node's own scale -- only
# $GoodGhostSprite.
func show_portal_pose() -> void:
	is_showing_portal_pose = true
	_apply_portal_pose()
	$GoodGhostSprite.material = _portal_outline_material
	_play_portal_pop_tween()
	$PortalPoseTimer.start()


# Called by checkpoint.gd alongside show_portal_pose(), once per checkpoint
# activation (checkpoint.gd's own _activated guard ensures this).
func play_portal_sound() -> void:
	$PortalEnterSFX.play()


# Called by good_spirit_orb.gd once collection is confirmed (its own
# _collected guard ensures this fires at most once per orb). The orb
# queue_free()s itself immediately after calling this, so the sound plays
# from the player (which persists) rather than from the orb (which would
# cut it off mid-playback).
func play_pure_orb_sound() -> void:
	$PureOrbSFX.play()


# Quick "magical" scale pop played once at the start of the portal pose:
# PORTAL_SCALE -> 120% (TRANS_BACK, a slight springy overshoot) over 0.12s,
# then eases back to a 108% resting size (TRANS_QUAD) over 0.18s, where it
# stays for the remainder of the reaction. Any previous portal-reaction
# tween is killed first so rapid re-triggers (or an interrupted-then-somehow-
# retriggered reaction) can never stack two tweens fighting over the scale.
func _play_portal_pop_tween() -> void:
	if _portal_reaction_tween != null and _portal_reaction_tween.is_valid():
		_portal_reaction_tween.kill()

	$GoodGhostSprite.scale = PORTAL_SCALE
	_portal_reaction_tween = create_tween()
	_portal_reaction_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_portal_reaction_tween.tween_property(
		$GoodGhostSprite, "scale", PORTAL_SCALE * PORTAL_POP_SCALE_FACTOR, PORTAL_POP_GROW_DURATION
	)
	_portal_reaction_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_portal_reaction_tween.tween_property(
		$GoodGhostSprite, "scale", PORTAL_SCALE * PORTAL_SETTLE_SCALE_FACTOR, PORTAL_POP_SETTLE_DURATION
	)


# Restores whatever pose actually fits the player's current state (moving,
# airborne, or idle) rather than always the idle texture, since the player
# may well have kept moving during the reaction. Called automatically when
# PortalPoseTimer times out; also safe to call directly (e.g. if some other
# state needs to cut the reaction short), since it stops the timer itself.
# Kills the pop tween and restores the sprite's original material first, so
# neither the outline nor the enlarged scale can ever linger past this call
# -- _restore_pose_for_current_state() then sets the exact scale, position,
# texture and facing the current pose actually requires.
func clear_portal_pose() -> void:
	is_showing_portal_pose = false
	$PortalPoseTimer.stop()
	if _portal_reaction_tween != null and _portal_reaction_tween.is_valid():
		_portal_reaction_tween.kill()
	$GoodGhostSprite.material = _sprite_original_material
	_restore_pose_for_current_state()


func _on_portal_pose_timer_timeout() -> void:
	clear_portal_pose()


# Called by Good Spirit Orbs on collection, regardless of whether SOUL was
# actually restored. Ranks below Crying (a hit reaction should not be
# interrupted by a pickup) but above Surprise, so collecting an orb while
# airborne still shows the holding-orb reaction.
func show_good_orb_reaction() -> void:
	if is_respawning or is_showing_crying or is_showing_portal_pose or is_showing_caster_transition:
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
# handled separately by the caller. Skipped during the portal pose (a hit
# landing during the brief checkpoint reaction must not visually interrupt
# it) -- take_corruption()'s own soul bookkeeping already ran before this
# call and is unaffected.
func show_crying_reaction() -> void:
	if is_respawning or is_showing_portal_pose or is_showing_caster_transition:
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


# Shared by the Good Orb reaction, the Crying reaction, the portal reaction,
# and the caster transition when their timers/tweens end: pick the correct
# pose immediately based on the player's state at that instant
# (airborne -> Surprise, moving -> side, still -> front) rather than waiting
# through another idle delay. Also guards itself against is_showing_portal_pose
# and is_showing_caster_transition, so a Crying/Good-Orb timer that was
# already running when one of those took over can't fire later and knock
# the reaction out early -- clear_portal_pose()/_finish_caster_transition()
# each clear their own flag themselves before calling this, so their own
# timeout/callback still restores the pose correctly.
func _restore_pose_for_current_state() -> void:
	if is_showing_portal_pose or is_showing_caster_transition:
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
# touched. Gameplay protection (collision_layer) is granted immediately,
# before any visual plays, so nothing can damage the player during the
# transition below. The full invisibility-duration timer only starts once
# that transition actually reaches invisible -- see _finish_caster_transition()
# -- so the visible hold-and-fade never eats into the existing stealth
# duration. $StealthTimer.stop() cancels any run already in progress (from
# an earlier caster) so it can't fire mid-transition and restore collision/
# tint early -- picking up a second caster while already stealthed (or mid-
# transition) simply replays the transition and restarts the timer once it
# completes, rather than stacking or double-firing.
func activate_stealth() -> void:
	if is_respawning:
		return

	is_stealthed = true
	collision_layer = 0
	$StealthTimer.stop()
	$SuperpowerSFX.play()
	superpower_activated.emit()
	_play_caster_transition()


# Ghost-portal.png transition played by activate_stealth(): fully visible for
# CASTER_TRANSITION_HOLD_DURATION, then its modulate tweens straight to
# STEALTH_TINT (the existing invisibility look) over
# CASTER_TRANSITION_FADE_DURATION -- no texture switch in either step.
# Cancels any Good Orb/Crying/Portal reaction in progress first (flags,
# timers, and the portal's own tween + outline material) so none of them can
# fire mid-transition and fight the caster pose for texture/material/scale/
# alpha -- mirrors the cleanup _freeze_for_respawn() already does for the
# same reason, just without freezing movement. Any previous caster-transition
# tween is killed first so a second caster picked up mid-transition replays
# cleanly instead of stacking two tweens.
func _play_caster_transition() -> void:
	is_showing_good_orb_reaction = false
	$GoodOrbReactionTimer.stop()

	is_showing_crying = false
	$CryingTimer.stop()

	is_showing_portal_pose = false
	$PortalPoseTimer.stop()
	if _portal_reaction_tween != null and _portal_reaction_tween.is_valid():
		_portal_reaction_tween.kill()
	$GoodGhostSprite.material = _sprite_original_material

	if _caster_transition_tween != null and _caster_transition_tween.is_valid():
		_caster_transition_tween.kill()

	is_showing_caster_transition = true
	_apply_caster_transition_pose()
	$GoodGhostSprite.modulate = NORMAL_TINT

	_caster_transition_tween = create_tween()
	_caster_transition_tween.tween_interval(CASTER_TRANSITION_HOLD_DURATION)
	_caster_transition_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_caster_transition_tween.tween_property(
		$GoodGhostSprite, "modulate", STEALTH_TINT, CASTER_TRANSITION_FADE_DURATION
	)
	_caster_transition_tween.tween_callback(_finish_caster_transition)


# Fade reached invisible -- drop the transition pose in favor of whatever
# pose actually fits the player's current state (movement kept working the
# whole time), while keeping STEALTH_TINT so nothing flashes back to full
# opacity even for a frame. Only now does the existing full invisibility
# duration actually begin.
func _finish_caster_transition() -> void:
	is_showing_caster_transition = false
	$GoodGhostSprite.modulate = STEALTH_TINT
	_restore_pose_for_current_state()
	$StealthTimer.start()


# Kills the caster-transition tween (safe no-op if it already finished) and
# clears its pose flag, so an interruption (death, respawn) can never leave
# it running or the pose flag stuck true -- whatever pose is applied right
# after (Evil, Dead, or a normal pose on respawn) still sets its own real
# texture/scale/position/modulate anyway. Called from _freeze_for_respawn().
func _clear_caster_transition_tween() -> void:
	if _caster_transition_tween != null and _caster_transition_tween.is_valid():
		_caster_transition_tween.kill()
	is_showing_caster_transition = false


func _on_stealth_timer_timeout() -> void:
	is_stealthed = false
	collision_layer = PLAYER_COLLISION_LAYER
	$GoodGhostSprite.modulate = NORMAL_TINT
	superpower_deactivated.emit()


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

	$HurtSFX.play()
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


# Shared setup for both respawn causes: captures the facing direction to
# die with (before movement freezes, so nothing afterward can change it),
# freezes movement, disables further damage, hides the player from
# hazard/orb detection, and cancels any in-progress Good Orb, Crying,
# checkpoint-portal, or caster-transition reaction (so a death mid-reaction
# can never leave is_showing_portal_pose/is_showing_caster_transition stuck
# true, which would otherwise block every future pose update). Also kills
# the portal pop tween, Evil's disappear tween, and the caster-transition
# tween (and restores the sprite's original material), so a death during any
# of their outline/scale/fade animations -- or a hypothetical second death
# arriving mid-transition -- can never leave any of them stuck on the player
# through a respawn. Does not choose a pose or start a timer -- callers do
# that afterward, since SOUL_CORRUPTION and FALL_DEATH show different
# pre-respawn sequences.
func _freeze_for_respawn() -> void:
	$DeathSFX.play()

	_death_facing_direction = facing_direction

	is_respawning = true
	is_immune = true
	$HitFlashTimer.stop()

	is_showing_good_orb_reaction = false
	$GoodOrbReactionTimer.stop()

	is_showing_crying = false
	$CryingTimer.stop()

	is_showing_portal_pose = false
	$PortalPoseTimer.stop()
	if _portal_reaction_tween != null and _portal_reaction_tween.is_valid():
		_portal_reaction_tween.kill()
	_clear_evil_disappear_tween()
	_clear_caster_transition_tween()
	$GoodGhostSprite.material = _sprite_original_material

	velocity = Vector2.ZERO
	collision_layer = 0


# SOUL reaching zero through corruption: Good Ghost -> Evil Ghost -> [shrink
# and fade to nothing] -> Respawn -> Good Ghost. There is no Dead pose
# anywhere in this sequence (Dead is FALL_DEATH-only). Evil Ghost is shown
# at full size/color/opacity for evil_pose_duration, facing
# _death_facing_direction (captured moments ago in _freeze_for_respawn(),
# before input froze), then _on_evil_ghost_timer_timeout() below hands off
# to _play_evil_disappear_tween(), which shrinks/fades $GoodGhostSprite
# directly to nothing and calls _finish_respawn() itself once that
# completes -- no soul/health state is touched across any of this, so the
# HUD's three fatal indicators stay exactly as take_corruption() already
# left them until _finish_respawn() resets soul back to MAX_SOUL.
func _begin_corruption_respawn_sequence() -> void:
	if is_respawning:
		return

	respawn_cause = RespawnCause.SOUL_CORRUPTION
	_freeze_for_respawn()

	current_pose = POSE_EVIL
	$GoodGhostSprite.texture = evil_texture
	$GoodGhostSprite.scale = EVIL_SCALE
	$GoodGhostSprite.position = EVIL_POSITION
	$GoodGhostSprite.flip_h = _death_facing_direction < 0
	$GoodGhostSprite.modulate = NORMAL_TINT

	$EvilGhostTimer.start()


# Evil's hold finished -- shrink and fade it away to nothing instead of
# switching to any other pose.
func _on_evil_ghost_timer_timeout() -> void:
	_play_evil_disappear_tween()


# Shrinks and fades $GoodGhostSprite (still showing evil_texture the whole
# time -- no texture switch) from EVIL_SCALE/EVIL_POSITION/alpha 1.0 down to
# EVIL_DISAPPEAR_SCALE/POSITION/alpha 0.0 over EVIL_DISAPPEAR_DURATION, with
# an accelerating TRANS_QUAD/EASE_IN curve so it reads as collapsing away
# rather than a linear shrink. Calls the existing _finish_respawn() exactly
# once, directly, the instant the disappearance completes -- no Dead pose,
# no extra timer. Any leftover tween from this same slot is killed first,
# both as an interruption-safety measure and to prevent overlapping tweens
# if this is somehow ever triggered twice in a row.
func _play_evil_disappear_tween() -> void:
	if _evil_disappear_tween != null and _evil_disappear_tween.is_valid():
		_evil_disappear_tween.kill()

	_evil_disappear_tween = create_tween()
	_evil_disappear_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_evil_disappear_tween.tween_property($GoodGhostSprite, "modulate:a", 0.0, EVIL_DISAPPEAR_DURATION)
	_evil_disappear_tween.parallel().tween_property($GoodGhostSprite, "scale", EVIL_DISAPPEAR_SCALE, EVIL_DISAPPEAR_DURATION)
	_evil_disappear_tween.parallel().tween_property(
		$GoodGhostSprite, "position", EVIL_DISAPPEAR_POSITION, EVIL_DISAPPEAR_DURATION
	)
	_evil_disappear_tween.tween_callback(_finish_respawn)


# Kills the disappear tween (safe no-op if it already finished) and restores
# $GoodGhostSprite's alpha and transform to Evil's own un-shrunk values, so
# no trace of the shrink/fade can remain visible even for a frame. Called
# from _freeze_for_respawn() so an interruption (another death, a respawn)
# can never leave the tween running or $GoodGhostSprite faded/shrunk --
# whatever pose is applied immediately afterward (Evil, Dead, or a normal
# pose on respawn) still sets its own real scale/position/texture anyway.
func _clear_evil_disappear_tween() -> void:
	if _evil_disappear_tween != null and _evil_disappear_tween.is_valid():
		_evil_disappear_tween.kill()
	$GoodGhostSprite.modulate.a = 1.0
	$GoodGhostSprite.scale = EVIL_SCALE
	$GoodGhostSprite.position = EVIL_POSITION


func _show_dead_pose() -> void:
	current_pose = POSE_DEAD
	$GoodGhostSprite.texture = dead_texture
	$GoodGhostSprite.scale = DEAD_SCALE
	$GoodGhostSprite.position = DEAD_POSITION
	$GoodGhostSprite.flip_h = _death_facing_direction < 0
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

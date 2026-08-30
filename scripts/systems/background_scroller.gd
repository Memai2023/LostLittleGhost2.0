extends Node2D

## Far is currently disabled (set invisible in main_level.tscn). Its own
## clamped/section-anchored scroll logic is left intact below (harmless
## while invisible) so re-enabling it later is a one-line visibility
## change, not a rewrite.
##
## Sky, Horizon, Mid and Near (bg-sky.png / bg-bottom.png / bg-mid.png /
## bg-near.png) are one continuous painted composition split across four
## textures, all driven from the same shared level progress computed once
## per frame -- no independent scroll/clamp/loop logic per layer, and no
## per-layer speed curve either. progress 0 at the player's spawn
## (camera_start_x) pans every layer fully left (each layer's own left edge
## meets the viewport's left edge); progress 1 at the final door
## (camera_end_x) pans every layer fully right (each layer's own right edge
## meets the viewport's right edge).
##
## The parallax speed difference comes from TWO combined sources:
## 1. Each layer's own rendered width (wider textures cover more
##    screen-relative ground per unit of shared progress).
## 2. A per-layer depth offset applied to a shared sin(PI * progress) curve,
##    producing a per-layer layer_progress that is DIFFERENT from the base
##    level progress (see _panorama_depths / _update_panorama below). This
##    is what makes Sky/Horizon -- which share the same rendered width --
##    move at different speeds from one another, and is also why Near
##    visibly outpaces Mid by more than width alone would produce.
##
## Each depth is kept small enough (|depth| < 1/pi =~ 0.318) that
## d/dprogress (progress + depth*sin(PI*progress)) = 1 + depth*PI*cos(PI*progress)
## stays positive across the whole [0, 1] range -- layer_progress is
## strictly monotonic for every layer, so the ordering can never reverse
## partway through the level.
##
## None of the four tiles, mirrors, wraps, or re-anchors -- the source art
## isn't a repeatable pattern, so panning across each texture once, exactly
## in sync with how far the player has traveled, is the whole mechanism.

@export var camera_start_x: float = 200.0
@export var camera_end_x: float = 9780.0

## Camera-x positions of the level's own narrative section boundaries
## (matches the Graveyard / Haunted Woods / Haunted House Grounds zones).
## Only used by Far's clamped drift below; Sky/Horizon/Mid/Near don't
## re-anchor.
@export var section_boundaries: Array[float] = [3070.0, 6150.0]

## Fraction of each source image's height aligned to the viewport's vertical
## center. 0.5 = true center. Raising this shifts the shared crop window
## down the source image, revealing more foreground/ground detail near the
## bottom of the viewport at the cost of upper-sky detail. Applied
## identically to every layer, so the stack stays vertically locked
## together.
## 0.5 (true center): at the Sky/Horizon layers' 1.6 scale, the 682px
## source only renders 1091.2px tall against a 1080px viewport -- ~11px of
## total vertical slack, split ~5.6px above/below center. Any fraction
## further from 0.5 than that exceeds the available slack and opens a gap
## at the top or bottom of the screen, so 0.5 is the only value with margin
## on both sides at this scale. Mid and Near are also 682px source height
## at the same 1.6 scale, so this holds for all four layers identically.
@export_range(0.0, 1.0) var vertical_anchor_fraction: float = 0.5

## Per-layer scroll_scale (fraction of the camera's own apparent motion
## shown on screen), still used by the disabled Far layer only.
@export var far_scroll_scale: float = 0.20

## Per-layer depth offsets applied on top of the shared sin(PI * progress)
## curve (see _panorama_depths / _update_panorama). Negative = slower than
## the base progress, positive = faster. Magnitudes stay below 1/pi so
## layer_progress is always monotonic (no reversal).
@export var sky_parallax_depth: float = -0.17
@export var horizon_parallax_depth: float = -0.06
@export var mid_parallax_depth: float = 0.12
@export var near_parallax_depth: float = 0.30

## Target screen-space X (0 = viewport left edge, viewport width = right
## edge) that MidSprite/HouseDoorTarget is shifted toward as the player
## nears the door, so the background house doorway and the foreground
## EndPortal read as two distinct, simultaneously-visible destinations
## instead of overlapping. Fades in only across the level's final
## (1.0 - house_reveal_start) fraction.
@export var house_target_screen_x: float = 1500.0
@export_range(0.0, 1.0) var house_reveal_start: float = 0.82

# Far -- the one remaining clamped/section-anchored layer (currently
# invisible).
@onready var _layers: Array[Sprite2D] = [
	$FarLayer/FarSprite,
]

# Sky, Horizon, Mid, Near -- the synchronized single-composition layers,
# back to front. Index order is shared with _panorama_depths and
# _panorama_widths below.
@onready var _panorama_sprites: Array[Sprite2D] = [
	$SkyLayer/SkySprite,
	$HorizonLayer/HorizonSprite,
	$MidLayer/MidSprite,
	$NearLayer/NearSprite,
]

const _MID_PANORAMA_INDEX := 2

# Static-color safety net behind SkyLayer (see main_level.tscn,
# BackgroundParallax/SkyFallback/Fill) -- a plain camera-following quad, sized
# with generous overscan, so the engine's own clear color can never show
# through even in a hypothetical single-frame coverage gap the panorama
# layers' own clamp doesn't already account for. Never covers or replaces the
# real artwork -- it sits at a lower z_index than every real layer (see the
# node's z_index in the scene) and only matters if something is already
# failing to cover the viewport.
const _FALLBACK_OVERSCAN := 1.5
@onready var _sky_fallback: Polygon2D = $SkyFallback/Fill

var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _layer_sizes: Array[Vector2] = []
var _scroll_scales: Array[float] = []
var _panorama_widths: Array[float] = []
var _panorama_depths: Array[float] = []

# Marker2D child of MidSprite placed exactly on the painted house doorway
# (see main_level.tscn, group "house_door_target"). Used both to derive
# _mid_house_shift below and, at the ending, as the exact landing point for
# ArrivalGhost.
var _house_door_target: Marker2D = null

# Constant extra rightward shift applied to MidSprite's screen-relative X
# (faded in via house_reveal_start) so that, once fully faded in,
# _house_door_target sits at house_target_screen_x on screen. Derived once
# in _ready() from the marker's actual local position, MidSprite's scale,
# Mid's rendered width and the viewport size -- never hardcoded.
var _mid_house_shift: float = 0.0

var _current_section: int = 0
# Per-layer anchor: this layer's own world x, and the camera's world x, at
# the moment the current section's drift started (either level start or the
# last section-boundary crossing). Drift within a section is always
# measured relative to these, so a reset never causes a visual pop.
var _section_anchor_x: Array[float] = []
var _section_anchor_camera_x: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_scroll_scales = [far_scroll_scale]
	for sprite in _layers:
		_layer_sizes.append(sprite.texture.get_size() * sprite.scale)
	# Anchors every layer's left edge to the viewport's left edge at the
	# level's own start, matching the framing before independent scroll_scale
	# existed -- only the drift after that point is new.
	for i in _layers.size():
		_section_anchor_x.append(camera_start_x - _viewport_size.x * 0.5)
	_section_anchor_camera_x = camera_start_x

	for sprite in _panorama_sprites:
		_panorama_widths.append(sprite.texture.get_width() * absf(sprite.scale.x))

	_panorama_depths = [
		sky_parallax_depth,
		horizon_parallax_depth,
		mid_parallax_depth,
		near_parallax_depth,
	]

	var mid_sprite: Sprite2D = _panorama_sprites[_MID_PANORAMA_INDEX]
	_house_door_target = mid_sprite.get_node("HouseDoorTarget")

	var mid_rendered_width: float = _panorama_widths[_MID_PANORAMA_INDEX]
	# screen_relative_x MidSprite would sit at once its own layer_progress
	# reaches 1.0, with no house shift applied yet.
	var mid_full_screen_relative: float = _viewport_size.x * 0.5 - mid_rendered_width
	# HouseDoorTarget's screen-relative X at that same moment (its local
	# position is scaled by MidSprite's own scale, same as any other child).
	var door_screen_relative_at_full: float = (
		mid_full_screen_relative + _house_door_target.position.x * mid_sprite.scale.x
	)
	var target_screen_relative: float = house_target_screen_x - _viewport_size.x * 0.5
	_mid_house_shift = target_screen_relative - door_screen_relative_at_full

	var fallback_size: Vector2 = _viewport_size * _FALLBACK_OVERSCAN
	_sky_fallback.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(fallback_size.x, 0.0),
		fallback_size,
		Vector2(0.0, fallback_size.y),
	])


func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return

	# get_screen_center_position() (NOT global_position) is what actually
	# feeds the rendered view: global_position is the Camera2D node's raw
	# transform and snaps instantly to wherever its parent (the player)
	# currently is, completely ignoring position_smoothing -- while the
	# viewport visually still eases toward that position over several
	# frames. Using global_position here positioned every layer around
	# where the camera was ABOUT to be rather than where it was actually
	# rendering, so during any fast camera movement (jumps, direction
	# reversals, deceleration) the two diverge -- by over 1000px in testing
	# with this project's position_smoothing_speed -- and the background
	# ends up clamped to cover the wrong region entirely, exposing the
	# viewport's clear color on whichever edge the true (lagging) camera
	# had not caught up to yet. This was the verified cause of the
	# intermittent grey viewport-edge strip.
	var camera_pos: Vector2 = _camera.get_screen_center_position()
	_update_section(camera_pos.x)

	$SkyFallback.global_position = camera_pos - _viewport_size * _FALLBACK_OVERSCAN * 0.5

	var traveled_in_section: float = camera_pos.x - _section_anchor_camera_x

	for i in _layers.size():
		var sprite: Sprite2D = _layers[i]
		var size: Vector2 = _layer_sizes[i]
		var depth_factor: float = 1.0 - _scroll_scales[i]
		var desired_x: float = _section_anchor_x[i] + traveled_in_section * depth_factor

		# Clamp to whatever window of this layer's own texture still fully
		# covers the current viewport -- the hard guarantee against gaps,
		# independent of how aggressive scroll_scale is.
		var min_x: float = camera_pos.x + _viewport_size.x * 0.5 - size.x
		var max_x: float = camera_pos.x - _viewport_size.x * 0.5
		var final_x: float = clampf(desired_x, min_x, max_x)

		sprite.global_position = Vector2(final_x, camera_pos.y - size.y * vertical_anchor_fraction)

	_update_panorama(camera_pos)


# Drives Sky, Horizon, Mid and Near from one shared base level progress, but
# each layer is positioned using its OWN layer_progress -- base progress
# warped by that layer's depth against a shared sin(PI * progress) curve
# (see _panorama_depths). progress 0 at camera_start_x pans every layer
# fully left (each layer's own left edge meets the viewport's left edge);
# progress 1 at camera_end_x pans every layer fully right (each layer's own
# right edge meets the viewport's right edge). No clamping to a single
# shared position, no section-anchoring, no looping.
func _update_panorama(camera_pos: Vector2) -> void:
	var progress: float = clampf(
		(camera_pos.x - camera_start_x) / (camera_end_x - camera_start_x), 0.0, 1.0
	)
	var depth_curve: float = sin(PI * progress)

	for i in _panorama_sprites.size():
		var layer_progress: float = clampf(progress + _panorama_depths[i] * depth_curve, 0.0, 1.0)
		var extra_shift: float = 0.0
		if i == _MID_PANORAMA_INDEX:
			extra_shift = _mid_house_shift * smoothstep(house_reveal_start, 1.0, progress)
		_position_panorama_layer(_panorama_sprites[i], _panorama_widths[i], layer_progress, extra_shift, camera_pos)


# Shared positioning helper for every panorama layer (Sky/Horizon/Mid/Near).
# Sprites are top-left anchored (centered = false), so global_position.x
# directly IS the sprite's own left edge -- no size-based recentering
# needed. At layer_progress=0, screen_relative_x = -viewport_width/2, i.e.
# this layer's left edge sits exactly at the viewport's left edge. At
# layer_progress=1, screen_relative_x = viewport_width/2 - rendered_width,
# i.e. this layer's right edge (left edge + rendered_width) sits exactly at
# the viewport's right edge. Passing each layer its OWN layer_progress
# (rather than one shared progress) is what makes each depth value actually
# reach the final sprite position -- rendered_width alone no longer carries
# the whole speed difference. extra_shift (nonzero for Mid only, once the
# player nears the door) is added before the coverage clamp, so the ending
# house-reveal shift can never open a gap at either viewport edge.
func _position_panorama_layer(
	sprite: Sprite2D, rendered_width: float, layer_progress: float, extra_shift: float, camera_pos: Vector2
) -> void:
	var screen_relative_x: float = lerpf(
		-_viewport_size.x * 0.5, _viewport_size.x * 0.5 - rendered_width, layer_progress
	)

	var x: float = camera_pos.x + screen_relative_x + extra_shift
	var min_x: float = camera_pos.x + _viewport_size.x * 0.5 - rendered_width
	var max_x: float = camera_pos.x - _viewport_size.x * 0.5
	x = clampf(x, min_x, max_x)

	var y: float = camera_pos.y - sprite.texture.get_height() * absf(sprite.scale.y) * vertical_anchor_fraction

	sprite.global_position = Vector2(x, y)


# Detects a section-boundary crossing (in either direction) and re-anchors
# every layer's drift reference to its OWN current on-screen position, so
# the reset is invisible -- next frame's desired_x starts exactly where
# this frame's final_x left off. Only affects Far; the panorama layers
# never re-anchor.
func _update_section(camera_x: float) -> void:
	var new_section := 0
	for boundary in section_boundaries:
		if camera_x >= boundary:
			new_section += 1
		else:
			break

	if new_section == _current_section:
		return

	for i in _layers.size():
		_section_anchor_x[i] = _layers[i].global_position.x
	_section_anchor_camera_x = camera_x
	_current_section = new_section

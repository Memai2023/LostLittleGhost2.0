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
## The parallax itself comes purely from each layer's own rendered width:
## Sky and Horizon are 2048x682 @ 1.6 (rendered 3276.8 wide); Mid is
## 3200x682 @ 1.6 (rendered 5120 wide); Near is 3600x682 @ 1.6 (rendered
## 5760 wide). Panning a wider texture across the same [0, 1] progress over
## the same level distance means it has to cover more screen-relative
## ground per unit of camera movement -- so Near (widest) visibly outpaces
## Mid, which outpaces Sky/Horizon (equal width, so equal speed), with no
## separate per-layer curve or offset needed. A previous version added a
## sin(PI * progress) depth wobble on top of a shared progress to fake this
## with same-width source art; now that Mid/Near are genuinely wider than
## Sky/Horizon, that wobble is gone -- width alone drives the speed
## difference, and the ordering can't reverse partway through the level the
## way the old sine curve did.
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

# Far -- the one remaining clamped/section-anchored layer (currently
# invisible).
@onready var _layers: Array[Sprite2D] = [
	$FarLayer/FarSprite,
]

# Sky, Horizon, Mid, Near -- the synchronized single-composition layers,
# back to front.
@onready var _panorama_sprites: Array[Sprite2D] = [
	$SkyLayer/SkySprite,
	$HorizonLayer/HorizonSprite,
	$MidLayer/MidSprite,
	$NearLayer/NearSprite,
]

var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _layer_sizes: Array[Vector2] = []
var _scroll_scales: Array[float] = []
var _panorama_widths: Array[float] = []

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


func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return

	var camera_pos: Vector2 = _camera.global_position
	_update_section(camera_pos.x)

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


# Drives Sky, Horizon, Mid and Near from one shared level progress -- no
# per-layer curve or offset. progress 0 at camera_start_x pans every layer
# fully left (each layer's own left edge meets the viewport's left edge);
# progress 1 at camera_end_x pans every layer fully right (each layer's own
# right edge meets the viewport's right edge). The parallax speed
# difference comes entirely from each layer's own rendered width -- see
# _position_panorama_layer(). No clamping, section-anchoring, or looping.
func _update_panorama(camera_pos: Vector2) -> void:
	var progress: float = clampf(
		(camera_pos.x - camera_start_x) / (camera_end_x - camera_start_x), 0.0, 1.0
	)

	for i in _panorama_sprites.size():
		_position_panorama_layer(_panorama_sprites[i], _panorama_widths[i], progress, camera_pos)


# Shared positioning helper for every panorama layer (Sky/Horizon/Mid/Near).
# Sprites are top-left anchored (centered = false), so global_position.x
# directly IS the sprite's own left edge -- no size-based recentering
# needed. At progress=0, screen_relative_x = -viewport_width/2, i.e. this
# layer's left edge sits exactly at the viewport's left edge. At progress=1,
# screen_relative_x = viewport_width/2 - rendered_width, i.e. this layer's
# right edge (left edge + rendered_width) sits exactly at the viewport's
# right edge. A wider rendered_width makes that second value more negative,
# so wider layers travel further in screen-relative terms over the same
# progress range -- that's the entire parallax mechanism; no per-layer
# speed constant is needed. (All four layers currently render well over
# viewport width, so the right-edge endpoint is always negative -- coverage
# holds throughout; this stops being true only if a layer were ever made
# narrower than the viewport, which none are.)
func _position_panorama_layer(
	sprite: Sprite2D, rendered_width: float, progress: float, camera_pos: Vector2
) -> void:
	var screen_relative_x: float = lerpf(
		-_viewport_size.x * 0.5, _viewport_size.x * 0.5 - rendered_width, progress
	)

	var x: float = camera_pos.x + screen_relative_x
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

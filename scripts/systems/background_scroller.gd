extends Node2D

## Drives each background layer with its OWN independent scroll_scale,
## for real cinematic parallax depth: scroll_scale is "how much of the
## camera's own apparent motion this layer shows on screen" -- 0.0 would
## be perfectly static (infinitely far away), 1.0 matches how a normal
## world-fixed object appears to slide past as the camera pans, and
## anything above 1.0 overtakes that, reading as extreme foreground.
## Sky barely moves; Near/foreground rushes past faster than the camera's
## own pan.
##
## bg-sky/far/mid.png are each a single continuous painted panorama with
## specific, non-repeating landmarks (the moon, the graveyard entrance, the
## house itself) -- not a tileable pattern -- so there's no seamless way to
## let those layers scroll indefinitely once their own texture edge is
## reached; repeating them would show the same unique painted content
## twice, most jarringly for whichever one still holds a story landmark.
## Their position is clamped every frame to whatever window of their own
## texture still fully covers the current viewport, and Sky/Far/Mid also
## get their drift re-anchored at the level's own narrative section
## boundaries (see _update_section) so they don't fully plateau for the
## whole back half of the level even though they can't loop.
##
## Near is the one layer actually set to LOOP: it moves too fast (and is
## the closest, so its content reads as more generic foreground clutter
## than a specific landmark) to make sense clamped. It scrolls forever via
## two copies of its own texture placed edge-to-edge, wrapping which one
## leads as the camera moves -- genuinely continuous motion for the whole
## level, at the cost of a visible seam once per texture-width cycle where
## the Near texture's (currently bg-bottom.png) right edge meets its own
## left edge (it isn't drawn as a seamless tile).

@export var camera_start_x: float = 200.0
@export var camera_end_x: float = 9800.0

## Camera-x positions of the level's own narrative section boundaries
## (matches the Graveyard / Haunted Woods / Haunted House Grounds zones).
## Sky/Far/Mid's independent-scroll drift resets to zero here (Near loops
## instead, so it doesn't need this).
@export var section_boundaries: Array[float] = [3070.0, 6150.0]

## Fraction of each source image's height aligned to the viewport's vertical
## center. 0.5 = true center. Raising this shifts the shared crop window
## down the source image, revealing more foreground/ground detail near the
## bottom of the viewport at the cost of upper-sky detail. Applied
## identically to all layers, so the stack stays vertically locked together.
## 0.55 keeps bg-far's moon (measured at 19.6%-25% of image height) fully in
## frame while still showing most of the Near layer's dense foreground band
## (measured starting at ~75% of image height in the original bg-near.png).
@export_range(0.0, 1.0) var vertical_anchor_fraction: float = 0.55

## Independent per-layer scroll_scale (fraction of the camera's own apparent
## motion shown on screen). Sky: virtually imperceptible. Far: slow,
## grounded background depth. Mid: moderate, bridges background and
## gameplay plane. Near: hyper-parallax foreground, overtakes the camera's
## own pan rate.
@export var sky_scroll_scale: float = 0.035
@export var far_scroll_scale: float = 0.20
@export var mid_scroll_scale: float = 0.50
@export var near_scroll_scale: float = 1.35

# Sky, Far, Mid -- the clamped/section-anchored layers.
@onready var _layers: Array[Sprite2D] = [
	$SkyLayer/SkySprite,
	$FarLayer/FarSprite,
	$MidLayer/MidSprite,
]

@onready var _near_sprite_a: Sprite2D = $NearLayer/NearSprite
var _near_sprite_b: Sprite2D = null

var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _layer_sizes: Array[Vector2] = []
var _scroll_scales: Array[float] = []
var _near_size: Vector2 = Vector2.ZERO
var _near_depth_factor: float = 0.0

var _current_section: int = 0
# Per-layer anchor: this layer's own world x, and the camera's world x, at
# the moment the current section's drift started (either level start or the
# last section-boundary crossing). Drift within a section is always
# measured relative to these, so a reset never causes a visual pop.
var _section_anchor_x: Array[float] = []
var _section_anchor_camera_x: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_scroll_scales = [sky_scroll_scale, far_scroll_scale, mid_scroll_scale]
	for sprite in _layers:
		_layer_sizes.append(sprite.texture.get_size() * sprite.scale)
	# Anchors every layer's left edge to the viewport's left edge at the
	# level's own start, matching the framing before independent scroll_scale
	# existed -- only the drift after that point is new.
	for i in _layers.size():
		_section_anchor_x.append(camera_start_x - _viewport_size.x * 0.5)
	_section_anchor_camera_x = camera_start_x

	_near_size = _near_sprite_a.texture.get_size() * _near_sprite_a.scale
	_near_depth_factor = 1.0 - near_scroll_scale
	_near_sprite_b = Sprite2D.new()
	_near_sprite_b.texture = _near_sprite_a.texture
	_near_sprite_b.scale = _near_sprite_a.scale
	_near_sprite_b.centered = _near_sprite_a.centered
	_near_sprite_a.get_parent().add_child(_near_sprite_b)


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

	_update_near(camera_pos)


# Near loops instead of clamping: an unbounded (never-clamped) desired_x,
# wrapped into a single texture-width-sized window via fposmod (handles
# near_scroll_scale > 1's negative depth_factor correctly too), covered by
# two copies of the same texture placed edge-to-edge so the wrap point
# itself never shows a gap -- one copy is always fully covering the
# viewport, or handing off to the other mid-transition.
func _update_near(camera_pos: Vector2) -> void:
	var base_x: float = camera_start_x - _viewport_size.x * 0.5
	var desired_x: float = base_x + (camera_pos.x - camera_start_x) * _near_depth_factor

	var viewport_left: float = camera_pos.x - _viewport_size.x * 0.5
	var tile_left: float = viewport_left - fposmod(viewport_left - desired_x, _near_size.x)
	var y: float = camera_pos.y - _near_size.y * vertical_anchor_fraction

	_near_sprite_a.global_position = Vector2(tile_left, y)
	_near_sprite_b.global_position = Vector2(tile_left + _near_size.x, y)


# Detects a section-boundary crossing (in either direction) and re-anchors
# every layer's drift reference to its OWN current on-screen position, so
# the reset is invisible -- next frame's desired_x starts exactly where
# this frame's final_x left off.
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

extends Node2D

## Drives all background layers from ONE shared normalized progress value
## (camera position mapped 0.0-1.0 across the level) as their base position,
## so they stay narratively synchronized (same normalized position in their
## own source image) the way Parallax2D's independent per-layer scroll_scale
## never could. On top of that shared base, each layer gets a small, tiny
## differential scroll-speed offset (far_scroll_speed / mid_scroll_speed /
## near_scroll_speed below) for an actual parallax depth cue -- real
## differential speed, just kept small enough that it can never desync the
## layers by more than a few dozen pixels over the whole level.

@export var camera_start_x: float = 200.0
@export var camera_end_x: float = 9800.0

## Fraction of each source image's height aligned to the viewport's vertical
## center. 0.5 = true center. Raising this shifts the shared crop window
## down the source image, revealing more foreground/ground detail near the
## bottom of the viewport at the cost of upper-sky detail. Applied
## identically to all three layers, so the synchronized stack always moves
## together. 0.55 keeps bg-far's moon (measured at 19.6%-25% of image
## height) fully in frame while still showing most of bg-near's dense
## foreground band (measured starting at ~75% of image height).
@export_range(0.0, 1.0) var vertical_anchor_fraction: float = 0.55

## Per-layer scroll speed as a multiplier of the shared base speed (1.0 =
## moves exactly with the synchronized progression, same as Mid). This is
## real differential-speed parallax, not a position-keyed wave: each
## layer's extra offset grows/shrinks in direct, monotonic proportion to
## how far the camera has actually traveled, so it only moves in response
## to real player movement, never on its own, and never reverses unless the
## player actually walks backward. The differences are kept tiny on
## purpose -- over the full ~9600-unit level, even the largest gap here
## (Far vs Near, 0.995 vs 1.005) only ever accumulates to about +-48px of
## relative drift, comfortably inside "a few dozen pixels" of tolerated
## scene desync. Mid stays the anchor (1.0, zero extra offset, always
## exactly the shared position).
@export var far_scroll_speed: float = 0.995
@export var mid_scroll_speed: float = 1.005
@export var near_scroll_speed: float = 1.010

## Hard safety cap, in rendered pixels, on the extra per-layer offset below.
## The speeds above already stay well under this over the level's actual
## length; this just guarantees it can never grow unbounded even if the
## level were extended later.
@export var max_parallax_drift: float = 60.0

@onready var _layers: Array[Sprite2D] = [
	$FarLayer/FarSprite,
	$MidLayer/MidSprite,
	$NearLayer/NearSprite,
]

var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _layer_sizes: Array[Vector2] = []


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	for sprite in _layers:
		_layer_sizes.append(sprite.texture.get_size() * sprite.scale)


func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return

	var camera_pos: Vector2 = _camera.global_position
	var progress: float = clampf(
		(camera_pos.x - camera_start_x) / (camera_end_x - camera_start_x), 0.0, 1.0
	)

	# Real differential-speed parallax: "distance traveled through the
	# level" (progress, already clamped to the level's own bounds so it
	# can't run away if the player wanders past either end), times each
	# layer's own tiny speed difference from the shared base. This is a
	# monotonic function of actual camera displacement -- not of absolute
	# position via a wave -- so a layer only moves while the player is
	# actually moving, holds still the instant they stop, and only reverses
	# if the player genuinely walks back the other way.
	var traveled: float = progress * (camera_end_x - camera_start_x)
	var speeds: Array[float] = [far_scroll_speed, mid_scroll_speed, near_scroll_speed]
	var offsets: Array[float] = []
	for speed in speeds:
		offsets.append(clampf(traveled * (speed - 1.0), -max_parallax_drift, max_parallax_drift))

	for i in _layers.size():
		var sprite: Sprite2D = _layers[i]
		var size: Vector2 = _layer_sizes[i]
		var travel_range: float = size.x - _viewport_size.x
		sprite.global_position = Vector2(
			camera_pos.x - _viewport_size.x * 0.5 - progress * travel_range + offsets[i],
			camera_pos.y - size.y * vertical_anchor_fraction
		)

extends Node2D

## Drives all background layers from ONE shared normalized progress value
## (camera position mapped 0.0-1.0 across the level), instead of Parallax2D's
## independent per-layer scroll_scale. This keeps every layer showing the
## same normalized position in its own source image at all times.

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

## Bounded horizontal depth offsets, in rendered (post-scale) pixels, applied
## on top of the shared synchronized progression -- NOT independent scroll
## speeds. Far and Mid share a plain sin(PI * progress) timing; Near uses a
## differently-shaped curve (see _process) so it doesn't peak at the same
## moment as Mid. All three curves are 0 at progress=0 and progress=1
## regardless of shape, so the graveyard-start and dawn/house-end scene sync
## stays exact no matter how the amplitudes or easing above are tuned.
## far_parallax_offset/mid_parallax_offset are each that layer's exact peak
## offset (sin peaks at 1.0). near_parallax_offset is a coefficient, not the
## peak directly, because its easing curve peaks below 1.0 -- see _process.
@export var far_parallax_offset: float = 45.0
@export var mid_parallax_offset: float = 165.0
@export var near_parallax_offset: float = 144.0

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

	# Centered bounded wave: 0 at progress=0 and progress=1 (perfect sync at
	# the graveyard start and the dawn/house end), peaking at the level's
	# midpoint (the forest). A function of progress alone -- never of
	# elapsed camera travel -- so it can never exceed its amplitude or
	# accumulate, unlike independent per-layer scroll speeds.
	# Far and Mid share this plain wave -- same timing, different amplitude.
	var parallax_wave: float = sin(PI * progress)
	# Near uses a differently-shaped curve: the same sine, biased to grow
	# stronger later (0.65 at the start of the level, 1.0 at the end), which
	# shifts its peak past the midpoint and gives it a distinct "catching up"
	# motion instead of breathing in lockstep with Mid. Still 0 at both ends
	# because the sine factor alone already forces that.
	var near_wave: float = parallax_wave * (0.65 + 0.35 * progress)
	var offsets: Array[float] = [
		-far_parallax_offset * parallax_wave,
		mid_parallax_offset * parallax_wave,
		near_parallax_offset * near_wave,
	]

	for i in _layers.size():
		var sprite: Sprite2D = _layers[i]
		var size: Vector2 = _layer_sizes[i]
		var travel_range: float = size.x - _viewport_size.x
		sprite.global_position = Vector2(
			camera_pos.x - _viewport_size.x * 0.5 - progress * travel_range + offsets[i],
			camera_pos.y - size.y * vertical_anchor_fraction
		)

extends Node2D

## Purely visual door-proximity enhancement: brightens the sky and fades in
## warm sun rays as the player closes in on the final door, layered on top
## of (but never replacing) the level's existing static background art.
## There is no separate countdown/dawn-progression system in this project
## to coordinate with -- this node is fully self-contained.
##
## The door is referenced via the existing "end_portal" group (see
## end_portal.gd / main_level.tscn) rather than a hardcoded world
## coordinate, so this keeps working if the door's position ever changes.
## Reuses the EndPortal node purely as a position reference -- it does not
## touch the portal's own Area2D trigger or activation signal, since that
## fires once on overlap and can't provide the continuously-graded
## distance this effect needs.
##
## Follows the active camera every frame (same approach as
## background_scroller.gd's layers) so the effect is always anchored to
## the screen with no seams or camera-relative jumps, and draws as a
## sibling of SkyLayer at the same z_index (-10), placed immediately after
## it in the scene tree so it renders in front of the sky but behind
## Horizon/Mid/Near and all gameplay content -- respecting the existing
## parallax stack instead of adding a new draw order scheme.

@export var activation_distance: float = 1400.0
@export_range(0.0, 2.0) var max_sky_brightness: float = 0.55
@export var sunrise_color: Color = Color(1.0, 0.72, 0.4, 1.0)
@export_range(0.0, 1.0) var max_ray_opacity: float = 0.42
@export var ray_color: Color = Color(1.0, 0.82, 0.5, 1.0)
@export_range(0.0, 2.0) var ray_speed: float = 0.06
## How quickly the effect eases toward its target strength each second
## (exponential smoothing rate). Higher = catches up faster; lower = a
## slower, softer fade. Never an instant jump either way.
@export_range(0.1, 10.0) var transition_smoothing: float = 2.0

## Shared origin (SCREEN_UV space, 0..1) for the sun disc, its glow, and
## every ray -- see door_sunrise.gdshader. Keep this near the horizon on
## the right side, not high in the sky.
@export var sun_position: Vector2 = Vector2(0.85, 0.59)
## Radius of the sun's bright core, in the shader's aspect-corrected
## (screen-height-normalized) units.
@export_range(0.0, 0.3) var sun_radius: float = 0.032
## Width of the soft fade band around the core -- no hard edge either way.
@export_range(0.0, 0.3) var sun_softness: float = 0.045
## Outer radius of the wide, dim halo around the core.
@export_range(0.0, 1.0) var sun_glow_radius: float = 0.32
@export_range(0.0, 3.0) var sun_intensity: float = 0.7

## Ray length in the same aspect-corrected units as sun_radius (roughly a
## fraction of the screen height).
@export_range(0.0, 1.5) var ray_length: float = 0.55
## Half-width of each ray at its base (widens gently toward the tip).
@export_range(0.0, 0.5) var ray_width: float = 0.05
## Total angular width (radians) of the fan of rays, centered up-and-left
## from the sun.
@export_range(0.0, 3.14159265) var ray_spread: float = 1.7
@export_range(1.0, 10.0) var ray_count: float = 6.0

@onready var _glow: Polygon2D = $Glow

var _door: Node2D = null
var _player: Node2D = null
var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _current_intensity: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_glow.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(_viewport_size.x, 0.0),
		_viewport_size,
		Vector2(0.0, _viewport_size.y),
	])
	_glow.uv = PackedVector2Array([
		Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])

	_door = get_tree().get_first_node_in_group("end_portal")
	_player = get_tree().get_first_node_in_group("player")

	_apply_static_shader_params()


func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
	if _camera != null:
		global_position = _camera.global_position - _viewport_size * 0.5

	var target_intensity: float = _compute_target_intensity()
	var ease_amount: float = 1.0 - exp(-transition_smoothing * delta)
	_current_intensity = lerpf(_current_intensity, target_intensity, ease_amount)

	var material: ShaderMaterial = _glow.material
	material.set_shader_parameter("intensity", _current_intensity)


# Horizontal progress toward the door: 0 once further than
# activation_distance away, ramping smoothly to 1 exactly at the door's own
# x position. Only x is used since this is a side-scrolling level and the
# door's y never factors into "how close is the player to the end."
func _compute_target_intensity() -> float:
	if _door == null or _player == null or activation_distance <= 0.0:
		return 0.0
	var distance: float = absf(_player.global_position.x - _door.global_position.x)
	return clampf(1.0 - distance / activation_distance, 0.0, 1.0)


func _apply_static_shader_params() -> void:
	var material: ShaderMaterial = _glow.material
	material.set_shader_parameter("sunrise_color", sunrise_color)
	material.set_shader_parameter("max_sky_brightness", max_sky_brightness)
	material.set_shader_parameter("ray_color", ray_color)
	material.set_shader_parameter("max_ray_opacity", max_ray_opacity)
	material.set_shader_parameter("ray_speed", ray_speed)
	material.set_shader_parameter("sun_position", sun_position)
	material.set_shader_parameter("sun_radius", sun_radius)
	material.set_shader_parameter("sun_softness", sun_softness)
	material.set_shader_parameter("sun_glow_radius", sun_glow_radius)
	material.set_shader_parameter("sun_intensity", sun_intensity)
	material.set_shader_parameter("ray_length", ray_length)
	material.set_shader_parameter("ray_width", ray_width)
	material.set_shader_parameter("ray_spread", ray_spread)
	material.set_shader_parameter("ray_count", ray_count)

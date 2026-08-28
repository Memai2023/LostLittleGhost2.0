extends Area2D

## Single-use pickup: grants the player temporary stealth (see
## Player.activate_stealth()) and disappears, matching the existing
## orb-pickup pattern. Does not touch Ghost Hunter detection code at all --
## stealth works entirely from the player's side.

@export var bob_height: float = 5.0
@export var bob_speed: float = 2.0
@export var pulse_amount: float = 0.08
@export var pulse_speed: float = 3.0
@export var fade_min_alpha: float = 0.55
@export var fade_speed: float = 1.8

var _time: float = 0.0
var _base_y: float = 0.0
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_base_y = position.y
	_base_scale = $Sprite.scale
	body_entered.connect(_on_body_entered)


# Slight bounce/hover, a soft breathing pulse on scale, and a slow fade
# in/out on alpha -- purely cosmetic, doesn't touch the CollisionShape2D's
# own size, so pickup range is unaffected.
func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height
	$Sprite.scale = _base_scale * (1.0 + sin(_time * pulse_speed) * pulse_amount)
	var fade_t: float = (sin(_time * fade_speed) + 1.0) * 0.5
	$Sprite.modulate.a = lerpf(fade_min_alpha, 1.0, fade_t)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("activate_stealth"):
		body.activate_stealth()

	queue_free()

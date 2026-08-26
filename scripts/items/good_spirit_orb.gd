extends Area2D

@export var bob_height: float = 6.0
@export var bob_speed: float = 2.5

var _collected: bool = false
var _time: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not body.is_in_group("player"):
		return

	_collected = true

	if body.has_method("restore_soul"):
		body.restore_soul()

	queue_free()

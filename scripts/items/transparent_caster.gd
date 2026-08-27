extends Area2D

## Single-use pickup: grants the player temporary stealth (see
## Player.activate_stealth()) and disappears, matching the existing
## orb-pickup pattern. Does not touch Ghost Hunter detection code at all --
## stealth works entirely from the player's side.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("activate_stealth"):
		body.activate_stealth()

	queue_free()

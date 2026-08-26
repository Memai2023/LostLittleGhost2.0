extends Area2D

signal portal_activated

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _activated:
		return
	if not body.is_in_group("player"):
		return

	_activated = true
	portal_activated.emit()

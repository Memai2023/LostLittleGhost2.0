extends Area2D

signal checkpoint_activated(respawn_position: Vector2)

const FLAME_COLOR_INACTIVE := Color(0.55, 0.75, 0.95, 0.85)
const FLAME_COLOR_ACTIVE := Color(0.85, 0.98, 1.0, 1.0)
const GLOW_COLOR_INACTIVE := Color(0.55, 0.75, 0.95, 0.25)
const GLOW_COLOR_ACTIVE := Color(0.85, 0.98, 1.0, 0.5)

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _activated:
		return
	if not body.is_in_group("player"):
		return

	_activated = true
	_set_active_appearance()

	# Same moment the portal itself changes appearance -- the body that
	# actually entered this Area2D reacts with its own portal expression, no
	# global player lookup needed. _activated above is this checkpoint's own
	# one-shot guard, so this can only ever fire once per checkpoint: not
	# while still standing inside it, not on a later re-entry, and not on a
	# respawn back at an already-activated checkpoint (respawning doesn't
	# re-enter this Area2D at all).
	if body.has_method("show_portal_pose"):
		body.show_portal_pose()

	var respawn_position: Vector2 = $RespawnPoint.global_position
	checkpoint_activated.emit(respawn_position)

	if body.has_method("set_respawn_position"):
		body.set_respawn_position(respawn_position)


func _set_active_appearance() -> void:
	$Flame.color = FLAME_COLOR_ACTIVE
	$Glow.color = GLOW_COLOR_ACTIVE

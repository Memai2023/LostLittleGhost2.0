extends CanvasLayer

const HEART_COLOR_PURE := Color(0.85, 0.92, 1, 1)
const HEART_COLOR_CORRUPTED := Color(0.5, 0.15, 0.55, 1)

@onready var hearts: Array[ColorRect] = [
	$Margin/SoulRow/Heart1,
	$Margin/SoulRow/Heart2,
	$Margin/SoulRow/Heart3,
]

var player: Node = null


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	player.soul_changed.connect(_on_player_soul_changed)
	player.soul_depleted.connect(_on_player_soul_depleted)

	_update_hearts(player.soul)


func _on_player_soul_changed(current_soul: int, _max_soul: int) -> void:
	_update_hearts(current_soul)


func _on_player_soul_depleted() -> void:
	# TEMPORARY DEBUG: remove once a real Evil Ghost / game-over flow exists.
	print("HUD: SOUL depleted — respawn sequence starting.")


func _update_hearts(current_soul: int) -> void:
	for i in hearts.size():
		hearts[i].color = HEART_COLOR_PURE if i < current_soul else HEART_COLOR_CORRUPTED

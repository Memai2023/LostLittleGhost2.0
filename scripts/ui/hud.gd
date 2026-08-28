extends CanvasLayer

## Each heart slot holds two independently-sized TextureRects (Pure/Evil)
## instead of one node swapping texture. state-pure.png and state-evil.png
## have different content aspect ratios (1.465 vs 1.090), so fitting both
## into one shared box via stretch_mode would render one visibly smaller
## than the other -- each icon gets its own box sized to the same target
## height instead, then toggled by visibility, so they read as the same
## size regardless of which is currently shown.

@onready var hearts: Array[Node] = [
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
		var is_pure: bool = i < current_soul
		hearts[i].get_node("Pure").visible = is_pure
		hearts[i].get_node("Evil").visible = not is_pure

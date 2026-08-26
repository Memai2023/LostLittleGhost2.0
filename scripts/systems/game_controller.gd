extends Node2D

var _ending_triggered: bool = false


func _ready() -> void:
	var end_portal: Node = get_tree().get_first_node_in_group("end_portal")
	if end_portal != null:
		end_portal.portal_activated.connect(_on_portal_activated)

	$EndScreen.play_again_requested.connect(_on_play_again_requested)


func _on_portal_activated() -> void:
	if _ending_triggered:
		return
	_ending_triggered = true

	# Pausing the tree freezes player movement, hazards and further damage
	# in one place instead of adding stop-flags to each existing system.
	get_tree().paused = true
	$EndScreen.show_ending()


func _on_play_again_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

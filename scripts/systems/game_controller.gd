extends Node2D

## Timings for the door-arrival sequence (total ~1.7s, within the 1.5-2.5s
## target once the initial pulse/fade phases are included).
const PULSE_STEP_DURATION := 0.12
const GLOW_FADE_IN_DURATION := 0.35
const GHOST_SWAP_DURATION := 0.35
const HOLD_DURATION := 1.0

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

	_run_arrival_sequence()


# Runs entirely in real time (the tree is not paused until the very end),
# so this plays out over roughly two seconds instead of happening instantly.
# Every step is guarded with a null/has_node check so a missing node can
# never prevent the ending from completing -- the sequence degrades
# gracefully and always still reaches _finish_ending().
func _run_arrival_sequence() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("stop_for_ending"):
		player.stop_for_ending()

	var end_portal: Node = get_tree().get_first_node_in_group("end_portal")
	var house_glow: Node = get_tree().get_first_node_in_group("house_doorway_glow")
	var arrival_ghost: Node = get_tree().get_first_node_in_group("arrival_ghost")

	# Door light pulse (two quick blinks) -- its own short-lived tween so it
	# runs alongside the main sequence below without complicating its
	# parallel/sequential structure.
	if end_portal != null and end_portal.has_node("DoorLight"):
		var door_light: CanvasItem = end_portal.get_node("DoorLight")
		var pulse := create_tween()
		pulse.tween_property(door_light, "modulate:a", 1.0, PULSE_STEP_DURATION)
		pulse.tween_property(door_light, "modulate:a", 0.45, PULSE_STEP_DURATION)
		pulse.tween_property(door_light, "modulate:a", 1.0, PULSE_STEP_DURATION)

	var tween := create_tween()

	# Phase 1: warm glow fades in over the painted house doorway.
	if house_glow != null:
		house_glow.visible = true
		house_glow.modulate.a = 0.0
		tween.tween_property(house_glow, "modulate:a", 0.9, GLOW_FADE_IN_DURATION)

	# Phase 2: normal ghost fades out while the small glowing ghost fades in
	# at the house entrance, together.
	tween.set_parallel(true)
	if player != null and player.has_node("GoodGhostSprite"):
		tween.tween_property(player.get_node("GoodGhostSprite"), "modulate:a", 0.0, GHOST_SWAP_DURATION)
	if arrival_ghost != null:
		arrival_ghost.visible = true
		arrival_ghost.modulate.a = 0.0
		tween.tween_property(arrival_ghost, "modulate:a", 1.0, GHOST_SWAP_DURATION)
	tween.set_parallel(false)

	# Phase 3: brief hold on the arrival image, then complete.
	tween.tween_interval(HOLD_DURATION)
	tween.tween_callback(_finish_ending)


func _finish_ending() -> void:
	# Pausing the tree freezes remaining hazards/timers in one place instead
	# of adding stop-flags to each existing system.
	get_tree().paused = true
	$EndScreen.show_ending()


func _on_play_again_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

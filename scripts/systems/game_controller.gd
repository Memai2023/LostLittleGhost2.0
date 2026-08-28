extends Node2D

## The main arrival sequence is 1.8 seconds. Door pulses run in parallel so
## the full effect stays inside the intended 1.5-2.5 second window.
const PULSE_STEP_DURATION := 0.14
const DOOR_BRIGHTEN_DURATION := 0.28
const GLOW_FADE_IN_DURATION := 0.35
const GHOST_SWAP_DURATION := 0.45
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

	# Pulse the soft light centered inside the door artwork. This replaces the
	# old solid Polygon2D placeholder, so no geometric circle sits over the art.
	if end_portal != null and end_portal.has_node("DoorLightPulse"):
		var door_light: CanvasItem = end_portal.get_node("DoorLightPulse")
		door_light.visible = true
		door_light.modulate.a = 0.0
		var pulse := create_tween()
		pulse.tween_property(door_light, "modulate:a", 0.95, PULSE_STEP_DURATION)
		pulse.tween_property(door_light, "modulate:a", 0.2, PULSE_STEP_DURATION)
		pulse.tween_property(door_light, "modulate:a", 1.0, PULSE_STEP_DURATION)
		pulse.tween_property(door_light, "modulate:a", 0.18, PULSE_STEP_DURATION)

	# Briefly brighten the full door while its internal light blinks.
	if end_portal != null and end_portal.has_node("Sprite"):
		var door_artwork: CanvasItem = end_portal.get_node("Sprite")
		var brighten := create_tween()
		brighten.tween_property(
			door_artwork,
			"modulate",
			Color(1.3, 1.16, 0.86, 1.0),
			DOOR_BRIGHTEN_DURATION
		)
		brighten.tween_property(
			door_artwork,
			"modulate",
			Color.WHITE,
			DOOR_BRIGHTEN_DURATION
		)

	var tween := create_tween()

	# Phase 1: warm glow fades in over the painted house doorway.
	if house_glow != null:
		house_glow.visible = true
		house_glow.modulate.a = 0.0
		tween.tween_property(house_glow, "modulate:a", 0.9, GLOW_FADE_IN_DURATION)
	else:
		tween.tween_interval(GLOW_FADE_IN_DURATION)

	# Phase 2: normal ghost fades out while the small glowing ghost fades in
	# at the house entrance, together.
	var swap_started := false
	if player != null and player.has_node("GoodGhostSprite"):
		tween.tween_property(player.get_node("GoodGhostSprite"), "modulate:a", 0.0, GHOST_SWAP_DURATION)
		swap_started = true
	if arrival_ghost != null:
		arrival_ghost.visible = true
		arrival_ghost.modulate.a = 0.0
		if swap_started:
			tween.parallel().tween_property(arrival_ghost, "modulate:a", 1.0, GHOST_SWAP_DURATION)
		else:
			tween.tween_property(arrival_ghost, "modulate:a", 1.0, GHOST_SWAP_DURATION)
		swap_started = true
	if not swap_started:
		tween.tween_interval(GHOST_SWAP_DURATION)
	tween.tween_callback(_hide_player_visual.bind(player))

	# Phase 3: brief hold on the arrival image, then complete.
	tween.tween_interval(HOLD_DURATION)
	tween.tween_callback(_finish_ending)


func _hide_player_visual(player: Node) -> void:
	if is_instance_valid(player) and player.has_node("GoodGhostSprite"):
		player.get_node("GoodGhostSprite").visible = false


func _finish_ending() -> void:
	# Pausing the tree freezes remaining hazards/timers in one place instead
	# of adding stop-flags to each existing system.
	get_tree().paused = true
	$EndScreen.show_ending()


func _on_play_again_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

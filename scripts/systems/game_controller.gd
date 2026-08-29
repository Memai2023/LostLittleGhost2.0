extends Node2D

## The main arrival sequence is 1.8 seconds. Door pulses run in parallel so
## the full effect stays inside the intended 1.5-2.5 second window.
const PULSE_STEP_DURATION := 0.14
const DOOR_BRIGHTEN_DURATION := 0.28
const GLOW_FADE_IN_DURATION := 0.35
const GHOST_SWAP_DURATION := 0.45
const HOLD_DURATION := 1.0
# Player walking into the foreground EndPortal, before the ghost is shown at
# the background house doorway. Kept short -- it's a final step-in, not a
# separate cutscene beat.
const PLAYER_ENTER_PORTAL_DURATION := 0.4
# ArrivalGhost's small settle-in slide (offset -> exact HouseDoorTarget
# position), run in parallel with its own fade-in.
const GHOST_ARRIVE_OFFSET := Vector2(0, -24)

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
	var portal_entry_target: Node2D = get_tree().get_first_node_in_group("portal_entry_target")
	var house_door_target: Node2D = get_tree().get_first_node_in_group("house_door_target")

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

	# Phase 0: the world-space player steps fully into the foreground portal.
	# This only ever tweens the player's own global_position -- it never
	# joins the parallax hierarchy. The camera is already frozen (see
	# player.stop_for_ending()/_lock_camera_for_ending()), so this movement
	# doesn't drag the background framing along with it.
	if player != null and portal_entry_target != null:
		tween.tween_property(player, "global_position", portal_entry_target.global_position, PLAYER_ENTER_PORTAL_DURATION)
	else:
		tween.tween_interval(PLAYER_ENTER_PORTAL_DURATION)

	# Phase 1: the normal ghost fades out now that it has reached the portal.
	if player != null and player.has_node("GoodGhostSprite"):
		tween.tween_property(player.get_node("GoodGhostSprite"), "modulate:a", 0.0, GHOST_SWAP_DURATION)
	else:
		tween.tween_interval(GHOST_SWAP_DURATION)
	tween.tween_callback(_hide_player_visual.bind(player))

	# Phase 2: warm glow fades in over the painted house doorway, while
	# ArrivalGhost appears just above HouseDoorTarget and settles exactly
	# onto it -- both together, at the destination side of the ending.
	var phase2_started := false
	if house_glow != null:
		house_glow.visible = true
		house_glow.modulate.a = 0.0
		if phase2_started:
			tween.parallel().tween_property(house_glow, "modulate:a", 0.9, GLOW_FADE_IN_DURATION)
		else:
			tween.tween_property(house_glow, "modulate:a", 0.9, GLOW_FADE_IN_DURATION)
		phase2_started = true
	if arrival_ghost != null:
		var landing_position: Vector2 = (
			house_door_target.global_position if house_door_target != null
			else arrival_ghost.global_position
		)
		arrival_ghost.global_position = landing_position + GHOST_ARRIVE_OFFSET
		arrival_ghost.visible = true
		arrival_ghost.modulate.a = 0.0
		if phase2_started:
			tween.parallel().tween_property(arrival_ghost, "modulate:a", 1.0, GHOST_SWAP_DURATION)
		else:
			tween.tween_property(arrival_ghost, "modulate:a", 1.0, GHOST_SWAP_DURATION)
		tween.parallel().tween_property(arrival_ghost, "global_position", landing_position, GHOST_SWAP_DURATION)
		phase2_started = true
	if not phase2_started:
		tween.tween_interval(GLOW_FADE_IN_DURATION)

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

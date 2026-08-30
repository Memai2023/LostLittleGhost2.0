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

# Godot's WAV importer (edit/loop_mode in the .import file) does not take
# effect for these streams in this project's pipeline -- confirmed via direct
# load()+playback testing. loop_mode/loop_end are set programmatically in
# _ready() instead (see _configure_loop()), which does produce a
# verified-seamless loop. AudioStreamMP3 uses a different native API
# (a plain .loop bool, no sample-position math) -- _configure_loop() branches
# on the stream's actual type so either kind can be assigned here.
const THEME_SAMPLE_RATE := 44100.0

# The selected victory theme. Exposed as an export so it can be swapped for
# any of the available alternatives (victory-new.mp3, victory_theme.wav,
# victory_theme_gentle.wav, victory_theme_enchanted.wav,
# victory_theme_triumphant.wav) from the Inspector on this node in
# main.tscn, without touching any script code or scattering file paths
# across multiple methods.
@export var victory_theme: AudioStream = preload("res://assets/audio/music/victory-new.mp3")

# Central music volume constants -- referenced everywhere volume is set so
# levels never drift out of sync between the gameplay/superpower/victory
# transitions.
const GAMEPLAY_MUSIC_DB := -20.0
const SUPERPOWER_MUSIC_DB := -16.0
const SILENT_MUSIC_DB := -60.0
# Victory is intentionally a bit more present than gameplay -- each
# alternative theme was leveled (via its own generator peak, or the
# supplied victory-new.mp3's own mastering) to sit well at this same
# volume, so switching victory_theme above never requires retuning this
# constant.
const VICTORY_MUSIC_DB := -10.0

const SUPERPOWER_CROSSFADE_DURATION := 0.75
const DEACTIVATE_CROSSFADE_DURATION := 0.75
const VICTORY_MUSIC_FADE_DURATION := 0.8

enum MusicState { GAMEPLAY, SUPERPOWER, VICTORY }

var _ending_triggered: bool = false
var _music_state: MusicState = MusicState.GAMEPLAY
var _player: Node = null

# Tracked so a new transition can always cancel whatever's still running
# instead of letting two tweens fight over the same volume_db.
var _background_music_tween: Tween = null
var _superpower_music_tween: Tween = null


func _ready() -> void:
	_configure_loop($SuperpowerMusic.stream)
	if victory_theme != null:
		_configure_loop(victory_theme)

	$BackgroundMusic.volume_db = GAMEPLAY_MUSIC_DB

	var end_portal: Node = get_tree().get_first_node_in_group("end_portal")
	if end_portal != null:
		end_portal.portal_activated.connect(_on_portal_activated)

	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		if _player.has_signal("superpower_activated"):
			_player.superpower_activated.connect(_on_superpower_activated)
		if _player.has_signal("superpower_deactivated"):
			_player.superpower_deactivated.connect(_on_superpower_deactivated)

	$EndScreen.play_again_requested.connect(_on_play_again_requested)


# Dispatches to whichever native loop API the stream's actual type supports,
# so SuperpowerMusic/victory_theme can each be freely reassigned (in the
# Inspector, or here) between an AudioStreamWAV (the generated
# alternatives -- sample-position based looping) and an AudioStreamMP3 (the
# supplied tracks -- a plain .loop bool) without this call site caring which.
func _configure_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(round(stream.get_length() * THEME_SAMPLE_RATE))
	elif stream is AudioStreamMP3:
		stream.loop = true


func _cancel_music_tweens() -> void:
	if _background_music_tween != null and _background_music_tween.is_valid():
		_background_music_tween.kill()
	if _superpower_music_tween != null and _superpower_music_tween.is_valid():
		_superpower_music_tween.kill()


# Fires on every activate_stealth() call, including a refresh while already
# stealthed (activate_stealth() has no re-entry guard -- see player.gd). The
# MusicState guards below are what make a refresh a no-op for music: no
# restarted crossfade, no second SuperpowerMusic instance, no competing
# tweens. Victory always wins outright.
func _on_superpower_activated() -> void:
	if _music_state == MusicState.VICTORY:
		return
	if _music_state == MusicState.SUPERPOWER:
		return

	_music_state = MusicState.SUPERPOWER
	_crossfade_to_superpower()


# Fades $BackgroundMusic out and pauses it (never stops it, so its playback
# position survives), then fades $SuperpowerMusic in from silent. Both
# fades run concurrently, matching the requested crossfade behavior.
func _crossfade_to_superpower() -> void:
	_cancel_music_tweens()

	var bg_tween := create_tween()
	_background_music_tween = bg_tween
	bg_tween.tween_property($BackgroundMusic, "volume_db", SILENT_MUSIC_DB, SUPERPOWER_CROSSFADE_DURATION)
	bg_tween.tween_callback(func() -> void: $BackgroundMusic.stream_paused = true)

	if not $SuperpowerMusic.playing:
		$SuperpowerMusic.volume_db = SILENT_MUSIC_DB
		$SuperpowerMusic.play()

	var sp_tween := create_tween()
	_superpower_music_tween = sp_tween
	sp_tween.tween_property($SuperpowerMusic, "volume_db", SUPERPOWER_MUSIC_DB, SUPERPOWER_CROSSFADE_DURATION)


# Fires from the actual existing deactivation event (player.gd's
# StealthTimer timing out -- see superpower_deactivated). Guarded so a stray
# deactivation while the game is already in another state (most importantly
# VICTORY, e.g. transparency expiring during/after the ending) can never
# resume gameplay music once it shouldn't.
func _on_superpower_deactivated() -> void:
	if _music_state != MusicState.SUPERPOWER:
		return

	_music_state = MusicState.GAMEPLAY
	_crossfade_to_gameplay()


# Fades $SuperpowerMusic out and stops it, while unpausing $BackgroundMusic
# and fading it back up from silent -- since it was only paused (never
# stopped) it resumes from exactly where it left off, not from the start.
func _crossfade_to_gameplay() -> void:
	_cancel_music_tweens()

	var sp_tween := create_tween()
	_superpower_music_tween = sp_tween
	sp_tween.tween_property($SuperpowerMusic, "volume_db", SILENT_MUSIC_DB, DEACTIVATE_CROSSFADE_DURATION)
	sp_tween.tween_callback($SuperpowerMusic.stop)

	$BackgroundMusic.volume_db = SILENT_MUSIC_DB
	$BackgroundMusic.stream_paused = false
	var bg_tween := create_tween()
	_background_music_tween = bg_tween
	bg_tween.tween_property($BackgroundMusic, "volume_db", GAMEPLAY_MUSIC_DB, DEACTIVATE_CROSSFADE_DURATION)


func _on_portal_activated() -> void:
	if _ending_triggered:
		return
	_ending_triggered = true
	# Set before anything else so _on_superpower_activated()/
	# _on_superpower_deactivated() immediately treat victory as final,
	# regardless of exactly when either signal happens to arrive relative
	# to this frame.
	_music_state = MusicState.VICTORY

	_run_arrival_sequence()
	_run_victory_audio()


# Overrides whatever music state was active (gameplay playing, gameplay
# fading, gameplay paused mid-superpower, or superpower music playing) and
# transitions cleanly to the victory theme. Runs alongside
# _run_arrival_sequence() rather than blocking it -- both were kicked off
# together from _on_portal_activated(), which is itself guarded by
# _ending_triggered, so this whole sequence can only ever run once.
func _run_victory_audio() -> void:
	_cancel_music_tweens()

	# Safe no-op if it was never playing. Stopped outright (not faded) since
	# victory overrides every other music state immediately. Any later
	# superpower_deactivated (transparency expiring after the ending
	# started) is a no-op, since _music_state is already VICTORY by the
	# time this runs (set in _on_portal_activated()).
	$SuperpowerMusic.stop()

	# Unpausing before the fade means: if BackgroundMusic was already paused
	# (and therefore already silent, from a prior superpower crossfade),
	# this fade is inaudible; if it was still playing normally, this is a
	# normal audible fade-out. Either way it ends silent and paused-off.
	$BackgroundMusic.stream_paused = false
	var tween := create_tween()
	_background_music_tween = tween
	tween.tween_property($BackgroundMusic, "volume_db", SILENT_MUSIC_DB, VICTORY_MUSIC_FADE_DURATION)
	await tween.finished

	$BackgroundMusic.stop()
	$VictoryChimeSFX.play()
	_start_victory_theme()


func _start_victory_theme() -> void:
	$BackgroundMusic.stream = victory_theme
	$BackgroundMusic.volume_db = VICTORY_MUSIC_DB
	$BackgroundMusic.stream_paused = false
	$BackgroundMusic.play()


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
	var arrival_ghost: Node2D = get_tree().get_first_node_in_group("arrival_ghost")
	var portal_entry_target: Node2D = get_tree().get_first_node_in_group("portal_entry_target")
	var house_door_arrival_marker: Node2D = get_tree().get_first_node_in_group("house_door_arrival_marker")

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
	# ArrivalGhost appears just above HouseDoorArrivalMarker and settles
	# exactly onto it -- both together, at the destination side of the
	# ending. _begin_house_arrival() positions ArrivalGhost using LOCAL
	# coordinates relative to HouseDoorArrivalMarker (both are children of
	# the same MidSprite -- see main_level.tscn), never global_position or
	# a camera reset: MidSprite's own on-screen position can keep changing
	# for a while after the camera freezes (its SMOOTHED render position,
	# get_screen_center_position(), eases toward the frozen target rather
	# than snapping -- see background_scroller.gd), but two siblings placed
	# in the same *local* space stay correctly aligned no matter where
	# MidSprite itself currently is, so there's nothing here for camera
	# timing to get wrong.
	tween.tween_callback(_begin_house_arrival.bind(house_glow, arrival_ghost, house_door_arrival_marker))
	tween.tween_interval(GHOST_SWAP_DURATION)

	# Phase 3: brief hold on the arrival image, then complete.
	tween.tween_interval(HOLD_DURATION)
	tween.tween_callback(_finish_ending)


# house_glow and arrival_ghost each get their own independent tween (both
# started together, in this same call) so they still animate in parallel;
# GHOST_SWAP_DURATION (the longer of the two) is what the caller waits on
# afterward, preserving the original total timing.
func _begin_house_arrival(house_glow: Node, arrival_ghost: Node2D, marker: Node2D) -> void:
	if house_glow != null:
		house_glow.visible = true
		house_glow.modulate.a = 0.0
		var glow_tween := create_tween()
		glow_tween.tween_property(house_glow, "modulate:a", 0.9, GLOW_FADE_IN_DURATION)

	if arrival_ghost != null:
		# Local coordinates, not global_position: arrival_ghost and marker
		# are both direct children of the same MidSprite, so this lines
		# them up correctly regardless of MidSprite's own current
		# on-screen position -- see the comment above _run_arrival_sequence()'s
		# Phase 2 for why global_position/to_global() would reintroduce a
		# dependency on camera timing here.
		var landing_position: Vector2 = (
			marker.position if marker != null else arrival_ghost.position
		)
		arrival_ghost.position = landing_position + GHOST_ARRIVE_OFFSET
		arrival_ghost.visible = true
		arrival_ghost.modulate.a = 0.0
		var ghost_tween := create_tween()
		ghost_tween.tween_property(arrival_ghost, "modulate:a", 1.0, GHOST_SWAP_DURATION)
		ghost_tween.parallel().tween_property(arrival_ghost, "position", landing_position, GHOST_SWAP_DURATION)


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

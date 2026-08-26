extends CanvasLayer

signal play_again_requested

@export var fade_duration: float = 0.8

var _shown: bool = false


func _ready() -> void:
	# Keep this whole UI (and any tween it starts) responsive while the
	# game is paused, so Play Again always works.
	process_mode = Node.PROCESS_MODE_ALWAYS

	visible = false
	$FadeRect.color = Color(0, 0, 0, 0)
	$ContentCenter/ContentBox.visible = false

	$ContentCenter/ContentBox/PlayAgainButton.pressed.connect(_on_play_again_pressed)


func show_ending() -> void:
	if _shown:
		return
	_shown = true

	visible = true

	var tween := create_tween()
	tween.tween_property($FadeRect, "color:a", 1.0, fade_duration)
	tween.finished.connect(_on_fade_finished)


func _on_fade_finished() -> void:
	$ContentCenter/ContentBox.visible = true


func _on_play_again_pressed() -> void:
	play_again_requested.emit()

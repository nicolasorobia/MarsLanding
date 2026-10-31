## Start screen: explains how to play, then loads the level when Start is pressed.
## Attach to the root of start_menu.tscn.
extends Node2D

const LEVEL_PATH := "res://scenes/main.tscn"

@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	# Enter or Space also starts the game.
	_start_button.grab_focus()
	# The colonists here are decoration: keep them animating in place
	# instead of wandering behind the menu.
	for colonist in $Colonists.get_children():
		colonist.set_process(false)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_PATH)

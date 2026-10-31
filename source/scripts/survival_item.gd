## A structure in the level the player can click as the colony's next priority.
## Attach to the structure's Sprite2D. Several sprites can share one item_id
## (e.g. Carrots and Potatoes are both "food").
## Starts dulled (grayish); its true colors come back once it's placed correctly.
## Items with growth_stages (the crops) then loop a growing animation.
class_name SurvivalItem
extends Sprite2D

signal clicked(item: SurvivalItem)

const HOVER_TINT := Color(1.3, 1.3, 1.3)
const DULL_SHADER := preload("res://shaders/dull.gdshader")
## Seconds for the true colors to fade in after a correct pick.
const REVEAL_TIME := 0.6

## Must match an entry in SurvivalPuzzle.correct_order, e.g. "oxygen".
@export var item_id := ""
## Optional growing animation, played only once placed: these textures in order
## (e.g. seed, sprout), then the item's own texture, then back to the first.
## Each should be the same size as the item's texture so clicks still line up.
@export var growth_stages: Array[Texture2D] = []
## Seconds each growth stage is shown.
@export var stage_time := 1.5

## Turned off once this item is placed or while a popup is open.
var enabled := true
## True once the player has put this item in its right box.
var placed := false

var _base_scale := Vector2.ONE
## Growth frames: growth_stages followed by the grown texture.
var _frames: Array[Texture2D] = []
var _frame := 0
var _stage_left := 0.0


func _ready() -> void:
	_base_scale = scale
	_frames = growth_stages.duplicate()
	_frames.append(texture)
	_frame = _frames.size() - 1
	material = ShaderMaterial.new()
	material.shader = DULL_SHADER
	_set_dullness(1.0)


func _process(delta: float) -> void:
	modulate = HOVER_TINT if enabled and _is_hovered() else Color.WHITE
	# Grow only after a correct pick; while dulled the item stays still.
	if placed and _frames.size() > 1:
		_stage_left -= delta
		if _stage_left <= 0.0:
			_stage_left = stage_time
			_show_frame((_frame + 1) % _frames.size())


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	# Use the click's own position (works for touch too) in this sprite's space.
	var local_click := (make_input_local(mouse) as InputEventMouseButton).position
	if get_rect().has_point(local_click):
		get_viewport().set_input_as_handled()
		clicked.emit(self)


## Shows true colors (with a small pop) when placed, or dulls the item again.
func set_placed(value: bool) -> void:
	if placed == value:
		return
	placed = value
	if not placed:
		scale = _base_scale
		_set_dullness(1.0)
		_show_frame(_frames.size() - 1)
		return
	# Show the grown crop while the colors fade in, then start the cycle at seed.
	_stage_left = stage_time
	var tween := create_tween().set_parallel()
	tween.tween_method(_set_dullness, 1.0, 0.0, REVEAL_TIME)
	tween.tween_property(self, "scale", _base_scale * 1.12, REVEAL_TIME * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", _base_scale, REVEAL_TIME * 0.6)


func _show_frame(index: int) -> void:
	_frame = index
	texture = _frames[index]


func _set_dullness(amount: float) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"dullness", amount)


func _is_hovered() -> bool:
	return get_rect().has_point(get_local_mouse_position())

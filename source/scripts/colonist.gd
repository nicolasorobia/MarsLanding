## A colonist living in the level. Purely visual flavor: wanders between colony
## spots, chats with other colonists, and says little lines in a speech bubble.
## One scene is shared by every colonist; each instance sets its own sprite sheet
## and personality in the Inspector.
class_name Colonist
extends CharacterBody2D

enum State { IDLE, WALK, CHAT, LEAVING }

const CHAT_LINES: Array[String] = [
	"Hi!", "How's it going?", "Nice view!", "Haha!", "Did you see that?",
	"I miss Earth...", "Same!", "Totally!", "Hmm...", "Look at the dust!",
]
## Lines said on arriving at a spot. Keys match the Marker2D names under Spots.
const SPOT_LINES := {
	&"Water": ["Thirsty!", "Water looks clean."],
	&"Crops": ["Growing nicely!", "Yum, carrots!"],
	&"Shelter": ["Home sweet home.", "Nap time?"],
	&"Oxygen": ["O2 check!", "Breathe in..."],
	&"Silo": ["Counting supplies.", "Storage looks good."],
	&"Landing": ["Any ships yet?", "Waiting for supplies."],
}
## Random wander points are picked inside the crater floor.
const WANDER_AREA := Rect2(110, 230, 650, 210)
const CHAT_GAP := 60.0
## Seconds after a chat before a colonist will chat again.
const CHAT_COOLDOWN := Vector2(8, 14)
## Seconds between lines in a chat.
const CHAT_LINE_TIME := 1.7

@export var colonist_name := "Colonist"
## Same layout as Jojo.png: 4 frames, 32x32, one row.
@export var sprite_sheet: Texture2D

@export_group("Personality")
@export var walk_speed := 50.0
## Min and max seconds spent standing still between walks.
@export var idle_time := Vector2(1.5, 4.0)
## Chance (0-1) to go chat with someone when deciding what to do next.
@export_range(0.0, 1.0) var chattiness := 0.3
## Spot visited most often: Water, Crops, Shelter, Oxygen, Silo or Landing.
@export var favorite_spot: StringName = &"Landing"
@export var catchphrase := "Hello!"

var state := State.IDLE
var partner: Colonist = null
var _target := Vector2.ZERO
var _target_spot: StringName = &""
var _idle_left := 0.0
var _chat_cooldown := 0.0
var _bob_time := 0.0
var _bubble_left := 0.0
## True for the colonist who started the current chat; it drives the lines.
var _leading_chat := false
var _chat_lines_left := 0
var _chat_line_timer := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var bubble: Label = $Bubble


func _ready() -> void:
	if sprite_sheet:
		sprite.texture = sprite_sheet
	anim.play("idle")
	# Start everyone at a different point so they don't animate in lockstep.
	anim.seek(randf() * anim.current_animation_length)
	_idle_left = randf_range(idle_time.x, idle_time.y)


func _process(delta: float) -> void:
	_chat_cooldown -= delta
	_bubble_left -= delta
	if bubble.visible and _bubble_left <= 0.0:
		bubble.hide()
	match state:
		State.IDLE:
			_idle_left -= delta
			if _idle_left <= 0.0:
				_decide()
		State.WALK:
			_walk(delta)
		State.CHAT:
			if _leading_chat:
				_lead_chat(delta)
	_update_bob(delta)


## Shows a speech bubble above the colonist for a few seconds.
func say(text: String, duration := 2.0) -> void:
	bubble.text = text
	bubble.reset_size()
	bubble.position = Vector2(-bubble.size.x * bubble.scale.x * 0.5, -18.0 - bubble.size.y * bubble.scale.y)
	bubble.show()
	_bubble_left = duration


## Removes this colonist from the colony with a short fade-out.
func leave(last_words := "Bye...") -> void:
	if state == State.LEAVING:
		return
	if is_instance_valid(partner) and partner.partner == self:
		partner.end_chat()
	partner = null
	_leading_chat = false
	state = State.LEAVING
	anim.speed_scale = 1.0
	say(last_words, 2.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.tween_property(self, "position:y", position.y - 24.0, 2.0)
	tween.chain().tween_callback(queue_free)


## Called by another colonist who is walking over to chat with this one.
func wait_for_chat(other: Colonist) -> void:
	partner = other
	state = State.CHAT
	_target_spot = &""
	anim.speed_scale = 1.0


func end_chat() -> void:
	if state == State.LEAVING:
		return
	partner = null
	_leading_chat = false
	_chat_cooldown = randf_range(CHAT_COOLDOWN.x, CHAT_COOLDOWN.y)
	_go_idle()


func _decide() -> void:
	if _chat_cooldown <= 0.0 and randf() < chattiness:
		var other := _find_chat_partner()
		if other:
			partner = other
			other.wait_for_chat(self)
			var side := 1.0 if global_position.x > other.global_position.x else -1.0
			_walk_to(other.global_position + Vector2(CHAT_GAP * side, 0))
			return

	var roll := randf()
	var spot: Node2D = null
	if roll < 0.45:
		spot = _get_spot(favorite_spot)
	elif roll < 0.75:
		spot = get_tree().get_nodes_in_group(&"colony_spot").pick_random()

	if spot:
		_target_spot = spot.name
		_walk_to(spot.global_position + Vector2(randf_range(-20, 20), randf_range(-6, 6)))
	else:
		_walk_to(Vector2(
			randf_range(WANDER_AREA.position.x, WANDER_AREA.end.x),
			randf_range(WANDER_AREA.position.y, WANDER_AREA.end.y)))


func _walk_to(pos: Vector2) -> void:
	_target = pos
	state = State.WALK
	anim.speed_scale = 1.8


func _walk(delta: float) -> void:
	if absf(_target.x - global_position.x) > 1.0:
		sprite.flip_h = _target.x < global_position.x
	global_position = global_position.move_toward(_target, walk_speed * delta)
	if global_position.distance_to(_target) < 1.0:
		_arrive()


func _arrive() -> void:
	anim.speed_scale = 1.0
	if partner:
		state = State.CHAT
		_face(partner)
		partner._face(self)
		_leading_chat = true
		_chat_lines_left = randi_range(2, 4)
		_chat_line_timer = 0.0
		return
	_go_idle()
	if SPOT_LINES.has(_target_spot) and randf() < 0.6:
		say(SPOT_LINES[_target_spot].pick_random())
	_target_spot = &""


## Run by the colonist who started the chat; both take turns talking.
func _lead_chat(delta: float) -> void:
	_chat_line_timer -= delta
	if _chat_line_timer > 0.0:
		return
	if not is_instance_valid(partner) or partner.partner != self:
		end_chat()
		return
	if _chat_lines_left == 0:
		partner.end_chat()
		end_chat()
		return
	# Odd counts are this colonist's turn, even counts the partner's.
	var speaker: Colonist = self if _chat_lines_left % 2 == 1 else partner
	var line: String = speaker.catchphrase if randf() < 0.25 else CHAT_LINES.pick_random()
	speaker.say(line, 1.4)
	_chat_lines_left -= 1
	_chat_line_timer = CHAT_LINE_TIME


func _go_idle() -> void:
	state = State.IDLE
	anim.speed_scale = 1.0
	_idle_left = randf_range(idle_time.x, idle_time.y)


func _find_chat_partner() -> Colonist:
	var free: Array[Colonist] = []
	for node in get_parent().get_children():
		# Only idle colonists can be pulled into a chat, so walks aren't cut short.
		if node is Colonist and node != self and node.state == State.IDLE and node._chat_cooldown <= 0.0:
			free.append(node)
	return free.pick_random() if free else null


func _get_spot(spot_name: StringName) -> Node2D:
	for spot: Node2D in get_tree().get_nodes_in_group(&"colony_spot"):
		if spot.name == spot_name:
			return spot
	return null


func _face(other: Node2D) -> void:
	sprite.flip_h = other.global_position.x < global_position.x


## Small hop while walking, since the sheet only has idle frames.
func _update_bob(delta: float) -> void:
	if state == State.WALK:
		_bob_time += delta
		sprite.position.y = -absf(sin(_bob_time * 10.0)) * 2.0
	else:
		sprite.position.y = 0.0

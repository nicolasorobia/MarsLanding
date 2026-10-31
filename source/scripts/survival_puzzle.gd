## Level controller: the player clicks structures in the level in order of
## survival priority. A right pick fills the next box; a wrong pick sends a
## colonist home and shows a hint about what the colony needed instead.
## Each round opens with a real weather report from NASA's Curiosity rover, and
## the hints use real measurements (see MarsData and tools/fetch_nasa_data.py).
## Attach to the root of puzzle_ui.tscn.
class_name SurvivalPuzzle
extends CanvasLayer

signal level_completed
signal level_failed

## The right answer, top priority first. Each entry must match a SurvivalItem's item_id.
@export var correct_order: Array[String] = ["oxygen", "shelter", "water", "food", "storage"]

## Text shown in a box once its item is placed.
@export var labels := {
	"oxygen": "Oxygen",
	"shelter": "Shelter",
	"water": "Water",
	"food": "Food",
	"storage": "Silo",
}

## Kid-friendly hints about the item that SHOULD have been picked.
## {placeholders} are filled with real Curiosity rover data (see _build_hint_values).
@export var hints := {
	"oxygen": "You can only survive about 3 minutes without air. Curiosity measured Mars air at just {air_percent}% as thick as Earth's. Way too thin to breathe!",
	"shelter": "Tonight it will be {today_low}°C outside, and Curiosity once measured {record_low}°C on {record_low_date}! Colonists need a warm shelter within hours.",
	"water": "People can only last about 3 days without water. At {today_low}°C, any water left outside on Mars freezes solid!",
	"food": "You can last about 3 weeks without food, but crops take time to grow. With highs of only about {avg_high}°C outside, they need a warm greenhouse!",
	"storage": "A silo keeps extra supplies safe for later. Curiosity has been exploring Mars for {mission_sols} sols (Mars days), and long missions need a lot of supplies!",
}

## Parent of the clickable SurvivalItems (the Structures node).
@export var structures: Node
## Parent of the Colonist nodes.
@export var colonists: Node
@export var empty_slot_style: StyleBox
@export var filled_slot_style: StyleBox

var _step := 0
var _items: Array[SurvivalItem] = []
var _game_over := false
var _intro_open := false
## Curiosity's newest report we have, and the values used to fill the hints.
var _today := {}
var _facts := {}
var _hint_values := {}
var _badge_refresh := 0.0

@onready var _slots: Array[Node] = %Slots.get_children()
@onready var _popup: Control = %Popup
@onready var _popup_title: Label = %PopupTitle
@onready var _popup_text: Label = %PopupText
@onready var _popup_button: Button = %PopupButton
@onready var _right_sfx: AudioStreamPlayer = %RightSfx
@onready var _wrong_sfx: AudioStreamPlayer = %WrongSfx
@onready var _weather_badge: Label = %WeatherBadge


func _ready() -> void:
	assert(_slots.size() == correct_order.size(),
		"Number of boxes must match correct_order size.")
	for node in structures.get_children():
		if node is SurvivalItem:
			_items.append(node)
			node.clicked.connect(_on_item_clicked)
	_popup_button.pressed.connect(_on_popup_button_pressed)
	_facts = MarsData.load_facts()
	# Start with the newest report on disk, then try to get a newer one online.
	_set_report(MarsData.newest_offline_report())
	reset_puzzle()
	_show_weather_report()
	_fetch_latest_report()


func _process(delta: float) -> void:
	# Keep the Mars clock on the badge ticking.
	_badge_refresh -= delta
	if _badge_refresh <= 0.0:
		_badge_refresh = 1.0
		_update_badge()


func reset_puzzle() -> void:
	_step = 0
	_game_over = false
	for i in _slots.size():
		_set_slot(i, "?", false)
	for item in _items:
		item.enabled = true
		item.set_placed(false)
	_popup.hide()


func _on_item_clicked(item: SurvivalItem) -> void:
	if _game_over or _popup.visible or _step >= correct_order.size():
		return

	var needed := correct_order[_step]
	if item.item_id == needed:
		_place_correct(needed)
	else:
		_pick_wrong(item.item_id, needed)


func _place_correct(item_id: String) -> void:
	_right_sfx.play()
	_set_slot(_step, labels.get(item_id, item_id), true)
	for item in _items:
		if item.item_id == item_id:
			item.enabled = false
			item.set_placed(true)
	_step += 1
	if _step == correct_order.size():
		_win()


func _pick_wrong(picked_id: String, needed_id: String) -> void:
	_wrong_sfx.play()
	var lost := _send_colonist_home(needed_id)
	var left := _colonists_left()
	var needed_name: String = labels.get(needed_id, needed_id)
	var picked_name: String = labels.get(picked_id, picked_id)

	var hint: String = hints.get(needed_id, "")
	var text := "%s can wait. Without %s, %s got sick and had to fly back to Earth.\n\nHint: %s" % [
		picked_name, needed_name.to_lower(), lost.colonist_name if lost else "a colonist", hint.format(_hint_values)]

	if left == 0:
		_game_over = true
		level_failed.emit()
		_show_popup("Oh no! Everyone went home...", text + "\n\nThe colony is empty. Let's try again!", "Try again")
	else:
		var noun := "colonist" if left == 1 else "colonists"
		_show_popup("Oh no!", text + "\n\n%d %s left." % [left, noun], "Got it!")


func _win() -> void:
	_game_over = true
	var order := ""
	for i in correct_order.size():
		order += "%d. %s\n" % [i + 1, labels.get(correct_order[i], correct_order[i])]
	for colonist in _active_colonists():
		colonist.say("Yay!", 3.0)
	level_completed.emit()
	_show_popup("Your colony is safe!", "Great job keeping everyone alive on Mars!\n\n" + order.strip_edges(), "Play again")


## Picks a random colonist to leave. Returns null if none are left.
func _send_colonist_home(needed_id: String) -> Colonist:
	var active := _active_colonists()
	if active.is_empty():
		return null
	var colonist: Colonist = active.pick_random()
	colonist.leave("I need %s..." % labels.get(needed_id, needed_id).to_lower())
	return colonist


func _active_colonists() -> Array[Colonist]:
	var active: Array[Colonist] = []
	for node in colonists.get_children():
		if node is Colonist and node.state != Colonist.State.LEAVING:
			active.append(node)
	return active


func _colonists_left() -> int:
	return _active_colonists().size()


func _set_slot(index: int, text: String, filled: bool) -> void:
	var slot := _slots[index] as PanelContainer
	slot.add_theme_stylebox_override(&"panel", filled_slot_style if filled else empty_slot_style)
	(slot.get_child(0) as Label).text = "%d\n%s" % [index + 1, text]


func _show_popup(title: String, text: String, button_text: String) -> void:
	_popup_title.text = title
	_popup_text.text = text
	_popup_button.text = button_text
	for item in _items:
		item.enabled = false
	_popup.show()


func _on_popup_button_pressed() -> void:
	if _game_over:
		# Restart the whole level so the colonists come back too.
		get_tree().reload_current_scene()
		return
	_popup.hide()
	for item in _items:
		item.enabled = not _is_placed(item.item_id)
	if _intro_open:
		_intro_open = false
		_colonists_react_to_weather()


## Opening card: the current Mars date and time at Curiosity's site, plus
## Curiosity's newest weather report.
func _show_weather_report() -> void:
	if _today.is_empty():
		_weather_badge.get_parent().hide()
		return
	_intro_open = true
	_show_popup("Mars Weather Report", _weather_report_text(), "Let's go!")


func _weather_report_text() -> String:
	var now := MarsData.mars_clock()
	var earth := Time.get_datetime_dict_from_system()
	var age: int = now.sol - int(_today.sol)
	var report_when := "today"
	if age == 1:
		report_when = "Sol %d, yesterday" % int(_today.sol)
	elif age > 1:
		report_when = "Sol %d, %d sols ago" % [int(_today.sol), age]
	return ("Right now at Curiosity's spot in Gale Crater it is\n"
		+ "Sol %d, %s Mars time (%s, %s %d, %d:%02d %s on Earth).\n"
		+ "It's %s, about %d°C outside.\n\n"
		+ "Curiosity's newest weather report (%s):\n"
		+ "Low: %d°C     High: %d°C\n"
		+ "Air pressure: %d Pa (Earth has 101,325 Pa!)\n"
		+ "Sunlight: %s UV\n\n"
		+ "Your colonists just landed. Click what they need most, in order!\n\n%s") % [
			now.sol, now.clock, _weekday(earth.weekday), MarsData.MONTHS[earth.month - 1].left(3), earth.day,
			(earth.hour + 11) % 12 + 1, earth.minute, "AM" if earth.hour < 12 else "PM",
			"daytime" if MarsData.is_daytime(_today, now.hour) else "night",
			MarsData.estimate_temp(_today, now.hour),
			report_when, int(_today.min_temp_c), int(_today.max_temp_c),
			int(_today.pressure_pa), str(_today.uv).replace("_", " "), MarsData.CREDIT]


func _update_badge() -> void:
	if _today.is_empty():
		return
	var now := MarsData.mars_clock()
	_weather_badge.text = "Mars - Sol %d, %s\nNow about %d°C" % [
		now.sol, now.clock, MarsData.estimate_temp(_today, now.hour)]


## Asks NASA for Curiosity's newest report. If it's newer than what we have,
## the report, badge and hints update (and the opening card, if still open).
func _fetch_latest_report() -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var report := MarsData.parse_feed(body.get_string_from_utf8())
		if report.is_empty() or int(report.sol) <= int(_today.get("sol", -1)):
			return
		MarsData.save_cache(report)
		_set_report(report)
		if _intro_open and _popup.visible:
			_popup_text.text = _weather_report_text())
	if http.request(MarsData.FEED_URL) != OK:
		http.queue_free()


func _set_report(report: Dictionary) -> void:
	_today = report
	_hint_values = _build_hint_values(_facts)
	_update_badge()


func _colonists_react_to_weather() -> void:
	var active := _active_colonists()
	active.shuffle()
	var now := MarsData.mars_clock()
	var lines: Array[String] = [
		"Brr! About %d°C right now!" % MarsData.estimate_temp(_today, now.hour),
		"The air is so thin...",
		"Only %d°C at the warmest?!" % int(_today.max_temp_c),
	]
	# Take turns so the bubbles don't overlap when colonists stand close together.
	for i in mini(active.size(), lines.size()):
		# Weak reference: the colonist may be sent home before their turn.
		var colonist_ref: WeakRef = weakref(active[i])
		var line := lines[i]
		get_tree().create_timer(i * 1.4).timeout.connect(func() -> void:
			var colonist := colonist_ref.get_ref() as Colonist
			if colonist and colonist.state != Colonist.State.LEAVING:
				colonist.say(line, 2.2))


## Real numbers for the hint placeholders. The defaults are used if the data
## files are missing, so the hints always read correctly.
func _build_hint_values(facts: Dictionary) -> Dictionary:
	var coldest: Dictionary = facts.get("coldest", {})
	return {
		"today_low": int(_today.get("min_temp_c", facts.get("avg_low_c", -75))),
		"record_low": int(coldest.get("temp_c", -100)),
		"record_low_date": MarsData.pretty_date(str(coldest.get("earth_date", "2020-06-25"))),
		"air_percent": facts.get("pressure_percent_of_earth", 0.81),
		"avg_high": roundi(facts.get("avg_high_c", -12)),
		"mission_sols": int(MarsData.mars_clock().sol),
	}


func _weekday(day: int) -> String:
	return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day]


func _is_placed(item_id: String) -> bool:
	return correct_order.slice(0, _step).has(item_id)

## Background that follows the real time of day at Curiosity's site on Mars:
## the day art during Mars daytime, the night art after sunset, fading across
## dawn and dusk. Sunrise and sunset come from Curiosity's newest weather report.
## Attach to the background Sprite2D (with the day texture) and set night_texture.
class_name DayNightBackground
extends Sprite2D

## Mars hours the fade takes at sunrise and at sunset.
const TWILIGHT_HOURS := 0.75

@export var night_texture: Texture2D
## For testing: a Mars hour (0-24) to preview. -1 follows the real Mars time.
@export_range(-1.0, 24.0, 0.25) var preview_hour := -1.0

var _night: Sprite2D
var _sunrise := 6.0
var _sunset := 18.0
var _refresh := 0.0


func _ready() -> void:
	# The night art sits exactly on top of the day art and fades in and out.
	_night = Sprite2D.new()
	_night.texture = night_texture
	_night.centered = centered
	add_child(_night)
	var report := MarsData.newest_offline_report()
	_sunrise = MarsData.clock_to_hours(report.get("sunrise", "06:00"))
	_sunset = MarsData.clock_to_hours(report.get("sunset", "18:00"))
	_update()


func _process(delta: float) -> void:
	# Mars time moves slowly, so once a second is plenty.
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_update()


## 0 in full daylight, 1 in full night, in between during dawn and dusk.
func night_amount(hour: float) -> float:
	var half := TWILIGHT_HOURS / 2.0
	var day_progress := clampf((hour - (_sunrise - half)) / TWILIGHT_HOURS, 0.0, 1.0)
	var night_progress := clampf((hour - (_sunset - half)) / TWILIGHT_HOURS, 0.0, 1.0)
	return 1.0 - day_progress + night_progress


func _update() -> void:
	var hour: float = preview_hour if preview_hour >= 0.0 else MarsData.mars_clock().hour
	_night.modulate.a = night_amount(hour)

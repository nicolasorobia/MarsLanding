## Real weather data from NASA's Curiosity rover, plus a clock for the current
## Mars date and time at Curiosity's landing site (Gale Crater).
## Data comes from three places, newest wins: a live download (see FEED_URL),
## a cache of the last live download, and the snapshot in data/ saved by
## tools/fetch_nasa_data.py. Everything returns empty dictionaries when data is
## missing, so callers should always have fallback values.
class_name MarsData
extends RefCounted

const FEED_URL := "https://mars.nasa.gov/rss/api/?feed=weather&category=msl&feedtype=json"
const WEATHER_PATH := "res://data/curiosity_weather.json"
const FACTS_PATH := "res://data/curiosity_facts.json"
const CACHE_PATH := "user://latest_curiosity_report.json"
const CREDIT := "Data: NASA/JPL-Caltech/CAB"
const MONTHS: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

## Gale Crater, where Curiosity landed (degrees east).
const GALE_LONGITUDE_E := 137.4
## Curiosity's sol = floor(Mars Sol Date + longitude/360) - this. Matches every
## date in NASA's feed and puts the 2012 landing at sol 0, about 3 PM local time.
const CURIOSITY_SOL_OFFSET := 49269
## Hours of Mars local time when the day is coldest and warmest (for estimates).
const COLDEST_HOUR := 6.0
const WARMEST_HOUR := 13.5


## Summary stats: records, averages, monthly averages, latest report.
static func load_facts() -> Dictionary:
	return _load_json(FACTS_PATH)


## Current date and local mean solar time at Gale Crater, using NASA's Mars24
## formulas. Returns {sol, hour (float), clock ("05:47")}.
static func mars_clock(unix_time := Time.get_unix_time_from_system()) -> Dictionary:
	var jd_tt := unix_time / 86400.0 + 2440587.5 + 69.184 / 86400.0
	var mars_sol_date := (jd_tt - 2405522.0028779) / 1.0274912517
	var local := mars_sol_date + GALE_LONGITUDE_E / 360.0
	var hour := fposmod(local, 1.0) * 24.0
	return {
		"sol": floori(local) - CURIOSITY_SOL_OFFSET,
		"hour": hour,
		"clock": "%02d:%02d" % [floori(hour), floori(fposmod(hour, 1.0) * 60.0)],
	}


## Newest report available without going online: the cached live download or
## the bundled snapshot, whichever is newer. Keys: sol, earth_date, mars_month,
## min_temp_c, max_temp_c, pressure_pa, uv, sunrise, sunset.
static func newest_offline_report() -> Dictionary:
	var cached := _load_json(CACHE_PATH)
	var bundled := _newest_bundled_report()
	return cached if cached.get("sol", -1) > bundled.get("sol", -1) else bundled


## Picks the newest complete report out of a raw NASA feed download.
static func parse_feed(text: String) -> Dictionary:
	var feed: Variant = JSON.parse_string(text)
	if not feed is Dictionary:
		return {}
	for raw: Dictionary in feed.get("soles", []):
		var report := {
			"sol": _to_number(raw.get("sol")),
			"earth_date": str(raw.get("terrestrial_date", "")),
			"mars_month": _to_number(str(raw.get("season", "")).replace("Month", "")),
			"min_temp_c": _to_number(raw.get("min_temp")),
			"max_temp_c": _to_number(raw.get("max_temp")),
			"pressure_pa": _to_number(raw.get("pressure")),
			"uv": raw.get("local_uv_irradiance_index") if raw.get("local_uv_irradiance_index") != "--" else null,
			"sunrise": raw.get("sunrise"),
			"sunset": raw.get("sunset"),
		}
		if _is_complete(report):
			return report
	return {}


static func save_cache(report: Dictionary) -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report))


## Rough temperature at a given Mars hour, curving between the report's low
## (around dawn) and high (early afternoon). Curiosity only reports daily
## lows and highs, so this is an estimate.
static func estimate_temp(report: Dictionary, hour: float) -> int:
	var low: float = report.get("min_temp_c", -75)
	var high: float = report.get("max_temp_c", -12)
	var warming := WARMEST_HOUR - COLDEST_HOUR
	var since_dawn := fposmod(hour - COLDEST_HOUR, 24.0)
	if since_dawn < warming:
		return roundi(low + (high - low) * (1.0 - cos(PI * since_dawn / warming)) / 2.0)
	var since_peak := since_dawn - warming
	return roundi(high - (high - low) * (1.0 - cos(PI * since_peak / (24.0 - warming))) / 2.0)


## True between the report's sunrise and sunset ("06:46", "18:51").
static func is_daytime(report: Dictionary, hour: float) -> bool:
	return clock_to_hours(report.get("sunrise", "06:00")) <= hour \
		and hour < clock_to_hours(report.get("sunset", "18:00"))


## "2020-06-25" -> "June 25, 2020"
static func pretty_date(iso_date: String) -> String:
	var parts := iso_date.split("-")
	if parts.size() != 3:
		return iso_date
	return "%s %d, %s" % [MONTHS[int(parts[1]) - 1], int(parts[2]), parts[0]]


static func _newest_bundled_report() -> Dictionary:
	var weather := _load_json(WEATHER_PATH)
	var columns: Array = weather.get("columns", [])
	var rows: Array = weather.get("rows", [])
	# Rows are oldest first; walk back to the newest complete one.
	for i in range(rows.size() - 1, -1, -1):
		var report := {}
		for c in columns.size():
			report[columns[c]] = rows[i][c]
		if _is_complete(report):
			return report
	return {}


static func _is_complete(report: Dictionary) -> bool:
	for key in ["sol", "min_temp_c", "max_temp_c", "pressure_pa", "uv"]:
		if report.get(key) == null:
			return false
	# Same sanity range as tools/fetch_nasa_data.py.
	return -130 <= report.min_temp_c and report.min_temp_c <= report.max_temp_c and report.max_temp_c <= 40


static func _to_number(value: Variant) -> Variant:
	var text := str(value).strip_edges()
	return int(text) if text.is_valid_int() else null


## "06:46" -> 6.77
static func clock_to_hours(clock: String) -> float:
	var parts := clock.split(":")
	return float(parts[0]) + float(parts[1]) / 60.0 if parts.size() == 2 else 0.0


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

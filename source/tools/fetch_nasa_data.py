"""Download and clean Curiosity rover weather data for the game.

Source: Rover Environmental Monitoring Station (REMS) on NASA's Curiosity rover,
published for outreach by NASA/JPL-Caltech and Centro de Astrobiologia (CAB):
https://mars.nasa.gov/rss/api/?feed=weather&category=msl&feedtype=json

Outputs:
  tools/curiosity_weather.csv   cleaned table, one row per sol (for spreadsheets/Python)
  data/curiosity_weather.json   same rows, compact, for Godot to load
  data/curiosity_facts.json     summary stats the game can show to kids

Usage (from the project folder):
  python tools/fetch_nasa_data.py              # download fresh data
  python tools/fetch_nasa_data.py feed.json    # use an already-downloaded feed
Only the Python standard library is used.
"""

import csv
import json
import statistics
import sys
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

FEED_URL = "https://mars.nasa.gov/rss/api/?feed=weather&category=msl&feedtype=json"
EARTH_SEA_LEVEL_PA = 101325
CREDIT = "Data: NASA/JPL-Caltech/CAB (Curiosity rover REMS weather station)"

PROJECT = Path(__file__).resolve().parent.parent
CSV_OUT = PROJECT / "tools" / "curiosity_weather.csv"
JSON_OUT = PROJECT / "data" / "curiosity_weather.json"
FACTS_OUT = PROJECT / "data" / "curiosity_facts.json"

COLUMNS = ["sol", "earth_date", "mars_month", "min_temp_c", "max_temp_c",
           "pressure_pa", "uv", "sunrise", "sunset"]


def load_feed(path: str | None) -> dict:
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    request = urllib.request.Request(FEED_URL, headers={"User-Agent": "MarsLanding-edu-game"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def to_number(value: str) -> int | None:
    """The feed uses '--' for missing readings."""
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def clean(feed: dict) -> list[dict]:
    rows = []
    for sol in feed["soles"]:
        row = {
            "sol": to_number(sol["sol"]),
            "earth_date": sol["terrestrial_date"],
            "mars_month": to_number(sol["season"].replace("Month", "")),
            "min_temp_c": to_number(sol["min_temp"]),
            "max_temp_c": to_number(sol["max_temp"]),
            "pressure_pa": to_number(sol["pressure"]),
            "uv": sol["local_uv_irradiance_index"] if sol["local_uv_irradiance_index"] != "--" else None,
            "sunrise": sol["sunrise"],
            "sunset": sol["sunset"],
        }
        # Keep only sols with a usable temperature reading.
        if row["sol"] is None or row["min_temp_c"] is None or row["max_temp_c"] is None:
            continue
        # Drop sensor glitches (Curiosity's site never gets near these values).
        if not (-130 <= row["min_temp_c"] <= row["max_temp_c"] <= 40):
            continue
        rows.append(row)
    rows.sort(key=lambda r: r["sol"])
    return rows


def summarize(rows: list[dict]) -> dict:
    coldest = min(rows, key=lambda r: r["min_temp_c"])
    warmest = max(rows, key=lambda r: r["max_temp_c"])
    pressures = [r["pressure_pa"] for r in rows if r["pressure_pa"]]
    swings = [r["max_temp_c"] - r["min_temp_c"] for r in rows]

    by_month = defaultdict(list)
    for r in rows:
        if r["mars_month"]:
            by_month[r["mars_month"]].append(r)
    months = []
    for month in sorted(by_month):
        group = by_month[month]
        month_pressures = [r["pressure_pa"] for r in group if r["pressure_pa"]]
        months.append({
            "mars_month": month,
            "avg_min_temp_c": round(statistics.mean(r["min_temp_c"] for r in group), 1),
            "avg_max_temp_c": round(statistics.mean(r["max_temp_c"] for r in group), 1),
            "avg_pressure_pa": round(statistics.mean(month_pressures)) if month_pressures else None,
            "sols": len(group),
        })

    latest = rows[-1]
    avg_pressure = statistics.mean(pressures)
    return {
        "credit": CREDIT,
        "source": FEED_URL,
        "sols_with_data": len(rows),
        "first_earth_date": rows[0]["earth_date"],
        "last_earth_date": latest["earth_date"],
        "coldest": {"temp_c": coldest["min_temp_c"], "sol": coldest["sol"], "earth_date": coldest["earth_date"]},
        "warmest": {"temp_c": warmest["max_temp_c"], "sol": warmest["sol"], "earth_date": warmest["earth_date"]},
        "avg_low_c": round(statistics.mean(r["min_temp_c"] for r in rows), 1),
        "avg_high_c": round(statistics.mean(r["max_temp_c"] for r in rows), 1),
        "avg_daily_swing_c": round(statistics.mean(swings), 1),
        "biggest_daily_swing_c": max(swings),
        "pressure_pa": {"min": min(pressures), "max": max(pressures), "avg": round(avg_pressure)},
        "pressure_percent_of_earth": round(100 * avg_pressure / EARTH_SEA_LEVEL_PA, 2),
        "uv_days": dict(Counter(r["uv"] for r in rows if r["uv"]).most_common()),
        "by_mars_month": months,
        "latest": latest,
    }


def main() -> None:
    feed = load_feed(sys.argv[1] if len(sys.argv) > 1 else None)
    rows = clean(feed)

    CSV_OUT.parent.mkdir(parents=True, exist_ok=True)
    with CSV_OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    JSON_OUT.parent.mkdir(parents=True, exist_ok=True)
    JSON_OUT.write_text(json.dumps({"credit": CREDIT, "columns": COLUMNS,
                                    "rows": [[r[c] for c in COLUMNS] for r in rows]},
                                   separators=(",", ":")), encoding="utf-8")
    facts = summarize(rows)
    FACTS_OUT.write_text(json.dumps(facts, indent=2), encoding="utf-8")

    print(f"{len(rows)} sols kept out of {len(feed['soles'])}")
    print(f"Wrote {CSV_OUT.relative_to(PROJECT)}, {JSON_OUT.relative_to(PROJECT)}, {FACTS_OUT.relative_to(PROJECT)}")


if __name__ == "__main__":
    main()

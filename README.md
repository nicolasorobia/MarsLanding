# Mars Landing

An educational game that teaches kids what colonists need first to survive on Mars. Players pick the colony's needs in the right priority order. The hints and weather report use real data from NASA's Curiosity rover.

**Play it:** https://nicolasorobia.github.io/MarsLanding/

## What's in this repo

| Folder | Contents |
|---|---|
| `source/` | The full Godot 4.7.1 project: scenes, scripts, shaders, art, music and NASA data |
| (root) | The exported web build that GitHub Pages serves |

## Opening the source

1. Install [Godot 4.7.1](https://godotengine.org/download).
2. In the Godot Project Manager, click **Import** and choose `source/project.godot`.
3. Press **F5** to play. The game starts at the start menu (`scenes/start_menu.tscn`).

## Where the main code lives

- `source/scripts/survival_puzzle.gd`: the puzzle (correct order, right and wrong picks, hints, weather report)
- `source/scripts/survival_item.gd`: clickable structures (gray until placed, crop growth)
- `source/scripts/colonist.gd`: colonist wandering, personalities and chat
- `source/scripts/mars_data.gd`: NASA data loading, the live feed and the Mars clock
- `source/scripts/day_night_background.gd`: day and night background following Mars time
- `source/tools/fetch_nasa_data.py`: downloads and cleans the Curiosity weather data

## Data

Weather data: NASA/JPL-Caltech/CAB (Curiosity REMS), from the Mars weather feed at `https://mars.nasa.gov/rss/api/?feed=weather&category=msl&feedtype=json`.

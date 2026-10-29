# Formula Force

**Formula Force** is a personal 3D open-wheel racing game for Android, built with **Godot 4.4**.
It has real circuit layouts at real scale, an F1-style car model, AI opponents,
start lights, lap timing and touch or tilt controls. Everything is generated from
code and data, so the project runs with no third-party art.

## What's in it

| Feature | Where |
| --- | --- |
| 20 real circuits in calendar order (Albert Park to Yas Marina, plus Sepang, Hockenheim, Nurburgring, Sochi) from measured centerlines and track widths. The satellite-derived widths run narrow (median ~9 m at Spa, Suzuka, Monza), so they're scaled ×1.15 with the FIA's 12 m+ minimum (12.5 m here) and 15 m from the grid to Turn 1 | `tracks/*.csv`, `scripts/track.gd` |
| Track generation: asphalt with a rubbered-in racing line, edge lines, kerbs on corners, gravel traps on the outside of slow corners, mown-grass verges, barriers with collision, grandstands, Kenney forest and paddock tents, grid slots, chequered start line | `scripts/track.gd` |
| Elevation: hand-built height profiles for Spa (Eau Rouge/Raidillon, ~90 m), Suzuka (with a real bridge at the crossover), Red Bull Ring, COTA's Turn 1 climb, Interlagos, Zandvoort (19° and 17° banking), Hungaroring, Catalunya and the Nürburgring; gentle undulation elsewhere. Rolling terrain follows the circuit | `scripts/track_profiles.gd`, `scripts/track.gd` |
| Hills in the physics: gravity on gradients (slower uphill, longer braking downhill), more grip in compressions and less over crests, banking that holds the car in; the AI speed plan knows all of it | `scripts/car.gd`, `scripts/track.gd` |
| Handling: **Realistic** (default) planar vehicle dynamics: slip angles into a Pacejka-style tyre curve, 46/54 weight distribution with load transfer, speed-squared downforce, 600 kW rear-wheel drive, friction circle (wheelspin, lock-ups, power oversteer), speed-sensitive steering with a slip-angle limiter, traction control / stability control (Off/Low/High) and ABS, visible pitch and roll. **Arcade** model kept as an option and for the AI | `scripts/car.gd` |
| AI drivers: speed plan from track curvature with a braking pass, lookahead steering, simple overtaking, braking for a slower car they can't pass, stuck recovery | `scripts/car.gd`, `scripts/track.gd` |
| Damage (Settings → Driving → Damage: Realistic / Visual only / Off): hits are located (front, rear, sides) and sized by impact speed. Wings bend, then break off and bounce down the track; carbon bits fly; wheels lean on bent suspension. Realistic: lost front wing = understeer, rear wing = oversteer, bent suspension and punctures pull the steering, a big enough crash (~137 km/h into a wall) retires the car (DNF, no points). Pit stops fit a new nose (+5 s) and fix punctures; AI cars pit for repairs. HUD shows a damage diagram | `scripts/car.gd`, `scripts/car_model.gd`, `scripts/debris.gd`, `scripts/ui/damage_gauge.gd` |
| Clean low-poly modern F1 car modelled in code: lofted nose and sidepods, halo, multi-element wings, DRS flap, compound-coloured tyres, two-tone team liveries | `scripts/lowpoly_car.gd`, `scripts/car_model.gd` |
| DRS and slipstream: zones auto-placed on each circuit's two longest straights with detection boards, 1-second rule from lap 2, tap DRS button (or automatic), flap animates, closes on braking; tow behind any car within 30 m | `scripts/track.gd`, `scripts/car.gd` |
| Tyres and pit stops: soft/medium/hard with wear scaled to race length and a grip cliff, two-compound rule (+10 s penalty), pit lane fitted to each main straight with limiter, pit wall and team garages; tap BOX and pick a compound, the car drives the stop; AI strategies | `scripts/car.gd`, `scripts/track.gd`, `scripts/ui/tyre_gauge.gd` |
| Modes: Quick race; Season (5/10/16-round calendars, F1 points, grid in championship order, standings and champion screen, saved progress); Time trial (flying laps on softs, ghost of your best lap, live delta, track-limit invalidation) | `scripts/main_menu.gd`, `scripts/race.gd`, `scripts/game_state.gd` |
| Race flow: 5 red lights, random hold, lights out, laps, positions, wrong-way warning, results, personal bests saved per track | `scripts/race.gd` |
| Mobile controls modelled on GRID Autosport / Real Racing: arrow buttons, drag-to-steer wheel or tilt; pedal-shaped brake/gas; auto-throttle by default (manual "Pro" option); braking assist; haptic taps | `scripts/touch_controls.gd` |
| Controls & assists screen (main menu and pause): steering style, sensitivity, tilt direction + auto/manual tilt calibration, steering assist with edge protection, braking assist levels, auto/manual throttle, button size and opacity, mirrored layout, vibration | `scripts/ui/controls_panel.gd`, `scripts/car.gd` |
| HUD: position, lap, lap/last/best times, minimap, round icon buttons, F1-style driver display with shift lights, gear, speed and pedal bars | `scripts/hud.gd`, `scripts/ui/` |
| Sound: engine loop pitched by RPM, tyre squeal, light and heavy impacts, gravel rattle, stall on reset, trackside crowd, wrong-way and lost-position cues; AI cars are positional so you hear them pass | `scripts/car_audio.gd`, `scripts/race.gd` |
| Cameras: chase, far chase, cockpit that pitches and rolls with the car (CAM button / `C`) | `scripts/chase_camera.gd` |
| Branding: Formula Force logo in the menu, splash screen, launcher icon, race loading screen, on boards all round every circuit and on the start gantry | `assets/ui/`, `scripts/track.gd` |
| Sky and light: painted cloud panorama with a shader sun that matches the scene's light, warm sun with two-split shadows to 140 m, sky-coloured ambient and distance haze, light glow | `assets/sky/`, `scripts/race.gd` |

## Running it

1. Install **Godot 4.4+** (standard build, not .NET).
2. Open the project folder in Godot, then press **F5**.
3. Desktop controls: `W/S` or arrow keys for gas and brake, `A/D` to steer, `C` camera,
   `R` reset car, `Esc` pause. A gamepad works too. Mouse clicks emulate touch, so you
   can try the touch zones on desktop.

## Building the APK (Android)

One-time setup:

1. Godot: **Editor → Manage Export Templates → Download** (matching your version).
2. Install **Android Studio**, or just the command-line tools, plus a JDK 17. In Godot,
   go to **Editor Settings → Export → Android** and set the Android SDK path and Java SDK path.
3. Godot creates a debug keystore automatically. Debug builds are fine for personal use.

Then **Project → Export → Android** (the preset is already in `export_presets.cfg`) →
**Export Project** → `build/FormulaForce.apk`. Install it with
`adb install -r build/FormulaForce.apk`, or copy the APK to the phone and open it after
allowing "install unknown apps".

Even quicker: plug the phone in with USB debugging enabled and press the
**Android icon (Remote Debug / One-click deploy)** in the editor's top-right.

## Upgrading the art

- **Car:** drop a `car.glb` (or .gltf/.fbx/.obj) into `assets/cars/` and it's auto-fitted
  and team-coloured. `assets/cars/README.md` lists free open-wheel models on itch.io.
- **More tracks:** 20 of the [TUM racetrack-database](https://github.com/TUMFTM/racetrack-database)
  circuits are included; the rest use the same CSV format. Copy one into `tracks/`, add a
  `<name>.csv.import` file with the same contents as the existing ones (it stops
  Godot from treating the CSV as a translation table), then add an entry to `TRACKS`
  in `scripts/game_state.gd`. Monaco isn't in that database.
- **Elevation:** the source data is 2D, so heights are hand-made approximations
  in `scripts/track_profiles.gd`: `[lap fraction, metres]` keyframes per circuit,
  plus optional banking ranges. Tweak a profile and the road, terrain, bridges,
  physics and AI all follow.

## Tuning knobs

- Car feel: `MAX_ACCEL`, `TOP_SPEED`, braking and steering in `car.gd`, and grip in
  `track.gd` (`GRIP_BASE`, `GRIP_AERO`). The AI speed plan uses the same grip
  numbers, so changing grip keeps the AI consistent.
- AI difficulty: `ai_skill` in `race.gd::_spawn_cars` (fraction of the ideal corner speed).
- Performance: the project uses the **Mobile** renderer. On older or cheaper phones
  with flaky Vulkan drivers, switch to **Compatibility** in Project Settings →
  Rendering → Renderer. You can also lower `directional_shadow_max_distance`
  or turn shadows off in `race.gd`.

## Licences

- Track centerlines: TUM racetrack-database, **LGPL-3.0** (`tracks/LICENSE-LGPL-3.0.txt`).
- Menu music: your own track (made with Suno), converted to OGG in `assets/music/`.
- Forest/tent models and engine/skid/impact sounds: Kenney Starter Kit Racing, **CC0** (`assets/kenney/LICENSE.md`).
- Gravel, crash, stall, crowd and cue sounds: Free Racing and Driving Sounds by moneywithjjcom, royalty-free (`assets/sfx/LICENSE.md`).
- Logo: your own artwork (`assets/ui/`).
- Car models in `assets/cars/local/` are third-party and deliberately not in the repo.
- No team names, logos or liveries are included. Drivers and colours are fictional.

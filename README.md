# hesigame
potato

## Redline Rush

A roguelike traffic-weaving racer built in **Godot 4** (GDScript). You drive an endless four-lane highway: close passes and late lane changes at speed score the most, and each stage ends in a boss race.

### Open and run

1. Install **Godot 4.3 or newer** (the standard build, not .NET) from https://godotengine.org/download.
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then press **Run** (F5).

There are no asset files to download: the cars, road, trees, UI and sounds are all generated in code.

Each car has its own engine sound, generated live from a small engine model: cylinder count (from the hatch's four to the Last Exit's twelve), RPM through six gears with real shift points, throttle load, pops when you lift off, turbo whine and blow-off on the turbo cars, and tyre squeal when you push past the grip limit. The HUD shows your gear and an RPM bar under the speedometer.

### Controls

| Action | Phone | Desktop |
| --- | --- | --- |
| Accelerate | Hold the accelerator pedal (bottom right) | Up / W |
| Brake | Hold the brake pedal (bottom left) | Down / S / Space |
| Steer | Swipe left or right anywhere else on the screen | Left / Right (one lane per press) |
| Pause | Pause button, or Android Back | Esc / P |

With **Lane assist** on (menu toggle), lifting your finger settles the car into the nearest lane.

### How a run works

- **Lives:** 3. Touching a car, the rival or the guardrail costs one. The Spare chassis upgrade adds more.
- **Scoring:** a pass is worth more the faster you go. Passing within 1 m is a **near miss** and within 35 cm is a **razor pass**. A lane change right beside a car is a **close cut**. Each of those adds to a combo multiplier (up to x8) that resets after 3.5 s without one. Above 120 km/h you also earn points every second.
- **Stages:** reach the stage's distance and points target to meet the boss.
- **Boss race:** you have 2 km to out-score the boss before the finish gantry. Win and you get prize money, choose 1 of 3 upgrades for the rest of the run, and the boss's car goes on sale in the Garage. Lose and it costs a life, followed by a rematch.
- **Between runs:** cash from score, distance and boss prizes buys permanent upgrades and new cars. Progress is saved to `user://save.json`.

### Build for Android

1. In Godot: **Editor > Manage Export Templates > Download and Install**.
2. Install the Android SDK (Android Studio is the easiest way) and a JDK 17. Then in **Editor > Editor Settings > Export > Android**, set the SDK path. Godot's guide covers this step by step: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
3. **Project > Export > Add... > Android**. Set a package name (for example `com.redlinerush.game`). Portrait orientation is already set in the project.
4. With a phone connected over USB debugging, press the Android one-click deploy button in the editor's top-right corner, or click **Export Project** to get an `.apk`.

### Project layout

| Path | What it does |
| --- | --- |
| `scenes/main.tscn` | Entry scene; it only holds `game.gd` |
| `scripts/game.gd` | Driving physics, traffic AI, boss race, scoring, run flow, camera, input |
| `scripts/hud.gd` | HUD, pedals and every menu screen, built in code |
| `scripts/scenery.gd` | Endless road, guardrails, lamps, trees, km signs, finish gantry |
| `scripts/car_model.gd` | Builds the low-poly car, truck and van models |
| `scripts/pedal.gd` | Draws the accelerator and brake pedals |
| `scripts/engine_audio.gd` | Synthesised engine, wind and sound effects |
| `scripts/data.gd` | Autoload `Data`: cars, bosses, upgrades, targets. Balance lives here |
| `scripts/save.gd` | Autoload `Save`: persistent progress |
| `shaders/` | Road markings and grass stripes |

### Test flags

Arguments placed after `--` on the command line:

- `--autotest`: the car drives itself and the run loops, with status printed to the console. Combine it with `--headless` to run without a window.
- `--fast`: shrinks stage and boss targets so you reach a boss within seconds.
- `--quit-after=SECONDS`: exit after that many seconds.
- `--open=garage` / `--open=garage:up`: open the Garage on start.
- `--shot=SECONDS:PATH`: save a screenshot.

```bash
godot --headless --path . -- --autotest --fast --quit-after=90
```

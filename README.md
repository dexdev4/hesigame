# hesigame
potato

## Redline Rush

A roguelike traffic-weaving racer built in **Godot 4** (GDScript). You drive an endless four-lane highway: close passes and late lane changes at speed score the most, and each stage ends in a boss race.

### Open and run

1. Install **Godot 4.3 or newer** (the standard build, not .NET) from https://godotengine.org/download.
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then press **Run** (F5).

There are no asset files to download: the cars, road, trees, UI and sounds are all generated in code.

Each car has its own engine sound, generated live from a small engine model: cylinder count (from the hatch's four to the Last Exit's twelve), RPM through six gears with real shift points, throttle load, pops when you lift off and turbo whine and blow-off on the turbo cars. The HUD shows your gear and an RPM bar under the speedometer.

### Controls

| Action | Phone | Desktop |
| --- | --- | --- |
| Accelerate | Hold the accelerator pedal (bottom right) | Up / W |
| Brake | Hold the brake pedal (bottom left) | Down / S / Space |
| Steer | Swipe left or right anywhere else on the screen | Left / Right (one lane per press) |
| Pause | Pause button, or Android Back | Esc / P |

With **Lane assist** on (menu toggle), lifting your finger settles the car into the nearest lane.

### Cameras

Tap **CAM** (top right) to switch between **Chase**, **Hood** and **Cockpit** views. The cockpit is a full interior:
- **Instruments:** speedometer and rev counter with moving needles, a digital gear and speed readout, and a lit radio and trip screen.
- **Controls:** a three-spoke steering wheel that turns, and a gear lever that moves through the gears.
- **Cabin:** air vents, climate knobs, seats with headrests, a rear bench, door panels, sun visors and a mirror.

### Settings

Open **Settings** from the main menu or the pause menu. The game keeps drawing behind it, so camera changes preview live.
- **Camera:** choose a view and set its field of view, height, distance (forward/back for hood and cockpit) and angle. **Reset this view** restores the defaults.
- **Gameplay:** steering sensitivity, pedal size, lane assist, vibration, camera shake, engine sound, and speed in km/h or mph.
- **Pedal layout:** **Edit pedal layout** lets you drag the gas and brake anywhere on screen. **Swap pedals** puts the gas on the left, and **Reset pedals** returns them to the bottom corners.

### How a run works

- **Lives:** 3. Touching a car, the rival or the guardrail costs one. The Spare chassis upgrade adds more.
- **Scoring:** a pass is worth more the faster you go. Passing within 1 m is a **near miss** and within 35 cm is a **razor pass**. A lane change right beside a car is a **close cut**. Each of those adds to a combo multiplier (up to x8) that resets after 3.5 s without one. Above 120 km/h you also earn points every second.
- **Stages:** reach the stage's distance and points target to meet the boss.
- **Boss race:** you have 2 km to out-score the boss before the finish gantry. Win and you get prize money, choose 1 of 3 upgrades for the rest of the run, and the boss's car goes on sale in the Garage. Lose and it costs a life, followed by a rematch.
- **Between runs:** cash from score, distance and boss prizes buys permanent upgrades and new cars. Progress is saved to `user://save.json`.

### Build for Android

The project includes an export preset (`export_presets.cfg`) for a standard APK. It doesn't need Gradle or Android Studio's build system.

1. **Export templates:** in Godot, choose **Editor > Manage Export Templates > Download and Install**.
2. **Java and the Android SDK:** install a JDK (17 or newer) and the Android SDK. Android Studio is the easiest way to get the SDK; you need **build-tools** and **platform-tools** from its SDK Manager.
3. **Editor Settings > Export > Android:** set **Java SDK Path** and **Android SDK Path**. Godot creates the debug keystore itself the first time; if that field is empty, see the table below.
4. **Project > Export:** select **Android** and click **Export Project** to get `build/redline-rush.apk`. Or plug in a phone with USB debugging on and press the Android button in the editor's top-right corner.

Portrait orientation, immersive full screen and the vibration permission are already set.

**If the export fails**, the message at the bottom of the Export window usually names the cause:

| Message mentions | Fix |
| --- | --- |
| export templates / "No export template found" | Step 1, and make sure the templates match your Godot version exactly. |
| Android build template / Gradle | Turn **Use Gradle Build** off in the Android preset (it is off in the included preset). |
| Android SDK path / apksigner / build-tools | Step 3. The path must contain `build-tools/<version>/apksigner` and `platform-tools/adb`. |
| Java / JDK | Point **Java SDK Path** at the JDK folder (the one containing `bin/java`). |
| keystore | Leave the debug keystore fields empty so Godot creates one, or create one yourself: `keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -validity 10000 -dname "CN=Android Debug"` |
| ETC2 / ASTC texture compression | Already enabled in `project.godot`. If it was turned off, re-enable **Rendering > Textures > VRAM Compression > Import ETC2 ASTC**. |

Command-line export, once the editor settings are in place:

```bash
godot --headless --path . --export-debug "Android" build/redline-rush.apk
```

### Project layout

| Path | What it does |
| --- | --- |
| `scenes/main.tscn` | Entry scene; it only holds `game.gd` |
| `scripts/game.gd` | Driving physics, traffic AI, boss race, scoring, run flow, camera, input |
| `scripts/hud.gd` | HUD, pedals and every menu screen, built in code |
| `scripts/scenery.gd` | Endless highway: both carriageways with oncoming traffic, overpasses, exit-sign gantries, billboards, farms, fences, power lines, trees, mountains and clouds |
| `scripts/car_model.gd` | Builds the car, truck and van models and the player's cockpit interior |
| `scripts/pedal.gd` | Draws the accelerator and brake pedals |
| `scripts/engine_audio.gd` | Synthesised engine, wind and sound effects |
| `scripts/data.gd` | Autoload `Data`: cars, bosses, upgrades, targets. Balance lives here |
| `scripts/save.gd` | Autoload `Save`: persistent progress |
| `shaders/` | Road surface (markings, wear, rumble strips, reflectors), grass and fields, distant mountains and clouds |

### Test flags

Arguments placed after `--` on the command line:

- `--autotest`: the car drives itself and the run loops, with status printed to the console. Combine it with `--headless` to run without a window.
- `--fast`: shrinks stage and boss targets so you reach a boss within seconds.
- `--quit-after=SECONDS`: exit after that many seconds.
- `--open=garage` / `--open=garage:up`: open the Garage on start.
- `--shot=SECONDS:PATH`: save a screenshot.
- `--cam=chase|hood|cockpit`: start in that camera view (not saved). `--cam=inspect` looks across the cabin from the back seat.
- `--open=settings` / `--open=pedal_edit`: open the settings screen or the pedal editor on start.
- `--demo-pops`: show a sample score message every second, to check where messages appear in each camera view.
- `--burst=SECONDS:COUNT:DIR`: save COUNT consecutive frames from SECONDS onwards (for checking flicker).
- `--showroom` / `--showroom=front` / `--showroom=close`: park every player and boss car in a row with the game frozen, to inspect the models.

```bash
godot --headless --path . -- --autotest --fast --quit-after=90
```

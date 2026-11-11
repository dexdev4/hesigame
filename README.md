# hesigame
potato

## Redline Rush

A roguelike traffic-weaving racer built in **Godot 4** (GDScript). You drive an endless four-lane highway: close passes and late lane changes at speed score the most, and each stage ends in a boss race.

### Open and run

1. Install **Godot 4.3 or newer** (the standard build, not .NET) from https://godotengine.org/download.
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then press **Run** (F5).

There are no asset files to download: the cars, road, trees, UI and sounds are all generated in code.

Every player and boss car has its own body design: a hatchback, a sport sedan, a notchback and a fastback muscle car, a compact performance saloon, a mid-engined supercar, a rear-engined sports coupe and a V12 hypercar. The paint has a clear coat that reflects the sky and horizon, metallic flake that catches the sun up close, and tinted glass that turns into a mirror at shallow angles. Wheels have big alloys with concave spokes, low-profile tyres, brake discs and calipers. Lamps have projector lenses and LED running lights. Cars further than 40 m away switch to a lighter model, so the highway stays smooth on phones.

Each car has its own engine sound, generated live from a small engine model: cylinder count (from the hatch's four to the Last Exit's twelve), RPM through six gears with real shift points, throttle load, pops when you lift off and turbo whine and blow-off on the turbo cars. On and off throttle use different combustion sounds, every firing varies slightly, the exhaust pipe resonates, and you hear crank rumble at low revs, gearbox whine and an ignition-cut bark on upshifts. The HUD shows your gear and an RPM bar under the speedometer.

### Controls

| Action | Phone | Desktop |
| --- | --- | --- |
| Accelerate | Hold the accelerator pedal (bottom right) | Up / W |
| Brake | Hold the brake pedal (bottom left) | Down / S / Space |
| Steer | Swipe left or right anywhere else on the screen (how far your finger moves from where it landed is how far you steer) | Hold Left / Right |
| Pause | Pause button, or Android Back | Esc / P |

The car drives freely, like a real one: let go of the steering and the wheels self-centre, but the car keeps going the way it points, so you straighten up yourself. Nothing pulls it back into a lane. **Steering assist** (Settings › Controls, off by default) gently straightens the car up to the road when you let go, without snapping it to a lane.

### Cameras

Tap **CAM** (top right) to switch between **Chase**, **Hood** and **Cockpit** views. The cockpit is a full interior:
- **Instruments:** speedometer and rev counter with moving needles, a digital gear and speed readout, and a lit radio and trip screen.
- **Controls:** a three-spoke steering wheel that turns, and a gear lever that moves through the gears.
- **Cabin:** air vents, climate knobs, seats with headrests, a rear bench, door panels, sun visors and a mirror.

### Settings

Open **Settings** from the main menu or the pause menu. It has four tabs, each split into labelled groups with a short explanation under every option: **Controls** (steering method, sensitivity, steering assist, tilt direction, pedal size, vibration, on-screen layout), **Camera** (view, adjustments, camera shake), **Display & Audio** (orientation, graphics, speed units, mirror, sound) and **Developer**. The game keeps drawing behind it, so camera changes preview live.

The main menu is your **garage**: a large lit workshop (polished tiled floor, steel roof beams and skylights, hanging light bars, an LED-ringed turntable, tool chests, workbench, parts shelves, tyre racks, a lift, a diagnostics cart, posters and a roller door under the sign) with your car on a turntable, which you can drag to look around (left alone, the camera slowly circles it, and it always stops short of the walls and ceiling). A panel shows the car's name, fuel and stats (with your upgrades) and leads with **Start run**, with **Cars**, **Workshop** and **Settings** under it and **How to play** on its own screen. **Cars** lists every car (tap **View** to look at one on the turntable before you buy it). The **Workshop** works on your current car: **Upgrades** (fitted to that car only: each car is upgraded separately, and older saves keep the upgrades they had on every car they own), **Paint** (13 colours plus factory, free) and **Wheels** (six designs and six finishes, or factory). Paint and wheels are saved per car and used in your runs. The garage has its own camera, lights and render layer, so the highway never shows through, and the road simulation pauses while you're in it. The pause menu leads with **Resume** and keeps **End run** apart at the bottom, and the run-over screen leads with **Run again**.
- **Camera:** choose a view and set its field of view, height, distance (forward/back for hood and cockpit) and angle. **Reset this view** restores the defaults.
- **Car models:** every player, boss and traffic car (apart from the imported Comet and Hornet, and the van and lorry) is forged as a detailed mesh by `tools/carforge.py`: smooth curved bodywork with rounded bumpers, real glass with black window surrounds and frit, LED head and tail lamps with projectors and light bars, mesh, slatted or kidney grilles, lower intakes, bonnet louvres, side intakes, diffusers, shut lines, flush handles, mirrors, wipers, shark-fin aerial, exhaust tips, and each car's spoiler or wing. Boot lips and ducktails are swept into the bodywork itself, every detail follows the rounded nose and tail, lamps wrap only the corners, and grilles and intakes are sized to the nose they sit on. Nearby cars use the full-detail version and switch to a light one beyond 22 m; your own car is always full detail.
- **Interiors:** every car has its own cabin, set in `CABINS` in `scripts/car_model.gd`. Colours, seats (comfort seats or one-piece buckets with harness slots), steering wheel (round, flat-bottomed or a yoke, with two to four spokes and an optional twelve-o'clock mark), screen (a wide screen, a tall floating tablet, or a small radio with knobs), gauge colours, dash trim (aluminium, wood, carbon or body-bright) and extras all differ: blue cloth and a tablet in the Pulse, red-stitched black in the Vector, yellow buckets in the Hornet, tan leather with a two-spoke wheel in the Comet, plain grey cloth and a radio in the Kestrel, beige and wood in the Vanta, black vinyl with a thin chrome-spoked wheel and three dash-top gauges in the Bruiser, white buckets with cyan lighting in the Halcyon, saddle leather and gauge pods in the Copperhead, blue-stitched black in the Night Marshal, electric-blue buckets in the Blue Static, and red leather, a yoke and a roll cage in the Last Exit. Every cockpit is measured against its body's real roof, sides and tail and kept inside them.
- **Starter cars:** every new garage starts with the **Pulse Hatch**, a hot hatch with a roof spoiler, and the first car to buy is the **Vector GS** ($600), a turbocharged sports saloon with a boot spoiler. Both are imported 3D models with see-through glass, the full cabin and cockpit view, their own number plates, brake lights and indicators. Their texture's shut lines, handles and fuel flap are carved into the bodywork as real trim, the black band low on the sides is body colour above a gloss-black sill, and the cockpit is measured against the real shell (roof, glass and sides) so nothing pokes through. After them come the **Hornet Compact** ($800) and the **Comet Coupe** ($1,000), also imported models, then the Kestrel ($1,200). Older saves get the Pulse added and keep the cars they had.
- **Driving physics:** cars steer like real ones, and respond quickly: the front wheels turn in fast and the car starts to move over in about a quarter of a second. The nose answers the wheel with only a slight lag, and the direction of travel follows the nose only as fast as the tyres can push it round, so harsh inputs at speed give a small slide instead of an instant sideways jump; a steer-and-counter-steer lane change feels the same at any speed. The body rolls and pitches about the middle of the car at hub height (like real suspension), so the wheels stay inside their arches. The car turns only by rolling forward on its turned front wheels (you can see them turn), so it can't rotate or slide sideways when it's stopped, and at a crawl it needs plenty of lock to move over. The front wheels turn at a limited rate, the available lock shrinks with speed, and the tyres grip only up to a limit, so asking for too much at speed makes the car run wide. You steer it yourself the whole time: there is no lane snapping. Braking hard and driving on the shoulder cost grip. The body leans out of turns, and traffic, bosses and police also move over only as fast as they're rolling forward.
- **Steering:** **Stick**: a floating analog stick that appears wherever you put your finger (away from the pedals) and steers as far as you push it left or right; **Swipe** anywhere on the screen, an on-screen **Wheel** you turn with your thumb (it springs back to centre when you let go), **Buttons** for left and right, or **Tilt** (tilt the phone; the angle you hold it at when a run starts or resumes counts as straight, and **Tilt direction** flips it if it feels backwards). Every method turns the front wheels: full input asks for about the most grip the tyres have at your speed, so it feels the same at 60 and 200 km/h, and small inputs are softened for fine corrections.
- **Screen:** **Portrait** or **Landscape**. The game locks to the one you choose, so turning the phone never switches it by accident.
- **Graphics:** **High** (full shadows, anti-aliasing, speed blur at the screen edges and a colour grade), **Medium** or **Low** for older phones. On the first run on a phone the game checks the frame rate and steps down a level if it's struggling.
- **Developer tools:** **Infinite lives**, an **FPS counter**, **Unlock all cars**, **Max all upgrades**, **+$100,000 cash** and **Reset progress** (tap twice; keeps your settings).
- **Rear-view mirror:** on by default, at the top of the screen. Turn it off, or set **Mirror size**, in Settings. Move it in the layout editor.
- **Pedal layout:** **Edit pedal layout** lets you drag the gas, brake, steering wheel or buttons and the mirror anywhere on screen (**MIRROR −** / **MIRROR +** resize it there). **Swap pedals** puts the gas on the left, and **Reset pedals** returns them to the bottom corners.

### How a run works

- **Lives:** 3. Touching a car, the rival or the guardrail costs one. The Spare chassis upgrade adds more.
- **Scoring:** score messages appear in a short list just under the score counter, clear of the road. A pass is worth more the faster you go. Passing within 1 m is a **near miss** and within 35 cm is a **razor pass**. A lane change right beside a car is a **close cut**. Each of those adds to a combo multiplier (up to x8) that resets after 3.5 s without one. Above 120 km/h you also earn points every second.
- **Stages:** fill either the stage's distance bar or its points bar to trigger the next encounter.
- **World map:** **Start run** opens a road-atlas map (shaded terrain with coastline and shallows, beaches, rivers, woodland, hills and snowy peaks, each region coloured by its highway's country; winding highways with interstate shields; a little lit skyline for every city, padlocked until you can reach it; compass and scale bar) of 15 cities (Port Halden, Ashford, Millbrook, Cedar Falls, Red Mesa, Dustwater, Silver Lake, Ironvale, Northgate, Granite Pass, Copper Ridge, Sunset Bay, Lakeshore, Neon Heights and Summit City) joined end to end by 14 highways (I-10 to I-80). Each highway is its own endless run through its own country (green farmland, autumn woods, desert flats, northern pines, coast road or frosted plains, with matching ground and sky colours), and each one further along raises score targets and boss skill (+14% targets per highway). You start with only the first highway open: beat its final boss, Last Exit (boss 4), and the highway on to the next city opens. Tap a highway to see its country, your best score on it and how much harder it is, then **Drive**. Locked highways are grey dashes, and the stage sign shows which highway you're on.
- **Day and night:** time runs while you drive, one real minute to two game hours (a full day in 12 minutes), shown by the speedometer. Runs start in the afternoon; the sun crosses from east to west, sunset turns the sky gold and the hills purple, and night brings a moonlit sky full of stars. As it gets dark every car's headlights and tail lights come on (cone-shaped pools on the road, and real beams on yours), the median street lamps switch on and light the carriageways, and road studs and reflector posts shine. Dawn brings it all back. The boss theme, *Cold Iron Street*, fades in from 50 seconds into the track and plays through each boss or police encounter, fading out over about 6 seconds when it ends.
- **Boss warning:** filling the distance or points bar no longer stops the game. A 10-second countdown runs on the stage sign while you keep driving and scoring ("BOSS OR POLICE?" when it could be either), with beeps for the last three seconds, and then the boss (or the police) closes in from behind. Fuel stops are moved out of the way of the countdown and the race.
- **Police pursuit:** each trigger has a 30% chance to be a police car instead of the boss. It chases you down and tries to ram you: getting hit costs a life, but surviving 40 seconds untouched earns an extra life. Either way, the next trigger in that stage is always the real boss. The police hunt for gaps in traffic to get at you, and highway traffic moves over (or eases off if boxed in) when the siren comes up behind it.
- **Boss race:** you have 2 km to out-score the boss before the finish gantry. Bosses score exactly as you do (near misses, razor passes, close cuts, combos and speed) and drive hard to get them: they dart for gaps in traffic, brake late, pick lanes with slow cars to skim past and hug the car they're passing. Each boss is better at it than the last: Copperhead is a rookie, Last Exit a legend, and every lap of the four bosses gets harder again. All bosses score about 25% more than their driving alone earns, and start out more skilled than before. Win and you get prize money, choose 1 of 3 upgrades for the rest of the run, and the boss's car goes on sale in the Garage. Lose and it costs a life, followed by a rematch.
- **Traffic:** sedans, hatchbacks, SUVs and pickups come in many colours, wheel styles and makes, each with its own number plate. Delivery vans are modern high-roof panel vans with flush cargo sides, a sliding door, twin rear doors with windows, a tall slatted grille and big commercial mirrors, and the lorries are cab-over tractors with box trailers carrying a fleet livery and name, mud flaps, side guards and reflective tape.
- **Knocks:** bumping another car is a real momentum trade. Run into the back of one and it's shoved forward while you lose about the speed difference; an off-centre hit spins it. A side swipe pushes both cars apart and kicks both noses round, so you have to catch your car. Struck cars slide, spin out and brake to a stop (trucks are 3.5 times as heavy and barely move). A glancing scrape along a barrier costs little speed, hitting it at an angle a lot. Hard knocks throw off bits of bodywork, trim and glass.
- **Last-life crash:** losing your final life makes the car lose traction; bits of bodywork, trim and glass fly off, the tyres scrub sideways at about 0.8 g (much less rolling forwards), and the wreck smokes once it stops. It spins out in slow motion, leaving tyre marks and smoke. The sliding car collides with traffic instead of passing through it: impacts push both cars apart, spin it, and the cars it hits brake to a stop, while traffic behind stops or goes round the wreck. It doesn't always roll. A slide on its own only sometimes trips it, but sliding sideways into another car or the barrier often flips it over.
- **Replay editor:** the last 20 seconds are always recorded. Open it with **Watch replay** after a run or **Replay** in the pause menu. Play, pause, step frame by frame, scrub the timeline, play at 0.25x to 2x, and switch between Chase, Hood, Cockpit, Free cam, Keyframes, Trackside and Drone cameras. **Set in** and **Set out** trim the clip, which then loops.
  - **Hide UI** (top right) gives a clean view with no controls, name tags or score messages. You can still move the camera; tap the screen or the faint **Show UI** button to bring the controls back.
  - **Free cam:** drag to swing the camera round the car, pinch to move in and out, and drag with two fingers to pan. The camera follows the car.
  - **Keyframes:** set up a view, then press **+ KEY** to keyframe it at the playhead. Move the playhead, set up another view and add another key. The **Keyframes** camera glides smoothly between them, and keys show as diamonds on the timeline. **− KEY** deletes the key under the playhead, **< KEY** / **KEY >** jump between keys, and **Clear** removes them all.
- **Fuel:** every run starts with a full tank, shown by the gauge under the speedometer (in the cockpit, on the dashboard screen). Driving flat out burns it fastest. Run dry and the car coasts to a stop and the run ends. About every 10 km there's a fuel stop on the right: blue signs 600 m and 300 m before it, and a price pylon, show its prices. Move right into the exit lane and the car pulls in and parks right beside a pump by itself (the first pump it can still stop at; come in too fast and it can't pull in). **Hold to pump** for as much as you want, or **Fill up**, then **Pay & go**. You pay from this run's earnings first, then your bank.
  - Each station sets its own prices. The cheaper cars (Pulse, Vector, Hornet, Comet, Kestrel, Vanta) take regular, the middle ones (Copperhead, Bruiser, Night Marshal) mid-grade, and the fastest (Halcyon, Blue Static, Last Exit) premium. Mid-grade averages $5 a litre more than regular, and premium $15 more. The Garage shows each car's fuel and tank size.
  - Bosses and police pursuits never start near a fuel stop. Beating a boss can offer **Pit crew** (a free full tank) as one of the three upgrades when your tank isn't full.
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
| `scripts/scenery.gd` | Endless highway: both carriageways with oncoming traffic, overpasses, exit-sign gantries, billboards, farms, fences, power lines, trees, rolling hills, mountains and clouds; street lamps and studs that light up at night |
| `scripts/car_model.gd` | Car, truck and van models: body profiles for every car type, loading the forged and imported car meshes, wheels and brakes, materials, level of detail, and the player's cockpit interior |
| `tools/carforge.py` | The car forge: builds every player, boss and traffic car body (hatch, saloon, SUV, M-saloon, muscle, fastback, supercar, rear-engine coupe, hypercar) as a detailed mesh in `assets/models/cars/` (a full-detail version of about 50–65k triangles and a light one of about 3.5–4k). Smooth splined bodies with rounded noses and tails, glass with black surrounds, sculpted LED head and tail lamps, mesh or slatted grilles, intakes, louvres, diffusers, shut lines, flush handles, mirrors, wipers, exhausts, spoilers and wings. Run `python3 tools/carforge.py` after changing a design |
| `scripts/body_builder.gd` | Smooth one-piece car bodies: swept cross-sections with a shoulder crease, flared arches and rounded corners; wrap-round bumpers, lamps with projectors and LED running lights, grilles and intakes, mirrors, shut lines and baked shading |
| `scripts/car_textures.gd` | Lamp lens and grille textures drawn in code |
| `scripts/pedal.gd` | Draws the accelerator and brake pedals |
| `scripts/engine_audio.gd` | Synthesised engine, wind and sound effects |
| `scripts/replay.gd`, `scripts/replay_bar.gd` | 20-second replay recording and the editor's timeline |
| `scripts/skid_marks.gd` | Tyre marks laid on the road during a crash |
| `scripts/rear_mirror.gd` | On-screen rear-view mirror |
| `tools/convert_coupe.py` | Converts an imported car model (`tools/models/*.glb`: the Pulse hatchback, Vector sport sedan, Comet and Hornet) into a game mesh (`assets/models/*.mesh`), mapping extra parts by material (spoilers and mirrors as paint, trim, aero parts, chrome; the model's own calipers are left to the game's wheels), keeping painted number plates as plates and noticing red paint so a red car is not mistaken for a tail lamp. Options after the glass height: `lines` carves the texture's thin shut lines and handles into the mesh (texel-exact refinement), `gloss` makes the black trim gloss black, and `bodyside` paints a broad black lower bodyside band in body colour above the sill (the Pulse and Vector use `0.92 lines gloss bodyside`): turns it into the game's axes, splits the body into paint, glass, trim and lamps by its texture (refining the mesh along window and lamp edges), and shares vertices. Run `python3 tools/convert_coupe.py tools/models/compact_coupe.glb assets/models/compact_coupe.mesh` (likewise for `starter_coupe`) after changing a model |
| `scripts/gas_station.gd` | Fuel stops: exit lane, forecourt, canopy, pumps, kiosk, price pylon and approach signs |
| `scripts/data.gd` | Autoload `Data`: cars, bosses, upgrades, targets. Balance lives here |
| `scripts/save.gd` | Autoload `Save`: persistent progress |
| `shaders/car_paint.gdshader`, `car_glass.gdshader`, `car_env.gdshaderinc` | Car paint, chrome, trim and glass with sharp reflections of the sky and horizon, clear coat and metallic flake |
| `shaders/` | Road surface (markings, wear, rumble strips, reflectors, asphalt grain), grass and fields, distant mountains and clouds, and the full-screen finishing pass |

### Test flags

Arguments placed after `--` on the command line:

- `--autotest`: the car drives itself and the run loops, with status printed to the console. Combine it with `--headless` to run without a window.
- `--fast`: shrinks stage and boss targets so you reach a boss within seconds.
- `--cop`: the next encounter is always a police pursuit.
- `--crash-at=SECONDS`: trigger the last-life crash at that time.
- `--replay-at=SECONDS[:CAM]`: open the replay editor at that time, optionally with a camera (`chase`, `hood`, `cockpit`, `free`, `keys`, `tv`, `drone`).
- `--stations=KM` / `--first-station=M` / `--fuel=FRACTION`: a fuel stop every KM km (the tank range shrinks to match), the first stop M metres in, and starting with that fraction of a tank.
- `--start-stage=N` / `--godmode`: start runs at stage N, and never lose lives (not saved). With `--autotest` this prints each boss race's scores.
- `--quit-after=SECONDS`: exit after that many seconds.
- `--open=garage` / `--open=garage:up`: open the Garage on start.
- `--shot=SECONDS:PATH`: save a screenshot.
- `--cam=chase|hood|cockpit`: start in that camera view (not saved). `--cam=inspect` looks across the cabin from the back seat.
- `--route=N`: drive highway N (0 to 13), opening it if needed.
- `--hour=H`: hold the clock at that hour (0 to 24) to check the light at any time of day.
- `--open=settings` (or `--open=settings:controls|camera|display|dev` for a tab) / `--open=pedal_edit`: open the settings screen or the pedal editor on start.
- `--car=ID` / `--autospeed=M/S`: test-drive another car (not saved) and set how fast the test driver goes.
- `--steer=swipe|wheel|buttons|tilt|stick` (with `--fake-tilt=DEGREES` to simulate tilting) / `--orient=portrait|landscape`: try a steering method or orientation without saving it.
- `--idcolor`: draw each traffic car in a flat unique colour with no fog or scenery; with `--burst` it also logs where each car should be, to measure flicker.
- `--demo-pops`: show a sample score message every second, to check where messages appear in each camera view.
- `--burst=SECONDS:COUNT:DIR`: save COUNT consecutive frames from SECONDS onwards (for checking flicker).
- `--showroom` / `--showroom=front` / `--showroom=close` (or `t_rear` / `t_front` for traffic models; `--inspect=t_SHAPE:…` frames a single traffic model): park every player and boss car in a row with the game frozen, to inspect the models.
- `--inspect=CAR:YAWS:PITCH:DIST[:FOV]`: one car on its own, with the camera orbiting it at the given angles in degrees (several yaws separated by commas step every 3 seconds). Combine with `--win=WxH` (and Godot's `--resolution WxH`) for large screenshots.

```bash
godot --headless --path . -- --autotest --fast --quit-after=90
```

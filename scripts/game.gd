extends Node3D
## Redline Rush main script: driving physics, traffic, the boss race,
## scoring, run flow, camera and touch input.
##
## Logic uses "road coordinates": x = metres from the centre line, z = metres
## travelled. Nodes are placed relative to the player every frame (the player
## is always at the scene origin), so the highway never runs out and floats
## never lose precision.

enum S { MENU, GARAGE, PLAY, PAUSED, BOSS_INTRO, PICK, OVER, REPLAY, REFUEL }


class Vehicle:
	var x := 0.0
	var z := 0.0
	var v := 0.0
	var vx := 0.0
	var w := 1.8
	var l := 4.4
	var lane := 0
	var tlane := 0
	var cruise := 25.0
	var sig_t := 0.0
	var lc_t := 5.0
	var ahead := false
	var passed := false
	var min_clear := 99.0
	var cut := false
	var hit := false
	var braking := false
	var truck := false
	var is_boss := false
	var title := ""
	var is_cop := false
	var id := 0
	var yielding := false  # pulling over for the police
	var spin := 0.0        # a knocked car: extra yaw as it spins out (radians)
	var spin_rate := 0.0
	var slide := 0.0       # sideways slide after a knock (m/s)
	var yaw := 0.0         # heading (radians, + = nose right): the player's comes from its steering
	var yaw_rate := 0.0
	var steer := 0.0       # front road-wheel angle (radians)
	var course := 0.0      # direction of travel (radians); lags the heading in a slide
	var b_ahead := false   # boss scoring: this car is ahead of the boss
	var b_min := 99.0      # closest the boss got while passing it
	var b_cut := false
	var model: CarModel


## The last-life crash: the car has lost traction and slides, spins and can
## trip over and roll. Road coordinates, like everything else.
class Crash:
	var t := 0.0
	var vel := Vector2.ZERO  # x: across the road, y: along it (m/s)
	var yaw := 0.0           # heading, radians, + = nose to the right
	var yaw_rate := 0.0
	var roll := 0.0          # radians, + = right side up
	var roll_rate := 0.0
	var air := 0.0           # height off the road
	var vy := 0.0
	var can_trip := false
	var settled := false
	var face := 0            # which face it last landed on (multiples of 90 degrees)


class Run:
	var stage := 1
	var score := 0
	var dist := 0.0
	var stage_dist := 0.0
	var stage_score := 0
	var lives := 3
	var mods := {"accel": 1.0, "brake": 1.0, "handling": 1.0, "top": 1.0, "score": 1.0, "traffic": 1.0, "eco": 1.0}
	var shield := 0          # hits the crumple zone will absorb
	var armour := 0.0        # extra seconds of protection after a hit
	var clear_t := 0.0       # traffic stays away while this runs down
	var combo_time := 3.5
	var combo := 0
	var combo_t := 0.0
	var phase := "cruise"  # or "boss"
	var cash_bonus := 0
	var invuln := 1.5
	var bosses := 0
	var speed_acc := 0.0
	var dying := 0.0
	var rematch_t := 0.0
	var inc_t := 0.0        # countdown until the boss or police arrives
	var inc_cop := false     # what is coming (kept secret until it arrives)
	# boss race
	var b_len := Data.BOSS_RACE_LENGTH
	var b_dist := 0.0
	var b_score := 0
	var b_rival := 0
	var b_total := 0
	var b_next := 1.0
	var b_info := {}
	var b_skill := 0.0
	var b_combo := 0
	var b_combo_t := 0.0
	var b_speed_acc := 0.0
	# police pursuit
	var cop_t := 0.0
	var cop_due := false     # a pursuit happened this stage, so the next trigger is the boss
	var siren_t := 0.0
	# fuel
	var fuel := 0.0          # litres in the tank
	var fuel_warned := 0     # low-fuel warnings given so far (at 25 % and 10 %)
	var fuel_paid := 0       # dollars spent on fuel this run
	var fuel_from_run := 0   # ...of which came out of this run's earnings
	var dry_t := 0.0         # seconds stood still with an empty tank
	var pit := {}            # pulling in to the pumps, refuelling, pulling out
	var pit_skip := -1.0     # a fuel stop passed too fast to pull in
	var heads_up := -1.0     # the fuel stop already announced


var state := S.MENU
var hud: Hud
var scenery: Scenery
var cam: Camera3D
var sound: EngineAudio
var sparks: CPUParticles3D
var dust: CPUParticles3D
var traffic: Array[Vehicle] = []
var boss: Vehicle = null
var player := Vehicle.new()
var target_x := 0.0
var on_shoulder := false
var player_accel := 0.0   # smoothed longitudinal accel, for body pitch
var finish_z := -1.0
var t := 0.0
var st := {}
var run: Run = null
var cam_x := 0.0
var shake := 0.0
var _flash: ColorRect

# input
var touches := {}       # touch index -> {"role": String, "x": float}
var key_gas := false
var key_brake := false
var key_left := false
var key_right := false
var in_gas := false
var in_brake := false
var ap_t := 0.0
var ap_gas := true
var ap_brake := false

# test flags (see README): --autotest drives itself, --fast shrinks targets
var autotest := false
var auto_quit := 0.0
var showroom := ""  # --showroom=rear|front: every player car parked in a row, simulation frozen (test view)
var _inspect: PackedStringArray = []
var _test_win := Vector2i.ZERO
var shots: Array = []
var burst: Array = []  # --burst=START:COUNT:DIR saves COUNT consecutive frames (test aid)
var _burst_i := 0
var force_cop := false
var auto_speed := 46.0  # --autospeed=M/S: how fast the test driver goes
var idcolor := false   # --idcolor: flat unique colour per traffic car, no fog or scenery (flicker test)
var _id_next := 1
var _id_log: FileAccess
var demo_pops := false  # --demo-pops: show a sample score message every second (test aid)
var _demo_t := 0.0  # [[seconds, path], ...] from --shot=SEC:PATH
var _log_t := 0.0
var crash: Crash = null
var skids: SkidMarks
var smoke: CPUParticles3D
var _crash_cam_t := 0.0
var replay := Replay.new()
var _models := {}    # vehicle id -> CarModel, including cars kept only for the replay
var _retired := {}   # vehicle id -> replay clock when the car left the road
var _next_id := 1
var _fps_t := 0.0
var _env: Environment
var _hour := 14.0        # time of day in the game world (0..24); 1 real minute = 2 hours
var _hour_lock := -1.0   # --hour test aid: hold the clock here
var _lights := 0.0       # how much the cars' lights are on (0 day .. 1 night)
var _music: AudioStreamPlayer
var _music_tween: Tween
var _head_spots: Array[SpotLight3D] = []
var _sky: Sky
var _sun: DirectionalLight3D
var garage: GarageScene
var _orbit_i := -1
var _kick := Vector2.ZERO      # suspension kick after an impact: x = roll, y = pitch
var _kick_v := Vector2.ZERO
var _hitstop := 0.0            # a brief slow-down on a hard impact
var _post: ColorRect
var _post_mat: ShaderMaterial
var _vig_mat: ShaderMaterial
var _blur := 0.0
var _test_crash := -1.0
var _test_stage := 0
var _test_fuel := 1.0
var _test_first_station := -1.0
var station := {}       # the next fuel stop: {z, name, color, prices: {regular, mid, premium}}
var last_station := {}  # the one before (still shown in replays)
var pump := {}          # the refuel screen: {litres, bill, on, auto, t}
var godmode := false
var _test_replay := -1.0
var _test_replay_cam := ""
var _probe := {}  # first-run frame-rate check that picks the graphics level


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Input.use_accumulated_input = false  # touches reach the steering as they happen, not once a frame
	autotest = args.has("--autotest")
	if args.has("--fast"):
		Data.target_scale = 0.08
	for a in args:
		if a.begins_with("--quit-after="):
			auto_quit = float(a.split("=")[1])
		if a.begins_with("--showroom"):
			showroom = a.substr(11) if a.length() > 11 else "rear"
		if a.begins_with("--inspect="):  # one car, camera orbiting it: ID:YAW:PITCH:DIST[:FOV] (test aid)
			showroom = "inspect"
			_inspect = a.substr(10).split(":")
		if a.begins_with("--win="):  # desktop window size for screenshots, e.g. 1280x720 (test aid)
			var wh := a.substr(6).split("x")
			_test_win = Vector2i(int(wh[0]), int(wh[1]))
		if a.begins_with("--cam="):  # chase, hood or cockpit (not saved)
			Save.data.cam.mode = a.substr(6)
		if a.begins_with("--steer="):  # swipe, wheel or buttons (not saved)
			Save.data.settings.steer_mode = a.substr(8)
		if a.begins_with("--fake-tilt="):
			fake_tilt = float(a.substr(12))
		if a.begins_with("--orient="):  # portrait or landscape (not saved)
			Save.data.settings.orientation = a.substr(9)
		if a.begins_with("--autospeed="):
			auto_speed = float(a.substr(12))
		if a.begins_with("--car="):  # test drive another car (not saved)
			Save.data.selected = a.substr(6)
		if a == "--cop":  # every boss trigger is a police pursuit (test aid)
			force_cop = true
		if a.begins_with("--stations="):  # a fuel stop every KM km, tank range scaled to match (test aid)
			Data.station_scale = float(a.substr(11)) / Data.STATION_EVERY_KM
		if a.begins_with("--first-station="):  # the first fuel stop this many metres in (test aid)
			_test_first_station = float(a.substr(16))
		if a.begins_with("--route="):  # drive this highway (test aid; opens it if needed)
			Save.data.route_sel = int(a.substr(8))
			Save.data.routes = maxi(int(Save.data.get("routes", 1)), Save.data.route_sel + 1)
		if a.begins_with("--hour="):  # hold the clock at this hour, 0..24 (test aid)
			_hour_lock = float(a.substr(7))
			_hour = _hour_lock
		if a.begins_with("--fuel="):  # start runs with this fraction of a tank (test aid)
			_test_fuel = float(a.substr(7))
		if a.begins_with("--start-stage="):  # begin runs at this stage (test aid)
			_test_stage = int(a.substr(14))
		if a == "--godmode":  # infinite lives without saving it (test aid)
			godmode = true
		if a.begins_with("--steer-test="):  # a scripted hand drives the real steering: flick, lane (test aid)
			_steer_test = a.substr(13)
			godmode = true
		if a.begins_with("--steer-speed="):  # speed for --steer-test, m/s
			_steer_test_v = float(a.substr(14))
		if a == "--steer-assist":  # steering assist on for --steer-test
			Save.data.assist = true
		if a.begins_with("--crash-at="):  # last-life crash at this many seconds (test aid)
			_test_crash = float(a.substr(11))
		if a.begins_with("--replay-at="):  # open the replay editor at this many seconds (test aid)
			var rpa := a.substr(12).split(":")
			_test_replay = float(rpa[0])
			if rpa.size() > 1:
				_test_replay_cam = rpa[1]
		if a == "--idcolor":
			idcolor = true
		if a == "--demo-pops":
			demo_pops = true
		if a.begins_with("--burst="):
			var bp := a.substr(8).split(":", true, 2)
			burst = [float(bp[0]), int(bp[1]), bp[2]]
		if a.begins_with("--shot="):
			var parts := a.substr(7).split(":", true, 1)
			shots.append([float(parts[0]), parts[1]])

	_apply_orientation()
	_build_environment()
	scenery = Scenery.new()
	add_child(scenery)
	_apply_gfx()
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.5
	cam.far = 1000.0  # mountains and clouds are drawn closer and scaled down, so a short range loses nothing
	add_child(cam)
	cam.current = true
	cam.set_cull_mask_value(GarageScene.LAYER, false)  # the garage has its own camera
	_sun.set("light_cull_mask", _sun.light_cull_mask & ~GarageScene.LAYER)  # and its own lights
	garage = GarageScene.new()
	add_child(garage)
	garage.set_active(false)
	sparks = _make_sparks()
	dust = _make_dust()
	smoke = _make_smoke()
	skids = SkidMarks.new()
	add_child(skids)
	sound = EngineAudio.new()
	add_child(sound)
	sound.set_enabled(Save.data.sound)
	_music = AudioStreamPlayer.new()
	var ms: Variant = load("res://assets/audio/cold_iron_street.mp3")
	if ms is AudioStreamMP3:
		(ms as AudioStreamMP3).loop = true
		(ms as AudioStreamMP3).loop_offset = MUSIC_START  # loops back to the same point
	_music.stream = ms
	_music.volume_db = -60.0
	add_child(_music)

	hud = Hud.new()
	add_child(hud)
	hud.act.connect(_on_act)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.24, 0.16, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(_flash)
	hud.root.move_child(_flash, 0)

	_set_player_car()
	_compute_stats()
	_reset_world()
	_go_menu()
	if autotest or _steer_test != "":
		_start_run()
		if _steer_test != "":
			player.v = _steer_test_v
	if showroom != "":
		_build_showroom()
	if idcolor:
		scenery.visible = false
		player.model.visible = false
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		for n in get_children():
			if n is WorldEnvironment:
				n.environment.fog_enabled = false
				n.environment.glow_enabled = false
				n.environment.background_mode = Environment.BG_COLOR
				n.environment.background_color = Color.BLACK
				n.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				n.environment.adjustment_enabled = false
		for c in traffic:
			_paint_id(c)
	for a in args:
		if a.begins_with("--open="):  # e.g. --open=garage or --open=garage:up
			var parts := a.substr(7).split(":")
			_on_act(parts[0], parts[1] if parts.size() > 1 else "")
			if parts.size() > 1:
				_on_act("tab", parts[1])


func _build_showroom() -> void:
	for c in traffic:
		c.model.queue_free()
	traffic.clear()
	player.model.visible = false
	hud.show_screen("")
	var list: Array = Data.CARS
	if showroom == "inspect":
		var car: Dictionary
		if _inspect[0].begins_with("t_"):  # a traffic model: t_SHAPE
			car = {"shape": _inspect[0].substr(2), "color": "#2f5d8c", "style": CarModel.traffic_style(_inspect[0].substr(2))}
		else:
			car = Data.car_by_id(_inspect[0])
		var m := CarModel.new()
		m.build(car.shape, Color(car.color), Color("#b5322a"), car.style)
		add_child(m)
		m.position = Vector3(0, 0, float(Data.SHAPES[car.shape].l) / 2.0)  # centred on the origin
		m.build_interior()
		if _inspect.size() > 5 and _inspect[5] == "brake":
			m.set_brake(true)
		return
	if showroom.begins_with("t_"):  # traffic models instead of the player cars
		list = []
		for sh in ["hatch", "sedan", "suv", "van", "truck", "sedan", "hatch", "suv"]:
			list.append({"shape": sh, "color": Data.TRAFFIC_COLORS.pick_random(), "style": {"rim": "5spoke"}})
	for i in list.size():
		var car: Dictionary = list[i]
		var m := CarModel.new()
		m.build(car.shape, Color(car.color), Color("#b5322a"), car.style)
		add_child(m)
		m.position = Vector3(-5.4 + (i % 4) * 3.6, 0, -float(i / 4) * 9.0 - 4.0)
		m.build_interior()
		if i == 0:
			m.set_brake(true)


func _build_environment() -> void:
	# Late-afternoon light: a low warm sun, a deep blue sky fading to a hazy
	# horizon, ACES tone mapping with a mild grade, and haze that takes its
	# colour from the sky so distance reads naturally.
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = sky
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#2b5c96")
	sm.sky_horizon_color = Color("#d9d2c2")
	sm.sky_curve = 0.11
	sm.sky_energy_multiplier = 1.05
	sm.ground_horizon_color = Color("#c4b69c")
	sm.ground_bottom_color = Color("#3b4a2b")
	sm.ground_curve = 0.06
	sm.sun_angle_max = 26.0
	sm.sun_curve = 0.12
	sm.sky_cover = _star_texture()
	sm.sky_cover_modulate = Color(1, 1, 1, 0)
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.9
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.fog_enabled = true
	env.fog_light_color = Color("#cdc6b6")
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.3
	# Depth fog reaches 100% at 340 m on every renderer. Beyond ~300 m a car
	# is only a few pixels wide and flickers as it shrinks into the vanishing
	# point (most visible from the high chase camera), so the haze fades
	# traffic out smoothly before that. Cars are drawn only within 360 m and
	# added beyond it, so none can be seen appearing, however fast you drive.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 340.0
	env.fog_depth_curve = 1.35
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_color = Color("#fff0d8")
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-32, -40, 0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.3
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.22
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.65
	add_child(sun)
	# full-screen finishing pass, under the HUD
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_post)
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/post.gdshader")
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = load("res://shaders/vignette.gdshader")


## A night sky full of stars (an equirectangular map for the sky cover).
func _star_texture() -> ImageTexture:
	var img := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in 1400:
		var x := rng.randi() % 1024
		var y := rng.randi_range(0, 250)  # upper half: above the horizon
		var b := pow(rng.randf(), 3.0)
		var c := Color(0.85 + 0.15 * rng.randf(), 0.88, 1.0, 0.35 + 0.65 * b)
		img.set_pixel(x, y, c)
		if b > 0.7 and x < 1023:
			img.set_pixel(x + 1, y, Color(c, c.a * 0.5))
	return ImageTexture.create_from_image(img)


## Graphics quality: High (full shadows, anti-aliasing, speed blur and
## grade), Medium (lighter shadows, slightly lower resolution, vignette only)
## or Low (no shadows or glow, 75% resolution) for older phones.
func _apply_gfx() -> void:
	var g: String = Save.setting("gfx")
	if g == "":
		g = "high"
		Save.data.settings.gfx = g
		if OS.has_feature("mobile"):
			_probe = {"t": 0.0, "n": 0}  # check the frame rate during the first run
	var vp := get_viewport()
	var high := g == "high"
	var low := g == "low"
	vp.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low or high else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = 1.0 if high else (0.88 if g == "medium" else 0.75)
	_sun.shadow_enabled = not low
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if high else DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 90.0 if high else 55.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	_env.glow_enabled = not low
	_env.glow_bloom = 0.03 if high else 0.0
	_sky.radiance_size = Sky.RADIANCE_SIZE_256 if high else Sky.RADIANCE_SIZE_128
	_post.visible = not low
	_post.material = _post_mat if high else _vig_mat
	scenery.set_detail(high)


func _probe_gfx(delta: float) -> void:
	if _probe.is_empty() or state != S.PLAY:
		return
	_probe.t += delta
	if _probe.t < 3.0:
		return  # let the run settle first
	_probe.n += 1
	if _probe.t < 9.0:
		return
	var fps: float = _probe.n / (_probe.t - 3.0)
	var levels := ["high", "medium", "low"]
	var i := levels.find(Save.setting("gfx"))
	if fps < 45.0 and i < 2:
		Save.data.settings.gfx = levels[i + 1]
		_apply_gfx()
		_probe = {"t": 0.0, "n": 0}
		if i + 1 == 2:
			_probe = {}
	else:
		_probe = {}
	Save.persist()


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 48
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 1)
	p.spread = 60.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 16.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := BoxMesh.new()
	m.size = Vector3(0.08, 0.08, 0.2)
	p.mesh = m
	p.material_override = CarModel.mat(Color("#ffc04a"), 6.0)
	add_child(p)
	return p


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 40
	p.lifetime = 1.0
	p.direction = Vector3(0, 0.5, 1)
	p.spread = 25.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var m := SphereMesh.new()
	m.radius = 0.35
	m.height = 0.7
	m.radial_segments = 6
	m.rings = 3
	p.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.68, 0.55, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	add_child(p)
	return p


## Grey tyre smoke for the crash.
func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 60
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9, 0.1, 2.0)
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 40.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 0.5
	p.damping_max = 1.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.32))
	grad.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	p.color_ramp = grad
	var m := QuadMesh.new()
	m.size = Vector2(1.6, 1.6)
	p.mesh = m
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 64
	puff.height = 64
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	pg.add_point(0.45, Color(1, 1, 1, 0.55))
	puff.gradient = pg
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = puff
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.material_override = mat
	add_child(p)
	return p


# ---------------------------------------------------------------- setup

func _set_player_car() -> void:
	var c := Data.car_by_id(Save.data.selected)
	var sh: Dictionary = Data.SHAPES[c.shape]
	player.w = sh.w
	player.l = sh.l
	player.lane = -1
	player.tlane = -1
	if player.model:
		player.model.queue_free()
	player.model = CarModel.new()
	player.model.build(c.shape, Save.car_color(c), Color("#b5322a"), Save.car_style(c))
	player.model.force_detail()
	add_child(player.model)
	player.model.build_interior()
	_add_head_spots()
	if sound:
		sound.set_car(c)


func _compute_stats() -> void:
	var c := Data.car_by_id(Save.data.selected)
	var m: Dictionary = run.mods if run else {"accel": 1.0, "brake": 1.0, "handling": 1.0, "top": 1.0}
	st = {
		"accel": c.accel * (1.0 + 0.06 * Save.perm_level("accel")) * m.accel,
		"brake": c.brake * (1.0 + 0.06 * Save.perm_level("brake")) * m.brake,
		"grip": c.grip * (1.0 + 0.06 * Save.perm_level("handling")) * m.handling,
		"lat": c.lat * (1.0 + 0.04 * Save.perm_level("handling")) * sqrt(m.handling),
		"top": c.top * (1.0 + 0.04 * Save.perm_level("top")) * m.top,
		"tank": float(c.get("tank", 45)),
		"grade": String(c.get("fuel", "regular")),
	}


func _reset_world() -> void:
	_end_crash()
	for c in traffic:
		_models.erase(c.id)
		c.model.queue_free()
	traffic.clear()
	_free_retired()
	replay.clear()
	replay_keys.clear()
	_remove_boss()
	finish_z = -1.0
	player.z = 0.0
	player.x = Data.LANES[1]
	target_x = player.x
	player.v = 24.0
	player.vx = 0.0
	player.yaw = 0.0
	player.course = 0.0
	player.steer = 0.0
	var z := 45.0
	while z < 400.0:
		_try_spawn(z)
		z += randf_range(14.0, 26.0)


# ---------------------------------------------------------------- traffic

func _lane_free(lane: int, z: float, ahead: float, behind: float) -> bool:
	var lx: float = Data.LANES[lane]
	for c in traffic:
		if (absf(c.x - lx) < 2.4 or c.tlane == lane) and c.z + c.l > z - behind and c.z < z + ahead:
			return false
	return true


func _try_spawn(z: float, lane_hint := -1, v_override := 0.0) -> bool:
	if _steer_test != "":
		return false  # an empty road for the steering test
	var lane := lane_hint if lane_hint >= 0 else randi() % 4
	if not _lane_free(lane, z, 28.0, 28.0):
		return false
	var blocked := 0
	for i in 4:
		if i != lane and not _lane_free(i, z, 16.0, 16.0):
			blocked += 1
	if blocked >= 3 or (blocked >= 2 and randf() < 0.5):
		return false
	var r := randf()
	var shape := "hatch"
	if lane >= 2 and r < 0.17:
		shape = "truck"
	elif r < 0.27:
		shape = "van"
	elif r < 0.48:
		shape = "suv"
	elif r < 0.76:
		shape = "sedan"
	var sh: Dictionary = Data.SHAPES[shape]
	var c := Vehicle.new()
	c.x = Data.LANES[lane]
	c.z = z
	c.lane = lane
	c.tlane = lane
	c.w = sh.w
	c.l = sh.l
	c.truck = shape == "truck"
	c.cruise = v_override if v_override > 0.0 else ([31.0, 27.5, 24.0, 20.5][lane] + randf_range(-1.6, 1.6) - (2.0 if c.truck else 0.0)) * (run.mods.traffic if run else 1.0)
	c.v = c.cruise
	c.lc_t = randf_range(2.0, 9.0)
	c.ahead = z > player.z + player.l
	c.b_ahead = boss != null and z > boss.z + boss.l
	c.model = CarModel.new()
	if c.truck:
		c.model.build(shape, Color(Data.TRUCK_BOX_COLORS.pick_random()), Color(Data.TRUCK_CAB_COLORS.pick_random()), CarModel.traffic_style(shape))
	else:
		c.model.build(shape, Color(Data.TRAFFIC_COLORS.pick_random()), Color("#b5322a"), CarModel.traffic_style(shape))
	c.model.position = Vector3(c.x, 0.0, -(c.z - player.z))  # place before it is first drawn
	add_child(c.model)
	_register(c)
	traffic.append(c)
	if idcolor:
		_paint_id(c)
	return true


func _paint_id(c: Vehicle) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color8((_id_next % 32) * 8, (_id_next / 32 % 32) * 8, 200)
	c.set_meta("id", _id_next)
	_id_next += 1
	var stack: Array[Node] = [c.model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).material_override = m
			if n is Label3D:
				n.visible = false
		for ch in n.get_children():
			stack.append(ch)


func _lane_open_for(c: Vehicle, nl: int) -> bool:
	var lx: float = Data.LANES[nl]
	for o in traffic:
		if o == c:
			continue
		if (absf(o.x - lx) < 2.6 or o.tlane == nl) and o.z + o.l > c.z - 14.0 and o.z < c.z + c.l + 16.0:
			return false
	var others: Array[Vehicle] = [player]
	if boss:
		others.append(boss)
	for o in others:
		if absf(o.x - lx) < 2.6 and o.z + o.l > c.z - 24.0 and o.z < c.z + c.l + 14.0:
			return false
	return true


func _update_traffic(dt: float) -> void:
	var stage := run.stage if run else 1
	var everyone: Array[Vehicle] = traffic.duplicate()
	everyone.append(player)
	if boss:
		everyone.append(boss)
	# a crashed car sliding or lying across the road blocks its whole footprint
	var p_half := player.w / 2.0
	var p_z0 := player.z
	if crash:
		var hl := player.l / 2.0
		var hw := player.w / 2.0
		var ez := absf(hl * cos(crash.yaw)) + absf(hw * sin(crash.yaw))
		p_half = absf(hl * sin(crash.yaw)) + absf(hw * cos(crash.yaw))
		p_z0 = player.z + hl - ez
	for c in traffic:
		var gap := 1e9
		var lead: Vehicle = null
		for o in everyone:
			if o == c:
				continue
			var half := p_half if o == player else o.w / 2.0
			var oz := p_z0 if o == player else o.z
			if absf(o.x - c.x) < half + c.w / 2.0 + 0.35 and oz > c.z:
				var g := oz - (c.z + c.l)
				if g < gap:
					gap = g
					lead = o
		var want := c.cruise
		if lead and gap < 45.0:
			want = minf(want, lead.v + (gap - 9.0) * 0.35)
		var dv := want - c.v
		c.v += minf(dv, 2.2 * dt) if dv > 0.0 else maxf(dv, -(9.0 if gap < 6.0 else 5.0) * dt)
		if lead and gap < 0.6:
			c.v = minf(c.v, lead.v)
		c.v = maxf(0.0, c.v)
		c.braking = dv < -0.6
		c.z += c.v * dt
		c.vx = 0.0
		if c.hit:
			# knocked: it slides and spins out while it brakes to a stop
			c.slide = move_toward(c.slide, 0.0, 11.0 * dt)
			c.x += c.slide * dt
			c.vx = c.slide
			c.spin += c.spin_rate * dt
			c.spin_rate *= exp(-3.0 * dt)
			c.spin = clampf(c.spin, -1.1, 1.1)
			c.x = clampf(c.x, -(Data.RAIL - c.w * 0.5), Data.RAIL - c.w * 0.5)
		if c.tlane == c.lane and _cop_behind(c):
			# siren behind: get out of the way, to the right if there is room, else the left
			var dirs := [1, -1] if c.lane < 3 else [-1, 1]
			for dl in dirs:
				var nl: int = c.lane + dl
				if nl >= 0 and nl < 4 and not (c.truck and nl < 2) and _lane_open_for(c, nl):
					c.tlane = nl
					c.sig_t = 0.2
					c.yielding = true
					if autotest:
						_yields += 1
					break
			if c.tlane == c.lane:
				c.v = maxf(c.v - 2.0 * dt, c.cruise * 0.8)  # boxed in: ease off and let it squeeze by
		if c.tlane == c.lane:
			var stuck := lead != null and gap < 30.0 and lead.v < c.cruise - 2.0
			c.lc_t -= dt * (1.0 + stage * 0.12) * (3.0 if stuck else 1.0)
			if c.lc_t <= 0.0:
				c.lc_t = randf_range(4.0, 11.0)
				var nl := c.lane + (-1 if randf() < 0.5 else 1)
				if nl >= 0 and nl < 4 and not (c.truck and nl < 2) and _lane_open_for(c, nl):
					c.tlane = nl
					c.sig_t = 1.15
		elif c.sig_t > 0.0:
			c.sig_t -= dt
		else:
			var tx: float = Data.LANES[c.tlane]
			var d := tx - c.x
			var lat := 3.2 if c.yielding else 1.9  # quicker when moving over for the police
			lat = minf(lat, c.v * 0.14)  # it can only drift over as fast as it rolls forward
			var step := lat * dt * signf(d)
			c.vx = lat * signf(d)
			if absf(d) <= absf(step):
				c.x = tx
				c.lane = c.tlane
				c.yielding = false
			else:
				c.x += step
	for i in range(traffic.size() - 1, -1, -1):
		var c := traffic[i]
		var tail_z := player.z
		if boss and not boss.is_cop:
			tail_z = clampf(boss.z, player.z - 160.0, player.z)  # keep the traffic a boss behind you is racing through
		if c.z < tail_z - 90.0 or c.z > player.z + 1100.0:
			_retire(c)
			traffic.remove_at(i)
	# keep the road populated
	var dens := minf(7.2, 3.3 + run.stage * 0.55) if run else 3.4
	# Cars are added and removed only far beyond the haze (and are not drawn
	# past CarModel.DRAW_DISTANCE), so none of them pops in or out of view.
	var ahead := 0
	for c in traffic:
		if c.z > player.z and c.z < player.z + 440.0:
			ahead += 1
	if run and run.clear_t > 0.0:
		run.clear_t -= dt
		return
	for k in 2:
		if ahead < dens * 4.4 and _try_spawn(player.z + randf_range(380.0, 440.0)):
			ahead += 1
	if player.v < 23.0 and randf() < dt * 0.6:
		_try_spawn(player.z - 75.0, 0 if randf() < 0.6 else 1, randf_range(29.0, 33.0))


# ---------------------------------------------------------------- boss

## True if anything (traffic, a car changing into the lane, or the player)
## occupies `lane` from `behind` metres behind the boss to `ahead` in front.
func _lane_blocked(b: Vehicle, lane: int, ahead: float, behind := 6.0) -> bool:
	var lx: float = Data.LANES[lane]
	for c in traffic:
		if (absf(c.x - lx) < 2.4 or c.tlane == lane) and c.z + c.l > b.z - behind and c.z < b.z + b.l + ahead:
			return true
	if absf(player.x - lx) < 2.4 and player.z + player.l > b.z - behind - 4.0 and player.z < b.z + b.l + ahead:
		return true
	return false


## Nearest vehicle ahead of the boss in its path, and the gap to it.
func _boss_leader(b: Vehicle) -> Array:
	var gap := 1e9
	var lead: Vehicle = null
	var others: Array[Vehicle] = traffic.duplicate()
	others.append(player)
	for o in others:
		if absf(o.x - b.x) < (o.w + b.w) / 2.0 + 0.35 and o.z + o.l > b.z:
			var g := o.z - (b.z + b.l)
			if g < gap:
				gap = g
				lead = o
	return [lead, gap]


func _remove_boss() -> void:
	if boss:
		_retire(boss)
		boss = null


## Give a new vehicle an id so the replay can find its model.
func _register(c: Vehicle) -> void:
	c.id = _next_id
	_next_id += 1
	_models[c.id] = c.model


func _free_retired() -> void:
	for id in _retired:
		if _models.has(id):
			(_models[id] as CarModel).queue_free()
			_models.erase(id)
	_retired.clear()


## A vehicle left the road. Its model is kept, hidden, while the replay can
## still show it, then freed.
func _retire(c: Vehicle) -> void:
	if state == S.MENU or state == S.GARAGE:
		_models.erase(c.id)
		c.model.queue_free()
		return
	c.model.visible = false
	_retired[c.id] = replay.clock


func _start_boss() -> void:
	_clear_station_for(run.b_len + 300.0)
	var bi := Data.boss_info(run.stage)
	var car := Data.car_by_id(bi.car)
	var sh: Dictionary = Data.SHAPES[car.shape]
	_remove_boss()
	boss = Vehicle.new()
	boss.lane = 2 if player.x < 0.0 else 1
	boss.tlane = boss.lane
	boss.x = Data.LANES[boss.lane]
	boss.z = player.z - 45.0
	boss.v = player.v + 11.0  # closes in from behind
	boss.w = sh.w
	boss.l = sh.l
	boss.is_boss = true
	# start in a lane that is clear around the boss's starting spot
	for l in [boss.lane, 3 - boss.lane, 0, 3]:
		boss.lane = l
		boss.x = Data.LANES[l]
		if not _lane_blocked(boss, l, 12.0, 12.0):
			break
	boss.tlane = boss.lane
	boss.title = bi.full
	boss.model = CarModel.new()
	boss.model.build(car.shape, Color(car.color), Color("#b5322a"), car.style)
	var tag := Label3D.new()
	tag.text = String(bi.full).to_upper()
	tag.font_size = 72
	tag.pixel_size = 0.012
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = Color("#f3f5ef")
	tag.outline_modulate = Color("#5a1717")
	tag.outline_size = 18
	tag.position = Vector3(0, sh.t + 1.4, -sh.l / 2.0)
	boss.model.add_child(tag)
	boss.model.position = Vector3(boss.x, 0.0, -(boss.z - player.z))  # place before it is first drawn
	add_child(boss.model)
	_register(boss)
	run.phase = "boss"
	run.b_dist = 0.0
	run.b_score = 0
	run.b_rival = 0
	run.b_total = Data.boss_total(run.stage)
	run.b_next = 1.2
	run.b_info = bi
	run.b_skill = Data.boss_skill(run.stage)
	run.b_combo = 0
	run.b_combo_t = 0.0
	run.b_speed_acc = 0.0
	_boss_think_t = 0.0
	_boss_off = 0.0
	finish_z = player.z + run.b_len
	var everyone: Array[Vehicle] = traffic.duplicate()
	everyone.append(player)
	for c in everyone:
		c.b_ahead = c.z > boss.z + boss.l
		c.b_min = 99.0
		c.b_cut = false
	hud.banner("VS " + String(bi.full).to_upper(), "OUT-SCORE %s IN %s" % [Data.boss_skill_name(run.stage), Fmt.km(run.b_len)])


var _bdbg := {}
var _boss_think_t := 0.0
var _boss_off := 0.0  # sideways offset inside the lane, to skim the car being passed


func _update_boss(dt: float) -> void:
	if boss == null:
		return
	if boss.is_cop:
		_update_cop(dt)
		return
	var b := boss
	var sk: float = run.b_skill if run else 0.3
	# Bosses race for points: they drive faster than traffic and weave through
	# it, but stay within sight (a little ahead of you), where the traffic is.
	var top: float = Data.car_by_id(String(run.b_info.car) if run else "copperhead").top
	var cruise := minf(top * lerpf(0.88, 1.0, minf(sk, 1.0)), 33.0 + 26.0 * minf(sk + 0.3, 1.2))
	var rel := b.z - player.z
	var want := cruise
	if rel > 140.0:
		want = minf(want, player.v + (140.0 - rel) * 0.15)  # too far ahead: ease off
	elif rel < 15.0:
		# behind you: traffic there has already been cleared, so push to get back ahead
		want = minf(maxf(want, player.v + clampf((15.0 - rel) * 0.3, 4.0, 18.0)), top * 1.08)
	if rel < -150.0:
		_boss_rejoin(b)
		rel = b.z - player.z
	var lg := _boss_leader(b)
	var lead: Vehicle = lg[0]
	var gap: float = lg[1]
	# better bosses brake later and closer
	var follow := lerpf(6.0, 3.2, minf(sk, 1.0))
	if lead and gap < 45.0:
		want = minf(want, lead.v + (gap - follow) * 0.5)
	b.v += clampf(want - b.v, -(12.0 if gap < 8.0 else 9.0) * dt, lerpf(6.5, 9.5, minf(sk, 1.0)) * dt)
	if lead and gap < 0.8:
		b.v = minf(b.v, lead.v)
	b.v = maxf(0.0, b.v)
	b.braking = want < b.v - 0.5
	b.z += b.v * dt
	if lead and b.z + b.l > lead.z - 0.3 and absf(lead.x - b.x) < (lead.w + b.w) / 2.0:
		b.z = lead.z - b.l - 0.3  # never inside the car ahead
	_boss_steer(b, dt, sk, lead, gap)
	if run == null or run.phase != "boss":
		return
	_boss_score(b, dt, sk)
	if autotest:
		_bdbg["v"] = snappedf(lerpf(float(_bdbg.get("v", b.v)), b.v, 0.002), 0.1)
		_bdbg["rel"] = snappedf(lerpf(float(_bdbg.get("rel", rel)), rel, 0.002), 0.1)


## A boss stuck far behind (out of sight in the haze) rejoins the race just
## behind you, in a clear lane, the way racing games keep rivals in contention.
func _boss_rejoin(b: Vehicle) -> void:
	for l in [0, 1, 2, 3]:
		var probe := Vehicle.new()
		probe.z = player.z - 70.0
		probe.l = b.l
		if absf(Data.LANES[l] - player.x) > 1.0 and not _lane_blocked(probe, l, 25.0, 15.0):
			b.lane = l
			b.tlane = l
			b.x = Data.LANES[l]
			b.z = probe.z
			b.v = player.v + 6.0
			_boss_off = 0.0
			for c in traffic:
				c.b_ahead = c.z > b.z + b.l
				c.b_min = 99.0
			player.b_ahead = player.z > b.z + b.l
			return


## Lane choice and position. Skilled bosses pick the lane with the best
## scoring chances (slow cars to skim past, gaps to thread) and hug the car
## they are passing; weak ones decide slowly and give cars a wide berth.
func _boss_steer(b: Vehicle, dt: float, sk: float, lead: Vehicle, gap: float) -> void:
	_boss_think_t -= dt
	if b.tlane == b.lane:
		b.sig_t = maxf(0.0, b.sig_t - dt)
		var blocked := lead != null and gap < 40.0 and (lead.v < b.v - 1.0 or lead == player)
		if (_boss_think_t <= 0.0 or blocked) and b.sig_t <= 0.0:
			_boss_think_t = lerpf(0.9, 0.22, minf(sk, 1.0)) * randf_range(0.8, 1.2)
			var best := b.lane
			var best_v := _boss_lane_value(b, b.lane, sk)
			for l in [b.lane - 1, b.lane + 1]:
				if l < 0 or l > 3 or _lane_blocked(b, l, lerpf(18.0, 10.0, minf(sk, 1.0)), lerpf(6.0, 3.5, minf(sk, 1.0))):
					continue
				var val := _boss_lane_value(b, l, sk) - lerpf(8.0, 2.0, minf(sk, 1.0))  # weak bosses are a little reluctant to move
				if val > best_v:
					best_v = val
					best = l
			if best != b.lane:
				b.tlane = best
	# where to sit across the lane: skim the slower car alongside or just ahead
	var want_off := 0.0
	var skim := lerpf(1.05, 0.28, minf(sk, 1.0))  # target clearance to the car being passed
	var near_d := 1e9
	for c in traffic:
		var dz := c.z - b.z
		if dz > -c.l - 1.0 and dz < 14.0 and absf(c.x - b.x) < 4.6 and absf(c.x - b.x) > 1.2:
			if dz < near_d:
				near_d = dz
				var s := signf(c.x - b.x)
				var lane_x: float = Data.LANES[b.tlane]
				var gap_x := absf(c.x - lane_x) - (c.w + b.w) / 2.0
				want_off = s * clampf(gap_x - skim, 0.0, 1.1)
	# never squeeze towards a car on the other side
	for c in traffic:
		if c.z < b.z + b.l + 2.0 and c.z + c.l > b.z - 2.0:
			var lane_x: float = Data.LANES[b.tlane]
			var room := absf(c.x - (lane_x + want_off)) - (c.w + b.w) / 2.0
			if room < 0.25 and signf(c.x - lane_x) == signf(want_off):
				want_off = signf(want_off) * maxf(0.0, absf(want_off) - (0.25 - room))
	_boss_off = move_toward(_boss_off, want_off, lerpf(0.8, 2.2, minf(sk, 1.0)) * dt)
	var tx: float = Data.LANES[b.tlane] + _boss_off
	if b.tlane != b.lane:
		# abort the move if the target lane fills up alongside
		if _lane_blocked(b, b.tlane, 4.0, 2.0) and absf(Data.LANES[b.tlane] - b.x) > 1.2:
			b.tlane = b.lane
			b.sig_t = 1.0
			tx = Data.LANES[b.lane] + _boss_off
	var d := tx - b.x
	var lat := lerpf(4.6, 6.2, minf(sk, 1.0)) if b.tlane != b.lane else 1.8
	lat = minf(lat, b.v * 0.2)  # real steering: no sideways motion without forward speed
	var step := clampf(d, -lat * dt, lat * dt)
	b.vx = step / maxf(dt, 0.0001)
	b.x += step
	if b.tlane != b.lane and absf(Data.LANES[b.tlane] - b.x) < 0.6:
		b.lane = b.tlane
		b.sig_t = lerpf(1.0, 0.25, minf(sk, 1.0))  # settle before the next lane change


## How promising a lane is: mostly how much open road it has (so the boss
## keeps moving), plus scoring chances (slow cars in the next lane to skim).
func _boss_lane_value(b: Vehicle, lane: int, sk: float) -> float:
	var lx: float = Data.LANES[lane]
	var free := 120.0
	var bonus := 0.0
	var others: Array[Vehicle] = traffic.duplicate()
	others.append(player)
	for c in others:
		var dz := c.z - (b.z + b.l)
		if dz < -c.l - 1.0 or dz > 120.0:
			continue
		var dx := absf(c.x - lx)
		if dx < 1.9 or (c.tlane >= 0 and c.tlane == lane and c != player):
			if c.v < b.v + 2.0:
				# a car in this lane: open road ends there (sooner if it is much slower)
				free = minf(free, maxf(dz, -5.0) - clampf((b.v - c.v) * 1.5, 0.0, 30.0))
		elif dx < 5.4 and c != player and dz > 0.0:
			# a slower car in the next lane: a near miss waiting to happen
			bonus += 10.0 * clampf((b.v - c.v) / 8.0, 0.0, 1.5) * (1.0 - dz / 140.0) * (1.5 if c.truck else 1.0)
		elif dx < 5.4 and c == player and dz > 0.0:
			bonus += 8.0
	return free + bonus * lerpf(0.4, 1.6, minf(sk, 1.0)) + randf_range(-10.0, 10.0) * (1.2 - minf(sk, 1.0))


## The boss earns points exactly as you do: passes worth more the faster and
## closer they are, close cuts, a combo multiplier and a high-speed bonus.
func _boss_score(b: Vehicle, dt: float, sk: float) -> void:
	if run.b_combo_t > 0.0:
		run.b_combo_t -= dt
		if run.b_combo_t <= 0.0:
			run.b_combo = 0
	var mult := _boss_mult(sk)
	# style points; scaled so the harder-driving bosses keep the same targets
	# (about 6k for the first boss up to about 20k for the last over 2 km)
	var flair := (lerpf(0.85, 1.25, minf(sk, 1.0)) + maxf(0.0, sk - 1.0) * 0.4) * lerpf(0.8, 0.55, minf(sk, 1.0)) * BOSS_EDGE
	if b.v > 33.0:
		run.b_speed_acc += (b.v - 33.0) * 1.3 * dt * mult * flair
		if run.b_speed_acc >= 1.0:
			var n := int(run.b_speed_acc)
			run.b_speed_acc -= n
			run.b_rival += n
	var sf := pow(maxf(b.v, 12.0) / 25.0, 1.5)
	var others: Array[Vehicle] = traffic.duplicate()
	others.append(player)
	for c in others:
		if c.z < b.z + b.l + 1.5 and c.z + c.l > b.z - 1.5:
			var clr := absf(b.x - c.x) - (b.w + c.w) / 2.0
			c.b_min = minf(c.b_min, clr)
			if not c.b_cut and absf(b.vx) > 1.7 and clr < 1.1 and clr > -0.05 and b.v > 18.0:
				c.b_cut = true
				_boss_award(75.0 * sf, 1, "CLOSE CUT", flair)
		if c.b_ahead and b.z > c.z + c.l:
			c.b_ahead = false
			var m := c.b_min
			if m < 0.35:
				_boss_award(245.0 * sf, 2, "RAZOR PASS", flair)
			elif m < 1.0:
				_boss_award(25.0 * sf + 95.0 * sf * (2.0 - m), 1, "NEAR MISS", flair)
			else:
				_boss_award(25.0 * sf, 0, "", flair)
		elif not c.b_ahead and c.z > b.z + b.l:
			c.b_ahead = true
			c.b_min = 99.0
			c.b_cut = false


## A boss's combo multiplier. Better bosses keep longer combos going.
func _boss_mult(sk: float) -> float:
	return minf(lerpf(2.2, 5.0, minf(sk, 1.0)) + maxf(0.0, sk - 1.0) * 3.0, 1.0 + run.b_combo * 0.3)


func _boss_award(base: float, combo: int, label: String, flair: float) -> void:
	if combo > 0:
		run.b_combo += combo
		run.b_combo_t = 3.5
	var pts := roundi(base * _boss_mult(run.b_skill) * flair)
	if autotest:
		_bdbg[label] = int(_bdbg.get(label, 0)) + 1
	run.b_rival += pts
	if label != "" and boss and boss.model:
		boss.model.show_tag_pop("%s +%s" % [label, Fmt.num(pts)])


## The highway's final boss is beaten: open the road on to the next city.
func _route_cleared() -> void:
	var r := Data.route
	if r == Data.ROUTES.size() - 1:
		if not Save.data.get("route_done", false):
			Save.data["route_done"] = true
			_notify("MAP CONQUERED · EVERY HIGHWAY CLEARED", "hot")
	elif int(Save.data.get("routes", 1)) < r + 2:
		Save.data.routes = r + 2
		var nxt: String = Data.CITIES[r + 2].name
		_notify("HIGHWAY TO %s OPEN" % nxt.to_upper(), "hot")
		hud.banner("NEW HIGHWAY OPEN", "%s → %s ON THE WORLD MAP" % [String(Data.CITIES[r + 1].name).to_upper(), nxt.to_upper()])
	Save.persist()
	if autotest:
		print("[autotest] route %d cleared, %d highways open" % [r, int(Save.data.get("routes", 1))])


func _end_battle() -> void:
	var bi := run.b_info
	_remove_boss()
	_boss_mood_end(6.0)
	finish_z = -1.0
	if autotest:
		print("[autotest] boss race stage %d skill %.2f: you %d, %s %d %s" % [run.stage, run.b_skill, run.b_score, bi.full, run.b_rival, _bdbg])
		_bdbg = {}
	if run.b_score > run.b_rival:
		run.bosses += 1
		if run.stage == Data.BOSSES.size():
			_route_cleared()
		run.cash_bonus += 200 * run.stage
		var unlocked_new := false
		if not Save.is_unlocked(bi.car):
			Save.data.unlocked.append(bi.car)
			Save.persist()
			unlocked_new = true
		sound.play("ding", 1.26, 3.0)
		_show_pick(bi, unlocked_new)
	else:
		if not (Save.setting("dev_lives") or godmode):  # infinite lives covers lost races too
			run.lives -= 1
		run.combo = 0
		_vib(200)
		if run.lives <= 0:
			_end_run("Lost the race to " + bi.full)
			return
		_notify("LOST TO %s · -1 LIFE" % String(bi.full).to_upper(), "bad")
		run.phase = "cruise"
		run.rematch_t = 2.5


# ---------------------------------------------------------------- scoring

## Scoring and crash messages: small text floating just above your car in the
## chase view, low on screen from the bonnet, and on the infotainment screen
## in the cockpit, so they never cover the traffic ahead.
func _notify(text: String, kind := "") -> void:
	if Save.data.cam.mode == "cockpit":
		player.model.show_message(text, kind)  # on the infotainment screen as well
	hud.pop_feed(text, kind)


func _mult() -> float:
	return minf(8.0, 1.0 + run.combo * 0.35) if run else 1.0


func _add_score(base: float, label: String, combo: int, kind := "") -> void:
	if combo > 0:
		run.combo += combo
		run.combo_t = run.combo_time
		sound.play("whoosh", randf_range(0.9, 1.15))
		sound.play("ding", pow(2.0, minf(run.combo, 14) / 12.0), -6.0)
	elif run.combo > 0:
		run.combo_t = minf(run.combo_time, run.combo_t + 0.6)
	var pts := roundi(base * _mult() * run.mods.score)
	run.score += pts
	run.stage_score += pts
	if run.phase == "boss":
		run.b_score += pts
	if label != "":
		_notify("%s +%s" % [label, Fmt.num(pts)], kind)


func _award(kind: String, c: Vehicle, clr: float) -> void:
	if run == null or state != S.PLAY or run.dying > 0.0 or c.hit:
		return
	var sf := pow(maxf(player.v, 12.0) / 25.0, 1.5)
	if kind == "pass":
		if clr < 0.35:
			_add_score(25.0 * sf + 220.0 * sf, "RAZOR PASS", 2, "hot")
		elif clr < 1.0:
			_add_score(25.0 * sf + 95.0 * sf * (2.0 - clr), "TRUCK SKIM" if c.truck else "NEAR MISS", 1)
		else:
			_add_score(25.0 * sf, "", 0)
	else:
		_add_score(75.0 * sf, "CLOSE CUT", 1)


# ---------------------------------------------------------------- player

func _live() -> bool:
	return state == S.PLAY and run != null and run.dying <= 0.0


func _autopilot(dt: float) -> void:
	ap_t -= dt
	if ap_t > 0.0:
		return
	ap_t = 0.3
	if run and not station.is_empty() and run.pit.is_empty() and state == S.PLAY:
		var rel := player.z - float(station.z)
		if rel > -GasStation.EXIT_FULL - 60.0 and rel < -GasStation.FORE and run.fuel < st.tank * 0.8:
			target_x = GasStation.LANE_X  # pull in for fuel
			ap_brake = player.v > 34.0
			ap_gas = player.v < 28.0
			return
	var cur := Data.nearest_lane(player.x)
	var best := cur
	var best_d := -1e9
	for l in [cur, cur - 1, cur + 1]:
		if l < 0 or l > 3:
			continue
		var d := 300.0
		for c in traffic:
			if absf(c.x - Data.LANES[l]) < 2.3 and c.z + c.l > player.z - (0.0 if l == cur else 5.0) and c.z < player.z + d:
				d = maxf(-5.0, c.z - player.z)
		if l != cur:
			d -= 10.0
		if d > best_d:
			best_d = d
			best = l
	target_x = Data.LANES[best]
	ap_brake = best_d < 16.0
	ap_gas = not ap_brake and player.v < (auto_speed if autotest else 38.0)


func _hit(reason: String, other: Vehicle = null) -> void:
	if not _live() or run.invuln > 0.0:
		return
	var shielded := run.shield > 0
	if shielded:
		run.shield -= 1
		_notify("CRUMPLE ZONE SAVED YOU", "hot")
	elif not (Save.setting("dev_lives") or godmode):
		run.lives -= 1
	var v0 := player.v
	var side := 0.0  # which side the hit came from (+ = right)
	if other:
		side = signf(other.x - player.x)
	elif absf(player.x) > Data.ROAD_HALF:
		side = signf(player.x)  # guardrail
	if side == 0.0:
		side = 1.0 if randf() < 0.5 else -1.0
	run.invuln = 2.4 + run.armour
	run.combo = 0
	run.combo_t = 0.0
	var jolt := 0.6
	if other:
		_knock(other)
		jolt = clampf(absf(v0 - player.v) / 12.0 + 0.4, 0.4, 1.3)
		var s := signf(other.x - player.x)
		target_x = Data.LANES[Data.nearest_lane(player.x - (s if s != 0.0 else 1.0) * 1.5)]
	else:
		# a barrier: a glancing scrape costs little, hitting it at an angle a lot
		player.v *= lerpf(0.9, 0.55, clampf(absf(player.course) / 0.35, 0.0, 1.0))
		jolt = 0.8
	shake = jolt
	_flash.color.a = 0.25 + 0.2 * jolt
	# the body rocks on its springs away from the blow, and a hard one stops time for a beat
	var kside := signf(other.x - player.x) if other else side
	_kick_v += Vector2(-kside * 2.4 * jolt, -2.0 * jolt)
	if jolt > 0.85:
		_hitstop = 0.1
	if jolt > 0.7:
		_debris_at(Vector3(player.x, 0.6, -player.l * 0.7), Save.car_color(Data.car_by_id(Save.data.selected)), 16)
	sparks.position = Vector3(player.x, 0.6, -player.l * 0.5)
	sparks.restart()
	sparks.emitting = true
	sound.play("crash")
	_vib(180)
	if run.lives <= 0:
		_start_crash(v0, side, other)
		_notify(reason, "bad")
	else:
		_notify(reason + (" · SAVED" if shielded else " · -1 LIFE"), "bad")


## A knock with another car that the player survives: real momentum trade.
## Running into the back of a car shoves it on and costs you about the speed
## difference (bounce 0.3); a side swipe pushes both apart and kicks both
## noses round, so you have to catch the car. The other car brakes, slides
## and spins out. Trucks are 3.5 times as heavy.
func _knock(o: Vehicle) -> void:
	var mp := 1.0
	var mo := 3.5 if o.truck else 1.0
	var dx := o.x - player.x
	var side_on := absf(dx) > (player.w + o.w) * 0.5 - 0.5
	var s := signf(dx) if dx != 0.0 else 1.0
	if not side_on:
		var vp := player.v
		var vo := o.v
		var e := 0.3
		var rel := vp - vo
		if o.z < player.z:  # it ran into us (from behind)
			rel = -rel
		player.v = maxf(0.0, (mp * vp + mo * vo - mo * e * (vp - vo)) / (mp + mo))
		o.v = maxf(0.0, (mp * vp + mo * vo + mp * e * (vp - vo)) / (mp + mo))
		var off := clampf(dx / ((player.w + o.w) * 0.5), -1.0, 1.0)  # off-centre hits spin
		var dv := absf(rel)
		o.spin_rate += off * dv * 0.1 / mo
		o.slide += off * dv * 0.07 / mo
		player.yaw_rate -= off * dv * 0.02
	else:
		var dvx := clampf(absf(player.vx - o.vx) + 1.8, 1.8, 4.5)
		_set_player_vx(player.vx - s * dvx * mo / (mp + mo))
		player.yaw_rate -= s * 0.3 * mo / (mp + mo)
		player.v *= 0.92  # metal scraping metal
		o.slide += s * dvx * mp / (mp + mo) * 0.7
		o.spin_rate += s * clampf(player.v - o.v, -8.0, 8.0) * 0.04 / mo
		o.v *= 0.9
	o.hit = true
	o.cruise = 0.0
	o.lc_t = 1e9
	o.tlane = o.lane


func _make_debris() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 32
	p.lifetime = 1.8
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	p.particle_flag_rotate_y = true
	var m := BoxMesh.new()
	m.size = Vector3(0.14, 0.03, 0.1)
	p.mesh = m
	var g := Gradient.new()  # body panels, black trim, glass
	g.set_color(0, Color(1, 1, 1))
	g.add_point(0.5, Color(0.08, 0.08, 0.09))
	g.set_color(1, Color(0.75, 0.85, 0.9))
	p.color_initial_ramp = g
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	mat.metallic = 0.3
	p.material_override = mat
	add_child(p)
	return p


var _debris: CPUParticles3D


## A burst of bits (body panel in `paint`, trim and glass) flying off.
func _debris_at(pos: Vector3, paint: Color, n := 32) -> void:
	if _debris == null:
		_debris = _make_debris()
	var g := _debris.color_initial_ramp
	g.set_color(0, paint)
	_debris.amount = n
	_debris.position = pos
	_debris.restart()
	_debris.emitting = true


# ---------------------------------------------------------------- last-life crash

func _start_crash(v0: float, side: float, other: Vehicle) -> void:
	crash = Crash.new()
	_crash_cam_t = 0.0
	var k := clampf(v0 / 30.0, 0.5, 1.6)
	crash.yaw = player.yaw
	# knocked away from whatever it hit, nose swung towards it
	crash.vel = Vector2(player.vx * 0.3 - side * randf_range(1.5, 3.0) * k, v0 * 0.78)
	crash.yaw_rate = side * randf_range(1.0, 1.7) * k
	if other and other.z < player.z:  # hit from behind (the police): shoved forward
		crash.vel.y = maxf(crash.vel.y, other.v * 0.9)
	# fast enough and the tyres can dig in sideways and trip it over
	# on its own a sliding car only sometimes digs in and flips; hitting
	# something side-on while sliding (see _crash_collide) is what usually rolls it
	crash.can_trip = v0 > 26.0 and randf() < clampf((v0 - 26.0) / 50.0, 0.08, 0.3)
	run.dying = 8.0
	_debris_at(Vector3(player.x, 0.7, -player.l * 0.6), Save.car_color(Data.car_by_id(Save.data.selected)), 40)
	player.v = maxf(crash.vel.y, 0.0)
	hud.set_play_visible(false)  # let the crash play out full screen
	shake = 1.4


func _update_crash(dt: float) -> void:
	var c := crash
	c.t += dt
	var h := Vector2(sin(c.yaw), cos(c.yaw))  # where the nose points (x, z)
	var right := Vector2(h.y, -h.x)
	var f := c.vel.dot(h)
	var sl := c.vel.dot(right)
	var grounded := c.air <= 0.0
	var on_wheels := absf(wrapf(c.roll, -PI, PI)) < 0.35
	var scraping := false
	if grounded:
		if on_wheels:
			# traction is gone: the tyres scrub sideways and roll on slowly
			# sideways the tyres scrub at about 0.8 g; rolling forward they only
			# drag a little, more the further the car is turned across its path
			sl = move_toward(sl, 0.0, 12.0 * dt)
			f = move_toward(f, 0.0, (3.2 + 8.0 * absf(sl) / maxf(c.vel.length(), 1.0)) * dt)
			c.yaw_rate = move_toward(c.yaw_rate, 0.0, 2.6 * dt)
			if c.can_trip and absf(sl) > 6.5 and c.t > 0.2:
				# the leading tyres dig in and the car flips over sideways
				c.can_trip = false
				_crash_trip(signf(sl), absf(sl))
				sl *= 0.6
		else:
			# on its side or roof: steel on asphalt
			var fr := 12.0 * dt
			sl = move_toward(sl, 0.0, fr)
			f = move_toward(f, 0.0, fr)
			c.yaw_rate = move_toward(c.yaw_rate, 0.0, 4.0 * dt)
			scraping = c.vel.length() > 3.0
		var face := roundi(c.roll / (PI / 2.0))
		var off := c.roll - face * PI / 2.0
		if absf(c.roll_rate) > 2.5:
			# tumbling: each landing on a new face costs energy and bounces it
			c.roll_rate *= exp(-0.55 * dt)
			var tumble := 9.0 * dt
			f = move_toward(f, 0.0, tumble)
			sl = move_toward(sl, 0.0, tumble)
			c.yaw_rate = move_toward(c.yaw_rate, 0.0, 1.5 * dt)
			if face != c.face and absf(off) < 0.25:
				c.face = face
				c.roll_rate *= 0.8
				c.vy = minf(absf(c.roll_rate) * 0.12, 1.2)
				c.air = 0.001
				shake = maxf(shake, 0.7)
				sound.play("crash", randf_range(0.8, 1.05), -5.0)
				_vib(60)
		else:
			# slow: it falls onto its wheels or its roof, whichever is nearer
			var rest := roundf(c.roll / PI) * PI
			c.roll_rate += (rest - c.roll) * 26.0 * dt
			c.roll_rate *= exp(-5.0 * dt)
	else:
		c.vy -= 9.8 * dt
		c.air += c.vy * dt
		if c.air <= 0.0:
			c.air = 0.0
			if c.vy < -2.5:
				c.vy = -c.vy * 0.3
				c.air = 0.001
				sound.play("crash", 1.1, -8.0)
			else:
				c.vy = 0.0
	c.roll += c.roll_rate * dt
	c.yaw += c.yaw_rate * dt
	c.vel = h * f + right * sl
	player.x += c.vel.x * dt
	player.z += maxf(c.vel.y, 0.0) * dt
	var lim := Data.RAIL - player.w / 2.0
	if absf(player.x) > lim:
		var s := signf(player.x)
		player.x = s * lim
		if c.vel.x * s > 0.0:
			if absf(c.vel.x) > 2.5:
				sound.play("crash", 1.2, -6.0)
				_spark_at(Vector3(s * Data.RAIL, 0.6, -player.l * 0.5))
			# sliding sideways into the barrier can trip it over too
			var side_on := absf(sin(c.yaw)) > 0.5
			if side_on and absf(c.vel.x) > 6.0 and absf(wrapf(c.roll, -PI, PI)) < 0.35 and randf() < 0.4:
				_crash_trip(signf(c.vel.dot(Vector2(cos(c.yaw), -sin(c.yaw)))), absf(c.vel.x))
			c.vel.x = -c.vel.x * 0.3
			c.yaw_rate += -s * 0.8
	var solid: Array[Vehicle] = traffic.duplicate()
	if boss:
		solid.append(boss)
	for o in solid:
		_crash_collide(o)
	player.v = maxf(c.vel.y, 0.0)
	player.vx = c.vel.x
	player.yaw = 0.0
	player.course = 0.0
	player.steer = 0.0
	if scraping and fmod(c.t, 0.12) < dt:
		_spark_at(Vector3(player.x, 0.3, -player.l * 0.5))
	if not c.settled and grounded and c.air <= 0.0 and c.vel.length() < 0.4 and absf(c.roll_rate) < 0.3:
		c.settled = true
		if run:
			run.dying = minf(run.dying, 2.2)


## Flip the car over sideways. `side` is the direction it is sliding across
## its own right (+1) or left (-1); `speed` how fast.
func _crash_trip(side: float, speed: float) -> void:
	var c := crash
	if c.air > 0.0 or absf(c.roll_rate) > 2.5:
		return
	if autotest:
		print("[autotest] crash TRIP speed=%.1f" % speed)
	c.roll_rate = -side * clampf(speed * 0.6, 5.0, 8.5)
	c.vy = minf(1.6 + speed * 0.1, 3.4)
	c.air = 0.001
	c.yaw_rate *= 0.4
	sound.play("crash", 0.9, 0.0)
	shake = maxf(shake, 1.2)
	_vib(120)


## The crashing car against another vehicle: both are boxes seen from above
## (the crashing one turned to its heading). Overlap is pushed apart, the
## impact trades momentum, spins the car, and the other car is knocked and
## brakes to a stop. A side-on hit while sliding is what trips a car over.
func _crash_collide(o: Vehicle) -> void:
	var c := crash
	var hl := player.l * 0.5
	var hw := player.w * 0.5
	var pc := Vector2(player.x, player.z + hl)
	var oc := Vector2(o.x, o.z + o.l * 0.5)
	var ohw := o.w * 0.5
	var ohl := o.l * 0.5
	var d := oc - pc
	if absf(d.y) > ohl + hl + 0.5 or absf(d.x) > ohw + hl + 0.5:
		return
	var h := Vector2(sin(c.yaw), cos(c.yaw))
	var r := Vector2(h.y, -h.x)
	var best := 1e9
	var n := Vector2.ZERO
	for ax: Vector2 in [Vector2(1, 0), Vector2(0, 1), h, r]:
		var reach := hl * absf(h.dot(ax)) + hw * absf(r.dot(ax)) + ohw * absf(ax.x) + ohl * absf(ax.y)
		var dist := d.dot(ax)
		var ov := reach - absf(dist)
		if ov <= 0.0:
			return  # a gap on this axis: no contact
		if ov < best:
			best = ov
			n = ax * (1.0 if dist >= 0.0 else -1.0)  # from the crashing car to the other one
	# push apart, the lighter car moving more (a truck barely moves)
	var mp := 1.0
	var mo := 3.5 if o.truck else 1.0
	var kp := mo / (mp + mo)
	player.x -= n.x * best * kp
	player.z -= n.y * best * kp
	o.x += n.x * best * (1.0 - kp)
	o.z += n.y * best * (1.0 - kp)
	var vo := Vector2(o.vx, o.v)
	var vn := (c.vel - vo).dot(n)
	if vn <= 0.0:
		return  # already moving apart
	var j := 1.3 * vn / (1.0 / mp + 1.0 / mo)
	c.vel -= n * (j / mp)
	# the other car is knocked along and gives up: it brakes to a stop
	o.v = maxf(0.0, o.v + n.y * j / mo)
	o.x += n.x * minf(j / mo * 0.04, 0.35)
	if not o.hit:
		o.hit = true
		o.cruise = 0.0
		o.lc_t = 1e9
		o.tlane = o.lane
	# an off-centre hit spins the car
	var contact := pc + d.normalized() * minf(d.length(), hl)
	var arm := contact - pc
	var imp := -n * j
	var inertia := (player.w * player.w + player.l * player.l) / 12.0
	c.yaw_rate -= (arm.x * imp.y - arm.y * imp.x) / inertia * 0.6
	if autotest and j > 1.0:
		print("[autotest] crash contact j=%.1f side=%.2f %s" % [j, n.dot(r), "truck" if o.truck else ""])
	o.spin_rate += signf(n.x) * minf(j / mo * 0.16, 1.6)  # the struck car spins out
	o.slide += n.x * minf(j / mo * 0.25, 3.2)
	if j > 3.0:
		_hitstop = maxf(_hitstop, 0.06)
	if j > 4.0:
		_debris_at(Vector3(contact.x, 0.6, -(contact.y - player.z)), Save.car_color(Data.car_by_id(Save.data.selected)), 20)
	if j > 2.0:
		sound.play("crash", randf_range(0.85, 1.1), clampf(-14.0 + j, -14.0, 0.0))
		shake = maxf(shake, minf(1.2, j * 0.08))
		_vib(int(clampf(j * 8.0, 30.0, 150.0)))
		_spark_at(Vector3(contact.x, 0.5, -(contact.y - player.z)))
	# hit side-on while sliding sideways: the wheels catch and it rolls
	var side := n.dot(r)
	var slip := absf(c.vel.dot(r)) + absf(vn)
	if absf(side) > 0.55 and absf(wrapf(c.roll, -PI, PI)) < 0.35 and slip > 5.0:
		if randf() < clampf(0.2 + j * 0.03 + slip * 0.025, 0.0, 0.85):
			_crash_trip(signf(side), slip)


func _spark_at(pos: Vector3) -> void:
	sparks.position = pos
	sparks.restart()
	sparks.emitting = true


func _end_crash() -> void:
	crash = null
	if player.model:
		player.model.clear_crash_pose()
	skids.clear_all()


func _update_player(dt: float) -> void:
	if crash:
		_update_crash(dt)
		return
	if run and not run.pit.is_empty():
		_update_pit(dt)
		return
	var live := _live()
	if not live or autotest:
		_autopilot(dt)
	var gas := (in_gas if live else ap_gas) if not autotest else ap_gas
	if run and run.fuel <= 0.0 and state == S.PLAY:
		gas = false  # the tank is dry: the engine has nothing to burn
	var brk := (in_brake if live else ap_brake) if not autotest else ap_brake
	var vr: float = player.v / st.top
	var a := 0.0
	if gas:
		a += st.accel * maxf(0.0, 1.0 - pow(vr, 3.0)) * (1.15 if player.v < 10.0 else 1.0)
	a -= 0.3 + 0.00022 * player.v * player.v
	if run and run.fuel <= 0.0 and state == S.PLAY:
		a -= 1.8  # a dry engine drags the car down
	if brk:
		a -= st.brake * (1.0 if player.v > 3.0 else 0.4)
	if on_shoulder:
		a -= 2.5 + player.v * 0.05
	var v_before := player.v
	player.v = maxf(0.0, player.v + a * dt)
	player.braking = brk
	if run and state == S.PLAY and run.dying <= 0.0:
		# fuel: a full tank lasts FUEL_RANGE_KM flat out, longer driven gently
		var lpm: float = st.tank / (Data.FUEL_RANGE_KM * 1000.0 * Data.station_scale)
		lpm *= (0.55 + (0.25 if gas else 0.0) + 0.2 * clampf(vr * vr, 0.0, 1.0)) * run.mods.eco
		run.fuel = maxf(0.0, run.fuel - lpm * player.v * dt)
		if live and _pit_ready():
			_start_pit()
			return
	player_accel = lerpf(player_accel, (player.v - v_before) / maxf(dt, 0.0001), minf(1.0, dt * 6.0))
	if live and not autotest:
		_drive_manual(dt, brk, vr, _steer_val)
	else:
		_drive_steer(dt, brk, vr)
	on_shoulder = absf(player.x) + player.w / 2.0 > Data.ROAD_HALF + 0.25 and not (player.x > 0.0 and _in_station_zone())
	var side := signf(player.x)
	var lim := (_right_limit() if side > 0.0 else Data.RAIL) - player.w / 2.0
	if absf(player.x) > lim and side > 0.0 and _in_station_zone():
		# the fuel stop's tapers and rails: a scrape along them, not a crash
		player.x = lim
		_set_player_vx(minf(player.vx, 0.0) - 0.4)
		player.v = maxf(0.0, player.v - 3.0 * dt)
		target_x = minf(target_x, lim - 0.2)
	elif absf(player.x) > lim:
		var s := signf(player.x)
		player.x = s * lim
		_set_player_vx(-s * 2.6)
		target_x = Data.LANES[3 if s > 0.0 else 0]
		sparks.position = Vector3(s * Data.RAIL, 0.6, -2.0)
		sparks.restart()
		sparks.emitting = true
		if live:
			_hit("GUARDRAIL")


## Real steering (a bicycle model): the car can only change direction by
## rolling forward on turned front wheels. Turn rate = speed x tan(wheel
## angle) / wheelbase, so a stopped car cannot turn at all and a slow one
## needs lots of lock. The front wheels turn at a limited rate, the lock
## available shrinks with speed, and the tyres only grip up to a sideways
## acceleration: ask for more and the car runs wide. Braking hard uses up
## some of that grip. The car's sideways speed is just where its nose points.
func _drive_steer(dt: float, brk: bool, vr: float) -> void:
	var v := player.v
	var wb := player.l * 0.6
	# where the input wants the car: a sideways speed towards the target
	var want_vx := clampf((target_x - player.x) * 3.2, -st.lat, st.lat)
	# the heading that gives it (a car moves sideways only by pointing that way)
	var max_head := 0.45
	var head_des := player.yaw
	if v > 0.2:
		head_des = asin(clampf(want_vx / v, -sin(max_head), sin(max_head)))
	var r_des := (head_des - player.yaw) * 6.0
	# the front-wheel angle the driver dials in for that turn rate
	var lock := lerpf(0.6, 0.06, clampf(v / 45.0, 0.0, 1.0))
	var steer_des := clampf(atan(r_des * wb / maxf(v, 0.5)), -lock, lock)
	if v < 0.2:
		steer_des = player.steer  # parked: the wheels stay where they were left
	player.steer = move_toward(player.steer, steer_des, 1.8 * dt)
	var r := v * tan(player.steer) / wb
	# grip limit (friction circle): less sideways grip while braking, on the
	# shoulder, and as the tyres load up near top speed
	var grip: float = st.grip * (1.0 - 0.18 * clampf(vr, 0.0, 1.2)) * (0.6 if on_shoulder else 1.0) * (0.75 if brk and v > 3.0 else 1.0)
	if absf(r) * v > grip:
		r = signf(r) * grip / maxf(v, 0.1)  # past the limit: understeer, the car runs wide
	player.yaw_rate = r
	player.yaw = clampf(player.yaw + r * dt, -0.6, 0.6)
	player.course = player.yaw
	player.vx = v * sin(player.yaw)
	player.x += player.vx * dt
	player.z += v * cos(player.yaw) * dt


## The player's own steering: the input turns the front wheels (like a real
## steering wheel), they self-centre when you let go, and the car keeps
## whatever heading it has: nothing pulls it back into a lane. Full input
## asks for about the most the tyres can give at the current speed, so the
## same push feels alike at 60 and 200 km/h. The car itself is SteerModel
## (tools/steer_test.gd measures how quickly it answers); the hand's side of
## it, SteerInput, turns tilt, stick, wheel and swipe into the command.
## Steering assist (optional) only straightens the car up to the road when
## you let go.
func _drive_manual(dt: float, brk: bool, vr: float, cmd: float) -> void:
	var v := player.v
	var wb := player.l * 0.6
	var grip: float = st.grip * (1.0 - 0.18 * clampf(vr, 0.0, 1.2)) * (0.6 if on_shoulder else 1.0) * (0.75 if brk and v > 3.0 else 1.0)
	var auth: float = SteerModel.feel(Save.setting("steer_feel")).auth
	SteerModel.drive(player, dt, v, grip, auth, wb, cmd, Save.data.assist)
	# how hard the tyres are working (0 .. 1: the limit), for the controls and the haptics
	var work := absf(v * player.yaw_rate) / maxf(SteerModel.usable(grip, auth), 0.1)
	_feel_load = lerpf(_feel_load, clampf(work, 0.0, 1.3), minf(1.0, dt * 14.0))
	player.vx = v * sin(player.course)
	player.x += player.vx * dt
	player.z += v * cos(player.course) * dt
	target_x = player.x  # the autopilot (if it takes over) starts from here


## Point the player's car so its sideways speed is vx (after a knock or a
## bounce off the rail). At a crawl it can only point so far.
func _set_player_vx(vx: float) -> void:
	player.yaw = asin(clampf(vx / maxf(player.v, 1.0), -0.5, 0.5))
	player.course = player.yaw
	player.vx = player.v * sin(player.yaw)


func _overlap(a: Vehicle, b: Vehicle) -> bool:
	return absf(a.x - b.x) < (a.w + b.w) / 2.0 - 0.12 and a.z < b.z + b.l - 0.2 and a.z + a.l > b.z + 0.2


func _collisions() -> void:
	if not _live() or not run.pit.is_empty():
		return
	var p := player
	for c in traffic:
		if p.z < c.z + c.l + 1.5 and p.z + p.l > c.z - 1.5:
			var clr := absf(p.x - c.x) - (p.w + c.w) / 2.0
			if clr < c.min_clear:
				c.min_clear = clr
			if not c.cut and absf(p.vx) > 1.7 and clr < 1.1 and clr > -0.05 and p.v > 18.0:
				c.cut = true
				_award("cut", c, clr)
		if c.ahead and not c.passed and p.z > c.z + c.l:
			c.passed = true
			_award("pass", c, c.min_clear)
		if not c.ahead and c.z > p.z + p.l:
			c.ahead = true
			c.passed = false
			c.min_clear = 99.0
		if run.invuln <= 0.0 and _overlap(p, c):
			_hit("CONTACT", c)
	var rammed: bool = boss != null and boss.is_cop and absf(p.x - boss.x) < (p.w + boss.w) / 2.0 - 0.15 \
		and p.z - (boss.z + boss.l) < 0.15 and boss.z < p.z + p.l
	if boss and run.invuln <= 0.0 and (rammed or _overlap(p, boss)):
		if boss.is_cop:
			if autotest:
				print("[autotest] cop BUSTED after %.1f s, traffic pulled over %d times" % [run.cop_t, _yields])
			_hit("BUSTED", boss)
			if run.phase == "cop":
				hud.banner("BUSTED", "-1 LIFE")
				_end_cop()
		else:
			_hit("RIVAL CONTACT", boss)


# ---------------------------------------------------------------- run flow

## Drive this highway: its landscape, sky and difficulty.
func _set_route(i: int) -> void:
	Data.route = clampi(i, 0, Data.ROUTES.size() - 1)
	var land: Dictionary = Data.route_info(Data.route).land
	_day = DAY.duplicate()
	_day.top = land.sky
	_day.hor = land.hor
	scenery.set_biome(land)


func _start_run() -> void:
	_leave_garage()
	_set_route(int(Save.data.get("route_sel", 0)))
	_boss_music(false, 0.5)
	_apply_time(_hour)
	_set_player_car()
	run = Run.new()
	run.lives = 3 + Save.perm_level("lives")
	station = {}
	last_station = {}
	if _test_stage > 1:
		run.stage = _test_stage
	_compute_stats()
	_reset_world()
	run.fuel = st.tank * _test_fuel
	_new_station(player.z)
	touches.clear()
	_refresh_inputs()
	state = S.PLAY
	hud.show_screen("")
	hud.set_play_visible(true)
	var ri := Data.route_info(Data.route)
	hud.banner(ri.name, "%s → %s · STAGE 1" % [String(ri.from).to_upper(), String(ri.to).to_upper()])
	hud.show_hint()
	_calibrate_tilt()


func _end_run(reason: String) -> void:
	if run == null:
		return
	_boss_mood_end(2.5)
	var earned := maxi(0, _gross_earnings() - run.fuel_from_run)
	Save.data.cash += earned
	var rb: Dictionary = Save.data.get("route_best", {})
	rb[str(Data.route)] = maxi(int(rb.get(str(Data.route), 0)), run.score)
	Save.data["route_best"] = rb
	var best: bool = run.score > Save.data.best
	if best:
		Save.data.best = run.score
	Save.data.runs += 1
	Save.persist()
	var notes: Array[String] = []
	if best:
		notes.append("New best run.")
	if run.cash_bonus > 0:
		notes.append("Includes $%s in boss prize money." % Fmt.num(run.cash_bonus))
	if run.fuel_paid > 0:
		notes.append("Fuel cost $%s this run." % Fmt.num(run.fuel_paid))
	var next_car := {}
	for c in Data.CARS:
		if not Save.owns(c.id) and (c.boss < 0 or Save.is_unlocked(c.id)):
			if next_car.is_empty() or c.price < next_car.price:
				next_car = c
	if not next_car.is_empty():
		if Save.data.cash >= next_car.price:
			notes.append("You can afford the %s now." % next_car.name)
		else:
			notes.append("$%s more for the %s." % [Fmt.num(next_car.price - Save.data.cash), next_car.name])
	var score := run.score
	var dist := run.dist
	var bosses := run.bosses
	if autotest:
		print("[autotest] run over: %s score=%d dist=%.0f bosses=%d earned=%d" % [reason, score, dist, bosses, earned])
	run = null
	_remove_boss()
	finish_z = -1.0
	_compute_stats()
	state = S.OVER
	hud.set_play_visible(false)
	hud.show_over(reason, Fmt.num(score), Fmt.km(dist), str(bosses), "+$" + Fmt.num(earned), " ".join(notes))
	if autotest and _test_replay < 0.0:
		_start_run()


func _show_pick(bi: Dictionary, unlocked_new: bool) -> void:
	state = S.PICK
	var pool: Array = []
	for b in Data.BOONS:
		if b.id == "life" and run.lives >= Data.MAX_LIVES:
			continue
		if b.id == "fuel" and run.fuel > st.tank * 0.85:
			continue  # a refuel is only offered when the tank could use it
		pool.append(b)
	pool.shuffle()
	var opts := pool.slice(0, 3)
	var line := "Choose one upgrade for the rest of this run."
	if unlocked_new:
		line = "The %s is now for sale in the Garage. " % Data.car_by_id(bi.car).name + line
	hud.show_pick("%s beaten · +$%s prize" % [bi.full, Fmt.num(200 * run.stage)], line, opts)
	if autotest:
		print("[autotest] beat %s, picking %s" % [bi.full, opts[0].id])
		_apply_boon(opts[0].id)


## After an upgrade is chosen: the traffic around you melts away so there is
## room to get a hand on the wheel again. Cars from 80 m behind to 260 m ahead
## are removed and nothing new appears for a second.
func _clear_road() -> void:
	for i in range(traffic.size() - 1, -1, -1):
		var c := traffic[i]
		if c.z > player.z - 80.0 and c.z < player.z + 260.0:
			_retire(c)
			traffic.remove_at(i)
	run.clear_t = 1.0


func _apply_boon(id: String) -> void:
	if run == null:
		return
	match id:
		"accel": run.mods.accel *= 1.15
		"brake": run.mods.brake *= 1.2
		"handling": run.mods.handling *= 1.12
		"top": run.mods.top *= 1.07
		"life": run.lives = mini(Data.MAX_LIVES, run.lives + 1)
		"score": run.mods.score *= 1.15
		"combo": run.combo_time += 1.0
		"fuel":
			run.fuel = st.tank
			run.fuel_warned = 0
		"shield": run.shield += 1
		"armour": run.armour += 1.5
		"calm":
			run.mods.traffic *= 0.9
			for c in traffic:
				c.cruise *= 0.9
		"eco": run.mods.eco *= 0.75
		"cash":
			run.cash_bonus += 400 * run.stage
			_notify("SPONSOR DEAL · +$%s" % Fmt.num(400 * run.stage), "hot")
	_compute_stats()
	_clear_road()
	run.stage += 1
	run.cop_due = false
	run.phase = "cruise"
	run.stage_dist = 0.0
	run.stage_score = 0
	run.invuln = 1.5
	run.combo = 0
	touches.clear()
	_refresh_inputs()
	state = S.PLAY
	hud.show_screen("")
	hud.banner("STAGE %d" % run.stage, String(Data.boss_info(run.stage).full).to_upper() + " WAITS AHEAD")


var _cop_aim := 0.0
var _cop_think := 0.0
var _yields := 0
const COP_CHANCE := 0.3   # chance that a boss trigger is a police pursuit instead
const COP_TIME := 40.0    # seconds to survive to escape
const BOSS_WARN := 10.0   # seconds of warning before the boss or police arrives
const MUSIC_START := 50.0  # seconds into the boss theme where it fades in
const MUSIC_DB := -1.5      # boss theme volume
const BOSS_EDGE := 1.25   # bosses score this much more than their driving alone earns (harder to beat)


## Police pursuit: a cop car comes up from behind and tries to ram you.
## Survive COP_TIME seconds for an extra life; get rammed and you lose one.
func _start_cop() -> void:
	_clear_station_for(COP_TIME * 85.0)
	_remove_boss()
	var sh: Dictionary = Data.SHAPES.sedan
	boss = Vehicle.new()
	boss.is_cop = true
	boss.lane = Data.nearest_lane(player.x)
	boss.tlane = boss.lane
	boss.x = Data.LANES[boss.lane]
	boss.z = player.z - 70.0
	boss.v = player.v + 6.0
	boss.w = sh.w
	boss.l = sh.l
	boss.title = "POLICE"
	_cop_aim = boss.x
	boss.model = CarModel.new()
	boss.model.build("sedan", Color("#f2f3f5"), Color("#b5322a"), {"rim": "steel", "badge": "POLICE", "plate": "PD 911"})
	boss.model.add_lightbar(sh.t)
	var tag := Label3D.new()
	tag.text = "POLICE"
	tag.font_size = 72
	tag.pixel_size = 0.012
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = Color("#f3f5ef")
	tag.outline_modulate = Color("#173a6e")
	tag.outline_size = 18
	tag.position = Vector3(0, sh.t + 1.4, -sh.l / 2.0)
	tag.name = "CopTag"
	boss.model.add_child(tag)
	boss.model.position = Vector3(boss.x, 0.0, -(boss.z - player.z))
	add_child(boss.model)
	_register(boss)
	run.phase = "cop"
	run.cop_t = 0.0
	run.siren_t = 0.0
	run.cop_due = true
	hud.banner("POLICE PURSUIT", "DON'T GET RAMMED FOR %d S · ESCAPE FOR +1 LIFE" % int(COP_TIME))
	if autotest:
		print("[autotest] police pursuit stage %d" % run.stage)


## Pursuit over (escaped or rammed): back to cruising, stage progress resets
## and the next trigger is the real boss.
func _end_cop() -> void:
	_remove_boss()
	_boss_mood_end(6.0)
	run.phase = "cruise"
	run.stage_dist = 0.0
	run.stage_score = 0


func _update_cop(dt: float) -> void:
	var b := boss
	var gap_to_player := player.z - (b.z + b.l)
	var tag := b.model.get_node_or_null("CopTag") as Label3D
	if tag:  # fade the tag out when it would sit on top of the player's car
		tag.modulate.a = clampf((gap_to_player - 8.0) / 10.0, 0.0, 1.0)
		tag.outline_modulate.a = tag.modulate.a
	# close in fast, then match speed and push for contact
	var want := player.v + clampf(gap_to_player * 0.45 + 2.5, -8.0, 16.0)  # keeps pushing at contact
	var lg := _boss_leader(b)
	var lead: Vehicle = lg[0]
	var gap: float = lg[1]
	if lead and lead != player and gap < 30.0:
		want = minf(want, lead.v + (gap - 3.0) * 0.6)  # traffic in the way: brakes late behind it
	b.v += clampf(want - b.v, -12.0 * dt, 10.5 * dt)
	b.v = clampf(b.v, 0.0, 90.0)
	b.z += b.v * dt
	if lead and lead != player and b.z + b.l > lead.z - 0.3 and absf(lead.x - b.x) < (lead.w + b.w) / 2.0:
		b.z = lead.z - b.l - 0.3
	# the player is solid: the cop pushes in for contact but never drives through
	# (and keeps a little back while the player is invulnerable)
	if absf(player.x - b.x) < (player.w + b.w) / 2.0 and b.z < player.z + 2.0:
		var limit := player.z + (0.3 if run.invuln <= 0.0 else -1.5) - b.l
		if b.z > limit:
			b.z = limit
			b.v = minf(b.v, player.v)
	# steer: at where it thinks the player is (it reacts with a delay, so a late
	# lane change can shake it off), otherwise lane by lane through gaps
	_cop_aim = lerpf(_cop_aim, player.x, minf(1.0, dt * 1.6))
	b.vx = 0.0
	var tx: float
	if absf(gap_to_player) < 20.0:
		tx = _cop_aim
	else:
		_cop_think -= dt
		if b.tlane == b.lane and _cop_think <= 0.0:
			# hunt for the gap: the lane with the most open road, leaning towards the player
			_cop_think = 0.25
			var pl := Data.nearest_lane(player.x)
			var best := b.lane
			var best_v := _free_ahead(b, b.lane) - absf(b.lane - pl) * 12.0
			for l in [b.lane - 1, b.lane + 1]:
				if l < 0 or l > 3 or _lane_blocked(b, l, 12.0, 3.5):
					continue
				var val := _free_ahead(b, l) - absf(l - pl) * 12.0 - 6.0
				if val > best_v:
					best_v = val
					best = l
			b.tlane = best
		tx = Data.LANES[b.tlane]
	var lat := 5.2 if absf(gap_to_player) >= 20.0 else 3.6  # darts into gaps; near you it reacts with a lag
	lat = minf(lat, b.v * 0.2)
	var step := clampf(tx - b.x, -lat * dt, lat * dt)
	var nx := b.x + step
	var clear := true
	for c in traffic:  # never slide sideways into a car
		if absf(c.x - nx) < (c.w + b.w) / 2.0 and c.z < b.z + b.l and c.z + c.l > b.z:
			clear = false
			break
	if clear:
		b.x = nx
		b.vx = step / maxf(dt, 0.0001)
	if absf(b.x - Data.LANES[b.tlane]) < 0.05:
		b.lane = b.tlane
	b.model.flash_lightbar(t)


# ---------------------------------------------------------------- boss mood

## Boss music in (a short fade) or out (over `fade` seconds).
func _boss_music(on: bool, fade := 6.0) -> void:
	if _music == null or _music.stream == null:
		return
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	if on:
		if not Save.data.sound:
			return
		if not _music.playing:
			_music.volume_db = -40.0
			_music.play(MUSIC_START)
		_music_tween.tween_property(_music, "volume_db", MUSIC_DB, 2.5)
	elif _music.playing:
		_music_tween.tween_property(_music, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE)
		_music_tween.tween_callback(_music.stop)


## Afternoon (0) to dusk (1): the sun sinks and reddens, the sky darkens to a
## glowing horizon, the haze cools, and every car's lights come on.
var _day := {}  # DAY with the current highway's sky (set_route)
const DAY := {"sun": Color("#fff0d8"), "sun_e": 1.4, "sun_x": -32.0, "top": Color("#2b5c96"), "hor": Color("#d9d2c2"),
	"ghor": Color("#c4b69c"), "sky_e": 1.05, "amb": 0.75, "fog": Color("#cdc6b6"), "exp": 1.05}
const DUSK := {"sun": Color("#ffa86a"), "sun_e": 1.05, "sun_x": -18.0, "top": Color("#38487e"), "hor": Color("#efa070"),
	"ghor": Color("#7a5c4c"), "sky_e": 0.9, "amb": 0.7, "fog": Color("#a98a8a"), "exp": 1.08}


## The sky through the day: keyframes at set hours, blended between. Day
## keys take their sky colours from the highway's country (_day).
const TIME_KEYS := [
	[0.0, {"sun": Color("#9fb4ff"), "e": 0.22, "elev": 40.0, "top": Color("#070b18"), "hor": Color("#1c2440"), "ghor": Color("#0c0f14"), "sky": 0.3, "amb": 0.34, "fog": Color("#1c2333"), "exp": 1.18, "lights": 1.0, "far": Color(0.22, 0.25, 0.38), "haze": Color(0.12, 0.14, 0.22)}],
	[5.0, {"sun": Color("#9fb4ff"), "e": 0.22, "elev": 30.0, "top": Color("#0a1022"), "hor": Color("#26304e"), "ghor": Color("#10131a"), "sky": 0.32, "amb": 0.36, "fog": Color("#232a3c"), "exp": 1.18, "lights": 1.0, "far": Color(0.25, 0.28, 0.4), "haze": Color(0.15, 0.17, 0.26)}],
	[6.3, {"sun": Color("#ffb07a"), "e": 0.6, "elev": 3.0, "top": Color("#2c3a6a"), "hor": Color("#f0a47a"), "ghor": Color("#5a4a44"), "sky": 0.6, "amb": 0.5, "fog": Color("#a08a8c"), "exp": 1.06, "lights": 0.6, "far": Color(0.7, 0.55, 0.55), "haze": Color(0.78, 0.55, 0.48)}],
	[8.0, {"sun": Color("#fff0dc"), "e": 1.25, "elev": 24.0, "top": "day", "hor": "day", "ghor": Color("#c4b69c"), "sky": 1.0, "amb": 0.72, "fog": Color("#cdc6b6"), "exp": 1.05, "lights": 0.0, "far": Color(1, 1, 1), "haze": Color(0.85, 0.82, 0.76)}],
	[12.5, {"sun": Color("#fffaf0"), "e": 1.5, "elev": 58.0, "top": "day", "hor": "day", "ghor": Color("#c8bca4"), "sky": 1.1, "amb": 0.8, "fog": Color("#d6d2c6"), "exp": 1.02, "lights": 0.0, "far": Color(1, 1, 1), "haze": Color(0.86, 0.84, 0.8)}],
	[16.0, {"sun": Color("#fff0d8"), "e": 1.4, "elev": 32.0, "top": "day", "hor": "day", "ghor": Color("#c4b69c"), "sky": 1.05, "amb": 0.75, "fog": Color("#cdc6b6"), "exp": 1.05, "lights": 0.0, "far": Color(1, 1, 1), "haze": Color(0.85, 0.82, 0.76)}],
	[18.6, {"sun": Color("#ffa86a"), "e": 1.0, "elev": 8.0, "top": Color("#38487e"), "hor": Color("#efa070"), "ghor": Color("#7a5c4c"), "sky": 0.85, "amb": 0.62, "fog": Color("#a98a8a"), "exp": 1.08, "lights": 0.45, "far": Color(0.62, 0.46, 0.46), "haze": Color(0.72, 0.44, 0.36)}],
	[20.0, {"sun": Color("#ff7a5a"), "e": 0.35, "elev": 1.0, "top": Color("#1a2246"), "hor": Color("#b0606a"), "ghor": Color("#3a2c30"), "sky": 0.45, "amb": 0.42, "fog": Color("#5a4a5a"), "exp": 1.12, "lights": 1.0, "far": Color(0.4, 0.32, 0.4), "haze": Color(0.36, 0.26, 0.3)}],
	[21.5, {"sun": Color("#9fb4ff"), "e": 0.22, "elev": 40.0, "top": Color("#070b18"), "hor": Color("#1c2440"), "ghor": Color("#0c0f14"), "sky": 0.3, "amb": 0.34, "fog": Color("#1c2333"), "exp": 1.18, "lights": 1.0, "far": Color(0.22, 0.25, 0.38), "haze": Color(0.12, 0.14, 0.22)}],
	[24.0, {"sun": Color("#9fb4ff"), "e": 0.22, "elev": 40.0, "top": Color("#070b18"), "hor": Color("#1c2440"), "ghor": Color("#0c0f14"), "sky": 0.3, "amb": 0.34, "fog": Color("#1c2333"), "exp": 1.18, "lights": 1.0, "far": Color(0.22, 0.25, 0.38), "haze": Color(0.12, 0.14, 0.22)}],
]


func _key_val(k: Dictionary, name: String) -> Variant:
	var v: Variant = k[name]
	if v is String:  # "day": the country's own sky colour
		return _day.top if name == "top" else _day.hor
	return v


## Light the world for this hour of the day.
func _apply_time(hour: float) -> void:
	if _day.is_empty():
		_day = DAY.duplicate()
	hour = fposmod(hour, 24.0)
	var i := 0
	while i < TIME_KEYS.size() - 2 and hour >= float(TIME_KEYS[i + 1][0]):
		i += 1
	var h0: float = TIME_KEYS[i][0]
	var h1: float = TIME_KEYS[i + 1][0]
	var a: Dictionary = TIME_KEYS[i][1]
	var b: Dictionary = TIME_KEYS[i + 1][1]
	var f := smoothstep(0.0, 1.0, (hour - h0) / maxf(h1 - h0, 0.001))
	var col := func(n: String) -> Color: return (_key_val(a, n) as Color).lerp(_key_val(b, n), f)
	var num := func(n: String) -> float: return lerpf(float(a[n]), float(b[n]), f)
	# the sun crosses from east to west by day; the moon hangs high at night
	var day_t := clampf((hour - 6.0) / 14.0, 0.0, 1.0)
	_sun.rotation_degrees = Vector3(-num.call("elev"), lerpf(-115.0, 75.0, day_t), 0.0)
	_sun.light_color = col.call("sun")
	_sun.light_energy = num.call("e")
	var sm := _sky.sky_material as ProceduralSkyMaterial
	var top: Color = col.call("top")
	var hor: Color = col.call("hor")
	if sm:
		sm.sky_top_color = top
		sm.sky_horizon_color = hor
		sm.ground_horizon_color = col.call("ghor")
		sm.sky_energy_multiplier = num.call("sky")
	_env.ambient_light_energy = num.call("amb")
	_env.fog_light_color = col.call("fog")
	_env.tonemap_exposure = num.call("exp")
	_lights = num.call("lights")
	_env.adjustment_saturation = lerpf(1.12, 0.9, _lights)
	_env.glow_intensity = lerpf(0.45, 1.0, _lights)  # lamps bloom more in the dark
	CarModel.set_night(smoothstep(0.0, 1.0, _lights), _sun.global_transform.basis.z.normalized(), top, hor)
	if scenery:
		scenery.set_sky_tint(col.call("far"), col.call("haze"))
		scenery.set_night(smoothstep(0.3, 1.0, _lights))
	if sm and sm.sky_cover:
		sm.sky_cover_modulate = Color(1, 1, 1, smoothstep(0.7, 1.0, _lights) * 0.9)  # stars
	for sp in _head_spots:
		if is_instance_valid(sp):
			sp.visible = _lights > 0.02
			sp.light_energy = 6.0 * smoothstep(0.0, 1.0, _lights)


## Time passes while you drive: one real minute is two hours.
func _update_time(dt: float) -> void:
	if _hour_lock >= 0.0:
		_hour = _hour_lock
	else:
		_hour = fposmod(_hour + dt * (2.0 / 60.0), 24.0)
	_apply_time(_hour)


func clock_text() -> String:
	var m := int(_hour * 60.0)
	return "%02d:%02d" % [(m / 60) % 24, m % 60]


## Real headlight beams on the player's car (the others get light pools).
func _add_head_spots() -> void:
	_head_spots.clear()
	var sh: Dictionary = player.model.shape
	for sd in [-1.0, 1.0]:
		var sp := SpotLight3D.new()
		sp.position = Vector3(sd * sh.w * 0.32, 0.7, -sh.l + 0.2)
		sp.rotation_degrees = Vector3(-2.5, sd * -2.5, 0.0)  # along the road, dipped, each lamp angled slightly outwards
		sp.light_color = Color("#fff1d6")
		sp.spot_range = 110.0
		sp.spot_angle = 30.0
		sp.spot_attenuation = 0.45
		sp.spot_angle_attenuation = 1.6  # soft edge to the cone
		sp.shadow_enabled = false
		sp.light_cull_mask = sp.light_cull_mask & ~GarageScene.LAYER
		sp.visible = _lights > 0.02
		sp.light_energy = 6.0 * smoothstep(0.0, 1.0, _lights)
		player.model.add_child(sp)
		_head_spots.append(sp)


## The boss encounter is over (won, lost or escaped): back to daylight.
func _boss_mood_end(fade := 6.0) -> void:
	_boss_music(false, fade)


## A stage is complete: warn that the boss (or a police car) is coming in
## BOSS_WARN seconds, without stopping the game. Fuel stops are moved out of
## the way of the countdown and the race.
func _begin_incoming(cop: bool) -> void:
	run.phase = "incoming"
	run.inc_t = BOSS_WARN
	run.inc_cop = cop
	_boss_music(true)
	_clear_station_for(player.v * BOSS_WARN + run.b_len + 300.0)
	var bi := Data.boss_info(run.stage)
	if cop or not run.cop_due:
		hud.banner("BOSS OR POLICE?", "SOMETHING IS COMING IN %d S" % int(BOSS_WARN))
	else:
		hud.banner(String(bi.full).to_upper() + " INCOMING", String(bi.line).to_upper())
	sound.play("ding", 1.2, -2.0)
	if autotest:
		print("[autotest] %s incoming stage %d" % ["police" if cop else "boss", run.stage])


func _show_boss_intro() -> void:
	state = S.BOSS_INTRO
	var bi := Data.boss_info(run.stage)
	hud.show_boss_intro("Stage %d boss" % run.stage, bi.full, bi.line, Data.boss_skill_name(run.stage), Data.car_by_id(bi.car).name)
	if autotest:
		print("[autotest] boss intro stage %d: %s" % [run.stage, bi.full])
		_on_act("race", "")


func _update_run(dt: float) -> void:
	if run == null:
		return
	if run.dying > 0.0:
		run.dying -= dt
		if run.dying <= 0.0:
			_end_run("Out of lives")
		return
	run.invuln = maxf(0.0, run.invuln - dt)
	var d := player.v * dt
	run.dist += d
	if run.combo_t > 0.0:
		run.combo_t -= dt
		if run.combo_t <= 0.0:
			run.combo = 0
	if player.v > 33.0:
		run.speed_acc += (player.v - 33.0) * 1.3 * dt * _mult() * run.mods.score
		if run.speed_acc >= 1.0:
			var n := int(run.speed_acc)
			run.speed_acc -= n
			run.score += n
			run.stage_score += n
			if run.phase == "boss":
				run.b_score += n
	_update_fuel(dt)
	if run == null:
		return  # ran dry
	if run.phase == "cruise":
		run.stage_dist += d
		if run.rematch_t > 0.0:
			run.rematch_t -= dt
			if run.rematch_t <= 0.0:
				if _station_busy():
					run.rematch_t = 0.5  # after the fuel stop
				else:
					_start_boss()
					_boss_music(true)
					hud.banner("REMATCH", "OUT-SCORE HIM IN %s" % Fmt.km(run.b_len))
			return
		var r := Data.stage_req(run.stage)
		if (run.stage_dist >= r.d or run.stage_score >= r.p) and not _station_busy():
			_begin_incoming(not run.cop_due and (force_cop or randf() < COP_CHANCE))
	elif run.phase == "incoming":
		# the game carries on; the boss (or the police) turns up when this runs out
		var before := run.inc_t
		run.inc_t -= dt
		if ceili(run.inc_t) != ceili(before) and run.inc_t <= 3.0 and run.inc_t > 0.0:
			sound.play("ding", 1.6, -6.0)
		if run.inc_t <= 0.0:
			if run.inc_cop:
				_start_cop()
			else:
				_start_boss()
				hud.banner(String(run.b_info.full).to_upper(), "OUT-SCORE HIM IN %s" % Fmt.km(run.b_len))
	elif run.phase == "cop":
		run.cop_t += dt
		run.siren_t -= dt
		if run.siren_t <= 0.0:
			run.siren_t = 1.1
			sound.play("siren", 1.0, -4.0)
		if run.cop_t >= COP_TIME:
			run.lives = mini(Data.MAX_LIVES, run.lives + 1)
			_notify("ESCAPED · +1 LIFE", "hot")
			if autotest:
				print("[autotest] cop ESCAPED, traffic pulled over %d times" % _yields)
			hud.banner("ESCAPED", "+1 LIFE")
			sound.play("ding", 1.5, 3.0)
			_end_cop()
	elif run.phase == "boss":
		run.b_dist += d
		if run.b_dist >= run.b_len:
			_end_battle()


# ---------------------------------------------------------------- frame

func _sim_running() -> bool:
	return state == S.PLAY or state == S.OVER or state == S.REFUEL  # the menus show the garage instead


func _process(delta: float) -> void:
	if showroom != "":
		scenery.update_view(0.0, -1.0, 0.0)
		var front := showroom == "front"
		cam.fov = 55.0
		var views := {"rear": [Vector3(-9.5, 2.4, 6.0), Vector3(-1.0, 0.6, -6.0)], "front": [Vector3(9.0, 2.2, -24.0), Vector3(-1.0, 0.6, -9.0)],
			"close": [Vector3(-7.6, 1.5, 2.2), Vector3(-5.4, 0.7, -2.0)],
			"m_front": [Vector3(1.6, 1.3, -21.0), Vector3(-1.8, 0.6, -15.4)], "m_rear": [Vector3(-4.6, 1.5, -7.4), Vector3(-1.8, 0.6, -15.0)],
			"m_side": [Vector3(4.2, 1.1, -14.6), Vector3(-1.8, 0.6, -15.3)],
			"sign": [Vector3(0.0, 5.0, -398.0), Vector3(0.0, 6.4, -420.0)], "bill": [Vector3(4.0, 5.0, -232.0), Vector3(22.0, 9.4, -260.0)],
			"trees": [Vector3(9.0, 2.2, -10.0), Vector3(24.0, 4.0, -50.0)],
			"t_rear": [Vector3(-9.5, 2.4, 6.0), Vector3(-1.0, 0.6, -6.0)], "t_front": [Vector3(9.0, 2.2, -24.0), Vector3(-1.0, 0.6, -9.0)]}
		var v: Array = views.get(showroom, views.rear)
		if showroom == "inspect":
			# several yaws (comma separated) step every 3 s from 7.5 s, for a set of shots in one run
			var yaws := (_inspect[1] if _inspect.size() > 1 else "35").split(",")
			var yi := clampi(int((Time.get_ticks_msec() / 1000.0 - 7.5) / 3.0), 0, yaws.size() - 1)
			var yaw := deg_to_rad(float(yaws[yi]))
			var pitch := deg_to_rad(float(_inspect[2]) if _inspect.size() > 2 else 12.0)
			var dist := float(_inspect[3]) if _inspect.size() > 3 else 7.5
			cam.fov = float(_inspect[4]) if _inspect.size() > 4 else 40.0
			var aim := Vector3(0, 0.6, 0)
			v = [aim + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist, aim]
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.global_transform = Transform3D(Basis(), v[0])
		cam.look_at(v[1])
		hud.set_play_visible(false)
		_check_shots()
		return
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		hud.fps_label.visible = Save.setting("dev_fps")
		hud.fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if state == S.REPLAY:
		_replay_frame(delta)
		_post_speed()
		_check_shots()
		return
	var dt := minf(delta, 0.05)
	if _hitstop > 0.0:
		_hitstop -= delta
		dt *= 0.2
	if _sim_running():
		if crash and state == S.PLAY:
			# slow motion as the car lets go, easing back to real time
			dt *= lerpf(0.35, 1.0, clampf((crash.t - 0.9) / 1.4, 0.0, 1.0))
		if _live() and not autotest and crash == null and run.pit.is_empty():
			_analog_steer(minf(delta, 0.05))  # the hand is read once per frame, in real time, even in hit-stop
		var h := dt / 2.0
		for i in 2:
			t += h
			_update_player(h)
			_update_traffic(h)
			_update_boss(h)
			_collisions()
			if state == S.PLAY:
				_update_run(h)
			if not _sim_running():
				break
	if state == S.PLAY and run:
		_record(dt)
	if state == S.REFUEL and run:
		_pump_frame(delta)
	_probe_gfx(delta)
	if _sim_running():
		_update_time(delta)
	_post_speed()
	var now := Time.get_ticks_msec() / 1000.0
	if _test_crash > 0.0 and now > _test_crash and _live():
		_test_crash = -1.0
		run.lives = 1
		run.invuln = 0.0
		var other: Vehicle = null
		if not traffic.is_empty():
			# test aid: put a car alongside so the crash runs into it
			other = traffic[0]
			var lane := Data.nearest_lane(player.x)
			var nl := lane + (1 if lane < 2 else -1)
			other.lane = nl
			other.tlane = nl
			other.x = Data.LANES[nl]
			other.z = player.z + 6.0
			other.v = player.v * 0.7
			if traffic.size() > 1:  # and one on the side it will be knocked towards
				var o2: Vehicle = traffic[1]
				var l2 := lane - (nl - lane)
				if l2 >= 0 and l2 < 4:
					o2.lane = l2
					o2.tlane = l2
					o2.x = Data.LANES[l2]
					o2.z = player.z + 14.0
					o2.v = player.v * 0.6
		_hit("TEST CRASH", other)
	if _test_replay > 0.0 and now > _test_replay:
		_test_replay = -1.0
		_open_replay()
		if _test_replay_cam != "":
			rp.cam = _test_replay_cam
		print("[autotest] replay opened, %.1f s recorded" % replay.duration())
	shake = maxf(0.0, shake - delta * 2.2)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.8)
	_sync_visuals(delta)
	_update_hud()
	var snd_gas := ((in_gas if _live() else ap_gas) if not autotest else ap_gas) and state != S.PAUSED
	if run and run.pit.get("step", "") == "out":
		snd_gas = true  # driving itself back out onto the highway
	var snd_brake := (in_brake if _live() else ap_brake) if not autotest else ap_brake
	sound.drive(player.v, st.top, snd_gas, snd_brake, state == S.PLAY, delta)
	if autotest:
		_log_t += delta
		if _log_t > 3.0:
			_log_t = 0.0
			if run:
				print("[autotest] t=%.0f stage=%d phase=%s lives=%d score=%d v=%.0fkm/h dist=%.0f cars=%d" % [
					Time.get_ticks_msec() / 1000.0, run.stage, run.phase, run.lives, run.score, player.v * 3.6, run.dist, traffic.size()])
		if crash:
			print("[autotest] crash t=%.2f x=%.2f vel=%s yaw=%.2f roll=%.2f rr=%.2f air=%.2f settled=%s" % [crash.t, player.x, crash.vel, crash.yaw, crash.roll, crash.roll_rate, crash.air, crash.settled])
	if demo_pops and run:
		_demo_t += delta
		if _demo_t > 1.0:
			_demo_t = 0.0
			_notify("NEAR MISS +%d" % randi_range(120, 480), ["", "hot"].pick_random())
	_check_shots()


func _check_shots() -> void:
	if idcolor and burst.size() == 3 and Time.get_ticks_msec() / 1000.0 > burst[0] and burst[1] > 0:
		if _id_log == null:
			_id_log = FileAccess.open(burst[2] + "/log.txt", FileAccess.WRITE)
		var line := "%d" % _burst_i
		for c in traffic:
			var wp := c.model.global_position + Vector3(0, 0.7, -c.l / 2.0)
			if not cam.is_position_behind(wp):
				var sp := cam.unproject_position(wp)
				line += " %d:%.0f:%.0f:%.0f" % [c.get_meta("id", 0), c.z - player.z, sp.x, sp.y]
		_id_log.store_line(line)
		_id_log.flush()
	if burst.size() == 3 and Time.get_ticks_msec() / 1000.0 > burst[0] and burst[1] > 0:
		get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [burst[2], _burst_i])
		_burst_i += 1
		burst[1] -= 1
	for sh in shots:
		if sh[0] > 0.0 and Time.get_ticks_msec() / 1000.0 > sh[0]:
			sh[0] = -1.0
			get_viewport().get_texture().get_image().save_png(sh[1])
	if auto_quit > 0.0 and Time.get_ticks_msec() / 1000.0 > auto_quit:
		print("[autotest] done")
		get_tree().quit()


func _place(c: Vehicle, delta: float) -> void:
	c.model.spin(c.v, delta)
	c.model.position = Vector3(c.x, 0.0, -(c.z - player.z))
	# a car points where it is going (none of them can move sideways while stopped)
	c.model.rotation.y = -(c.yaw if c == player else atan2(c.vx, maxf(c.v, 1.0)) + c.spin)
	c.model.set_wheel_steer(_steer_vis / 7.0 if c == player else clampf(atan2(c.vx, maxf(c.v, 1.0)) * 2.5, -0.5, 0.5))
	c.model.set_brake(c.braking)
	var dir := 0
	if c.tlane >= 0 and c.tlane != c.lane:
		dir = -1 if Data.LANES[c.tlane] < c.x else 1
	c.model.set_signal(dir, fmod(t * 2.6, 1.0) < 0.55)


func _sync_visuals(delta: float) -> void:
	scenery.update_view(player.z, finish_z, delta)
	for c in traffic:
		_place(c, delta)
	if boss:
		_place(boss, delta)
	_place(player, delta)
	if crash:
		player.model.set_crash_pose(player.x, crash.yaw, crash.roll, crash.air)
		_crash_marks()
	else:
		# the kick is a damped spring (about 3 Hz, settling in half a second)
		_kick_v += (-_kick * 150.0 - _kick_v * 9.0) * delta
		_kick += _kick_v * delta
		player.model.set_roll(clampf(-player.v * player.yaw_rate * 0.0035, -0.035, 0.035) + _kick.x * 0.05)
		player.model.set_pitch(clampf(-player_accel * 0.0018, -0.014, 0.02) + _kick.y * 0.05)
		smoke.emitting = false
	skids.update_view(player.z)
	var cam_mode: String = Save.data.cam.mode
	hud.set_speedo_visible(cam_mode != "cockpit")
	# Invulnerability used to blink the car on and off, which in the chase view
	# looked like a car popping in and out at the centre of the road. Now a
	# soft glow pulses on the road under the car instead.
	player.model.visible = not idcolor
	player.model.set_ghost(run != null and run.invuln > 0.0 and run.dying <= 0.0, t)
	player.model.set_gauges(player.v * 3.6 / 300.0, sound.rpm / (sound.redline * 1.1))
	# the wheel in the car turns with your hand however fast you go (at a crawl, with the road wheels)
	var hand := _steer_cmd * 1.5 if (_live() and not autotest) else 0.0
	var phys := player.steer * 7.0
	var vis_to := hand if absf(hand) > absf(phys) else phys
	_steer_vis = lerpf(_steer_vis, clampf(vis_to, -2.6, 2.6) if crash == null else 0.0, 1.0 - exp(-delta * 30.0))
	player.model.set_steer(_steer_vis)
	hud.set_feel(_steer_cmd if (_live() and not autotest) else 0.0, player.yaw, _feel_load)
	_feel_haptics(delta)
	player.model.set_gear(sound.gear, delta)
	var sp := _speed_text()
	player.model.set_display(sound.gear, sp[0], sp[1], ("Fuel %d L" % ceili(run.fuel)) if run else ("%.1f km" % (player.z / 1000.0)))
	# rear-view mirror camera: above the tail of the car, looking back
	var sh: Dictionary = player.model.shape
	var eye := Transform3D(Basis.looking_at(Vector3(0.0, -0.045, 1.0)), Vector3(0.0, float(sh.t) * 0.92, 0.45))
	hud.mirror.half_rate = Save.setting("gfx") != "high"
	hud.mirror.update_view(player.model.global_transform * eye)
	dust.position = Vector3(player.x, 0.2, 0.0)
	dust.emitting = on_shoulder and player.v > 8.0
	_update_camera(delta, cam_mode)


## Tyre marks and smoke while the crashed car slides on its wheels.
func _crash_marks() -> void:
	var c := crash
	var h := Vector2(sin(c.yaw), cos(c.yaw))
	var sl := absf(c.vel.dot(Vector2(h.y, -h.x)))
	var sliding := c.air <= 0.0 and absf(wrapf(c.roll, -PI, PI)) < 0.3 and (sl > 1.6 or c.t < 0.5) and c.vel.length() > 1.0
	var contacts := player.model.wheel_contacts()
	for i in contacts.size():
		if sliding:
			skids.add_point(i, contacts[i].x, player.z - contacts[i].z, clampf(sl / 6.0, 0.4, 1.0))
		else:
			skids.lift(i)
	smoke.emitting = sliding or (c.air <= 0.0 and c.vel.length() > 3.0) or c.settled
	smoke.position = Vector3(player.x, 0.3, -player.l * 0.5)
	if c.settled:  # the wrecked engine smokes once it comes to rest
		var h3 := Vector2(sin(c.yaw), cos(c.yaw))
		smoke.position = Vector3(player.x + h3.x * player.l * 0.35, 0.7, -player.l * 0.5 - h3.y * player.l * 0.35)


func _speed_text() -> Array:
	if Save.setting("units") == "mph":
		return [str(roundi(player.v * 2.23694)), "MPH"]
	return [str(roundi(player.v * 3.6)), "KM/H"]


func _shake_k() -> float:
	return 1.0 if Save.setting("shake") else 0.0


func _vib(ms: int) -> void:
	if Save.setting("haptics"):
		Input.vibrate_handheld(ms)


## What the car feels like through the phone: a rumble-strip buzz on the verge
## (quicker the faster you go) and a faint tremble when the tyres are working at
## their limit, so you can feel the grip run out before the car runs wide.
func _feel_haptics(delta: float) -> void:
	if not Save.setting("haptics") or not _live() or autotest:
		return
	_rumble_t -= delta
	if on_shoulder and player.v > 8.0 and _rumble_t <= 0.0:
		_rumble_t = clampf(3.2 / player.v, 0.05, 0.16)
		Input.vibrate_handheld(22, 0.6)
	_slide_t -= delta
	if _feel_load > 0.93 and not on_shoulder and _slide_t <= 0.0:
		_slide_t = 0.11
		Input.vibrate_handheld(14, 0.3)


## Portrait or landscape, chosen in Settings. The screen is locked to it, so
## turning the phone never switches orientation by accident.
func _apply_orientation() -> void:
	var land: bool = Save.setting("orientation") == "landscape"
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE if land else DisplayServer.SCREEN_PORTRAIT)
	get_tree().root.content_scale_size = Vector2i(1280, 720) if land else Vector2i(720, 1280)
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(_test_win if _test_win != Vector2i.ZERO else (Vector2i(768, 432) if land else Vector2i(432, 768)))
	if hud:
		hud.layout_pedals()


func _update_camera(delta: float, mode: String) -> void:
	if mode == "inspect":  # test view (--cam=inspect): looks across the cabin from the back seat
		var e: Vector3 = player.model.cockpit_eye()
		var from := Vector3(-e.x + 0.15, e.y + 0.05, e.z + 0.75)
		cam.near = 0.02
		cam.fov = 75.0
		cam.global_transform = player.model.body_node().global_transform * Transform3D(Basis.looking_at(Vector3(e.x * 0.6, e.y - 0.35, e.z - 0.7) - from), from)
		return
	if crash and state != S.REPLAY:
		player.model.set_cabin_view(false)
		_crash_cam_t += delta
		# swing round from behind to a rear three-quarter view, then hold
		# (towards the middle of the road, so it never ends up out on the verge)
		var toward := 1.0 if player.x <= 0.0 else -1.0
		_orbit_cam(toward * (0.9 * smoothstep(0.0, 3.5, _crash_cam_t) + 0.04 * _crash_cam_t), 9.5, 3.2)
		return
	var cfg := Save.cam(mode)
	# portrait keeps the horizontal field of view; landscape keeps a vertical one
	var land := get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT if land else Camera3D.KEEP_WIDTH
	var fov_k := 0.82 if land else 1.0
	var speed_k := clampf(player.v / 70.0, 0.0, 1.0)
	# the cockpit looks a little lower than the road, so the wheel and dials are in view
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(float(cfg.angle) - ((4.0 if land else 1.0) if mode == "cockpit" else 0.0)))
	cam_x = lerpf(cam_x, player.x * 0.62, minf(1.0, delta * 3.5))
	sound.set_interior(mode == "cockpit")
	player.model.set_cabin_view(mode == "cockpit")
	if mode == "chase" and run and not run.pit.is_empty():
		# at the fuel stop: drop under the canopy and follow the car right in
		cam.near = 0.3
		cam.fov = cfg.fov * fov_k
		cam_x = lerpf(cam_x, player.x - 1.2, minf(1.0, delta * 3.0))
		var low := Basis(Vector3.RIGHT, deg_to_rad(-11.0))
		cam.global_transform = Transform3D(low, Vector3(cam_x, 3.0, 7.2))
		return
	if mode == "chase":
		# high chase view so the next few cars are readable
		cam.near = 0.5
		cam.fov = (cfg.fov + 12.0 * speed_k) * fov_k
		var jitter := Vector3.ZERO
		if shake > 0.0:
			jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.35 * shake * _shake_k()
		cam.global_transform = Transform3D(pitch, Vector3(cam_x, cfg.height - 0.6 * speed_k, cfg.dist - 1.2 * speed_k) + jitter)
		return
	# hood and cockpit ride on the car body, so they lean and dip with it
	cam.near = 0.05
	cam.fov = (cfg.fov + 8.0 * speed_k) * fov_k
	var eye: Vector3 = player.model.cockpit_eye() if mode == "cockpit" else player.model.hood_eye()
	eye += Vector3(0, cfg.height, -cfg.dist)
	var buzz := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * (0.003 * speed_k + 0.04 * shake) * _shake_k()
	cam.global_transform = player.model.body_node().global_transform * Transform3D(pitch, eye + buzz)


## Speed blur strength for the High graphics pass.
func _post_speed() -> void:
	if _post.material != _post_mat:
		return
	var k := 0.0
	var mode: String = rp.cam if state == S.REPLAY else Save.data.cam.mode
	if (state == S.PLAY or state == S.REPLAY) and crash == null and mode in ["chase", "hood", "cockpit"]:
		k = clampf((player.v - 22.0) / maxf(float(st.top) - 22.0, 1.0), 0.0, 1.0) * (0.6 if mode == "cockpit" else 1.0)
	_blur = lerpf(_blur, k, 0.08)
	_post_mat.set_shader_parameter("speed", _blur)


## Look at the player's car from `ang` radians round from straight behind.
func _orbit_cam(ang: float, radius: float, height: float) -> void:
	var centre := Vector3(player.x, 0.7, -player.l * 0.5)
	cam.near = 0.1
	cam.fov = 60.0
	var land := get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT if land else Camera3D.KEEP_WIDTH
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.25 * shake * _shake_k()
	var from := centre + Vector3(sin(ang) * radius, height, cos(ang) * radius)
	from.x = clampf(from.x, -Data.RAIL - 1.0, Data.RAIL + 1.0)
	cam.global_transform = Transform3D(Basis.looking_at(centre - from), from + jitter)


func _update_hud() -> void:
	if run == null:
		return
	var d := {
		"score": Fmt.num(run.score),
		"mult": "x%.1f" % _mult(),
		"combo_on": run.combo > 0,
		"combo_frac": run.combo_t / run.combo_time if run.combo > 0 else 0.0,
		"lives": run.lives,
		"max_lives": maxi(3 + Save.perm_level("lives"), run.lives),
		"kmh": _speed_text()[0],
		"unit": _speed_text()[1],
		"gear": sound.gear,
		"rpm": sound.rpm / sound.redline,
		"fast": player.v > 33.0,
		"boss": run.phase == "boss",
		"cop": run.phase == "cop",
		"inf": Save.setting("dev_lives") or godmode,
		"fuel": run.fuel / maxf(st.tank, 1.0),
		"fuel_l": "%d L" % ceili(run.fuel),
		"fuel_next": _fuel_next_text(),
		"clock": clock_text(),
	}
	if run.phase == "cop":
		var gp: float = maxf(0.0, player.z - (boss.z + boss.l)) if boss else 99.0
		d.merge({"title": "POLICE PURSUIT", "sub": "ESCAPE IN %d S" % ceili(maxf(0.0, COP_TIME - run.cop_t)),
			"l1": "ESCAPE", "l2": "GAP", "f1": run.cop_t / COP_TIME, "f2": clampf(gp / 60.0, 0.0, 1.0),
			"v1": "%d/%d s" % [int(run.cop_t), int(COP_TIME)], "v2": "%d m" % int(gp), "done1": false, "done2": gp > 30.0})
	elif run.phase == "incoming":
		var mystery: bool = run.inc_cop or not run.cop_due
		var bi := Data.boss_info(run.stage)
		d.merge({"title": ("BOSS OR POLICE?" if mystery else String(bi.full).to_upper()) + " · %d" % ceili(maxf(run.inc_t, 0.0)),
			"sub": "ARRIVING IN %d S" % ceili(maxf(run.inc_t, 0.0)), "l1": "ARRIVES", "l2": "RIVAL",
			"f1": 1.0 - run.inc_t / BOSS_WARN, "f2": 0.0, "v1": "%d s" % ceili(maxf(run.inc_t, 0.0)),
			"v2": "???" if mystery else Data.boss_skill_name(run.stage).to_upper(), "done1": false, "done2": false})
		d.boss = true
	elif run.phase == "boss":
		var mx := maxf(float(maxi(run.b_score, run.b_rival)) * 1.15, 1000.0)
		d.merge({"title": "VS " + String(run.b_info.full).to_upper(), "sub": "FINISH " + Fmt.km(maxf(0.0, run.b_len - run.b_dist), 2),
			"l1": "YOU", "l2": "RIVAL", "f1": run.b_score / mx, "f2": run.b_rival / mx,
			"v1": Fmt.num(run.b_score), "v2": Fmt.num(run.b_rival), "done1": run.b_score > run.b_rival, "done2": false})
	else:
		var r := Data.stage_req(run.stage)
		var d_ok: bool = run.stage_dist >= r.d
		var p_ok: bool = run.stage_score >= r.p
		var sub := "BOSS · " + String(Data.boss_info(run.stage).full).to_upper()
		if run.rematch_t > 0.0:
			sub = "REMATCH INCOMING"
		elif not run.cop_due:
			sub = "BOSS OR POLICE?"
		d.merge({"title": "%s · STAGE %d" % [Data.ROUTES[Data.route].name, run.stage], "sub": sub, "l1": "DIST", "l2": "PTS",
			"f1": run.stage_dist / r.d, "f2": run.stage_score / r.p,
			"v1": "%.1f/%.1f km" % [minf(run.stage_dist, r.d) / 1000.0, r.d / 1000.0],
			"v2": "%s/%s" % [Fmt.num(mini(run.stage_score, int(r.p))), Fmt.num(r.p)],
			"done1": d_ok, "done2": p_ok})
	hud.update_play(d)


# ---------------------------------------------------------------- input

var _steer_val := 0.0     # the command the car gets: the hand's, shaped, plus the quick-movement boost
var _steer_cmd := 0.0     # the same without the boost: what the hand is asking for (drawn on the controls)
var _steer_vis := 0.0     # how far the steering wheel in the car is turned (radians)
var _steer_in := SteerInput.new()
var _arrow_val := 0.0
var _btn_val := 0.0
var _feel_load := 0.0     # how much of its grip the car is using, 0 .. 1
var _rumble_t := 0.0
var _slide_t := 0.0

const SWIPE_RANGE := 130.0  # how far a finger travels sideways for full lock, in screen units


## Reads the steering control once per frame: the hand's movement becomes a
## command from -1 (full left) to 1 (full right) with as little delay as the
## sensors and the screen allow (see SteerInput), and the car gets it at once.
func _analog_steer(dt: float) -> void:
	var mode: String = Save.setting("steer_mode")
	var held := false
	var left := key_left
	var right := key_right
	var swipe := 0.0
	var swiping := false
	for k in touches:
		match touches[k].role:
			"wheel":
				held = true
			"left":
				left = true
			"right":
				right = true
			"steer":
				# swipe: how far the finger has moved sideways from where it landed
				# (the start point trails the finger past full lock, so reversing answers at once)
				swiping = true
				swipe = clampf((float(touches[k].x) - float(touches[k].x0)) / SWIPE_RANGE, -1.0, 1.0)
	hud.wheel.held = held
	hud.arrows.left_on = left
	hud.arrows.right_on = right
	var raw := 0.0
	match mode:
		"wheel":
			if not held:
				hud.wheel.angle = _wheel_return(hud.wheel.angle, dt)
			raw = SteerInput.dead(hud.wheel.angle / SteerWheel.MAX_ANGLE, float(Save.setting("dz_wheel")))
		"tilt":
			var ang := _roll() - _tilt_zero
			_steer_in.tilt_dead = float(Save.setting("dz_tilt"))
			raw = _steer_in.tilt(-ang if Save.setting("tilt_invert") else ang, dt, Input.get_gyroscope().z)
		"stick":
			raw = hud.stick.value()
		"buttons":
			var want := (1.0 if right else 0.0) - (1.0 if left else 0.0)
			_btn_val = move_toward(_btn_val, want, (7.0 if want != 0.0 else 14.0) * dt)  # eases in, lets go quickly
			raw = _btn_val
		_:  # swipe
			raw = SteerInput.dead(swipe, float(Save.setting("dz_swipe"))) if swiping else 0.0
	if _steer_test != "":
		raw = _steer_test_raw(dt, raw)
	# the arrow keys steer in every mode (desktop testing)
	if mode != "buttons" and (key_left or key_right):
		_arrow_val = move_toward(_arrow_val, (1.0 if key_right else 0.0) - (1.0 if key_left else 0.0), 6.0 * dt)
		raw = _arrow_val
	else:
		_arrow_val = 0.0
	_steer_cmd = SteerInput.shape(raw, float(Save.setting("steer_sens")))
	_steer_val = _steer_in.boosted(_steer_cmd, dt, SteerModel.feel(Save.setting("steer_feel")).lead * (0.6 if mode == "tilt" else 1.0))


var _steer_test := ""
var _steer_test_v := 30.0
var _steer_test_t := 0.0
var _steer_test_phase := 0
var _steer_test_x0 := 0.0
var _steer_test_t0 := 0.0


## A scripted hand for --steer-test, fed through the real pipeline; logs what the car does.
func _steer_test_raw(dt: float, hand := 0.0) -> float:
	Save.data.settings.steer_sens = 1.0
	_steer_test_t += dt
	var tt := _steer_test_t
	var raw := 0.0
	match _steer_test:
		"pass":  # the real control's own value goes through (to check the dead zones and the controls themselves)
			raw = hand
		"flick":  # a 60 ms flick to half lock at 1 s, held
			raw = 0.5 * clampf((tt - 1.0) / 0.06, 0.0, 1.0)
		"full":  # a 60 ms flick to full lock at 1 s, held
			raw = clampf((tt - 1.0) / 0.06, 0.0, 1.0)
		"lane":  # hard right, then hard left until the nose is back along the road, then let go
			match _steer_test_phase:
				0:
					if tt >= 1.0:
						_steer_test_phase = 1
						_steer_test_x0 = player.x
						_steer_test_t0 = tt
				1:
					raw = clampf((tt - _steer_test_t0) / 0.06, 0.0, 1.0)
					if tt - _steer_test_t0 >= 0.5:
						_steer_test_phase = 2
				2:
					raw = -clampf((tt - _steer_test_t0 - 0.5) / 0.06 + 0.0, 0.0, 1.0)
					if player.yaw <= 0.0:
						_steer_test_phase = 3
						print("[steer] lane change: %.2f m in %.2f s, nose %.2f deg" % [player.x - _steer_test_x0, tt - _steer_test_t0, rad_to_deg(player.yaw)])
	var mode: String = Save.setting("steer_mode")
	if mode == "stick":  # show the control being used, so the feel marks can be seen in a screenshot
		var vs := get_viewport().get_visible_rect().size
		if not hud.stick.active:
			hud.stick.press(Vector2(vs.x * 0.3, vs.y * 0.62))
		hud.stick.drag(hud.stick.origin + Vector2(raw * hud.stick.radius() * 0.8, 0.0))
	elif mode == "wheel":
		hud.wheel.angle = raw * SteerWheel.MAX_ANGLE
	print("[steer] t=%.3f raw=%.3f cmd=%.3f boosted=%.3f wheel=%.4f yaw=%.4f course=%.4f x=%.3f vx=%.3f v=%.1f load=%.2f" % [tt, raw, SteerInput.shape(raw, float(Save.setting("steer_sens"))), _steer_val, player.steer, player.yaw, player.course, player.x, player.vx, player.v, _feel_load])
	return raw


## The on-screen wheel, let go of, runs back to centre like a real one: a
## spring that is stiffer the faster the car goes.
func _wheel_return(angle: float, dt: float) -> float:
	var a := angle * exp(-(9.0 + 0.2 * player.v) * dt)
	return 0.0 if absf(a) < 0.01 else a


var _tilt_zero := 0.0
var fake_tilt := 0.0  # --fake-tilt=DEGREES: pretend the phone is tilted (test aid)


## The phone's left-right roll in radians, from the accelerometer (Godot
## reports it relative to the current screen orientation).
func _roll() -> float:
	var a := Input.get_accelerometer()
	if a.length() < 1.0:
		return _tilt_zero + deg_to_rad(fake_tilt)
	return atan2(a.x, sqrt(a.y * a.y + a.z * a.z)) + deg_to_rad(fake_tilt)


## Hold the phone however is comfortable: the angle at the start of a run
## (or when resuming) counts as straight ahead.
func _calibrate_tilt() -> void:
	_tilt_zero = _roll() - deg_to_rad(fake_tilt)
	_steer_in.reset()


func _refresh_inputs() -> void:
	if hud and hud.stick.active and not touches.values().any(func(t: Dictionary) -> bool: return t.role == "stick"):
		hud.stick.release()  # its finger was let go of (or the touches were cleared)
	var tg := false
	var tb := false
	for k in touches:
		if touches[k].role == "gas":
			tg = true
		elif touches[k].role == "brake":
			tb = true
	in_gas = tg or key_gas
	in_brake = tb or key_brake
	hud.set_pedals(in_gas and state == S.PLAY, in_brake and state == S.PLAY)


const EDGE := 36.0        # a swipe that starts this close to a screen edge goes back
const EDGE_PULL := 110.0  # and has to travel this far inwards


## Swipe in from the left or right edge of the screen to go back.
func _edge_swipe(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		var w := get_viewport().get_visible_rect().size.x
		if e.pressed and (e.position.x < EDGE or e.position.x > w - EDGE):
			_edge = {"i": e.index, "x0": e.position.x, "dir": 1.0 if e.position.x < EDGE else -1.0}
		elif not e.pressed and not _edge.is_empty() and e.index == _edge.i:
			_edge = {}
	elif event is InputEventScreenDrag and not _edge.is_empty() and (event as InputEventScreenDrag).index == _edge.i:
		var d := ((event as InputEventScreenDrag).position.x - float(_edge.x0)) * float(_edge.dir)
		if d > EDGE_PULL:
			_edge = {}
			touches.clear()
			_refresh_inputs()
			if state != S.PLAY:  # mid-drive it must not pause by accident
				_go_back()
				get_viewport().set_input_as_handled()
			return true
	return not _edge.is_empty()


var _edge := {}


func _input(event: InputEvent) -> void:
	if _edge_swipe(event) and state != S.PLAY:
		return  # an edge swipe is not a tap on whatever is underneath
	if state == S.REPLAY:
		_replay_input(event)
		return
	if garage.active and (state == S.MENU or state == S.GARAGE):
		# drag the 3D view (not the panels) to look round the car
		if event is InputEventScreenTouch:
			var e := event as InputEventScreenTouch
			if e.pressed and not hud.ui_blocks(e.position):
				_orbit_i = e.index
			elif not e.pressed and e.index == _orbit_i:
				_orbit_i = -1
		elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _orbit_i:
			var e := event as InputEventScreenDrag
			garage.orbit(e.relative.x, e.relative.y)
		elif event is InputEventMouseMotion and not OS.has_feature("mobile") and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) \
				and not hud.ui_blocks((event as InputEventMouseMotion).position):
			garage.orbit((event as InputEventMouseMotion).relative.x, (event as InputEventMouseMotion).relative.y)
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var role := hud.role_at(e.position) if state == S.PLAY else "ui"
			if role == "":
				role = "steer"
			touches[e.index] = {"role": role, "x": e.position.x, "x0": e.position.x}
			if role == "stick":
				hud.stick.press(e.position)
			if role == "wheel":
				touches[e.index]["a"] = (e.position - hud.wheel.centre()).angle()
		else:
			var tt: Variant = touches.get(e.index)
			touches.erase(e.index)
			if tt and tt.role == "stick":
				hud.stick.release()
		_refresh_inputs()
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		var tt: Variant = touches.get(e.index)
		if tt == null:
			return
		tt.x = e.position.x
		if tt.role == "steer":
			var dx: float = e.position.x - float(tt.x0)
			if absf(dx) > SWIPE_RANGE:
				tt.x0 = e.position.x - signf(dx) * SWIPE_RANGE  # the start point trails the finger past full lock: reversing answers at once
		if tt.role == "stick":
			hud.stick.drag(e.position)
		if tt.role == "wheel":
			var a: float = (e.position - hud.wheel.centre()).angle()
			hud.wheel.angle = clampf(hud.wheel.angle + wrapf(a - tt.a, -PI, PI), -SteerWheel.MAX_ANGLE, SteerWheel.MAX_ANGLE)
			tt.a = a
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		match k.physical_keycode:
			KEY_UP, KEY_W:
				key_gas = k.pressed
			KEY_DOWN, KEY_S, KEY_SPACE:
				key_brake = k.pressed
			KEY_LEFT, KEY_A:
				key_left = k.pressed
			KEY_RIGHT, KEY_D:
				key_right = k.pressed
			KEY_ESCAPE, KEY_P:
				if k.pressed:
					if state == S.PLAY:
						_pause()
					elif state == S.PAUSED:
						_resume()
		_refresh_inputs()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if state == S.PLAY and not autotest:
				_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_go_back()


## The back button, or a swipe in from the edge of the screen.
func _go_back() -> void:
	if state == S.REPLAY:
		_close_replay()
	elif state == S.REFUEL:
		_pay_and_go()
	elif hud.screens.pedals.visible:
		_on_act("pedal_done", "")
	elif hud.screens.settings.visible:
		_on_act("settings_back", "")
	elif hud.screens.help.visible or hud.screens.map.visible:
		_on_act("menu", "")
	elif state == S.PLAY:
		_pause()
	elif state == S.PAUSED:
		_resume()
	elif state == S.GARAGE or state == S.OVER:
		_go_menu()


# ---------------------------------------------------------------- screens

func _go_menu() -> void:
	_boss_music(false, 1.0)
	_end_crash()
	_free_retired()
	state = S.MENU
	hud.set_play_visible(false)
	hud.render_menu()
	hud.show_screen("menu")
	_enter_garage()


## Show the workshop with the selected car (or another car to look at).
func _enter_garage(view_id := "") -> void:
	if showroom != "" or _inspect.size() > 0:
		return
	var c := Data.car_by_id(view_id if view_id != "" else Save.data.selected)
	if garage.car == null or garage.get_meta("car", "") != c.id + str(Save.car_color(c)) + str(Save.car_style(c)):
		garage.set_car(c, Save.car_color(c), Save.car_style(c))
		garage.set_meta("car", c.id + str(Save.car_color(c)) + str(Save.car_style(c)))
	garage.set_active(true)
	sound.set_enabled(false)  # no engine drone in the garage


func _leave_garage() -> void:
	if garage.active:
		garage.set_active(false)
		cam.current = true
		sound.set_enabled(Save.data.sound)


func _pause() -> void:
	if state != S.PLAY:
		return
	state = S.PAUSED
	if _music:
		_music.stream_paused = true
	touches.clear()
	key_gas = false
	key_brake = false
	_refresh_inputs()
	hud.show_pause(Fmt.num(run.score), Fmt.km(run.dist), str(run.stage))
	hud.render_cam()


func _resume() -> void:
	if state != S.PAUSED:
		return
	state = S.PLAY
	if _music:
		_music.stream_paused = false
	hud.show_screen("")
	_calibrate_tilt()


var _reset_armed := 0  # msec until which a second RESET PROGRESS tap wipes the save


func _dev_tool(id: String) -> void:
	match id:
		"cars":
			Save.unlock_all_cars()
			hud.dev_note("Every car is unlocked and in your Garage.")
		"upgrades":
			Save.max_all_upgrades()
			_compute_stats()
			hud.dev_note("Every Garage upgrade is at its top level.")
		"cash":
			Save.data.cash += 100000
			Save.persist()
			hud.dev_note("Added $100,000. You now have $%s." % Fmt.num(Save.data.cash))
		"reset":
			if Time.get_ticks_msec() < _reset_armed:
				_reset_armed = 0
				Save.reset_progress()
				if run == null:
					_set_player_car()
				_compute_stats()
				hud.dev_note("Progress reset. Settings were kept.")
			else:
				_reset_armed = Time.get_ticks_msec() + 3000
				hud.dev_note("Tap RESET PROGRESS again within 3 seconds to wipe cars, cash and upgrades.")
				return
	sound.play("ding", 1.4)


func _on_act(action: String, arg: String) -> void:
	# a drag that scrolled a menu must not also press the button it started on
	if hud and hud.clicks_blocked() and not action in ["cam_set", "set", "cam_save", "save", "pause", "cam_cycle", "rp", "rp_scrub", "pump", "fill", "pay"]:
		return
	match action:
		"start":
			_start_run()
		"garage":
			_end_crash()
			_free_retired()
			state = S.GARAGE
			if arg != "":
				hud.garage_tab = arg
			hud.render_garage()
			hud.show_screen("garage")
			_enter_garage()
		"help":
			hud.show_screen("help")
		"map":
			state = S.MENU
			hud.render_map()
			hud.show_screen("map")
			hud.call_deferred("_apply_safe_area")
			get_tree().create_timer(0.15).timeout.connect(hud._apply_safe_area)  # again once the panel has its real size
		"route":
			var ri := int(arg)
			if ri < int(Save.data.get("routes", 1)):
				Save.data.route_sel = ri
				Save.persist()
				sound.play("ding", 1.4, -8.0)
				hud.render_map()
			else:
				hud.render_map()
				hud.map_note("Locked. Beat %s, the final boss on the highway before it, to open this one." % Data.BOSSES[3].name)
		"drive":
			_start_run()
		"preview":
			_enter_garage(arg)
		"paint", "rim", "rim_color", "rim_reset":
			var key: String = {"paint": "color", "rim": "rim", "rim_color": "rim_color"}.get(action, "")
			if action == "rim_reset":
				Save.set_look(Save.data.selected, "rim", "")
				Save.set_look(Save.data.selected, "rim_color", "")
			else:
				Save.set_look(Save.data.selected, key, arg)
			sound.play("ding", 1.5, -8.0)
			_enter_garage()
			hud.render_garage()
		"menu":
			_go_menu()
		"tab":
			hud.garage_tab = arg
			hud.render_garage()
			if state == S.GARAGE:
				_enter_garage()  # back to your own car after looking at others
		"buy":
			var c := Data.car_by_id(arg)
			if Save.data.cash >= c.price and not Save.owns(arg):
				Save.data.cash -= c.price
				Save.data.owned.append(arg)
				Save.data.selected = arg
				Save.persist()
				_set_player_car()
				_compute_stats()
				sound.play("ding", 1.5)
				_enter_garage()
			hud.render_garage()
		"select":
			if Save.owns(arg):
				Save.data.selected = arg
				Save.persist()
				_set_player_car()
				_compute_stats()
				_enter_garage()
			hud.render_garage()
		"perm":
			for p in Data.PERM:
				if p.id == arg:
					var lv := Save.perm_level(arg)
					var cost := Data.perm_cost(p, lv)
					if lv < p.max and Save.data.cash >= cost:
						Save.data.cash -= cost
						Save.set_perm(arg, lv + 1)  # this car only
						Save.persist()
						_compute_stats()
						sound.play("ding", 1.3 + lv * 0.08)
			hud.render_garage()
		"settings":
			_leave_garage()
			if arg != "":
				hud.settings_tab = arg  # e.g. --open=settings:camera
			hud.render_settings()
			hud.show_screen("settings")
		"settings_back":
			Save.persist()
			if state == S.PAUSED:
				hud.show_screen("pause")
			else:
				_go_menu()
		"set":
			var kv := arg.split("=")
			Save.data.settings[kv[0]] = float(kv[1])
			if kv[0] == "pedal_scale" or kv[0] == "mirror_scale":
				hud.layout_pedals()
			hud.render_settings()
		"save":
			Save.persist()
		"toggle":
			match arg:
				"sound":
					Save.data.sound = not Save.data.sound
					sound.set_enabled(Save.data.sound)
					if not Save.data.sound and _music:
						_music.stop()
				"assist":
					Save.data.assist = not Save.data.assist
				"steer_feel":
					Save.data.settings.steer_feel = SteerModel.FEEL_ORDER[(SteerModel.FEEL_ORDER.find(Save.setting("steer_feel")) + 1) % SteerModel.FEEL_ORDER.size()]
				"steer_mode":
					var order := ["swipe", "wheel", "buttons", "tilt", "stick"]
					Save.data.settings.steer_mode = order[(order.find(Save.setting("steer_mode")) + 1) % order.size()]
					hud.layout_pedals()
				"orientation":
					Save.data.settings.orientation = "portrait" if Save.setting("orientation") == "landscape" else "landscape"
					_apply_orientation()
				"units":
					Save.data.settings.units = "kmh" if Save.setting("units") == "mph" else "mph"
				"mirror":
					Save.data.settings.mirror = not Save.setting("mirror")
					hud.layout_pedals()
				"gfx":
					var levels := ["high", "medium", "low"]
					Save.data.settings.gfx = levels[(levels.find(Save.setting("gfx")) + 1) % levels.size()]
					_apply_gfx()
				_:
					Save.data.settings[arg] = not Save.setting(arg)
			Save.persist()
			hud.render_settings()
		"dev":
			_dev_tool(arg)
		"pump":
			if state == S.REFUEL:
				pump.on = arg == "on"
				pump.auto = false
		"fill":
			if state == S.REFUEL:
				pump.on = true
				pump.auto = true
		"pay":
			if state == S.REFUEL:
				_pay_and_go()
		"replay":
			_open_replay()
		"rp":
			if state == S.REPLAY:
				_replay_act(arg)
		"rp_scrub":
			if state == S.REPLAY:
				rp.play = false
				rp.t = lerpf(replay.start_t(), replay.end_t(), clampf(float(arg), 0.0, 1.0))
		"pedal_edit":
			hud.begin_pedal_edit()
		"pedal_done":
			hud.end_pedal_edit()
			Save.persist()
			hud.render_settings()
			hud.show_screen("settings")
		"pedal_moved":
			Save.persist()
		"pedal_swap":
			hud.swap_pedals()
			Save.persist()
		"mirror_size":
			var ms := float(Save.setting("mirror_scale")) + (0.1 if arg == "+" else -0.1)
			Save.data.settings.mirror_scale = clampf(ms, 0.6, 1.8)
			hud.layout_pedals()
			Save.persist()
		"pedal_reset":
			Save.data.settings.gas_pos = []
			Save.data.settings.brake_pos = []
			Save.data.settings.mirror_pos = []
			hud.layout_pedals()
			Save.persist()
		"sound":
			Save.data.sound = not Save.data.sound
			Save.persist()
			sound.set_enabled(Save.data.sound)
			hud.render_menu()
		"assist":
			Save.data.assist = not Save.data.assist
			Save.persist()
			hud.render_menu()
		"race":
			if state == S.BOSS_INTRO:
				state = S.PLAY
				hud.show_screen("")
				_start_boss()
		"boon":
			if state == S.PICK:
				_apply_boon(arg)
		"pause":
			_pause()
		"cam_cycle":
			var i: int = (Data.CAM_MODES.find(Save.data.cam.mode) + 1) % Data.CAM_MODES.size()
			Save.data.cam.mode = Data.CAM_MODES[i]
			Save.persist()
			hud.pop(String(Data.CAM_NAMES[Save.data.cam.mode]).to_upper() + " VIEW", "small")
			hud.render_cam()
		"cam_mode":
			Save.data.cam.mode = arg
			Save.persist()
			hud.render_cam()
		"cam_set":
			var kv := arg.split("=")
			Save.cam(Save.data.cam.mode)[kv[0]] = float(kv[1])
			hud.render_cam()
		"cam_save":
			Save.persist()
		"cam_reset":
			Save.data.cam[Save.data.cam.mode] = Data.CAM_DEFAULTS[Save.data.cam.mode].duplicate()
			Save.persist()
			hud.render_cam()
		"resume":
			_resume()
		"quit":
			if run:
				state = S.PLAY
				hud.show_screen("")
				_end_run("You ended the run")


# ---------------------------------------------------------------- replay

const REPLAY_CAMS := ["chase", "hood", "cockpit", "free", "keys", "tv", "drone"]
const REPLAY_CAM_NAMES := {"chase": "CHASE", "hood": "HOOD", "cockpit": "COCKPIT", "free": "FREE CAM", "keys": "KEYFRAMES", "tv": "TRACKSIDE", "drone": "DRONE"}
const FREE_CAM := {"yaw": 0.7, "pitch": 0.28, "dist": 9.0, "px": 0.0, "py": 0.0, "pz": 0.0, "fov": 55.0}

## Camera keyframes for the replay, by recording time. Kept while the run's
## recording lasts, so closing and reopening the editor keeps your shot.
var replay_keys: Array[Dictionary] = []
const REPLAY_SPEEDS := [1.0, 0.5, 0.25, 2.0]

var rp := {}  # replay editor state while state == S.REPLAY


## Store one frame of the run for the replay.
func _record(dt: float) -> void:
	if not replay.tick(dt):
		return
	var pv := PackedFloat32Array()
	pv.resize(13)
	pv[Replay.P_X] = player.x
	pv[Replay.P_Z] = player.z
	pv[Replay.P_V] = player.v
	pv[Replay.P_VX] = player.vx
	if crash:
		pv[Replay.P_YAW] = crash.yaw
		pv[Replay.P_ROLL] = crash.roll
		pv[Replay.P_AIR] = crash.air
		pv[Replay.P_CRASH] = 1.0
	else:
		pv[Replay.P_YAW] = player.yaw
		pv[Replay.P_ROLL] = clampf(-player.v * player.yaw_rate * 0.0035, -0.035, 0.035)
		pv[Replay.P_PITCH] = clampf(-player_accel * 0.0028, -0.022, 0.03)
	var live := _live()
	pv[Replay.P_GAS] = 1.0 if (in_gas if live and not autotest else ap_gas) else 0.0
	pv[Replay.P_BRAKE] = 1.0 if player.braking else 0.0
	pv[Replay.P_STEER] = _steer_vis if crash == null else 0.0
	pv[Replay.P_GHOST] = 1.0 if run.invuln > 0.0 and run.dying <= 0.0 else 0.0
	var cars := {}
	var all: Array[Vehicle] = traffic.duplicate()
	if boss:
		all.append(boss)
	for c in all:
		if c.z > player.z - 130.0 and c.z < player.z + 420.0:
			var dir := 0
			if c.tlane >= 0 and c.tlane != c.lane:
				dir = -1 if Data.LANES[c.tlane] < c.x else 1
			cars[c.id] = PackedFloat32Array([c.x, c.z, c.v, c.vx, 1.0 if c.braking else 0.0, dir])
	var f := {"p": pv, "cars": cars, "finish": finish_z, "gear": sound.gear, "rpm": sound.rpm}
	if boss and boss.is_cop:
		f["cop"] = boss.id
	replay.push(f)
	# forget cars that have dropped out of the recording
	for id in _retired.keys():
		if replay.clock - float(_retired[id]) > Replay.LENGTH + 1.0:
			if _models.has(id):
				(_models[id] as CarModel).queue_free()
				_models.erase(id)
			_retired.erase(id)


func _open_replay() -> void:
	if replay.empty():
		hud.pop("NOTHING RECORDED YET", "small")
		return
	rp = {"from": state, "t": replay.start_t(), "play": true, "speed": 1.0, "cam": "chase",
		"a": replay.start_t(), "b": replay.end_t(), "tv_z": -1.0, "tv_x": 0.0, "hide": false,
		"live": [player.x, player.z, player.v, player.vx], "touch": {}, "fc": FREE_CAM.duplicate()}
	if Save.data.cam.mode in REPLAY_CAMS:
		rp.cam = Save.data.cam.mode
	state = S.REPLAY
	touches.clear()
	key_gas = false
	key_brake = false
	_refresh_inputs()
	sparks.emitting = false
	smoke.emitting = false
	dust.emitting = false
	scenery.begin_replay()
	hud.show_screen("")
	hud.set_play_visible(false)
	hud.show_replay(true)
	_replay_show(rp.t, 0.0)


func _close_replay() -> void:
	if state != S.REPLAY:
		return
	_replay_ui(true)  # restores name tags hidden for a clean view
	scenery.end_replay()
	var lv: Array = rp.live
	player.x = lv[0]
	player.z = lv[1]
	player.v = lv[2]
	player.vx = lv[3]
	player.yaw = asin(clampf(player.vx / maxf(player.v, 1.0), -0.5, 0.5))
	player.course = player.yaw
	for id in _models:
		(_models[id] as CarModel).visible = not _retired.has(id)
	if crash == null:
		player.model.clear_crash_pose()
	skids.visible = true
	sound.quiet = false
	state = rp.from
	hud.show_replay(false)
	if run and crash == null:
		hud.set_play_visible(true)
	match state:
		S.OVER:
			hud.show_screen("over")
		S.PAUSED:
			hud.show_screen("pause")
	_sync_visuals(0.0)


func _replay_frame(delta: float) -> void:
	var prev: float = rp.t
	if rp.play:
		rp.t += delta * rp.speed
		if rp.t >= rp.b:
			rp.t = rp.a  # loop the clip
			prev = rp.t
	_replay_show(rp.t, rp.t - prev)
	_replay_cam(delta)
	var s := replay.start_t()
	var e := replay.end_t()
	var span := maxf(e - s, 0.001)
	hud.update_replay({"pos": (rp.t - s) / span, "a": (rp.a - s) / span, "b": (rp.b - s) / span,
		"time": "%.1f s" % (rp.t - rp.a), "clip": "%.1f s" % (rp.b - rp.a), "play": rp.play,
		"speed": {1.0: "1x", 0.5: "0.5x", 0.25: "0.25x", 2.0: "2x"}.get(rp.speed, "1x"),
		"keys": replay_keys.map(func(k: Dictionary) -> float: return (float(k.t) - s) / span), "nkeys": replay_keys.size(), "cam": REPLAY_CAM_NAMES[rp.cam], "len": span})


## Put the world, every car and the player where they were at time t.
func _replay_show(t: float, dt: float) -> void:
	var f := replay.sample(t)
	if f.is_empty():
		return
	var p: PackedFloat32Array = f.p
	var pz: float = p[Replay.P_Z]
	player.x = p[Replay.P_X]
	player.z = pz
	player.v = p[Replay.P_V]
	player.vx = p[Replay.P_VX]
	scenery.update_view(pz, f.finish, dt)
	var crashed := p[Replay.P_CRASH] > 0.5
	skids.visible = crashed
	skids.update_view(pz)
	var seen := {}
	var cars: Dictionary = f.cars
	for id in cars:
		var m: CarModel = _models.get(id)
		if m == null:
			continue
		var v: PackedFloat32Array = cars[id]
		m.visible = true
		m.position = Vector3(v[Replay.C_X], 0.0, -(v[Replay.C_Z] - pz))
		m.rotation.y = -atan2(v[Replay.C_VX], maxf(v[Replay.C_V], 1.0))
		m.spin(v[Replay.C_V], absf(dt))
		m.set_brake(v[Replay.C_BRAKE] > 0.5)
		m.set_signal(roundi(v[Replay.C_SIG]), fmod(t * 2.6, 1.0) < 0.55)
		seen[id] = true
	for id in _models:
		if not seen.has(id):
			(_models[id] as CarModel).visible = false
	if f.has("cop") and _models.has(f.cop):
		(_models[f.cop] as CarModel).flash_lightbar(t)
	var pm := player.model
	pm.spin(p[Replay.P_V], absf(dt))
	if crashed:
		pm.set_crash_pose(p[Replay.P_X], p[Replay.P_YAW], p[Replay.P_ROLL], p[Replay.P_AIR])
	else:
		pm.clear_crash_pose()
		pm.position = Vector3(p[Replay.P_X], 0.0, 0.0)
		pm.rotation.y = -p[Replay.P_YAW]
		pm.set_roll(p[Replay.P_ROLL])
		pm.set_pitch(p[Replay.P_PITCH])
	pm.set_brake(p[Replay.P_BRAKE] > 0.5)
	pm.set_ghost(p[Replay.P_GHOST] > 0.5, t)
	pm.set_steer(p[Replay.P_STEER])
	pm.set_wheel_steer(p[Replay.P_STEER] / 7.0)
	pm.set_gear(int(f.gear), absf(dt))
	pm.set_gauges(p[Replay.P_V] * 3.6 / 300.0, float(f.rpm) / (sound.redline * 1.1))
	sound.quiet = not rp.play
	sound.drive(p[Replay.P_V], st.top, p[Replay.P_GAS] > 0.5, p[Replay.P_BRAKE] > 0.5, true, absf(dt) if absf(dt) > 0.0 else 0.016)


func _replay_cam(delta: float) -> void:
	match rp.cam:
		"free":
			_free_cam(rp.fc)
		"keys":
			if replay_keys.is_empty():
				_free_cam(rp.fc)
			else:
				_free_cam(_keyed_cam(rp.t))
		"tv":
			# a camera operator at the roadside who pans and zooms as the car goes by
			var pz := player.z
			if rp.tv_z < 0.0 or pz - rp.tv_z > 40.0 or rp.tv_z - pz > 160.0:
				rp.tv_z = pz + 70.0 + player.v * 0.8
				rp.tv_x = (Data.RAIL + 2.5) * (1.0 if randf() < 0.5 else -1.0)
			var from := Vector3(rp.tv_x, 1.5, -(rp.tv_z - pz))
			var centre := Vector3(player.x, 0.8, -player.l * 0.5)
			var dist := from.distance_to(centre)
			cam.near = 0.2
			cam.fov = clampf(rad_to_deg(2.0 * atan(5.5 / dist)), 6.0, 55.0)
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.global_transform = Transform3D(Basis.looking_at(centre - from), from)
		"drone":
			var centre := Vector3(player.x, 0.0, -player.l * 0.5)
			var from := centre + Vector3(0.0, 26.0, 16.0)
			cam.near = 0.5
			cam.fov = 50.0
			cam.global_transform = Transform3D(Basis.looking_at(centre + Vector3(0, 0, -14.0) - from), from)
		_:
			_update_camera(delta, rp.cam)


func _replay_act(arg: String) -> void:
	match arg:
		"play":
			rp.play = not rp.play
			if rp.play and rp.t >= rp.b - 0.05:
				rp.t = rp.a
		"back", "fwd":
			rp.play = false
			rp.t = clampf(rp.t + (-1.0 if arg == "back" else 1.0) / Replay.RATE, replay.start_t(), replay.end_t())
		"speed":
			rp.speed = REPLAY_SPEEDS[(REPLAY_SPEEDS.find(rp.speed) + 1) % REPLAY_SPEEDS.size()]
		"cam":
			var was: String = rp.cam
			rp.cam = REPLAY_CAMS[(REPLAY_CAMS.find(rp.cam) + 1) % REPLAY_CAMS.size()]
			rp.tv_z = -1.0
			if rp.cam == "free":
				_grab_free_cam(was)
		"key_add":
			if rp.cam != "free" and rp.cam != "keys":
				_grab_free_cam(rp.cam)
			var cur: Dictionary = rp.fc if rp.cam != "keys" or replay_keys.is_empty() else _keyed_cam(rp.t)
			var key := cur.duplicate()
			key["t"] = rp.t
			for i in range(replay_keys.size() - 1, -1, -1):
				if absf(float(replay_keys[i].t) - rp.t) < 0.1:
					replay_keys.remove_at(i)  # replace a key at the same moment
			replay_keys.append(key)
			replay_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
			rp.cam = "keys"
			hud.pop("KEYFRAME %d SET" % replay_keys.size(), "small")
		"key_del":
			var best := -1
			for i in replay_keys.size():
				if absf(float(replay_keys[i].t) - rp.t) < 0.4 and (best < 0 or absf(float(replay_keys[i].t) - rp.t) < absf(float(replay_keys[best].t) - rp.t)):
					best = i
			if best >= 0:
				replay_keys.remove_at(best)
				hud.pop("KEYFRAME DELETED", "small")
			else:
				hud.pop("MOVE THE PLAYHEAD ONTO A KEYFRAME", "small")
		"key_prev", "key_next":
			rp.play = false
			var nxt := arg == "key_next"
			var pick := -1.0
			for k in replay_keys:
				var kt: float = k.t
				if (nxt and kt > rp.t + 0.02 and (pick < 0.0 or kt < pick)) or (not nxt and kt < rp.t - 0.02 and (pick < 0.0 or kt > pick)):
					pick = kt
			if pick >= 0.0:
				rp.t = pick
		"key_clear":
			replay_keys.clear()
			if rp.cam == "keys":
				rp.cam = "free"
			hud.pop("KEYFRAMES CLEARED", "small")
		"in":
			rp.a = minf(rp.t, rp.b - 0.5)
		"out":
			rp.b = maxf(rp.t, rp.a + 0.5)
		"clear":
			rp.a = replay.start_t()
			rp.b = replay.end_t()
		"start":
			rp.t = rp.a
		"hide":
			_replay_ui(false)
		"show":
			_replay_ui(true)
		"done":
			_close_replay()


## Clean view: no controls and no floating name tags or score messages, so
## the clip looks like footage. The camera can still be moved; a tap (or the
## faint SHOW UI button) brings the controls back.
func _replay_ui(on: bool) -> void:
	rp.hide = not on
	hud.replay_ui_visible(on)
	var models: Array = _models.values()
	models.append(player.model)
	for m in models:
		for ch in (m as Node).get_children():
			if ch is Label3D:
				(ch as Label3D).visible = on


func _replay_input(event: InputEvent) -> void:
	var touch: Dictionary = rp.touch
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed and not hud.replay_ui_at(e.position):
			touch[e.index] = e.position
			rp["tap"] = [e.position, Time.get_ticks_msec()]
		elif not e.pressed:
			touch.erase(e.index)
			# a quick tap without dragging brings the hidden controls back
			if rp.hide and rp.has("tap") and e.position.distance_to(rp.tap[0]) < 14.0 and Time.get_ticks_msec() - int(rp.tap[1]) < 350:
				_replay_ui(true)
			rp.erase("tap")
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if not touch.has(e.index):
			return
		_take_free_cam()
		var fc: Dictionary = rp.fc
		if touch.size() == 1:
			# one finger: swing round the car
			fc.yaw = float(fc.yaw) - e.relative.x * 0.008
			fc.pitch = clampf(float(fc.pitch) + e.relative.y * 0.006, -0.08, 1.5)
		else:
			# two fingers: pinch to move in and out, drag together to pan
			var ids := touch.keys()
			var other: Vector2 = touch[ids[0] if ids[0] != e.index else ids[1]]
			var before: float = (touch[e.index] as Vector2).distance_to(other)
			var after := e.position.distance_to(other)
			if before > 10.0 and after > 10.0:
				fc.dist = clampf(float(fc.dist) * before / after, 2.5, 60.0)
			var yaw: float = fc.yaw
			var k: float = float(fc.dist) * 0.0006
			fc.px = float(fc.px) - cos(yaw) * e.relative.x * k
			fc.pz = float(fc.pz) + sin(yaw) * e.relative.x * k
			fc.py = clampf(float(fc.py) + e.relative.y * k, -0.6, 6.0)
		touch[e.index] = e.position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_take_free_cam()
			rp.fc.dist = clampf(float(rp.fc.dist) * (0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 2.5, 60.0)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_replay_act("play")
			KEY_LEFT:
				_replay_act("back")
			KEY_RIGHT:
				_replay_act("fwd")
			KEY_K:
				_replay_act("key_add")
			KEY_ESCAPE:
				_close_replay()


## Moving the view by hand: switch to the free camera, starting from
## wherever the camera is now so nothing jumps.
func _take_free_cam() -> void:
	if rp.cam == "free":
		return
	if rp.cam == "keys" and not replay_keys.is_empty():
		rp.fc = _keyed_cam(rp.t).duplicate()
	else:
		_grab_free_cam(rp.cam)
	rp.cam = "free"


## Free-camera settings that reproduce the current view of the car.
func _grab_free_cam(_from_mode: String) -> void:
	var centre := Vector3(player.x, 0.8, -player.l * 0.5)
	var d := cam.global_position - centre
	var dist := clampf(d.length(), 2.5, 60.0)
	rp.fc = {"yaw": atan2(d.x, d.z), "pitch": clampf(asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0)), -0.08, 1.5),
		"dist": dist, "px": 0.0, "py": 0.0, "pz": 0.0, "fov": clampf(cam.fov, 20.0, 90.0)}


## A camera on a sphere round the car (plus a pan offset), so a shot keeps
## following the car however far it travels.
func _free_cam(fc: Dictionary) -> void:
	var centre := Vector3(player.x + float(fc.px), 0.8 + float(fc.py), -player.l * 0.5 + float(fc.pz))
	var yaw: float = fc.yaw
	var pitch: float = fc.pitch
	var dist: float = fc.dist
	var from := centre + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	from.y = maxf(from.y, 0.25)
	cam.near = 0.1
	cam.fov = fc.fov
	var land := get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT if land else Camera3D.KEEP_WIDTH
	cam.global_transform = Transform3D(Basis.looking_at(centre - from), from)


## The camera between keyframes: a smooth Catmull-Rom curve through them.
func _keyed_cam(t: float) -> Dictionary:
	var n := replay_keys.size()
	if n == 1 or t <= float(replay_keys[0].t):
		return replay_keys[0]
	if t >= float(replay_keys[n - 1].t):
		return replay_keys[n - 1]
	var i := 0
	while i < n - 2 and float(replay_keys[i + 1].t) <= t:
		i += 1
	var k1: Dictionary = replay_keys[i]
	var k2: Dictionary = replay_keys[i + 1]
	var k0: Dictionary = replay_keys[maxi(i - 1, 0)]
	var k3: Dictionary = replay_keys[mini(i + 2, n - 1)]
	var u := (t - float(k1.t)) / maxf(float(k2.t) - float(k1.t), 0.001)
	var out := {}
	for key in ["yaw", "pitch", "dist", "px", "py", "pz", "fov"]:
		var p1: float = k1[key]
		var p0: float = k0[key]
		var p2: float = k2[key]
		var p3: float = k3[key]
		if key == "yaw":  # turn the short way round
			p0 = p1 + wrapf(p0 - p1, -PI, PI)
			p2 = p1 + wrapf(p2 - p1, -PI, PI)
			p3 = p2 + wrapf(p3 - p2, -PI, PI)
		out[key] = 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)
	out.pitch = clampf(out.pitch, -0.08, 1.5)
	out.dist = clampf(out.dist, 2.5, 60.0)
	return out


# ---------------------------------------------------------------- fuel

## Plan the next fuel stop about STATION_EVERY_KM past after_z, on one of the
## scenery's station sites, with its own name and prices.
func _new_station(after_z: float) -> void:
	if not station.is_empty():
		last_station = station
	var km := randf_range(0.96, 1.08) * Data.STATION_EVERY_KM * Data.station_scale
	if _test_first_station > 0.0 and station.is_empty():
		km = _test_first_station / 1000.0
	var n := ceili((after_z + km * 1000.0 - Scenery.SITE) / Scenery.TREE_PERIOD)
	var reg := randf_range(2.4, 4.4)
	var price := func(v: float) -> float:
		return floorf(v * 10.0) / 10.0 + 0.09  # pump prices end in 9
	station = {"z": Scenery.site_z(n), "name": Data.STATION_NAMES.pick_random(), "color": Data.STATION_COLORS.pick_random(),
		"prices": {"regular": price.call(reg), "mid": price.call(reg + 5.0 + randf_range(-0.8, 0.8)),
			"premium": price.call(reg + 15.0 + randf_range(-1.6, 1.6))}}
	_send_stations()


func _send_stations() -> void:
	var list: Array = [station]
	if not last_station.is_empty():
		list.append(last_station)
	scenery.set_stations(list)


## Road distance of the player from the next fuel stop's pumps (negative before them).
func _station_rel() -> float:
	return player.z - float(station.z) if not station.is_empty() else -1.0e9


func _in_station_zone() -> bool:
	var rel := _station_rel()
	return rel > -GasStation.EXIT_START and rel < GasStation.MERGE_END


func _right_limit() -> float:
	return GasStation.right_edge(_station_rel()) if run and not station.is_empty() else Data.RAIL


## The exit lane counts as a lane (for lane assist and the arrow keys) while
## it is there to turn into.
func _exit_open() -> bool:
	if run == null or station.is_empty() or not run.pit.is_empty() or run.pit_skip == float(station.z):
		return false
	var rel := _station_rel()
	return rel > -GasStation.EXIT_FULL - 30.0 and rel < -GasStation.FORE + 5.0


func _lane_xs() -> Array:
	var xs: Array = Data.LANES.duplicate()
	if _exit_open():
		xs.append(GasStation.LANE_X)
	return xs


func _nearest_x(x: float) -> float:
	var best: float = Data.LANES[0]
	for lx in _lane_xs():
		if absf(float(lx) - x) < absf(best - x):
			best = lx
	return best


func _step_lane(x: float, dir: int) -> float:
	var xs := _lane_xs()
	var i := xs.find(_nearest_x(x))
	return xs[clampi(i + dir, 0, xs.size() - 1)]


## A fuel stop is close (or the car is at the pumps): hold back the boss and
## the police until it is behind.
func _station_busy() -> bool:
	if run == null or station.is_empty():
		return false
	if not run.pit.is_empty():
		return true
	var ahead := float(station.z) - player.z
	return ahead < GasStation.SIGNS[0] + 760.0 and ahead > -GasStation.MERGE_END - 30.0


## A race or pursuit is starting: if the next fuel stop would come up during
## it, move the stop to just after (it is still out of sight).
func _clear_station_for(span: float) -> void:
	if station.is_empty():
		return
	if float(station.z) - player.z < span + 400.0:
		var n := ceili((player.z + span + 600.0 - Scenery.SITE) / Scenery.TREE_PERIOD)
		station.z = Scenery.site_z(n)
		_send_stations()


func _gross_earnings() -> int:
	return run.score / 40 + int(run.dist / 50.0) + run.cash_bonus


## Money that can pay for fuel: the bank, plus what this run has earned so far.
func _funds() -> Dictionary:
	var from_run := maxi(0, _gross_earnings() - run.fuel_from_run)
	return {"bank": Save.data.cash, "run": from_run, "total": Save.data.cash + from_run}


func _fuel_next_text() -> String:
	if station.is_empty() or run == null:
		return ""
	var ahead := float(station.z) - player.z
	if ahead < -GasStation.FORE:
		return ""
	if ahead > 3000.0 and run.fuel > st.tank * 0.3:
		return ""
	return "FUEL %s" % Fmt.km(maxf(ahead, 0.0))


## Warnings, the heads-up for the next stop, running dry, and moving on to
## the next stop once this one is behind.
func _update_fuel(dt: float) -> void:
	var frac: float = run.fuel / maxf(st.tank, 1.0)
	if frac > 0.3:
		run.fuel_warned = 0
	elif frac < 0.1 and run.fuel_warned < 2 and run.fuel > 0.0:
		run.fuel_warned = 2
		_notify("FUEL CRITICAL", "bad")
		sound.play("ding", 0.55, 0.0)
	elif frac < 0.25 and run.fuel_warned < 1:
		run.fuel_warned = 1
		_notify("LOW FUEL", "bad")
		sound.play("ding", 0.6, -2.0)
	if not station.is_empty():
		var ahead := float(station.z) - player.z
		if ahead < 1000.0 and ahead > 600.0 and run.heads_up != float(station.z):
			run.heads_up = float(station.z)
			var g: String = st.grade
			hud.pop("%s IN 1 KM · %s $%.2f/L" % [String(station.name).to_upper(), Data.FUEL_GRADES[g].short, station.prices[g]], "small")
		if ahead < 450.0 and ahead > 250.0 and run.heads_up != -float(station.z) and run.fuel < st.tank * 0.9:
			run.heads_up = -float(station.z)
			hud.pop("MOVE RIGHT INTO THE EXIT LANE TO PULL IN", "small")
		if ahead < -GasStation.MERGE_END - 30.0 and run.pit.is_empty():
			_new_station(float(station.z))
	if run.fuel <= 0.0 and run.pit.is_empty():
		if run.dry_t == 0.0:
			hud.banner("OUT OF FUEL", "COASTING")
		run.dry_t += dt if player.v < 1.0 else 0.0001
		if run.dry_t > 1.2:
			_end_run("Ran out of fuel")


## In the exit lane, early enough to stop at the pumps: pull in.
func _pit_ready() -> bool:
	if station.is_empty() or run.phase != "cruise" or run.pit_skip == float(station.z):
		return false
	var rel := _station_rel()
	return rel > -GasStation.EXIT_FULL + 5.0 and rel < -GasStation.FORE + 6.0 and player.x > Data.ROAD_HALF + 1.0


func _start_pit() -> void:
	var zs: float = station.z
	var need := player.v * player.v / (2.0 * 13.0)  # the hardest the car will brake
	# park with the car's middle level with a pump: the nearer pump if the car
	# can stop for it, otherwise the one further on
	var stop := -1.0
	for pump_rel in GasStation.PUMPS:
		var rear: float = zs + float(pump_rel) - player.l * 0.5
		if rear - player.z >= need:
			stop = rear
			break
	if stop < 0.0:
		run.pit_skip = zs
		_notify("TOO FAST TO PULL IN", "bad")
		return
	run.pit = {"step": "in", "z0": player.z, "x0": player.x, "v0": maxf(player.v, 3.0), "stop": stop}
	run.combo = 0
	touches.clear()
	_refresh_inputs()
	_notify("PULLING IN", "small")


## The car drives itself into the station, stops at a pump, and afterwards
## drives back out along the slip road to merge into the right-hand lane.
func _update_pit(dt: float) -> void:
	var pt: Dictionary = run.pit
	var zs: float = station.z
	var nx := player.x
	match pt.step:
		"in":
			var total: float = maxf(float(pt.stop) - float(pt.z0), 0.5)
			var left: float = float(pt.stop) - player.z
			var a: float = float(pt.v0) * float(pt.v0) / (2.0 * total)
			player.v = maxf(sqrt(maxf(0.0, 2.0 * a * left)), 1.0 if left > 0.3 else 0.0)
			player.z = minf(player.z + player.v * dt, float(pt.stop))
			var lane_x := lerpf(float(pt.x0), GasStation.LANE_X, smoothstep(float(pt.z0), float(pt.z0) + 30.0, player.z))
			nx = lerpf(lane_x, GasStation.PUMP_X, smoothstep(zs - GasStation.FORE - 6.0, float(pt.stop) - 4.0, player.z))
			player.braking = true
			if player.z >= float(pt.stop) - 0.01:
				player.v = 0.0
				nx = GasStation.PUMP_X
				pt.step = "fuel"
				_open_refuel()
		"fuel":
			player.v = 0.0
		"out":
			player.v = minf(player.v + 6.0 * dt, 26.0)
			player.z += player.v * dt
			player.braking = false
			var to_lane := lerpf(GasStation.PUMP_X, GasStation.LANE_X, smoothstep(float(pt.stop) + 3.0, zs + GasStation.FORE + 10.0, player.z))
			nx = lerpf(to_lane, Data.LANES[3], smoothstep(zs + GasStation.FORE + 25.0, zs + GasStation.MERGE_END - 20.0, player.z))
			if player.z >= zs + GasStation.MERGE_END - 20.0:
				nx = Data.LANES[3]
				run.pit = {}
				target_x = nx
				run.invuln = maxf(run.invuln, 1.6)
	player.vx = (nx - player.x) / maxf(dt, 0.0001)
	player.x = nx
	if player.v > 0.05:
		# point along the path it is driving; the wheels turn for its curve
		var ny := clampf(atan2(player.vx, maxf(player.v, 0.5)), -0.5, 0.5)
		var r := (ny - player.yaw) / maxf(dt, 0.0001)
		player.yaw = ny
		player.course = ny
		player.yaw_rate = r
		player.steer = move_toward(player.steer, clampf(atan(r * player.l * 0.6 / maxf(player.v, 0.5)), -0.6, 0.6), 1.8 * dt)
	player_accel = 0.0


func _open_refuel() -> void:
	state = S.REFUEL
	pump = {"litres": 0.0, "bill": 0.0, "on": false, "auto": false, "t": 0.0, "msg": ""}
	touches.clear()
	key_gas = false
	key_brake = false
	_refresh_inputs()
	hud.set_play_visible(false)
	hud.show_refuel(_refuel_view())
	sound.play("ding", 0.8, -6.0)
	if autotest:
		print("[autotest] fuel stop %s: %.1f of %.0f L, %s $%.2f/L, funds $%d, car centre %.2f m from a pump, x %.1f" % [station.name, run.fuel, st.tank, st.grade, station.prices[st.grade], _funds().total,
			minf(absf(player.z + player.l * 0.5 - float(station.z) - GasStation.PUMPS[0]), absf(player.z + player.l * 0.5 - float(station.z) - GasStation.PUMPS[1])), player.x])


func _pump_frame(dt: float) -> void:
	pump.t += dt
	var price: float = station.prices[st.grade]
	if pump.on:
		var room: float = st.tank - run.fuel
		var afford: float = (float(_funds().total) - float(pump.bill)) / price
		var add := minf((32.0 if pump.auto else 14.0) * dt, minf(room, afford))
		if add <= 0.0005:
			pump.on = false
			pump.auto = false
			pump.msg = "Tank full." if room <= 0.01 else "That's all the money you have."
			sound.play("ding", 1.2, -4.0)
		else:
			run.fuel += add
			pump.litres += add
			pump.bill += add * price
	hud.update_refuel(_refuel_view())
	if autotest:
		if pump.t > 0.5 and float(pump.litres) == 0.0 and not pump.on:
			pump.on = true
			pump.auto = true
		elif pump.t > 3.0 and not pump.on:
			_pay_and_go()


func _refuel_view() -> Dictionary:
	var f := _funds()
	var price: float = station.prices[st.grade]
	return {"name": station.name, "grade": st.grade, "prices": station.prices, "fuel": run.fuel, "tank": st.tank,
		"litres": pump.litres, "bill": pump.bill, "pumping": pump.on, "bank": f.bank, "run": f.run, "total": f.total,
		"to_fill": (st.tank - run.fuel) * price, "price": price, "msg": pump.msg,
		"car": Data.car_by_id(Save.data.selected).name}


## Pay what was pumped (this run's earnings first, then the bank) and drive on.
func _pay_and_go() -> void:
	if state != S.REFUEL:
		return
	var bill := ceili(float(pump.bill) - 0.0001)
	if bill > 0:
		var from_run := mini(bill, maxi(0, _gross_earnings() - run.fuel_from_run))
		run.fuel_from_run += from_run
		Save.data.cash = maxi(0, Save.data.cash - (bill - from_run))
		run.fuel_paid += bill
		Save.persist()
		_notify("PAID $%s · %.1f L" % [Fmt.num(bill), pump.litres], "hot")
		if autotest:
			print("[autotest] paid $%d for %.1f L (%d from this run), tank %.1f L" % [bill, pump.litres, from_run, run.fuel])
	pump.on = false
	state = S.PLAY
	hud.show_screen("")
	hud.set_play_visible(true)
	run.pit.step = "out"
	run.dry_t = 0.0


## The police are coming up behind this car in its lane, lights flashing.
func _cop_behind(c: Vehicle) -> bool:
	if boss == null or not boss.is_cop or run == null or run.phase != "cop":
		return false
	var dz := c.z - (boss.z + boss.l)
	return dz > -1.0 and dz < 75.0 and absf(c.x - boss.x) < 2.4


## Open road ahead of b in a lane: distance to the first car there that is
## not pulling away (150 m if clear).
func _free_ahead(b: Vehicle, lane: int) -> float:
	var lx: float = Data.LANES[lane]
	var free := 150.0
	for c in traffic:
		if (absf(c.x - lx) < 1.9 or c.tlane == lane) and c.z + c.l > b.z and c.v < b.v + 1.0:
			free = minf(free, c.z - (b.z + b.l))
	return free

extends Node3D
## Redline Rush main script: driving physics, traffic, the boss race,
## scoring, run flow, camera and touch input.
##
## Logic uses "road coordinates": x = metres from the centre line, z = metres
## travelled. Nodes are placed relative to the player every frame (the player
## is always at the scene origin), so the highway never runs out and floats
## never lose precision.

enum S { MENU, GARAGE, PLAY, PAUSED, BOSS_INTRO, PICK, OVER }


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
	var model: CarModel


class Run:
	var stage := 1
	var score := 0
	var dist := 0.0
	var stage_dist := 0.0
	var stage_score := 0
	var lives := 3
	var mods := {"accel": 1.0, "brake": 1.0, "handling": 1.0, "top": 1.0, "score": 1.0}
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
	# boss race
	var b_len := Data.BOSS_RACE_LENGTH
	var b_dist := 0.0
	var b_score := 0
	var b_rival := 0
	var b_total := 0
	var b_next := 1.0
	var b_info := {}


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
var in_gas := false
var in_brake := false
var ap_t := 0.0
var ap_gas := true
var ap_brake := false

# test flags (see README): --autotest drives itself, --fast shrinks targets
var autotest := false
var auto_quit := 0.0
var showroom := ""  # --showroom=rear|front: every player car parked in a row, simulation frozen (test view)
var shots: Array = []
var burst: Array = []  # --burst=START:COUNT:DIR saves COUNT consecutive frames (test aid)
var _burst_i := 0
var auto_speed := 46.0  # --autospeed=M/S: how fast the test driver goes
var idcolor := false   # --idcolor: flat unique colour per traffic car, no fog or scenery (flicker test)
var _id_next := 1
var _id_log: FileAccess
var demo_pops := false  # --demo-pops: show a sample score message every second (test aid)
var _demo_t := 0.0  # [[seconds, path], ...] from --shot=SEC:PATH
var _log_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	if args.has("--fast"):
		Data.target_scale = 0.08
	for a in args:
		if a.begins_with("--quit-after="):
			auto_quit = float(a.split("=")[1])
		if a.begins_with("--showroom"):
			showroom = a.substr(11) if a.length() > 11 else "rear"
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
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.5
	cam.far = 1000.0  # mountains and clouds are drawn closer and scaled down, so a short range loses nothing
	add_child(cam)
	cam.current = true
	sparks = _make_sparks()
	dust = _make_dust()
	sound = EngineAudio.new()
	add_child(sound)
	sound.set_enabled(Save.data.sound)

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
	if autotest:
		_start_run()
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
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
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
	player.model.build(c.shape, Color(c.color), Color("#b5322a"), c.style)
	add_child(player.model)
	player.model.build_interior()
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
	}


func _reset_world() -> void:
	for c in traffic:
		c.model.queue_free()
	traffic.clear()
	_remove_boss()
	finish_z = -1.0
	player.z = 0.0
	player.x = Data.LANES[1]
	target_x = player.x
	player.v = 24.0
	player.vx = 0.0
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
	c.cruise = v_override if v_override > 0.0 else [31.0, 27.5, 24.0, 20.5][lane] + randf_range(-1.6, 1.6) - (2.0 if c.truck else 0.0)
	c.v = c.cruise
	c.lc_t = randf_range(2.0, 9.0)
	c.ahead = z > player.z + player.l
	c.model = CarModel.new()
	if c.truck:
		c.model.build(shape, Color(Data.TRUCK_BOX_COLORS.pick_random()), Color(Data.TRUCK_CAB_COLORS.pick_random()))
	else:
		c.model.build(shape, Color(Data.TRAFFIC_COLORS.pick_random()), Color("#b5322a"), {"rim": ["steel", "5spoke", "5spoke", "multi"].pick_random()})
	c.model.position = Vector3(c.x, 0.0, -(c.z - player.z))  # place before it is first drawn
	add_child(c.model)
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
	for c in traffic:
		var gap := 1e9
		var lead: Vehicle = null
		for o in everyone:
			if o == c:
				continue
			if absf(o.x - c.x) < (o.w + c.w) / 2.0 + 0.35 and o.z > c.z:
				var g := o.z - (c.z + c.l)
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
			var step := 1.9 * dt * signf(d)
			c.vx = 1.9 * signf(d)
			if absf(d) <= absf(step):
				c.x = tx
				c.lane = c.tlane
			else:
				c.x += step
	for i in range(traffic.size() - 1, -1, -1):
		var c := traffic[i]
		if c.z < player.z - 90.0 or c.z > player.z + 1100.0:
			c.model.queue_free()
			traffic.remove_at(i)
	# keep the road populated
	var dens := minf(7.2, 3.3 + run.stage * 0.55) if run else 3.4
	# Cars are added and removed only far beyond the haze (and are not drawn
	# past CarModel.DRAW_DISTANCE), so none of them pops in or out of view.
	var ahead := 0
	for c in traffic:
		if c.z > player.z and c.z < player.z + 440.0:
			ahead += 1
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
		boss.model.queue_free()
		boss = null


func _start_boss() -> void:
	var bi := Data.boss_info(run.stage)
	var car := Data.car_by_id(bi.car)
	var sh: Dictionary = Data.SHAPES[car.shape]
	_remove_boss()
	boss = Vehicle.new()
	boss.lane = 2 if player.x < 0.0 else 1
	boss.tlane = boss.lane
	boss.x = Data.LANES[boss.lane]
	boss.z = player.z - 20.0
	boss.v = player.v + 8.0
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
	run.phase = "boss"
	run.b_dist = 0.0
	run.b_score = 0
	run.b_rival = 0
	run.b_total = Data.boss_total(run.stage)
	run.b_next = 1.2
	run.b_info = bi
	finish_z = player.z + run.b_len
	for c in traffic:
		if absf(c.z - player.z) < 30.0:
			c.z += 60.0  # breathing room at the start
	hud.banner("VS " + String(bi.full).to_upper(), "BEAT %s IN %s" % [Fmt.num(run.b_total), Fmt.km(run.b_len)])


func _update_boss(dt: float) -> void:
	if boss == null:
		return
	var b := boss
	# The boss paces the player, but drives like everyone else: it follows the
	# car ahead and brakes for it, and only changes lane into a clear gap.
	var tz := player.z + 16.0 + 13.0 * sin(t * 0.33)
	var want := player.v + clampf((tz - b.z) * 0.6, -10.0, 12.0)
	var lg := _boss_leader(b)
	var lead: Vehicle = lg[0]
	var gap: float = lg[1]
	if lead and gap < 45.0:
		want = minf(want, lead.v + (gap - 7.0) * 0.45)
	b.v += clampf(want - b.v, -(10.0 if gap < 8.0 else 7.0) * dt, 6.0 * dt)
	if lead and gap < 0.8:
		b.v = minf(b.v, lead.v)
	b.v = maxf(0.0, b.v)
	b.braking = want < b.v - 0.5
	b.z += b.v * dt
	if lead and b.z + b.l > lead.z - 0.3 and absf(lead.x - b.x) < (lead.w + b.w) / 2.0:
		b.z = lead.z - b.l - 0.3  # never inside the car ahead
	b.vx = 0.0
	if b.tlane == b.lane:
		b.sig_t = maxf(0.0, b.sig_t - dt)
		if lead and gap < 30.0 and lead.v < want + 1.0 and b.sig_t <= 0.0:
			var opts: Array[int] = []
			for l in [b.lane - 1, b.lane + 1]:
				if l >= 0 and l < 4 and not _lane_blocked(b, l, 32.0, 8.0):
					opts.append(l)
			if not opts.is_empty():
				b.tlane = opts.pick_random()
	else:
		var tx: float = Data.LANES[b.tlane]
		# abort the move if the target lane fills up alongside
		if _lane_blocked(b, b.tlane, 4.0, 2.0) and absf(tx - b.x) > 1.2:
			b.tlane = b.lane
			b.sig_t = 1.0
			tx = Data.LANES[b.lane]
		var d := tx - b.x
		var step := 4.0 * dt * signf(d)
		b.vx = 4.0 * signf(d)
		if absf(d) <= absf(step):
			b.x = tx
			b.lane = b.tlane
			b.sig_t = 0.8  # settle before the next lane change
		else:
			b.x += step
	if run == null or run.phase != "boss":
		return
	var target := run.b_total * minf(1.0, run.b_dist / run.b_len)
	run.b_next -= dt
	if run.b_next <= 0.0:
		run.b_next = randf_range(0.55, 1.5)
		if run.b_rival < target:
			run.b_rival = mini(run.b_total, roundi(run.b_rival + maxf(25.0, (target - run.b_rival) * randf_range(0.7, 1.25))))


func _end_battle() -> void:
	var bi := run.b_info
	run.b_rival = run.b_total
	_remove_boss()
	finish_z = -1.0
	if run.b_score > run.b_total:
		run.bosses += 1
		run.cash_bonus += 200 * run.stage
		var unlocked_new := false
		if not Save.is_unlocked(bi.car):
			Save.data.unlocked.append(bi.car)
			Save.persist()
			unlocked_new = true
		sound.play("ding", 1.26, 3.0)
		_show_pick(bi, unlocked_new)
	else:
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
	var mode: String = Save.data.cam.mode
	if mode == "cockpit":
		player.model.show_message(text, kind)
		return
	var vp := get_viewport().get_visible_rect().size
	var pos := Vector2(vp.x / 2.0, vp.y * 0.66)
	if mode == "chase":
		var above := player.model.global_position + Vector3(0, float(Data.SHAPES[Data.car_by_id(Save.data.selected).shape].t) + 0.35, -player.l * 0.5)
		if not cam.is_position_behind(above):
			pos = cam.unproject_position(above)
	hud.pop_at(text, kind, pos)


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
	run.lives -= 1
	run.invuln = 2.4
	run.combo = 0
	run.combo_t = 0.0
	player.v *= 0.55
	shake = 1.0
	_flash.color.a = 0.4
	if other:
		other.hit = true
		other.v = maxf(other.v, player.v + 5.0)
		var s := signf(other.x - player.x)
		if s == 0.0:
			s = 1.0
		player.vx = -s * 3.2
		target_x = Data.LANES[Data.nearest_lane(player.x - s * 1.5)]
	sparks.position = Vector3(0, 0.6, -player.l * 0.5)
	sparks.restart()
	sparks.emitting = true
	sound.play("crash")
	_vib(180)
	if run.lives <= 0:
		run.dying = 1.7
		_notify(reason, "bad")
	else:
		_notify(reason + " · -1 LIFE", "bad")


func _update_player(dt: float) -> void:
	var live := _live()
	if not live or autotest:
		_autopilot(dt)
	var gas := (in_gas if live else ap_gas) if not autotest else ap_gas
	var brk := (in_brake if live else ap_brake) if not autotest else ap_brake
	var vr: float = player.v / st.top
	var a := 0.0
	if gas:
		a += st.accel * maxf(0.0, 1.0 - pow(vr, 3.0)) * (1.15 if player.v < 10.0 else 1.0)
	a -= 0.3 + 0.00022 * player.v * player.v
	if brk:
		a -= st.brake * (1.0 if player.v > 3.0 else 0.4)
	if on_shoulder:
		a -= 2.5 + player.v * 0.05
	var v_before := player.v
	player.v = maxf(0.0, player.v + a * dt)
	player.braking = brk
	player_accel = lerpf(player_accel, (player.v - v_before) / maxf(dt, 0.0001), minf(1.0, dt * 6.0))
	# steering: chase the swipe target with limited lateral speed and grip
	var speed_k := clampf(player.v / 12.0, 0.25, 1.0)
	var lat_max: float = st.lat * speed_k
	if live and not autotest:
		_analog_steer(dt)
	var desired := clampf((target_x - player.x) * 3.2, -lat_max, lat_max)
	var grip: float = st.grip * (1.0 - 0.22 * clampf(vr, 0.0, 1.2)) * (0.6 if on_shoulder else 1.0)
	player.vx += clampf(desired - player.vx, -grip * dt, grip * dt)
	player.x += player.vx * dt
	player.z += player.v * dt
	on_shoulder = absf(player.x) + player.w / 2.0 > Data.ROAD_HALF + 0.25
	var lim := Data.RAIL - player.w / 2.0
	if absf(player.x) > lim:
		var s := signf(player.x)
		player.x = s * lim
		player.vx = -s * 2.6
		target_x = Data.LANES[3 if s > 0.0 else 0]
		sparks.position = Vector3(s * Data.RAIL - player.x, 0.6, -2.0)
		sparks.restart()
		sparks.emitting = true
		if live:
			_hit("GUARDRAIL")


func _overlap(a: Vehicle, b: Vehicle) -> bool:
	return absf(a.x - b.x) < (a.w + b.w) / 2.0 - 0.12 and a.z < b.z + b.l - 0.2 and a.z + a.l > b.z + 0.2


func _collisions() -> void:
	if not _live():
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
	if boss and run.invuln <= 0.0 and _overlap(p, boss):
		_hit("RIVAL CONTACT", boss)


# ---------------------------------------------------------------- run flow

func _start_run() -> void:
	_set_player_car()
	run = Run.new()
	run.lives = 3 + Save.perm_level("lives")
	_compute_stats()
	_reset_world()
	touches.clear()
	_refresh_inputs()
	state = S.PLAY
	hud.show_screen("")
	hud.set_play_visible(true)
	hud.banner("STAGE 1", String(Data.boss_info(1).full).to_upper() + " WAITS AHEAD")
	hud.show_hint()
	_calibrate_tilt()


func _end_run(reason: String) -> void:
	if run == null:
		return
	var earned := run.score / 40 + int(run.dist / 50.0) + run.cash_bonus
	Save.data.cash += earned
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
	if autotest:
		_start_run()


func _show_pick(bi: Dictionary, unlocked_new: bool) -> void:
	state = S.PICK
	var pool: Array = []
	for b in Data.BOONS:
		if b.id != "life" or run.lives < Data.MAX_LIVES:
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
	_compute_stats()
	run.stage += 1
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


func _show_boss_intro() -> void:
	state = S.BOSS_INTRO
	var bi := Data.boss_info(run.stage)
	hud.show_boss_intro("Stage %d boss" % run.stage, bi.full, bi.line, Fmt.num(Data.boss_total(run.stage)), Data.car_by_id(bi.car).name)
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
	if run.phase == "cruise":
		run.stage_dist += d
		if run.rematch_t > 0.0:
			run.rematch_t -= dt
			if run.rematch_t <= 0.0:
				_start_boss()
				hud.banner("REMATCH", "BEAT %s IN %s" % [Fmt.num(run.b_total), Fmt.km(run.b_len)])
			return
		var r := Data.stage_req(run.stage)
		if run.stage_dist >= r.d and run.stage_score >= r.p:
			_show_boss_intro()
	elif run.phase == "boss":
		run.b_dist += d
		if run.b_dist >= run.b_len:
			_end_battle()


# ---------------------------------------------------------------- frame

func _sim_running() -> bool:
	return state == S.PLAY or state == S.MENU or state == S.GARAGE or state == S.OVER


func _process(delta: float) -> void:
	if showroom != "":
		scenery.update_view(0.0, -1.0, 0.0)
		var front := showroom == "front"
		cam.fov = 55.0
		var views := {"rear": [Vector3(-9.5, 2.4, 6.0), Vector3(-1.0, 0.6, -6.0)], "front": [Vector3(9.0, 2.2, -24.0), Vector3(-1.0, 0.6, -9.0)],
			"close": [Vector3(-7.6, 1.5, 2.2), Vector3(-5.4, 0.7, -2.0)],
			"m_front": [Vector3(1.6, 1.3, -21.0), Vector3(-1.8, 0.6, -15.4)], "m_rear": [Vector3(-4.6, 1.5, -7.4), Vector3(-1.8, 0.6, -15.0)],
			"m_side": [Vector3(4.2, 1.1, -14.6), Vector3(-1.8, 0.6, -15.3)],
			"t_rear": [Vector3(-9.5, 2.4, 6.0), Vector3(-1.0, 0.6, -6.0)], "t_front": [Vector3(9.0, 2.2, -24.0), Vector3(-1.0, 0.6, -9.0)]}
		var v: Array = views.get(showroom, views.rear)
		cam.global_transform = Transform3D(Basis(), v[0])
		cam.look_at(v[1])
		hud.set_play_visible(false)
		_check_shots()
		return
	var dt := minf(delta, 0.05)
	if _sim_running():
		if run and run.dying > 0.0:
			dt *= 0.35
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
	shake = maxf(0.0, shake - delta * 2.2)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.8)
	_sync_visuals(delta)
	_update_hud()
	var snd_gas := ((in_gas if _live() else ap_gas) if not autotest else ap_gas) and state != S.PAUSED
	var snd_brake := (in_brake if _live() else ap_brake) if not autotest else ap_brake
	sound.drive(player.v, st.top, snd_gas, snd_brake, state == S.PLAY, delta)
	if autotest:
		_log_t += delta
		if _log_t > 3.0:
			_log_t = 0.0
			if run:
				print("[autotest] t=%.0f stage=%d phase=%s lives=%d score=%d v=%.0fkm/h dist=%.0f cars=%d" % [
					Time.get_ticks_msec() / 1000.0, run.stage, run.phase, run.lives, run.score, player.v * 3.6, run.dist, traffic.size()])
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
	c.model.rotation.y = -atan2(c.vx, maxf(c.v, 4.0)) * 0.9
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
	player.model.set_roll(clampf(-player.vx * 0.025, -0.06, 0.06))
	player.model.set_pitch(clampf(-player_accel * 0.0028, -0.022, 0.03))
	var cam_mode: String = Save.data.cam.mode
	hud.set_speedo_visible(cam_mode != "cockpit")
	# Invulnerability used to blink the car on and off, which in the chase view
	# looked like a car popping in and out at the centre of the road. Now a
	# soft glow pulses on the road under the car instead.
	player.model.visible = not idcolor
	player.model.set_ghost(run != null and run.invuln > 0.0 and run.dying <= 0.0, t)
	player.model.set_gauges(player.v * 3.6 / 300.0, sound.rpm / (sound.redline * 1.1))
	player.model.set_steer(clampf(player.vx * 0.3, -1.4, 1.4))
	player.model.set_gear(sound.gear, delta)
	var sp := _speed_text()
	player.model.set_display(sound.gear, sp[0], sp[1], "%.1f km" % ((run.dist if run else player.z) / 1000.0))
	dust.position = Vector3(player.x, 0.2, 0.0)
	dust.emitting = on_shoulder and player.v > 8.0
	_update_camera(delta, cam_mode)


func _speed_text() -> Array:
	if Save.setting("units") == "mph":
		return [str(roundi(player.v * 2.23694)), "MPH"]
	return [str(roundi(player.v * 3.6)), "KM/H"]


func _shake_k() -> float:
	return 1.0 if Save.setting("shake") else 0.0


func _vib(ms: int) -> void:
	if Save.setting("haptics"):
		Input.vibrate_handheld(ms)


## Portrait or landscape, chosen in Settings. The screen is locked to it, so
## turning the phone never switches orientation by accident.
func _apply_orientation() -> void:
	var land: bool = Save.setting("orientation") == "landscape"
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE if land else DisplayServer.SCREEN_PORTRAIT)
	get_tree().root.content_scale_size = Vector2i(1280, 720) if land else Vector2i(720, 1280)
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(768, 432) if land else Vector2i(432, 768))
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
	var cfg := Save.cam(mode)
	# portrait keeps the horizontal field of view; landscape keeps a vertical one
	var land := get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT if land else Camera3D.KEEP_WIDTH
	var fov_k := 0.82 if land else 1.0
	var speed_k := clampf(player.v / 70.0, 0.0, 1.0)
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(cfg.angle))
	cam_x = lerpf(cam_x, player.x * 0.62, minf(1.0, delta * 3.5))
	sound.set_interior(mode == "cockpit")
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
	}
	if run.phase == "boss":
		var mx := maxf(float(maxi(run.b_total, maxi(run.b_score, run.b_rival))) * 1.05, 1.0)
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
		elif d_ok and not p_ok:
			sub = "NEED MORE POINTS"
		d.merge({"title": "STAGE %d" % run.stage, "sub": sub, "l1": "DIST", "l2": "PTS",
			"f1": run.stage_dist / r.d, "f2": run.stage_score / r.p,
			"v1": "%.1f/%.1f km" % [minf(run.stage_dist, r.d) / 1000.0, r.d / 1000.0],
			"v2": "%s/%s" % [Fmt.num(mini(run.stage_score, int(r.p))), Fmt.num(r.p)],
			"done1": d_ok, "done2": p_ok})
	hud.update_play(d)


# ---------------------------------------------------------------- input

var _steer_val := 0.0
var _steer_active := false


## Wheel and button steering: the input sets how far ahead of the car the
## steering target sits, so the car's sideways speed follows the input
## smoothly and stops when you centre the wheel or let go of the button.
func _analog_steer(dt: float) -> void:
	var mode: String = Save.setting("steer_mode")
	var held := false
	var left := false
	var right := false
	for k in touches:
		match touches[k].role:
			"wheel":
				held = true
			"left":
				left = true
			"right":
				right = true
	hud.wheel.held = held
	hud.arrows.left_on = left
	hud.arrows.right_on = right
	if mode == "wheel":
		if not held:
			hud.wheel.angle = move_toward(hud.wheel.angle, 0.0, 7.0 * dt)  # springs back to centre
		var raw := hud.wheel.angle / SteerWheel.MAX_ANGLE
		_steer_val = 0.0 if absf(raw) < 0.04 else raw
		held = held or absf(_steer_val) > 0.0
	elif mode == "tilt":
		var raw := _tilt_value()
		_steer_val = lerpf(_steer_val, raw, minf(1.0, dt * 12.0))
		held = absf(_steer_val) > 0.03
	elif mode == "buttons":
		var want := (1.0 if right else 0.0) - (1.0 if left else 0.0)
		_steer_val = move_toward(_steer_val, want, (4.0 if want != 0.0 else 7.0) * dt)  # eases in and out
		held = absf(_steer_val) > 0.01
	else:
		return
	if not _live():
		return
	if held:
		var lead := 1.7 * float(Save.setting("steer_sens"))
		target_x = clampf(player.x + _steer_val * lead, -(Data.RAIL + 1.0), Data.RAIL + 1.0)
		_steer_active = true
	elif _steer_active:
		_steer_active = false
		# lane assist: settle into the lane the car is heading for
		target_x = Data.LANES[Data.nearest_lane(player.x + player.vx * 0.3)] if Save.data.assist else player.x


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


## Tilt steering, -1 (full left) .. 1 (full right). 22 degrees is full lock.
func _tilt_value() -> float:
	var r := (_roll() - _tilt_zero) / deg_to_rad(22.0)  # sign matched to real phones (tilt right = steer right)
	if Save.setting("tilt_invert"):
		r = -r
	return 0.0 if absf(r) < 0.06 else clampf(r, -1.0, 1.0)


func _refresh_inputs() -> void:
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


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var role := hud.role_at(e.position) if state == S.PLAY else "ui"
			if role == "":
				role = "steer"
			touches[e.index] = {"role": role, "x": e.position.x}
			if role == "wheel":
				touches[e.index]["a"] = (e.position - hud.wheel.centre()).angle()
		else:
			var tt: Variant = touches.get(e.index)
			touches.erase(e.index)
			if tt and tt.role == "steer" and Save.data.assist and _live():
				var others := false
				for k in touches:
					if touches[k].role == "steer":
						others = true
				if not others:
					target_x = Data.LANES[Data.nearest_lane(target_x)]
		_refresh_inputs()
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		var tt: Variant = touches.get(e.index)
		if tt == null:
			return
		var dx: float = e.position.x - tt.x
		tt.x = e.position.x
		if tt.role == "wheel":
			var a: float = (e.position - hud.wheel.centre()).angle()
			hud.wheel.angle = clampf(hud.wheel.angle + wrapf(a - tt.a, -PI, PI), -SteerWheel.MAX_ANGLE, SteerWheel.MAX_ANGLE)
			tt.a = a
		if tt.role == "steer" and _live():
			var vw := get_viewport().get_visible_rect().size
			var sens: float = (16.0 if vw.y > vw.x else 13.0) * float(Save.setting("steer_sens"))
			target_x = clampf(target_x + dx / vw.x * sens, -(Data.RAIL + 1.0), Data.RAIL + 1.0)
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
				if k.pressed and _live():
					target_x = Data.LANES[maxi(0, Data.nearest_lane(target_x) - 1)]
			KEY_RIGHT, KEY_D:
				if k.pressed and _live():
					target_x = Data.LANES[mini(3, Data.nearest_lane(target_x) + 1)]
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
			if hud.screens.pedals.visible:
				_on_act("pedal_done", "")
			elif hud.screens.settings.visible:
				_on_act("settings_back", "")
			elif state == S.PLAY:
				_pause()
			elif state == S.PAUSED:
				_resume()
			elif state == S.GARAGE or state == S.OVER:
				_go_menu()


# ---------------------------------------------------------------- screens

func _go_menu() -> void:
	state = S.MENU
	hud.set_play_visible(false)
	hud.render_menu()
	hud.show_screen("menu")


func _pause() -> void:
	if state != S.PLAY:
		return
	state = S.PAUSED
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
	hud.show_screen("")
	_calibrate_tilt()


func _on_act(action: String, arg: String) -> void:
	# a drag that scrolled a menu must not also press the button it started on
	if hud and hud.clicks_blocked() and not action in ["cam_set", "set", "cam_save", "save", "pause", "cam_cycle"]:
		return
	match action:
		"start":
			_start_run()
		"garage":
			state = S.GARAGE
			hud.render_garage()
			hud.show_screen("garage")
		"menu":
			_go_menu()
		"tab":
			hud.garage_tab = arg
			hud.render_garage()
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
			hud.render_garage()
		"select":
			if Save.owns(arg):
				Save.data.selected = arg
				Save.persist()
				_set_player_car()
				_compute_stats()
			hud.render_garage()
		"perm":
			for p in Data.PERM:
				if p.id == arg:
					var lv := Save.perm_level(arg)
					var cost := Data.perm_cost(p, lv)
					if lv < p.max and Save.data.cash >= cost:
						Save.data.cash -= cost
						Save.data.perm[arg] = lv + 1
						Save.persist()
						_compute_stats()
						sound.play("ding", 1.3 + lv * 0.08)
			hud.render_garage()
		"settings":
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
			if kv[0] == "pedal_scale":
				hud.layout_pedals()
			hud.render_settings()
		"save":
			Save.persist()
		"toggle":
			match arg:
				"sound":
					Save.data.sound = not Save.data.sound
					sound.set_enabled(Save.data.sound)
				"assist":
					Save.data.assist = not Save.data.assist
				"steer_mode":
					var order := ["swipe", "wheel", "buttons", "tilt"]
					Save.data.settings.steer_mode = order[(order.find(Save.setting("steer_mode")) + 1) % order.size()]
					hud.layout_pedals()
				"orientation":
					Save.data.settings.orientation = "portrait" if Save.setting("orientation") == "landscape" else "landscape"
					_apply_orientation()
				"units":
					Save.data.settings.units = "kmh" if Save.setting("units") == "mph" else "mph"
				_:
					Save.data.settings[arg] = not Save.setting(arg)
			Save.persist()
			hud.render_settings()
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
		"pedal_reset":
			Save.data.settings.gas_pos = []
			Save.data.settings.brake_pos = []
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

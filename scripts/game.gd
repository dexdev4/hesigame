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
var shots: Array = []  # [[seconds, path], ...] from --shot=SEC:PATH
var _log_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	if args.has("--fast"):
		Data.target_scale = 0.08
	for a in args:
		if a.begins_with("--quit-after="):
			auto_quit = float(a.split("=")[1])
		if a.begins_with("--shot="):
			var parts := a.substr(7).split(":", true, 1)
			shots.append([float(parts[0]), parts[1]])

	_build_environment()
	scenery = Scenery.new()
	add_child(scenery)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.3
	cam.far = 900.0
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
	for a in args:
		if a.begins_with("--open="):  # e.g. --open=garage or --open=garage:up
			var parts := a.substr(7).split(":")
			_on_act(parts[0], parts[1] if parts.size() > 1 else "")
			if parts.size() > 1:
				_on_act("tab", parts[1])


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#3d5f88")
	sm.sky_horizon_color = Color("#e9bb86")
	sm.ground_horizon_color = Color("#c9a27a")
	sm.ground_bottom_color = Color("#4a5a33")
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#d9b48a")
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe2b8")
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-24, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
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
	player.model.build(c.shape, Color(c.color))
	add_child(player.model)


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
	while z < 430.0:
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
		c.model.build(shape, Color(Data.TRAFFIC_COLORS.pick_random()))
	add_child(c.model)
	traffic.append(c)
	return true


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
		if c.z < player.z - 90.0 or c.z > player.z + 800.0:
			c.model.queue_free()
			traffic.remove_at(i)
	# keep the road populated
	var dens := minf(7.2, 3.3 + run.stage * 0.55) if run else 3.4
	var ahead := 0
	for c in traffic:
		if c.z > player.z:
			ahead += 1
	for k in 2:
		if ahead < dens * 4.2 and _try_spawn(player.z + randf_range(320.0, 420.0)):
			ahead += 1
	if player.v < 23.0 and randf() < dt * 0.6:
		_try_spawn(player.z - 75.0, 0 if randf() < 0.6 else 1, randf_range(29.0, 33.0))


# ---------------------------------------------------------------- boss

func _lane_blocked(b: Vehicle, lane: int, dist: float) -> bool:
	var lx: float = Data.LANES[lane]
	for c in traffic:
		if absf(c.x - lx) < 2.3 and c.z + c.l > b.z - 4.0 and c.z < b.z + b.l + dist:
			return true
	if absf(player.x - lx) < 2.3 and player.z + player.l > b.z - 9.0 and player.z < b.z + b.l + 10.0:
		return true
	return false


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
	boss.title = bi.full
	boss.model = CarModel.new()
	boss.model.build(car.shape, Color(car.color))
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
	var tz := player.z + 16.0 + 13.0 * sin(t * 0.33)
	var want := player.v + clampf((tz - b.z) * 0.6, -10.0, 12.0)
	b.v += clampf(want - b.v, -8.0 * dt, 6.0 * dt)
	b.z += b.v * dt
	b.vx = 0.0
	if b.tlane == b.lane:
		if _lane_blocked(b, b.lane, 24.0):
			var opts: Array[int] = []
			for l in [b.lane - 1, b.lane + 1]:
				if l >= 0 and l < 4 and not _lane_blocked(b, l, 30.0):
					opts.append(l)
			if not opts.is_empty():
				b.tlane = opts.pick_random()
	else:
		var tx: float = Data.LANES[b.tlane]
		var d := tx - b.x
		var step := 4.6 * dt * signf(d)
		b.vx = 4.6 * signf(d)
		if absf(d) <= absf(step):
			b.x = tx
			b.lane = b.tlane
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
		Input.vibrate_handheld(200)
		if run.lives <= 0:
			_end_run("Lost the race to " + bi.full)
			return
		hud.pop("LOST TO %s · -1 LIFE" % String(bi.full).to_upper(), "bad")
		run.phase = "cruise"
		run.rematch_t = 2.5


# ---------------------------------------------------------------- scoring

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
		hud.pop("%s  +%s" % [label, Fmt.num(pts)], kind)


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
	ap_gas = not ap_brake and player.v < (46.0 if autotest else 38.0)


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
	Input.vibrate_handheld(180)
	if run.lives <= 0:
		run.dying = 1.7
		hud.pop(reason, "bad")
	else:
		hud.pop(reason + " · -1 LIFE", "bad")


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
	player.v = maxf(0.0, player.v + a * dt)
	player.braking = brk
	# steering: chase the swipe target with limited lateral speed and grip
	var speed_k := clampf(player.v / 12.0, 0.25, 1.0)
	var lat_max: float = st.lat * speed_k
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
	sound.drive(player.v, st.top, (in_gas if _live() else false) or autotest, state == S.PLAY)
	if autotest:
		_log_t += delta
		if _log_t > 3.0:
			_log_t = 0.0
			if run:
				print("[autotest] t=%.0f stage=%d phase=%s lives=%d score=%d v=%.0fkm/h dist=%.0f cars=%d" % [
					Time.get_ticks_msec() / 1000.0, run.stage, run.phase, run.lives, run.score, player.v * 3.6, run.dist, traffic.size()])
	for sh in shots:
		if sh[0] > 0.0 and Time.get_ticks_msec() / 1000.0 > sh[0]:
			sh[0] = -1.0
			get_viewport().get_texture().get_image().save_png(sh[1])
	if auto_quit > 0.0 and Time.get_ticks_msec() / 1000.0 > auto_quit:
		print("[autotest] done")
		get_tree().quit()


func _place(c: Vehicle) -> void:
	c.model.position = Vector3(c.x, 0.0, -(c.z - player.z))
	c.model.rotation.y = -atan2(c.vx, maxf(c.v, 4.0)) * 0.9
	c.model.set_brake(c.braking)
	var dir := 0
	if c.tlane >= 0 and c.tlane != c.lane:
		dir = -1 if Data.LANES[c.tlane] < c.x else 1
	c.model.set_signal(dir, fmod(t * 2.6, 1.0) < 0.55)


func _sync_visuals(delta: float) -> void:
	scenery.update_view(player.z, finish_z)
	for c in traffic:
		_place(c)
	if boss:
		_place(boss)
	_place(player)
	player.model.set_roll(clampf(-player.vx * 0.025, -0.06, 0.06))
	player.model.visible = not (run and run.invuln > 0.0 and fmod(t * 10.0, 1.0) < 0.5)
	dust.position = Vector3(player.x, 0.2, 0.0)
	dust.emitting = on_shoulder and player.v > 8.0
	# camera: high chase view so the next few cars are readable
	cam_x = lerpf(cam_x, player.x * 0.62, minf(1.0, delta * 3.5))
	var speed_k := clampf(player.v / 70.0, 0.0, 1.0)
	cam.fov = 62.0 + 12.0 * speed_k
	var back := 10.5 - 1.2 * speed_k
	var height := 7.5 - 0.8 * speed_k
	var jitter := Vector3.ZERO
	if shake > 0.0:
		jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.35 * shake
	cam.position = Vector3(cam_x, height, back) + jitter
	cam.look_at(Vector3(cam_x * 0.7, 0.0, -18.0), Vector3.UP)


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
		"kmh": str(roundi(player.v * 3.6)),
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
		if tt.role == "steer" and _live():
			var vw := get_viewport().get_visible_rect().size
			var sens := 16.0 if vw.y > vw.x else 13.0
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
			if state == S.PLAY:
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


func _resume() -> void:
	if state != S.PAUSED:
		return
	state = S.PLAY
	hud.show_screen("")


func _on_act(action: String, arg: String) -> void:
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
		"resume":
			_resume()
		"quit":
			if run:
				state = S.PLAY
				hud.show_screen("")
				_end_run("You ended the run")

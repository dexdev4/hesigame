extends Node
## Static game data: road layout, vehicle shapes, cars, bosses and upgrades.
## Registered as the autoload "Data".

const LANES: Array[float] = [-5.4, -1.8, 1.8, 5.4]
const ROAD_HALF := 7.2   # edge of the drivable lanes (m)
const RAIL := 8.8        # guardrail position (m)

# Vehicle body proportions (metres). b = body height, t = roof height,
# c0/c1 = cabin start/end as a fraction of length, ins = cabin side inset.
const SHAPES := {
	"hatch":  {"w": 1.76, "l": 4.0, "b": 0.84, "t": 1.47, "c0": 0.10, "c1": 0.64, "ins": 0.12},
	"sedan":  {"w": 1.84, "l": 4.7, "b": 0.80, "t": 1.42, "c0": 0.27, "c1": 0.70, "ins": 0.14},
	"suv":    {"w": 1.96, "l": 4.8, "b": 1.02, "t": 1.80, "c0": 0.06, "c1": 0.72, "ins": 0.10},
	"muscle": {"w": 1.94, "l": 4.8, "b": 0.82, "t": 1.32, "c0": 0.32, "c1": 0.64, "ins": 0.18, "spoiler": true},
	"super":  {"w": 2.00, "l": 4.5, "b": 0.70, "t": 1.14, "c0": 0.30, "c1": 0.62, "ins": 0.22, "spoiler": true},
	"van":    {"w": 2.00, "l": 5.2, "b": 2.25, "t": 2.25, "c0": 0.0, "c1": 0.0, "ins": 0.0, "van": true},
	"truck":  {"w": 2.50, "l": 11.0, "b": 3.9, "t": 3.9, "c0": 0.0, "c1": 0.0, "ins": 0.0, "truck": true},
}

# accel/brake in m/s^2, grip = lateral accel (m/s^2), lat = max lateral speed (m/s), top in m/s.
const CARS := [
	{"id": "kestrel", "name": "Kestrel 1.6", "shape": "hatch", "color": "#d5dbe2", "accel": 5.2, "brake": 9.0, "grip": 9.0, "lat": 4.2, "top": 50.0, "price": 0, "boss": -1,
		"blurb": "Your starter hatch. Light, honest, slow."},
	{"id": "vanta", "name": "Vanta GT", "shape": "sedan", "color": "#2f6fd6", "accel": 6.4, "brake": 10.0, "grip": 10.0, "lat": 4.6, "top": 57.0, "price": 2500, "boss": -1,
		"blurb": "A sport sedan with real brakes."},
	{"id": "bruiser", "name": "Bruiser 5.7", "shape": "muscle", "color": "#e0a020", "accel": 8.0, "brake": 9.5, "grip": 9.0, "lat": 4.4, "top": 63.0, "price": 6000, "boss": -1,
		"blurb": "V8 torque, a bit of a handful."},
	{"id": "halcyon", "name": "Halcyon R", "shape": "super", "color": "#f1f1ee", "accel": 9.5, "brake": 12.0, "grip": 12.0, "lat": 5.3, "top": 72.0, "price": 15000, "boss": -1,
		"blurb": "Mid-engine supercar. Everything is sharper."},
	{"id": "copperhead", "name": "Copperhead", "shape": "muscle", "color": "#c9652e", "accel": 7.6, "brake": 10.5, "grip": 11.0, "lat": 5.0, "top": 61.0, "price": 4000, "boss": 0,
		"blurb": "Stage 1 boss car. Grippier than any muscle car should be."},
	{"id": "marshal", "name": "Night Marshal", "shape": "sedan", "color": "#1f2633", "accel": 8.6, "brake": 11.5, "grip": 11.5, "lat": 5.2, "top": 66.0, "price": 9000, "boss": 1,
		"blurb": "Stage 2 boss car. Stops like it hit a wall."},
	{"id": "static", "name": "Blue Static", "shape": "super", "color": "#1fa3ff", "accel": 10.2, "brake": 12.0, "grip": 13.0, "lat": 5.6, "top": 75.0, "price": 18000, "boss": 2,
		"blurb": "Stage 3 boss car. Twitchy and very fast."},
	{"id": "lastexit", "name": "Last Exit", "shape": "super", "color": "#b0122a", "accel": 11.0, "brake": 13.0, "grip": 14.0, "lat": 6.0, "top": 81.0, "price": 30000, "boss": 3,
		"blurb": "Stage 4 boss car. The fastest thing on the interstate."},
]

const BOSSES := [
	{"name": "Copperhead", "car": "copperhead", "line": "Lives in the left lane and never signals. Beat his score before the gantry."},
	{"name": "Night Marshal", "car": "marshal", "line": "Cold, precise, brakes later than you think possible."},
	{"name": "Blue Static", "car": "static", "line": "Threads gaps you did not know were there."},
	{"name": "Last Exit", "car": "lastexit", "line": "Nobody has seen the end of this highway after racing her."},
]

const PERM := [
	{"id": "accel", "name": "Engine tune", "desc": "+6% acceleration per level", "max": 5, "base": 300},
	{"id": "brake", "name": "Brake package", "desc": "+6% braking per level", "max": 5, "base": 250},
	{"id": "handling", "name": "Tyres & suspension", "desc": "+6% grip, +4% steering speed per level", "max": 5, "base": 300},
	{"id": "top", "name": "Gearing", "desc": "+4% top speed per level", "max": 5, "base": 400},
	{"id": "lives", "name": "Spare chassis", "desc": "+1 life at the start of each run", "max": 2, "base": 1500},
]

# Upgrades offered after beating a boss (applied for the rest of the run).
const BOONS := [
	{"id": "accel", "name": "Turbo kit", "desc": "+15% acceleration for this run", "tag": "ACCELERATION"},
	{"id": "brake", "name": "Big brakes", "desc": "+20% braking for this run", "tag": "BRAKING"},
	{"id": "handling", "name": "Sticky tyres", "desc": "+12% grip and steering speed", "tag": "HANDLING"},
	{"id": "top", "name": "Long gears", "desc": "+7% top speed for this run", "tag": "TOP SPEED"},
	{"id": "life", "name": "Spare wheel", "desc": "+1 life (max 6)", "tag": "EXTRA LIFE"},
	{"id": "score", "name": "Show-off", "desc": "+15% to every point earned", "tag": "SCORE"},
	{"id": "combo", "name": "Adrenaline", "desc": "Combo timer lasts 1 s longer", "tag": "COMBO"},
]

const TRAFFIC_COLORS := ["#c9ccd1", "#eef0f2", "#26292f", "#50555d", "#1f3a66", "#9b1c1c",
	"#5a1f2b", "#cbb995", "#2d4a36", "#7b8a99", "#a9b3bd", "#e6e2d6"]
const TRUCK_BOX_COLORS := ["#e9ebe6", "#d8d2c4", "#c4ccd2"]
const TRUCK_CAB_COLORS := ["#b5322a", "#1f4e8c", "#2a2d33", "#d9a21b", "#3d6b3a"]
const ROMAN := ["", "II", "III", "IV", "V", "VI", "VII", "VIII"]
const MAX_LIVES := 6
const BOSS_RACE_LENGTH := 2000.0

## Multiplies stage and boss targets. Only changed by the --fast test flag.
var target_scale := 1.0


func car_by_id(id: String) -> Dictionary:
	for c in CARS:
		if c.id == id:
			return c
	return CARS[0]


func stage_req(stage: int) -> Dictionary:
	return {
		"d": (2400.0 + 400.0 * stage) * target_scale,
		"p": roundi(4000.0 * pow(1.55, stage - 1) / 100.0) * 100 * target_scale,
	}


func boss_total(stage: int) -> int:
	return int(roundi(5000.0 * pow(1.55, stage - 1) / 100.0) * 100 * target_scale)


func boss_info(stage: int) -> Dictionary:
	var i := (stage - 1) % BOSSES.size()
	var tier := (stage - 1) / BOSSES.size()
	var b: Dictionary = BOSSES[i].duplicate()
	b["idx"] = i
	b["full"] = b.name + ("" if tier == 0 else " " + ROMAN[mini(tier, ROMAN.size() - 1)])
	return b


func perm_cost(p: Dictionary, level: int) -> int:
	return roundi(p.base * pow(1.85, level) / 10.0) * 10


func nearest_lane(x: float) -> int:
	var best := 0
	for i in range(1, 4):
		if absf(LANES[i] - x) < absf(LANES[best] - x):
			best = i
	return best

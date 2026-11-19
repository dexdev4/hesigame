extends Node
## Static game data: road layout, vehicle shapes, cars, bosses and upgrades.
## Registered as the autoload "Data".

const LANES: Array[float] = [-5.4, -1.8, 1.8, 5.4]
const ROAD_HALF := 7.2   # edge of the drivable lanes (m)
const RAIL := 8.8        # guardrail position (m)

# Vehicle body proportions (metres). b = body height, t = roof height,
# c0/c1 = cabin start/end as a fraction of length, ins = cabin side inset.
const SHAPES := {
	# BEGIN IMPORTED SHAPES
	"hot_hatch": {"w": 1.84, "l": 4.37, "b": 0.8, "t": 1.47, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"sport_sedan": {"w": 1.87, "l": 4.54, "b": 0.8, "t": 1.52, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"compact": {"w": 1.65, "l": 3.69, "b": 0.8, "t": 1.66, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"coupe": {"w": 1.83, "l": 4.30, "b": 0.8, "t": 1.36, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"kestrel": {"w": 1.68, "l": 4.02, "b": 0.8, "t": 1.59, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"bruiser": {"w": 1.98, "l": 5.08, "b": 0.8, "t": 1.38, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"copperhead": {"w": 1.99, "l": 4.82, "b": 0.8, "t": 1.30, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"halcyon": {"w": 2.00, "l": 4.59, "b": 0.8, "t": 1.18, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"static": {"w": 2.01, "l": 4.76, "b": 0.8, "t": 1.18, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"marshal": {"w": 1.94, "l": 5.31, "b": 0.8, "t": 1.56, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"lastexit": {"w": 2.10, "l": 4.87, "b": 0.8, "t": 1.17, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"vanta": {"w": 1.92, "l": 4.76, "b": 0.8, "t": 1.46, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"suv": {"w": 1.87, "l": 4.65, "b": 0.8, "t": 1.71, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"van": {"w": 2.01, "l": 5.43, "b": 0.8, "t": 2.40, "c0": 0.15, "c1": 0.66, "ins": 0.15, "van": true},
	"sedan": {"w": 1.90, "l": 4.91, "b": 0.8, "t": 1.48, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"hatch": {"w": 1.77, "l": 4.08, "b": 0.8, "t": 1.63, "c0": 0.15, "c1": 0.66, "ins": 0.15},
	"truck": {"w": 2.52, "l": 10.96, "b": 0.8, "t": 3.91, "c0": 0.15, "c1": 0.66, "ins": 0.15, "truck": true},
	# END IMPORTED SHAPES
	# compact performance saloon (proportions after the 2007 E90 M3)
	"msedan": {"w": 1.82, "l": 4.58, "b": 0.80, "t": 1.43, "c0": 0.19, "c1": 0.68, "ins": 0.13},
	"muscle": {"w": 1.94, "l": 4.8, "b": 0.82, "t": 1.33, "c0": 0.32, "c1": 0.64, "ins": 0.18, "spoiler": true},
	"super":  {"w": 2.00, "l": 4.5, "b": 0.70, "t": 1.2, "c0": 0.30, "c1": 0.62, "ins": 0.22, "spoiler": true},
	"fastback": {"w": 1.92, "l": 4.75, "b": 0.82, "t": 1.31, "c0": 0.32, "c1": 0.64, "ins": 0.18, "spoiler": true},
	"rcoupe": {"w": 1.9, "l": 4.5, "b": 0.75, "t": 1.29, "c0": 0.3, "c1": 0.62, "ins": 0.2, "spoiler": true},
	"hyper":  {"w": 2.05, "l": 4.75, "b": 0.68, "t": 1.13, "c0": 0.3, "c1": 0.62, "ins": 0.22, "spoiler": true},
}

# engine: cylinder count, idle/redline rpm, and synth character (res = exhaust
# resonance, decay = pulse length, var/uneven = per-cylinder variation that
# gives V8s their burble, rasp = exhaust grit, pops = lift-off crackle).
# style: body kit and details for CarModel (rim design, stripes, scoop, intakes...).
# accel/brake in m/s^2, grip = lateral accel (m/s^2), top in m/s. The rest is what CarStats makes of them:
# pull (how long the engine keeps pulling towards top speed: low = big torque low down, high = revs on to the top),
# agility (how readily it answers the steering), stability (how settled it stays: speed, braking, knocks),
# kg (weight: crash mass), range (km a full tank goes flat out; the tank, in litres, is what a fill costs).
# A car without them is the reference car: pull 3, agility 1, stability 1, 1,400 kg, 16.5 km.
const CARS := [
	{"id": "pulse", "fuel": "regular", "tank": 45, "style": {"rim": "factory", "rim_color": "#9aa0a6", "caliper": "#2a2c30", "badge": "PULSE", "plate": "PLS 100"},
		"engine": {"cyl": 4, "idle": 850, "redline": 6900, "res": 2.4, "decay": 2.3, "var": 0.05, "uneven": 0.03, "rasp": 0.42, "pops": 0.25, "turbo": true},
		"name": "Pulse Hatch", "shape": "hot_hatch", "color": "#2f62b0", "price": 0, "boss": -1,
		"accel": 5.40, "pull": 3.0, "top": 50.0, "brake": 9.0, "grip": 9.2, "agility": 1.00, "stability": 1.00, "kg": 1400, "range": 16.5,
		"blurb": "The starter hot hatch. Fair at everything: the car every other one is measured against."},
	{"id": "vector", "fuel": "regular", "tank": 52, "style": {"rim": "factory", "rim_color": "#2a2c30", "caliper": "#d9a21b", "badge": "VECTOR GS", "plate": "VGS 220"},
		"engine": {"cyl": 4, "idle": 820, "redline": 7000, "res": 2.2, "decay": 2.5, "var": 0.06, "uneven": 0.04, "rasp": 0.38, "pops": 0.4, "turbo": true},
		"name": "Vector GS", "shape": "sport_sedan", "color": "#c11a22", "price": 600, "boss": -1,
		"accel": 5.00, "pull": 4.0, "top": 53.5, "brake": 10.0, "grip": 9.1, "agility": 0.78, "stability": 1.25, "kg": 1560, "range": 21.0,
		"blurb": "A turbo saloon for the long haul: slow to get going, planted at speed, goes furthest on a tank."},
	{"id": "hornet", "fuel": "regular", "tank": 40, "style": {"rim": "factory", "rim_color": "#2a2c30", "caliper": "#c62828", "badge": "HORNET", "plate": "HRN 115"},
		"engine": {"cyl": 4, "idle": 880, "redline": 7200, "res": 2.5, "decay": 2.2, "var": 0.05, "uneven": 0.03, "rasp": 0.5, "pops": 0.5, "turbo": true},
		"name": "Hornet Compact", "shape": "compact", "color": "#e8b10f", "price": 800, "boss": -1,
		"accel": 5.80, "pull": 2.9, "top": 47.5, "brake": 9.2, "grip": 10.2, "agility": 1.40, "stability": 0.90, "kg": 1150, "range": 17.5,
		"blurb": "Short and light: turns on a coin and sips fuel. Runs out of top speed early, and is nervous there."},
	{"id": "comet", "fuel": "regular", "tank": 42, "style": {"rim": "factory", "rim_color": "#c3c8ce", "caliper": "#55595e", "badge": "COMET", "plate": "CMT 140"},
		"engine": {"cyl": 4, "idle": 820, "redline": 7000, "res": 2.4, "decay": 2.3, "var": 0.05, "uneven": 0.03, "rasp": 0.4, "pops": 0.3, "turbo": false},
		"name": "Comet Coupe", "shape": "coupe", "color": "#123f8c", "price": 1000, "boss": -1,
		"accel": 5.20, "pull": 4.5, "top": 52.0, "brake": 10.0, "grip": 10.5, "agility": 1.10, "stability": 1.20, "kg": 1230, "range": 15.0,
		"blurb": "Low and light: it grips and stops harder than its price says. Only average off the line."},
	{"id": "kestrel", "fuel": "regular", "tank": 40, "style": {"rim": "factory", "roofwing": true, "wiper": true, "caliper": "#55595e", "badge": "KESTREL", "plate": "KST 160"},
		"engine": {"cyl": 4, "idle": 850, "redline": 6800, "res": 2.3, "decay": 2.4, "var": 0.06, "uneven": 0.03, "rasp": 0.45, "pops": 0.2, "turbo": false},
		"name": "Kestrel 1.6", "shape": "kestrel", "color": "#d5dbe2", "price": 1200, "boss": -1,
		"accel": 6.50, "pull": 3.0, "top": 52.0, "brake": 9.2, "grip": 9.7, "agility": 1.25, "stability": 0.90, "kg": 1080, "range": 13.0,
		"blurb": "Feather-light and punchy: quick off the line and through the gears. Thirsty, and it brakes like a hatch."},
	{"id": "vanta", "fuel": "regular", "tank": 45, "style": {"rim": "factory", "lightbar": true, "splitter": true, "caliper": "#c62828", "badge": "VANTA GT", "plate": "VGT 057"},
		"engine": {"cyl": 6, "idle": 800, "redline": 7000, "res": 2.0, "decay": 2.6, "var": 0.08, "uneven": 0.04, "rasp": 0.35, "pops": 0.4, "turbo": true},
		"name": "Vanta GT", "shape": "vanta", "color": "#2f6fd6", "price": 2500, "boss": -1,
		"accel": 6.40, "pull": 3.4, "top": 57.0, "brake": 10.6, "grip": 10.2, "agility": 1.00, "stability": 1.25, "kg": 1600, "range": 17.0,
		"blurb": "A sport saloon with real brakes and a settled chassis: the first car that is quick and calm."},
	{"id": "bruiser", "fuel": "mid", "tank": 55, "style": {"rim": "factory", "rim_color": "#3a3d42", "accent": "#1b1e23", "caliper": "#c62828", "badge": "BRUISER", "plate": "BRZ 570"},
		"engine": {"cyl": 8, "idle": 700, "redline": 6300, "res": 1.4, "decay": 3.0, "var": 0.3, "uneven": 0.32, "rasp": 0.5, "pops": 0.9, "turbo": false},
		"name": "Bruiser 5.7", "shape": "bruiser", "color": "#e0a020", "price": 3200, "boss": -1,
		"accel": 8.80, "pull": 2.3, "top": 64.0, "brake": 9.6, "grip": 9.6, "agility": 0.80, "stability": 0.75, "kg": 1900, "range": 15.5,
		"blurb": "V8 torque and a lot of metal: huge shove, heavy, thirsty and a handful. Brake early, plan your moves."},
	{"id": "halcyon", "fuel": "premium", "tank": 52, "style": {"rim": "factory", "intakes": true, "vents": true, "splitter": true, "lightbar": true, "caliper": "#f5b52e", "badge": "HALCYON R", "plate": "HLC 072"},
		"engine": {"cyl": 10, "idle": 950, "redline": 8700, "res": 2.6, "decay": 2.1, "var": 0.08, "uneven": 0.05, "rasp": 0.3, "pops": 0.6, "turbo": false},
		"name": "Halcyon R", "shape": "halcyon", "color": "#f1f1ee", "price": 15000, "boss": -1,
		"accel": 9.50, "pull": 4.5, "top": 72.0, "brake": 12.0, "grip": 12.0, "agility": 1.25, "stability": 1.30, "kg": 1450, "range": 16.0,
		"blurb": "Mid-engine supercar: quick to turn in and planted at speed. Everything is sharper."},
	{"id": "copperhead", "fuel": "mid", "tank": 50, "style": {"rim": "factory", "rim_color": "#2a2c30", "stripes": true, "accent": "#f3f5ef", "scoop": true, "caliper": "#c62828", "badge": "COPPERHEAD", "plate": "BOSS 01"},
		"engine": {"cyl": 8, "idle": 720, "redline": 6800, "res": 1.5, "decay": 2.8, "var": 0.26, "uneven": 0.28, "rasp": 0.55, "pops": 1.0, "turbo": false},
		"name": "Copperhead", "shape": "copperhead", "color": "#c9652e", "price": 4000, "boss": 0,
		"accel": 7.40, "pull": 2.8, "top": 61.0, "brake": 10.6, "grip": 11.0, "agility": 1.05, "stability": 1.00, "kg": 1750, "range": 15.0,
		"blurb": "Stage 1 boss car. Muscle with manners: strong, grippy and steady, but hard on fuel."},
	{"id": "marshal", "fuel": "mid", "tank": 50, "style": {"rim": "factory", "rim_color": "#c3c8ce", "dome": true, "gills": true, "split_grille": true, "ltail": true, "halo": true, "lip": true, "crease": true, "m_bumper": true, "quad_diffuser": true, "caliper": "#1fa3ff", "badge": "MARSHAL", "plate": "BOSS 02"},
		"engine": {"cyl": 8, "idle": 850, "redline": 8400, "res": 2.0, "decay": 2.4, "var": 0.12, "uneven": 0.1, "rasp": 0.42, "pops": 0.8, "turbo": false},
		"name": "Night Marshal", "shape": "marshal", "color": "#1f2633", "price": 9000, "boss": 1,
		"accel": 8.60, "pull": 4.0, "top": 66.0, "brake": 11.8, "grip": 11.5, "agility": 1.00, "stability": 1.30, "kg": 1900, "range": 15.5,
		"blurb": "Stage 2 boss car. A heavy four-door that stays planted and brakes late. High-revving V8."},
	{"id": "static", "fuel": "premium", "tank": 48, "style": {"rim": "factory", "rim_color": "#f3f5ef", "stripes": true, "accent": "#f3f5ef", "intakes": true, "vents": true, "splitter": true, "caliper": "#1fa3ff", "badge": "BLUE STATIC", "plate": "BOSS 03"},
		"engine": {"cyl": 6, "idle": 900, "redline": 8200, "res": 2.5, "decay": 2.2, "var": 0.05, "uneven": 0.02, "rasp": 0.3, "pops": 0.5, "turbo": true},
		"name": "Blue Static", "shape": "static", "color": "#1fa3ff", "price": 18000, "boss": 2, "route": 4,
		"accel": 10.20, "pull": 3.2, "top": 75.0, "brake": 12.0, "grip": 13.0, "agility": 1.55, "stability": 0.75, "kg": 1500, "range": 16.0,
		"blurb": "Blue Static's own car, on sale once you have cleared the fifth highway. Twitchy and very fast."},
	{"id": "lastexit", "fuel": "premium", "tank": 58, "style": {"rim": "factory", "rim_color": "#c9a227", "stripes": true, "accent": "#1b1e23", "intakes": true, "vents": true, "splitter": true, "lightbar": true, "caliper": "#c62828", "badge": "LAST EXIT", "plate": "BOSS 04"},
		"engine": {"cyl": 12, "idle": 1000, "redline": 9200, "res": 2.8, "decay": 1.9, "var": 0.05, "uneven": 0.02, "rasp": 0.25, "pops": 0.5, "turbo": false},
		"name": "Last Exit", "shape": "lastexit", "color": "#b0122a", "price": 30000, "boss": 3, "route": 7,
		"accel": 11.00, "pull": 5.0, "top": 81.0, "brake": 13.0, "grip": 14.0, "agility": 1.15, "stability": 1.50, "kg": 1750, "range": 17.0,
		"blurb": "Last Exit's own car, on sale once you have cleared the eighth highway. The fastest, and the most planted."},
]

# Workshop paint and wheel options ("" = the car's factory colour).
const PAINTS := [["Factory", ""],
	["Arctic white", "#eef0f2"], ["Pearl white", "#f5f1e6"], ["Champagne", "#d8c8a8"], ["Silver", "#b9bec4"],
	["Gunmetal", "#52575e"], ["Graphite", "#3a3d42"], ["Charcoal", "#2a2d31"], ["Midnight black", "#121316"], ["Chocolate", "#4a2f20"],
	["Race red", "#c4161c"], ["Crimson", "#9d1127"], ["Burgundy", "#5a0f1e"], ["Hot pink", "#e6338a"], ["Magenta", "#a3187d"],
	["Sunburst orange", "#e86a12"], ["Sunset", "#ff5a3c"], ["Copper", "#b8622f"], ["Bronze", "#8a5a2b"], ["Rose gold", "#c98a7a"],
	["Taxi yellow", "#e8b10f"], ["Gold", "#d6a229"], ["Mustard", "#b88a14"], ["Sand", "#c9b48a"], ["Olive", "#5b6130"],
	["Lime", "#7cc242"], ["Mint", "#7fd1b0"], ["Racing green", "#1f4d2e"], ["Emerald", "#0d7a4a"], ["Teal", "#0e8a8a"],
	["Sky blue", "#4aa3e0"], ["Electric blue", "#1f6fe0"], ["Cobalt", "#1946b8"], ["Deep navy", "#14254f"], ["Indigo", "#35247a"],
	["Royal purple", "#5b2a86"], ["Violet", "#7a2fc0"], ["Lavender", "#9a86d6"], ["Ice blue", "#bcd9ee"], ["Peach", "#ffb38a"]]

## Paint finishes the workshop sells (CarModel.FINISH_LOOKS is how each one looks). A finish is bought once, for $price,
## and can then be put on any car; gloss is the factory finish and costs nothing.
const FINISHES := [
	{"id": "gloss", "name": "Gloss", "price": 0, "blurb": "The factory finish: deep and shiny."},
	{"id": "semigloss", "name": "Semi-gloss", "price": 150, "blurb": "Satin lacquer: a soft sheen, no mirror."},
	{"id": "matte", "name": "Matte", "price": 250, "blurb": "Flat and dark. Nothing reflects."},
	{"id": "metallic", "name": "Metallic", "price": 400, "blurb": "Heavy metal flake that glitters in the sun."},
	{"id": "pearl", "name": "Pearlescent", "price": 800, "blurb": "The colour turns to another as the light moves over it."},
	{"id": "candy", "name": "Candy", "price": 1200, "blurb": "A deep tinted lacquer over bright metal."},
	{"id": "chrome", "name": "Chrome", "price": 3500, "blurb": "A mirror finish. Costs what it looks like."},
]


func finish_by_id(id: String) -> Dictionary:
	for f in FINISHES:
		if f.id == id:
			return f
	return FINISHES[0]
## The workshop's wheel designs, every one built with the garage designer's own wheel (tools/garage/export_wheels.js:
## assets/models/wheels/) and fitted to each car's rims and tyres (besides each car's own, "Factory").
const RIMS := [["steel", "Steel"], ["5spoke", "5-spoke"], ["multi", "Multi-spoke"], ["mesh", "Mesh"], ["turbine", "Turbine"], ["double", "Double-spoke"],
	["split", "Split-spoke"], ["blade", "Blade"], ["aero", "Aero"], ["wire", "Wire"], ["tri", "Tri-spoke"], ["star", "Star"], ["vent", "Vented disc"], ["deep", "Deep dish"],
	["y5", "Y-spoke"], ["twist10", "Twisted 10"], ["classic", "Classic 5"], ["pepper", "Pepper-pot"], ["forged", "Forged twin"], ["rally", "Rally"],
	["hubcap", "Steel & cap"], ["mono12", "Monoblock 12"], ["directional", "Directional"], ["track7", "Track 7"]]
const RIM_CHROME := "#e6eaee"  # (the wheel colour that is polished chrome)
const RIM_COLORS := [["Silver", "#c3c8ce"], ["Chrome", "#e6eaee"], ["Gunmetal", "#5b5f64"], ["Anthracite", "#34373c"],
	["Black", "#2a2c30"], ["Gloss black", "#0d0e10"], ["White", "#f3f5ef"], ["Gold", "#c9a227"],
	["Bronze", "#8c6a3e"], ["Copper", "#b8622f"], ["Red", "#c4161c"], ["Orange", "#e86a12"],
	["Lime", "#7cc242"], ["Blue", "#1f6fe0"], ["Purple", "#6a2fb0"], ["Pink", "#e6338a"]]

const BOSSES := [
	{"name": "Copperhead", "car": "copperhead", "line": "Lives in the left lane and never signals. Beat his score before the gantry."},
	{"name": "Night Marshal", "car": "marshal", "line": "Cold, precise, brakes later than you think possible."},
	{"name": "Blue Static", "car": "static", "line": "Threads gaps you did not know were there."},
	{"name": "Last Exit", "car": "lastexit", "line": "Nobody has seen the end of this highway after racing her."},
]

const PERM := [
	{"id": "accel", "name": "Engine tune", "desc": "+6% acceleration per level", "max": 5, "base": 300},
	{"id": "brake", "name": "Brake package", "desc": "+6% braking per level", "max": 5, "base": 250},
	{"id": "handling", "name": "Tyres & suspension", "desc": "+6% grip per level", "max": 5, "base": 300},
	{"id": "top", "name": "Gearing", "desc": "+4% top speed per level", "max": 5, "base": 400},
	{"id": "lives", "name": "Spare chassis", "desc": "+1 life at the start of each run", "max": 2, "base": 1500},
]

# Upgrades offered after beating a boss (applied for the rest of the run).
const BOONS := [
	{"id": "accel", "name": "Turbo kit", "desc": "+15% acceleration for this run", "tag": "ACCELERATION"},
	{"id": "brake", "name": "Big brakes", "desc": "+20% braking for this run", "tag": "BRAKING"},
	{"id": "handling", "name": "Sticky tyres", "desc": "+12% grip for this run", "tag": "HANDLING"},
	{"id": "top", "name": "Long gears", "desc": "+7% top speed for this run", "tag": "TOP SPEED"},
	{"id": "life", "name": "Spare wheel", "desc": "+1 life (max 6)", "tag": "EXTRA LIFE"},
	{"id": "score", "name": "Show-off", "desc": "+15% to every point earned", "tag": "SCORE"},
	{"id": "combo", "name": "Adrenaline", "desc": "Combo timer lasts 1 s longer", "tag": "COMBO"},
	{"id": "fuel", "name": "Pit crew", "desc": "Fills your tank to the brim, free", "tag": "REFUEL"},
	{"id": "shield", "name": "Crumple zone", "desc": "The next hit costs no life", "tag": "SHIELD"},
	{"id": "armour", "name": "Roll cage", "desc": "1.5 s longer protection after every hit", "tag": "DEFENCE"},
	{"id": "calm", "name": "Rolling roadblock", "desc": "Traffic drives 10% slower for this run", "tag": "TRAFFIC"},
	{"id": "eco", "name": "Eco tune", "desc": "Burns 25% less fuel for this run", "tag": "FUEL"},
	{"id": "radar", "name": "Radar jammer", "desc": "Warns of a police speed check 250 m ahead, in time to slow down", "tag": "POLICE"},
	{"id": "cash", "name": "Sponsor deal", "desc": "A bonus of $400 per stage cleared, now", "tag": "CASH"},
	# rare: offered after about one boss in eight (RARE_CHANCE), never in the ordinary shuffle
	{"id": "drift", "name": "Drift tune", "desc": "Rear-drive drift setup with a drift assist: slide it sideways for points, and every point counts 100 times. Driven like a real drift car", "tag": "RARE · DRIFT", "rare": true},
]
const RARE_CHANCE := 0.12   # how often a rare upgrade is one of the cards after a boss
const DRIFT_SCORE := 100    # the drift tune: every point counts this many times in the run's score (not in its money, nor in a stage's or a boss race's target)

const TRAFFIC_COLORS := ["#c9ccd1", "#dfe2e4", "#26292f", "#50555d", "#1f3a66", "#9b1c1c",
	"#5a1f2b", "#cbb995", "#2d4a36", "#7b8a99", "#a9b3bd", "#d9d5c9"]
const TRUCK_BOX_COLORS := ["#d6d8d3", "#cfc8b8", "#b9c1c7", "#8e3b2f", "#2f4f7a"]
const TRUCK_CAB_COLORS := ["#b5322a", "#1f4e8c", "#2a2d33", "#d9a21b", "#3d6b3a"]
const ROMAN := ["", "II", "III", "IV", "V", "VI", "VII", "VIII"]
const MAX_LIVES := 6

# Fuel. The cheaper cars run on regular, the middle ones on mid-grade and the
# fastest on premium. Every station sets its own prices; on average mid-grade
# costs $5 a litre more than regular and premium $15 more at the first stop of a
# run, and every stop after it costs 5 to 25% more than the one before. How far a
# full tank goes is the car's own `range` (km, driven flat out, longer driven
# gently); its `tank` (litres) is what a fill costs.
const FUEL_GRADES := {
	"regular": {"name": "Regular", "short": "REG", "add": 0.0},
	"mid": {"name": "Mid-grade", "short": "MID", "add": 5.0},
	"premium": {"name": "Premium", "short": "PREM", "add": 15.0},
}
const FUEL_ORDER := ["regular", "mid", "premium"]
const STATION_EVERY_KM := 10.0 # a fuel stop about every 10 km
const STATION_NAMES := ["Sunset Fuel", "Pump & Go", "Interstate Oil", "Blue Flame Gas", "Crossroads Fuel",
	"Mesa Petroleum", "Lucky Stop", "Northstar Gas", "Prairie Pumps", "Redline Fuel", "Last Chance Gas", "Eagle Fuel"]
const STATION_COLORS := ["#c62828", "#1f4e8c", "#2e7d32", "#ef6c00", "#6a1b9a", "#00838f", "#c9a227", "#37474f"]

# Fuel gets dearer as a run goes on: every fuel stop asks 5 to 25% more than the one before it (see raised_price), whether
# or not the run stopped at that one. The first stop of a run charges the prices above.
const PRICE_RISE_MIN := 0.05
const PRICE_RISE_MAX := 0.25


## A price as a pump shows it: a whole number of tenths of a dollar and a 9 (3.49, 18.99).
static func pump_price(v: float) -> float:
	return snappedf(floorf(v * 10.0 + 1e-6) / 10.0 + 0.09, 0.01)


## What a fuel stop asks when the one before asked `p` for the same grade and this stop's rise is `rise` (a fraction, 0.05
## to 0.25): the pump price nearest p x (1 + rise), but never less than 5% or more than 25% above p, whatever the
## rounding does (pump prices move in steps of ten cents, so $3.49 cannot rise by exactly 6%).
static func raised_price(p: float, rise: float) -> float:
	var k := roundf((p * (1.0 + rise) - 0.09) / 0.1)
	var hi := floorf((p * (1.0 + PRICE_RISE_MAX) - 0.09) / 0.1 + 1e-6)
	var lo := minf(ceilf((p * (1.0 + PRICE_RISE_MIN) - 0.09) / 0.1 - 1e-6), hi)
	return snappedf(clampf(k, lo, hi) * 0.1 + 0.09, 0.01)

## Shrinks the distance between fuel stops (and the tank range with it). Only
## changed by the --stations test flag.
var station_scale := 1.0

# Camera views. chase: height/dist in metres behind the car. hood and cockpit:
# height/dist are offsets from the default eye point (dist > 0 moves forward).
# angle is the pitch in degrees (negative looks down).
const CAM_MODES := ["chase", "hood", "cockpit"]
const CAM_NAMES := {"chase": "Chase", "hood": "Hood", "cockpit": "Cockpit"}
const CAM_DEFAULTS := {
	"chase": {"fov": 62.0, "height": 7.5, "dist": 10.5, "angle": -15.0},
	"hood": {"fov": 75.0, "height": 0.0, "dist": 0.0, "angle": -3.0},
	"cockpit": {"fov": 70.0, "height": 0.0, "dist": 0.0, "angle": -1.0},
}
const CAM_RANGES := {
	"chase": {"fov": [45.0, 100.0], "height": [2.0, 14.0], "dist": [4.0, 22.0], "angle": [-45.0, 0.0]},
	"hood": {"fov": [50.0, 110.0], "height": [-0.3, 1.0], "dist": [-1.0, 1.0], "angle": [-25.0, 15.0]},
	"cockpit": {"fov": [50.0, 110.0], "height": [-0.25, 0.35], "dist": [-0.5, 0.6], "angle": [-25.0, 15.0]},
}
const BOSS_RACE_LENGTH := 2000.0

## Multiplies stage and boss targets. Only changed by the --fast test flag.
var target_scale := 1.0
var route := 0  # the highway being driven (index into ROUTES); harder the further along


# ---------------------------------------------------------------- world map

## Fifteen cities joined end to end by fourteen highways. Each highway is its
## own endless run; beating its final (fourth) boss opens the next one.
## "pos" is the city's place on the map (0..1 across, 0..1 down).
const CITIES := [
	{"name": "Port Halden", "pos": Vector2(0.12, 0.88)}, {"name": "Ashford", "pos": Vector2(0.34, 0.92)},
	{"name": "Millbrook", "pos": Vector2(0.58, 0.86)}, {"name": "Cedar Falls", "pos": Vector2(0.84, 0.82)},
	{"name": "Red Mesa", "pos": Vector2(0.88, 0.66)}, {"name": "Dustwater", "pos": Vector2(0.66, 0.62)},
	{"name": "Silver Lake", "pos": Vector2(0.42, 0.66)}, {"name": "Ironvale", "pos": Vector2(0.17, 0.6)},
	{"name": "Northgate", "pos": Vector2(0.12, 0.42)}, {"name": "Granite Pass", "pos": Vector2(0.36, 0.38)},
	{"name": "Copper Ridge", "pos": Vector2(0.6, 0.42)}, {"name": "Sunset Bay", "pos": Vector2(0.86, 0.36)},
	{"name": "Lakeshore", "pos": Vector2(0.82, 0.16)}, {"name": "Neon Heights", "pos": Vector2(0.54, 0.12)},
	{"name": "Summit City", "pos": Vector2(0.24, 0.14)},
]

## Landscape colours for each kind of country a highway runs through.
const BIOMES := {
	"meadow": {"fog": Color("#d2cdbd"), "flora": "temperate", "style": 0, "accent": Color(0.4, 0.3, 0.19), "title": "Green farmland", "grass_a": Color(0.32, 0.45, 0.17), "grass_b": Color(0.28, 0.4, 0.15), "field": Color(0.56, 0.5, 0.26), "dirt": Color(0.42, 0.37, 0.28), "sky": Color("#2b5c96"), "hor": Color("#d9d2c2")},
	"autumn": {"fog": Color("#dccdae"), "flora": "autumn", "style": 0, "accent": Color(0.5, 0.29, 0.13), "title": "Autumn woods", "grass_a": Color(0.42, 0.4, 0.17), "grass_b": Color(0.38, 0.33, 0.14), "field": Color(0.62, 0.44, 0.2), "dirt": Color(0.45, 0.33, 0.22), "sky": Color("#3a6496"), "hor": Color("#e0d0b4")},
	"desert": {"fog": Color("#e6d2a8"), "flora": "desert", "style": 1, "accent": Color(0.47, 0.45, 0.27), "title": "Desert flats", "grass_a": Color(0.66, 0.52, 0.32), "grass_b": Color(0.6, 0.46, 0.28), "field": Color(0.74, 0.6, 0.38), "dirt": Color(0.62, 0.42, 0.26), "sky": Color("#2f6fb0"), "hor": Color("#ecd9b8")},
	"pine": {"fog": Color("#bfcacc"), "flora": "conifer", "style": 2, "accent": Color(0.17, 0.3, 0.13), "title": "Northern pines", "grass_a": Color(0.2, 0.33, 0.17), "grass_b": Color(0.17, 0.29, 0.14), "field": Color(0.36, 0.4, 0.24), "dirt": Color(0.33, 0.3, 0.24), "sky": Color("#3d6488"), "hor": Color("#cfd6d8")},
	"coast": {"fog": Color("#cfdde0"), "flora": "coast", "style": 3, "sea_x": -112.0, "accent": Color(0.52, 0.56, 0.27), "title": "Coast road", "grass_a": Color(0.4, 0.5, 0.24), "grass_b": Color(0.36, 0.46, 0.22), "field": Color(0.78, 0.7, 0.5), "dirt": Color(0.64, 0.58, 0.44), "sky": Color("#2a6ab4"), "hor": Color("#e4e4dc")},
	"tundra": {"fog": Color("#d8e0e9"), "flora": "snow", "style": 4, "accent": Color(0.5, 0.45, 0.38), "title": "Frosted plains", "grass_a": Color(0.78, 0.8, 0.82), "grass_b": Color(0.72, 0.75, 0.78), "field": Color(0.86, 0.87, 0.88), "dirt": Color(0.55, 0.55, 0.56), "sky": Color("#4a6c90"), "hor": Color("#dfe4ea")},
}

const ROUTES := [
	{"name": "I-10", "biome": "meadow"}, {"name": "I-14", "biome": "meadow"}, {"name": "I-21", "biome": "autumn"},
	{"name": "I-27", "biome": "desert"}, {"name": "I-30", "biome": "desert"}, {"name": "I-35", "biome": "coast"},
	{"name": "I-40", "biome": "autumn"}, {"name": "I-44", "biome": "pine"}, {"name": "I-55", "biome": "pine"},
	{"name": "I-60", "biome": "tundra"}, {"name": "I-64", "biome": "desert"}, {"name": "I-70", "biome": "coast"},
	{"name": "I-77", "biome": "tundra"}, {"name": "I-80", "biome": "meadow"},
]


func route_info(i: int) -> Dictionary:
	var r: Dictionary = ROUTES[clampi(i, 0, ROUTES.size() - 1)].duplicate()
	r["from"] = CITIES[i].name
	r["to"] = CITIES[i + 1].name
	r["title"] = "%s · %s → %s" % [r.name, r.from, r.to]
	r["land"] = BIOMES[r.biome]
	return r


## Each highway further along asks for more: score targets and boss skill rise.
func route_scale() -> float:
	return 1.0 + 0.14 * route


## The highway (0 is the first) that has to be cleared before a car goes on sale: -1 for a car that goes on sale as
## soon as its boss is beaten (Copperhead, Night Marshal); Blue Static comes with the fifth highway, Last Exit with the eighth.
func car_unlock_route(c: Dictionary) -> int:
	return int(c.get("route", -1))


func car_by_id(id: String) -> Dictionary:
	for c in CARS:
		if c.id == id:
			return c
	return CARS[0]


## How much of the road's traffic there is for a car going at v m/s, as a share of what the stage has. Up to 50 m/s (180 km/h)
## all of it; above that the faster the car the fewer cars (36% fewer at 80 m/s): the cars come at you faster, so the same
## road gives you less time to find a gap, and at 280 km/h in the traffic of stage 8 there were none to find (the autopilot
## averaged 107 km/h there, no more than at 160: tools/economy_sim.py --sweep).
func traffic_for_speed(v: float) -> float:
	return clampf(1.0 - 0.012 * (v - 50.0), 0.6, 1.0) if speed_traffic else 1.0


## Off with --flat-traffic (a test aid: the traffic as it was before the rule above).
var speed_traffic := true


func stage_req(stage: int) -> Dictionary:
	return {
		"d": (2400.0 + 400.0 * stage) * target_scale,
		"p": roundi(4000.0 * pow(1.55, stage - 1) * route_scale() / 100.0) * 100 * target_scale,
	}


func boss_total(stage: int) -> int:
	return int(roundi(5000.0 * pow(1.55, stage - 1) * route_scale() / 100.0) * 100 * target_scale)


## How far along the map a highway is: 0 for the first, 1 for the last.
func route_t(r := -1) -> float:
	return clampf(float(route if r < 0 else r) / float(ROUTES.size() - 1), 0.0, 1.0)


## How good a boss is at scoring: 0 is a rookie, 1 an expert, more than that a legend. It climbs with the
## highway (the bosses of the first highways are easy, those of the last are the hardest there are) and
## from boss to boss along each highway, a little at first and more and more steeply further on. Every
## lap of the four bosses (a highway goes on after its fourth) adds more on top.
func boss_skill(stage: int, r := -1) -> float:
	var i := (stage - 1) % BOSSES.size()
	var tier := (stage - 1) / BOSSES.size()
	var rt := route_t(r)
	var rank := minf(lerpf(0.0, 0.85, rt) + i * lerpf(0.1, 0.3, rt) + 0.28 * tier, 1.9)
	return rank + BOSS_FLOOR * maxf(0.0, 1.0 - rank / BOSS_FLOOR_END)


## The lower bosses were rookies (the first boss of the first highway raced at skill 0, leaving a metre beside a car and
## driving 147 km/h) and far too easy. Now even the first race like a driver this much better than their rank in the
## climb says: it fades out, and bosses of a rank of BOSS_FLOOR_END and more (from about the ninth highway) race as they did.
const BOSS_FLOOR := 0.45
const BOSS_FLOOR_END := 1.25


## What a boss's race is meant to score, in points over its 2 km: the first and the last of the four bosses of a highway,
## for the highways listed (a highway between two of them gets the numbers in between, and the four bosses of a highway step
## evenly from the first to the last). From I-40 on they are what the bosses made before (measured: about 8,700 for the
## first boss of I-40 and 14,500 for the last, 25,800 for the last of I-60 and 35,700 for the last of I-80, the targets the
## game has always had being 16,200, 25,900 and 34,000 for the last bosses of I-40, I-60 and I-80); the first highways' were
## far too low, a rookie that left a metre beside a car and made 1,600 points for the first boss of I-10 and 5,100 for the
## last, and are raised to 3,800 and 8,500, and the ones after them in step. Every lap of the four bosses after the first is
## harder again, by LAP_PAR (up to LAP_MAX laps). Measured against the autopilot, which makes 2,000 to 3,500 in a race (a player who goes for
## the passes makes more).
const BOSS_PAR := [[0, 3800.0, 8500.0], [1, 5500.0, 10000.0], [2, 6500.0, 11500.0], [3, 7500.0, 12500.0], [4, 8500.0, 13500.0],
	[6, 9500.0, 15000.0], [9, 12500.0, 25000.0], [13, 19000.0, 35000.0]]
const LAP_PAR := 1.3
const LAP_MAX := 4  # (the bosses stop getting harder with the laps after this one: they did the same, at the skill's cap)


## The score the boss of this stage is meant to make (BOSS_PAR).
func boss_par(stage: int, r := -1) -> float:
	var rr := float(route if r < 0 else r)
	var t: Array = BOSS_PAR
	var first := float(t[0][1])
	var last := float(t[0][2])
	if rr >= float(t[t.size() - 1][0]):
		first = float(t[t.size() - 1][1])
		last = float(t[t.size() - 1][2])
	else:
		for k in range(1, t.size()):
			if rr <= float(t[k][0]):
				var u := (rr - float(t[k - 1][0])) / (float(t[k][0]) - float(t[k - 1][0]))
				first = lerpf(float(t[k - 1][1]), float(t[k][1]), u)
				last = lerpf(float(t[k - 1][2]), float(t[k][2]), u)
				break
	var i := (stage - 1) % BOSSES.size()
	var lap := (stage - 1) / BOSSES.size()
	return lerpf(first, last, float(i) / float(BOSSES.size() - 1)) * pow(LAP_PAR, mini(lap, LAP_MAX))


## What a boss earns in a race by driving at skill `sk`, if its driving were scored at face value (`boss_edge` 1): about
## BOSS_YIELD * exp(BOSS_YIELD_PER_SKILL * sk) points, times a factor for the car it drives (the Night Marshal's makes
## a sixth more than the Copperhead's). Measured: tools/boss_cal.py --extra=--boss-edge=1.0, 8 races at every highway and
## stage (the fit is within 13% of the mean of each set of eight, which is about as close as it can be: a single race varies
## by 40% and more, most of all for the best bosses, whose razor passes are worth thousands each). It has to be measured
## again if the way a boss drives or scores changes.
const BOSS_YIELD := 7200.0
const BOSS_YIELD_PER_SKILL := 0.745
const BOSS_CAR_YIELD := [1.0, 1.165, 1.083, 1.073]


func boss_yield(sk: float, stage: int) -> float:
	var i := (stage - 1) % BOSSES.size()
	return BOSS_YIELD * float(BOSS_CAR_YIELD[i]) * exp(BOSS_YIELD_PER_SKILL * sk)


## How generously a boss's driving is scored (bosses score more than their driving alone earns for the first highways,
## where they drive for less than they are worth, and less for the last): the number the driving's points are multiplied
## by so that the boss's race comes to what it is meant to be (`boss_par`, over what its skill earns: `boss_yield`).
func boss_edge(stage: int, r := -1) -> float:
	return boss_par(stage, r) / boss_yield(boss_skill(stage, r), stage)


## What a boss's driving is worth in points on top of `boss_edge`: a factor by skill, so that each boss keeps the
## difficulty it always had (the pop-ups over the boss show the points of a pass as they were; the rest of what it is
## worth comes into the rival's score smoothly over the next second or two, and with the speed bonus). The old driver slid sideways in a frame and drove through cars; the new one drives like a
## player, close but never through a car, so for the same skill it earns less, and its scores are brought back to where
## they were (the numbers are measured: the mean rival score of 6 test races at each skill, over the target for it).
## Pairs of (skill, factor); in between the factor is interpolated.
const BOSS_STYLE := [[0.0, 2.7], [0.3, 2.3], [0.63, 2.2], [0.97, 2.3], [1.3, 2.1], [1.75, 1.75]]


func boss_style(sk: float) -> float:
	var t: Array = BOSS_STYLE
	if sk <= float(t[0][0]):
		return float(t[0][1])
	for i in range(1, t.size()):
		if sk <= float(t[i][0]):
			var a: Array = t[i - 1]
			var b: Array = t[i]
			return lerpf(float(a[1]), float(b[1]), (sk - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(t[t.size() - 1][1])


const DIFFICULTY_NAMES := ["EASY", "EASY", "EASY", "MODERATE", "MODERATE", "MODERATE", "HARD", "HARD", "HARD",
	"VERY HARD", "VERY HARD", "VERY HARD", "BRUTAL", "BRUTAL"]


## What to call the bosses of highway i on the map.
func route_difficulty(i: int) -> String:
	return DIFFICULTY_NAMES[clampi(i, 0, DIFFICULTY_NAMES.size() - 1)]


const SKILL_NAMES := ["ROOKIE", "SKILLED", "EXPERT", "LEGEND", "UNTOUCHABLE"]


func boss_skill_name(stage: int) -> String:
	return SKILL_NAMES[clampi(int(boss_skill(stage) / 0.3), 0, SKILL_NAMES.size() - 1)]


func boss_info(stage: int) -> Dictionary:
	var i := (stage - 1) % BOSSES.size()
	var tier := (stage - 1) / BOSSES.size()
	var b: Dictionary = BOSSES[i].duplicate()
	b["idx"] = i
	b["full"] = b.name + ("" if tier == 0 else " " + ROMAN[mini(tier, ROMAN.size() - 1)])
	return b


func perm_cost(p: Dictionary, level: int) -> int:
	return roundi(p.base * pow(1.85, level) / 10.0) * 10


## How much a car's wear (0 as new .. 1 wrecked, see Save.wear) takes off its performance, as multipliers on its stats
## (and on its fuel use): see CarStats.damage_effects.
func damage_effects(wear: float) -> Dictionary:
	return CarStats.damage_effects(wear)


## The wear at which a car is a wreck (the garage shows it as 100%). A wreck ends the run it is in at once, whatever
## lives are left, and cannot be driven until it has been repaired.
const WRECKED_AT := 0.995


func is_wrecked(wear: float) -> bool:
	return wear >= WRECKED_AT


## What the garage charges to repair a car ($): a call-out fee, and more the worse the damage and the dearer the car.
func repair_cost(car: Dictionary, wear: float) -> int:
	if wear <= 0.004:
		return 0
	return roundi((40.0 + clampf(wear, 0.0, 1.0) * (150.0 + 0.012 * float(car.get("price", 0)))) / 10.0) * 10


## How much wear a knock adds to the car that took it (strength: the change of speed it gave the car, m/s): a tap
## leaves next to none, a hard knock (12 m/s and more) a seventh of the car's life.
func wear_for_strength(strength: float) -> float:
	return clampf((strength - 2.0) / 10.0, 0.0, 1.0) * 0.15


func nearest_lane(x: float) -> int:
	var best := 0
	for i in range(1, 4):
		if absf(LANES[i] - x) < absf(LANES[best] - x):
			best = i
	return best

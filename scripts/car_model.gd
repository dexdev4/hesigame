class_name CarModel
extends Node3D
## Low-poly vehicle with real proportions. The body is lofted from a side
## profile with rounded shoulders; the greenhouse has a raked windshield and
## rear glass with painted pillars. Geometry is built once per vehicle type
## and shared; only materials differ per car. Origin is the centre of the
## rear bumper at ground level; the car faces -Z.

static var _mats := {}
static var _meshes := {}
static var _kits := {}
static var _shadow_mat: StandardMaterial3D
static var _shadow_mesh: PlaneMesh
static var night := 0.0  # 0 = day .. 1 = dusk with headlights on (set_night)
static var _beam_mat: StandardMaterial3D
static var _beam_mesh: ArrayMesh

# Per-type body data. body stations: [distance from rear (m), top height, width scale].
# gh (greenhouse): [base rear z, base front z, roof rear z, roof front z, base y, roof y, base width, roof width].
# pillars: side-window pillar spans along the side, 0 = rear edge, 1 = front edge.
const PROFILES := {
	# BEGIN IMPORTED PROFILES
	"kestrel": {
		"mesh": "res://assets/models/car_kestrel.mesh",
		"mesh_lq": "res://assets/models/car_kestrel_lq.mesh",
		"body": [[0, 1.07, 0.847], [0.1, 1.051, 0.895], [0.3, 1.051, 0.976], [0.7, 1.051, 0.998], [1.2, 1.051, 0.997], [1.8, 1.051, 0.959], [2.4, 1.051, 0.952], [3, 0.904, 0.989], [3.5, 0.826, 0.968], [3.9, 0.737, 0.923], [4.2, 0.654, 0.809], [4.25, 0.61, 0.707]],
		"gh": [0.07, 2.535, 0.295, 1.93, 1.011, 1.418, 0.919, 0.559],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.235, 0.235],
		"wheel": [0.35, 0.75, 3.39],
		"wheel_x": [0.815, 0.8],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.3,
		"eye_y": 1.248,
		"dash_drop": 0,
		"dash_hw": 0.53,
		"ws_base_hw": 0.5,
		"mirror_d": 1.88},
	"bruiser": {
		"mesh": "res://assets/models/car_bruiser.mesh",
		"mesh_lq": "res://assets/models/car_bruiser_lq.mesh",
		"body": [[0, 0.879, 0.857], [0.1, 0.899, 0.913], [0.3, 0.91, 0.95], [0.7, 1.037, 1], [1.2, 0.995, 0.997], [1.8, 0.995, 0.954], [2.4, 0.995, 0.944], [3, 0.857, 0.942], [3.5, 0.841, 0.976], [3.9, 0.82, 0.95], [4.2, 0.791, 0.959], [4.8, 0.648, 0.715]],
		"gh": [0.73, 2.495, 1.33, 2.055, 0.955, 1.289, 0.83, 0.524],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.265, 0.265],
		"wheel": [0.36, 1.02, 3.85],
		"wheel_x": [0.835, 0.81],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.3,
		"eye_y": 1.088,
		"dash_drop": 0.17,
		"dash_hw": 0.52,
		"ws_base_hw": 0.49,
		"mirror_d": 2.01},
	"copperhead": {
		"mesh": "res://assets/models/car_copperhead.mesh",
		"mesh_lq": "res://assets/models/car_copperhead_lq.mesh",
		"body": [[0, 0.879, 0.857], [0.1, 0.899, 0.913], [0.3, 0.91, 0.95], [0.7, 1.037, 1], [1.2, 0.995, 0.997], [1.8, 0.995, 0.954], [2.4, 0.995, 0.944], [3, 0.857, 0.942], [3.5, 0.841, 0.976], [3.9, 0.82, 0.95], [4.2, 0.791, 0.959], [4.8, 0.648, 0.715]],
		"gh": [0.73, 2.495, 1.33, 2.055, 0.955, 1.289, 0.83, 0.524],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.265, 0.265],
		"wheel": [0.36, 1.02, 3.85],
		"wheel_x": [0.835, 0.81],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.3,
		"eye_y": 1.088,
		"dash_drop": 0.17,
		"dash_hw": 0.52,
		"ws_base_hw": 0.49,
		"mirror_d": 2.01},
	"halcyon": {
		"mesh": "res://assets/models/car_halcyon.mesh",
		"mesh_lq": "res://assets/models/car_halcyon_lq.mesh",
		"body": [[0, 0.841, 0.871], [0.1, 0.856, 0.923], [0.3, 0.874, 0.965], [0.7, 0.919, 0.995], [1.2, 0.896, 1], [1.8, 0.896, 0.947], [2.4, 0.896, 0.918], [3, 0.794, 0.937], [3.5, 0.795, 0.888], [3.9, 0.73, 0.94], [4.2, 0.623, 0.875], [4.5, 0.473, 0.666]],
		"gh": [0.815, 2.655, 1.555, 2.325, 0.856, 1.104, 0.744, 0.545],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.27, 0.27],
		"wheel": [0.35, 0.87, 3.52],
		"wheel_x": [0.87, 0.835],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.49,
		"eye_y": 0.832,
		"dash_drop": 0.17,
		"dash_hw": 0.5,
		"ws_base_hw": 0.47,
		"mirror_d": 2.28},
	"static": {
		"mesh": "res://assets/models/car_static.mesh",
		"mesh_lq": "res://assets/models/car_static_lq.mesh",
		"body": [[0, 0.841, 0.871], [0.1, 0.856, 0.923], [0.3, 0.874, 0.965], [0.7, 0.919, 0.995], [1.2, 0.899, 1], [1.8, 0.899, 0.947], [2.4, 0.899, 0.918], [3, 0.794, 0.937], [3.5, 0.795, 0.888], [3.9, 0.73, 0.94], [4.2, 0.623, 0.875], [4.5, 0.473, 0.666]],
		"gh": [0.835, 2.655, 1.555, 2.325, 0.859, 1.104, 0.744, 0.545],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.27, 0.27],
		"wheel": [0.35, 0.87, 3.52],
		"wheel_x": [0.87, 0.835],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.49,
		"eye_y": 0.828,
		"dash_drop": 0.17,
		"dash_hw": 0.5,
		"ws_base_hw": 0.47,
		"mirror_d": 2.28},
	"marshal": {
		"mesh": "res://assets/models/car_marshal.mesh",
		"mesh_lq": "res://assets/models/car_marshal_lq.mesh",
		"body": [[0, 0.942, 0.781], [0.1, 0.99, 0.873], [0.3, 1.007, 0.926], [0.7, 1.111, 0.993], [1.2, 1.071, 1], [1.8, 1.071, 0.961], [2.4, 1.071, 0.951], [3, 1.119, 0.949], [3.5, 0.901, 0.985], [3.9, 0.843, 0.966], [4.2, 0.789, 0.96], [4.765, 0.61, 0.704]],
		"gh": [0.75, 2.975, 1.35, 2.425, 1.031, 1.398, 0.914, 0.556],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.245, 0.245],
		"wheel": [0.35, 1.035, 3.885],
		"wheel_x": [0.815, 0.8],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.3,
		"eye_y": 1.228,
		"dash_drop": 0,
		"dash_hw": 0.53,
		"ws_base_hw": 0.5,
		"mirror_d": 2.38},
	"lastexit": {
		"mesh": "res://assets/models/car_lastexit.mesh",
		"mesh_lq": "res://assets/models/car_lastexit_lq.mesh",
		"body": [[0, 0.814, 0.813], [0.1, 0.856, 0.923], [0.3, 0.874, 0.965], [0.7, 0.917, 0.996], [1.2, 0.899, 1], [1.8, 0.899, 0.947], [2.4, 0.899, 0.92], [3, 0.813, 0.931], [3.5, 0.795, 0.888], [3.9, 0.735, 0.94], [4.2, 0.623, 0.875], [4.515, 0.473, 0.666]],
		"gh": [0.85, 2.67, 1.57, 2.34, 0.859, 1.104, 0.744, 0.545],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.27, 0.27],
		"wheel": [0.35, 0.885, 3.535],
		"wheel_x": [0.87, 0.835],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.49,
		"eye_y": 0.828,
		"dash_drop": 0.17,
		"dash_hw": 0.5,
		"ws_base_hw": 0.47,
		"mirror_d": 2.29},
	"vanta": {
		"mesh": "res://assets/models/car_vanta.mesh",
		"mesh_lq": "res://assets/models/car_vanta_lq.mesh",
		"body": [[0, 0.942, 0.781], [0.1, 0.99, 0.873], [0.3, 1.007, 0.926], [0.7, 1.111, 0.993], [1.2, 1.072, 1], [1.8, 1.072, 0.961], [2.4, 1.072, 0.951], [3, 1.119, 0.949], [3.5, 0.901, 0.985], [3.9, 0.843, 0.966], [4.2, 0.789, 0.96], [4.765, 0.61, 0.704]],
		"gh": [0.75, 2.975, 1.35, 2.425, 1.032, 1.398, 0.914, 0.556],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.245, 0.245],
		"wheel": [0.35, 1.035, 3.885],
		"wheel_x": [0.815, 0.8],
		"plate_y": 0.62,
		"badge_y": 0.74,
		"eye_back": 1.3,
		"eye_y": 1.228,
		"dash_drop": 0,
		"dash_hw": 0.53,
		"ws_base_hw": 0.5,
		"mirror_d": 2.38},
	"suv": {
		"mesh": "res://assets/models/car_traffic_suv.mesh",
		"mesh_lq": "res://assets/models/car_traffic_suv_lq.mesh",
		"body": [[0, 1.208, 0.811], [0.1, 1.308, 0.917], [0.3, 1.308, 0.954], [0.7, 1.308, 0.997], [1.2, 1.308, 1], [1.8, 1.308, 0.972], [2.4, 1.308, 0.965], [3, 1.33, 0.967], [3.5, 1.083, 0.991], [3.9, 1.037, 0.979], [4.2, 0.992, 0.971], [4.765, 0.826, 0.726]],
		"gh": [0.085, 2.9, 0.365, 2.185, 1.268, 1.77, 0.931, 0.67],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.255, 0.255],
		"wheel": [0.392, 0.965, 3.815],
		"wheel_x": [0.84, 0.83],
		"plate_y": 0.7,
		"badge_y": 0.95,
		"eye_back": 1.3,
		"eye_y": 1.6,
		"dash_drop": 0,
		"dash_hw": 0.62,
		"ws_base_hw": 0.59,
		"mirror_d": 2.14,
		"lod_near": 18,
		"no_cabin": false},
	"van": {
		"mesh": "res://assets/models/car_traffic_van.mesh",
		"mesh_lq": "res://assets/models/car_traffic_van_lq.mesh",
		"body": [[0, 2.15, 0.922], [0.1, 1.39, 0.961], [0.3, 1.39, 0.978], [0.7, 1.39, 0.999], [1.2, 1.39, 0.998], [1.8, 1.39, 0.978], [2.4, 1.39, 0.978], [3, 1.39, 0.978], [3.5, 1.39, 0.977], [3.9, 1.39, 0.991], [4.2, 1.269, 0.992], [5.215, 0.867, 0.769]],
		"gh": [0.033, 4.04, 0.075, 3.17, 1.35, 2.25, 0.948, 0.849],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.235, 0.235],
		"wheel": [0.385, 1.165, 4.415],
		"wheel_x": [0.845, 0.845],
		"plate_y": 0.7,
		"badge_y": 0.95,
		"eye_back": 1.3,
		"eye_y": 1.71,
		"dash_drop": 0,
		"dash_hw": 0.7,
		"ws_base_hw": 0.7,
		"mirror_d": 3.12,
		"lod_near": 18,
		"no_cabin": false},
	"truck": {
		"mesh": "res://assets/models/car_traffic_truck.mesh",
		"mesh_lq": "res://assets/models/car_traffic_truck_lq.mesh",
		"body": [[0, 3.91, 1], [0.1, 3.91, 1], [0.7, 0.9, 0.951], [2.4, 0.49, 0.843], [10.955, 1.595, 0.825]],
		"gh": [9.165, 10.881, 8.725, 10.105, 1.591, 3, 0.901, 0.805],
		"pillars": [[0, 0.28], [0.5, 0.54], [0.93, 1]],
		"rim_frac": 0.7,
		"tyre": [0.3, 0.3],
		"wheel": [0.51, 1.31, 9.86],
		"wheel_x": [0.98, 0.98],
		"plate_y": 0.82,
		"badge_y": 0.95,
		"eye_back": 1.3,
		"eye_y": 1.951,
		"dash_drop": 0,
		"dash_hw": 0.7,
		"ws_base_hw": 0.7,
		"mirror_d": 10.05,
		"lod_near": 18,
		"no_cabin": true,
		"extra_axles": [2.66],
		"truck": true},
	# END IMPORTED PROFILES
	# Optional shape keys read by BodyBuilder: corner = plan-view corner radii
	# [tail, nose]; flare / fender = arch flares and wing peaks [rear, front];
	# crease_h / tumble = shoulder crease height and how far the side leans in
	# above it; sharp = crisp crease; grille = "frame" (chrome-framed),
	# "none" (mid-engine cars breathe through the bumper), "bar" (slim slot).
	"hatch": {
		"mesh": "res://assets/models/cars/hatch.mesh", "mesh_lq": "res://assets/models/cars/hatch_lq.mesh",
		"body": [[0.0, 0.84, 0.88], [0.08, 0.92, 0.95], [0.35, 0.97, 0.99], [1.2, 0.98, 1.0], [2.4, 0.95, 1.0], [3.15, 0.89, 1.0], [3.62, 0.84, 0.98], [3.9, 0.76, 0.93], [4.0, 0.66, 0.88]],
		"gh": [0.12, 3.12, 0.64, 2.22, 0.97, 1.43, 0.92, 0.74], "pillars": [[0.0, 0.24], [0.52, 0.57], [0.93, 1.0]],
		"roof_drop": 0.08, "rim_frac": 0.62, "tyre": [0.215, 0.215], "head": [-0.17, -0.05, 0.32], "tail": [-0.27, -0.08, 0.55], "wheel": [0.33, 0.78, 3.28], "exhaust": 1, "corner": [0.18, 0.3], "flare": [0.02, 0.02], "crease_h": 0.66},
	"sedan": {
		"mesh": "res://assets/models/cars/sedan.mesh", "mesh_lq": "res://assets/models/cars/sedan_lq.mesh",
		"body": [[0.0, 0.86, 0.9], [0.1, 0.93, 0.96], [0.5, 0.98, 1.0], [1.2, 0.99, 1.0], [3.0, 0.96, 1.0], [3.7, 0.9, 1.0], [4.3, 0.84, 0.97], [4.6, 0.75, 0.92], [4.7, 0.66, 0.88]],
		"gh": [0.95, 3.56, 1.56, 2.76, 0.98, 1.41, 0.93, 0.78], "pillars": [[0.0, 0.14], [0.49, 0.53], [0.93, 1.0]],
		"roof_drop": 0.03, "rim_frac": 0.66, "tyre": [0.235, 0.235], "head": [-0.16, -0.05, 0.3], "tail": [-0.22, -0.07, 0.48], "wheel": [0.335, 0.98, 3.8], "exhaust": 2, "corner": [0.2, 0.3], "flare": [0.025, 0.02], "crease_h": 0.68},
	# compact performance saloon after the 2007 E90 M3: 4.58 m long, 1.82 m wide,
	# 2.76 m wheelbase, short rear and front overhangs, long bonnet, high short
	# boot, kinked C-pillar, flared wings, quad exhausts
	"msedan": {
		"mesh": "res://assets/models/cars/msedan.mesh", "mesh_lq": "res://assets/models/cars/msedan_lq.mesh",
		"body": [[0.0, 0.8, 0.9], [0.08, 0.9, 0.96], [0.22, 0.96, 0.99], [0.85, 0.97, 1.0], [3.1, 0.94, 1.0], [3.6, 0.89, 1.0], [4.1, 0.85, 0.98], [4.44, 0.8, 0.94], [4.58, 0.7, 0.88]],
		"gh": [0.88, 3.12, 1.44, 2.44, 0.96, 1.43, 0.93, 0.78], "pillars": [[0.0, 0.16], [0.47, 0.51], [0.92, 1.0]],
		"kink": [0.16, 0.25, 0.34], "roof_drop": 0.03, "rim_frac": 0.7, "tyre": [0.265, 0.245], "head": [-0.17, -0.05, 0.3], "drl": "none", "wheel": [0.34, 0.98, 3.74], "exhaust": 4, "exhaust_pairs": true,
		"corner": [0.2, 0.28], "flare": [0.04, 0.035], "crease_h": 0.7},
	# muscle notchback: long flat bonnet, upright nose, short high glasshouse
	"muscle": {
		"mesh": "res://assets/models/cars/muscle.mesh", "mesh_lq": "res://assets/models/cars/muscle_lq.mesh",
		"body": [[0.0, 0.86, 0.94], [0.12, 0.95, 0.98], [0.6, 0.98, 1.0], [1.4, 0.98, 1.0], [3.3, 0.96, 1.0], [4.4, 0.93, 0.99], [4.7, 0.87, 0.96], [4.8, 0.76, 0.93]],
		"gh": [1.18, 3.32, 1.62, 2.78, 0.98, 1.33, 0.92, 0.75], "pillars": [[0.0, 0.22], [0.9, 1.0]],
		"roof_drop": 0.02, "rim_frac": 0.68, "tyre": [0.275, 0.255], "head": [-0.2, -0.06, 0.5], "projectors": 2, "drl": "none", "tail": [-0.22, -0.05, 0.3], "wheel": [0.355, 0.95, 3.85], "exhaust": 2, "spoiler": "lip",
		"corner": [0.14, 0.16], "flare": [0.04, 0.03], "crease_h": 0.6, "tumble": 0.04},
	# muscle fastback: the roof runs in one long slope down to a short ducktail
	"fastback": {
		"mesh": "res://assets/models/cars/fastback.mesh", "mesh_lq": "res://assets/models/cars/fastback_lq.mesh",
		"body": [[0.0, 0.84, 0.94], [0.12, 0.93, 0.98], [0.5, 0.96, 1.0], [1.6, 0.97, 1.0], [3.3, 0.95, 1.0], [4.3, 0.9, 0.99], [4.65, 0.82, 0.95], [4.75, 0.72, 0.92]],
		"gh": [0.42, 3.3, 1.78, 2.8, 0.96, 1.31, 0.92, 0.74], "pillars": [[0.0, 0.42], [0.9, 1.0]],
		"rim_frac": 0.69, "tyre": [0.285, 0.255], "head": [-0.16, -0.05, 0.42], "projectors": 2, "drl": "L", "tail": [-0.2, -0.06, 0.38], "wheel": [0.355, 0.95, 3.76], "exhaust": 2, "spoiler": "ducktail",
		"corner": [0.16, 0.2], "flare": [0.045, 0.035], "fender": [0.02, 0.0], "crease_h": 0.62, "tumble": 0.05},
	# mid-engine supercar: cab forward, short nose, long engine deck, wing peaks
	"super": {
		"mesh": "res://assets/models/cars/super.mesh", "mesh_lq": "res://assets/models/cars/super_lq.mesh",
		"body": [[0.0, 0.8, 0.9], [0.12, 0.9, 0.96], [0.5, 0.93, 1.0], [1.45, 0.88, 1.0], [2.4, 0.84, 1.0], [3.5, 0.74, 1.0], [3.95, 0.66, 0.98], [4.35, 0.56, 0.93], [4.5, 0.48, 0.88]],
		"gh": [1.45, 3.5, 2.05, 2.86, 0.84, 1.2, 0.86, 0.66], "pillars": [[0.0, 0.26], [0.9, 1.0]],
		"roof_drop": 0.04, "rim_frac": 0.72, "tyre": [0.305, 0.255], "head": [-0.1, -0.035, 0.38], "tail": [-0.14, -0.05, 0.45], "wheel": [0.35, 0.86, 3.52], "exhaust": 2, "spoiler": "lip", "diffuser": true, "grille": "none",
		"corner": [0.26, 0.4], "flare": [0.06, 0.05], "fender": [0.04, 0.06], "crease_h": 0.55, "tumble": 0.1},
	# rear-engine sports coupe: rounded nose with tall front wings, roof sloping
	# smoothly to the tail, wide rear hips
	"rcoupe": {
		"mesh": "res://assets/models/cars/rcoupe.mesh", "mesh_lq": "res://assets/models/cars/rcoupe_lq.mesh",
		"body": [[0.0, 0.8, 0.9], [0.12, 0.88, 0.96], [0.6, 0.9, 1.0], [1.2, 0.9, 1.0], [2.6, 0.88, 1.0], [3.3, 0.82, 1.0], [3.9, 0.72, 0.97], [4.35, 0.62, 0.92], [4.5, 0.55, 0.88]],
		"gh": [0.45, 3.32, 1.72, 2.64, 0.9, 1.29, 0.9, 0.7], "pillars": [[0.0, 0.3], [0.9, 1.0]],
		"roof_drop": 0.08, "rim_frac": 0.71, "tyre": [0.305, 0.245], "round_lamps": true, "tail": [-0.11, -0.06, 0.0], "wheel": [0.345, 1.0, 3.45], "exhaust": 2, "spoiler": "ducktail", "diffuser": true, "grille": "bar",
		"corner": [0.32, 0.4], "flare": [0.085, 0.045], "fender": [0.04, 0.075], "crease_h": 0.6, "tumble": 0.08, "sharp": false},
	# V12 hypercar: very long and low, canopy far forward, long tail and a big wing
	"hyper": {
		"mesh": "res://assets/models/cars/hyper.mesh", "mesh_lq": "res://assets/models/cars/hyper_lq.mesh",
		"body": [[0.0, 0.78, 0.92], [0.12, 0.88, 0.97], [0.6, 0.9, 1.0], [1.65, 0.86, 1.0], [2.6, 0.8, 1.0], [3.7, 0.7, 1.0], [4.2, 0.6, 0.97], [4.6, 0.5, 0.92], [4.75, 0.42, 0.88]],
		"gh": [1.65, 3.72, 2.3, 3.1, 0.78, 1.13, 0.84, 0.62], "pillars": [[0.0, 0.3], [0.9, 1.0]],
		"roof_drop": 0.05, "rim_frac": 0.73, "tyre": [0.335, 0.275], "head": [-0.085, -0.03, 0.42], "projectors": 0, "tail": [-0.1, -0.045, 0.52], "wheel": [0.36, 0.95, 3.72], "exhaust": 4, "spoiler": "wing", "diffuser": true, "grille": "none",
		"corner": [0.3, 0.46], "flare": [0.07, 0.06], "fender": [0.06, 0.085], "crease_h": 0.55, "tumble": 0.11},
	# starter coupe: body from an imported model (assets/models/starter_coupe.mesh,
	# split into paint, glass and lamps); this profile only shapes its cabin
	"coupe": {
		"mesh": "res://assets/models/starter_coupe.mesh",
		"body": [[0.0, 0.88, 0.84], [0.25, 0.93, 0.95], [0.6, 0.97, 1.0], [2.6, 0.94, 1.0], [3.0, 0.86, 0.98], [3.5, 0.8, 0.95], [4.0, 0.7, 0.9], [4.3, 0.6, 0.8]],
		"gh": [0.62, 2.83, 1.45, 2.1, 0.93, 1.2, 0.74, 0.54], "pillars": [[0.0, 0.3], [0.9, 1.0]],
		"rim_frac": 0.68, "tyre": [0.245, 0.245], "wheel": [0.345, 0.82, 3.44], "wheel_x": [0.778, 0.752], "badge_y": 0.7, "eye_back": 1.3, "dash_drop": 0.17, "dash_hw": 0.52, "ws_base_hw": 0.4, "mirror_d": 2.3},
	# hot hatch, from an imported model (assets/models/hatchback.mesh)
	"hot_hatch": {
		"mesh": "res://assets/models/hatchback.mesh",
		"body": [[0.0, 1.0, 0.86], [0.25, 1.03, 0.95], [0.6, 1.04, 1.0], [2.4, 0.97, 1.0], [2.75, 0.95, 1.0], [3.0, 0.9, 0.99], [3.5, 0.83, 0.97], [4.0, 0.71, 0.9], [4.25, 0.6, 0.75]],
		"gh": [0.1, 2.72, 0.5, 2.15, 1.0, 1.33, 0.78, 0.56], "pillars": [[0.0, 0.3], [0.9, 1.0]],
		"rim_frac": 0.7, "tyre": [0.246, 0.246], "wheel": [0.35, 0.75, 3.39], "wheel_x": [0.815, 0.8], "badge_y": 0.74, "plate_y": 0.62,
		"dash_drop": 0.12, "dash_hw": 0.6, "ws_base_hw": 0.5, "mirror_d": 2.2},
	# sports saloon, from an imported model (assets/models/sport_sedan.mesh)
	"sport_sedan": {
		"mesh": "res://assets/models/sport_sedan.mesh",
		"body": [[0.0, 0.96, 0.84], [0.25, 1.0, 0.93], [0.6, 1.02, 0.98], [1.2, 1.0, 1.0], [3.0, 0.97, 1.0], [3.3, 0.95, 1.0], [3.6, 0.89, 0.99], [4.0, 0.82, 0.97], [4.5, 0.72, 0.92], [4.75, 0.6, 0.8]],
		"gh": [0.72, 3.2, 1.35, 2.5, 0.99, 1.32, 0.78, 0.56], "pillars": [[0.0, 0.25], [0.9, 1.0]],
		"rim_frac": 0.7, "tyre": [0.246, 0.246], "wheel": [0.35, 1.02, 3.87], "wheel_x": [0.815, 0.8], "badge_y": 0.74, "plate_y": 0.62,
		"dash_drop": 0.13, "dash_hw": 0.55, "ws_base_hw": 0.42, "mirror_d": 2.45},
	# compact hatchback coupe, also from an imported model (assets/models/compact_coupe.mesh)
	"compact": {
		"mesh": "res://assets/models/compact_coupe.mesh",
		"body": [[0.0, 0.96, 0.88], [0.25, 1.05, 0.97], [0.5, 1.0, 1.0], [2.4, 0.95, 1.0], [2.75, 0.87, 0.98], [3.25, 0.8, 0.96], [3.75, 0.7, 0.92], [4.05, 0.6, 0.82]],
		"gh": [0.35, 2.66, 0.9, 1.85, 0.97, 1.26, 0.74, 0.54], "pillars": [[0.0, 0.3], [0.9, 1.0]],
		"rim_frac": 0.68, "tyre": [0.234, 0.234], "wheel": [0.335, 0.71, 3.21], "wheel_x": [0.768, 0.752], "badge_y": 0.75, "eye_back": 1.2, "dash_drop": 0.17, "dash_hw": 0.52, "ws_base_hw": 0.4, "mirror_d": 2.05},
}


static func mat(c: Color, glow := 0.0, rough := 0.55, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), glow, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


## Emissive lamp that fades out with distance. A lit pixel that flickers on
## and off at the horizon (and gets bloomed) reads as a flashing car, so far
## lamps dissolve smoothly instead.
static func lamp(c: Color, glow: float) -> StandardMaterial3D:
	var key := "lamp|%s|%s" % [c.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 230.0  # min > max: fully faded beyond 230 m, solid within 110 m
	m.distance_fade_max_distance = 110.0
	_mats[key] = m
	return m


static var _paint_shader: Shader
static var _glass_shader: Shader
static var _glass_cracked_shader: Shader


## A material from shaders/car_paint.gdshader: glossy paint, trim, chrome or
## alloy with sharp reflections of the surroundings.
static func _car_shader_mat(key: String, params: Dictionary) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	if _paint_shader == null:
		_paint_shader = load("res://shaders/car_paint.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _paint_shader
	for k in params:
		m.set_shader_parameter(k, params[k])
	_dusk_params(m)  # a car built now reflects the sky of the moment
	_mats[key] = m
	return m


## What each paint finish asks of the paint shader (Data.FINISHES are the ones the workshop sells). "gloss" is the
## factory finish: a glossy metallic paint under a clear coat, with a little flake that glints in the sun.
const FINISH_LOOKS := {
	"gloss": {"metallic": 0.32, "roughness": 0.36, "coat": 0.6, "coat_roughness": 0.05, "reflect_amount": 1.0, "reflect_f0": 0.045, "flake": 0.7},
	"semigloss": {"metallic": 0.08, "roughness": 0.56, "coat": 0.2, "coat_roughness": 0.38, "reflect_amount": 0.4, "reflect_f0": 0.04, "flake": 0.0, "sheen": 0.3},
	"matte": {"metallic": 0.0, "roughness": 0.93, "coat": 0.0, "coat_roughness": 0.5, "reflect_amount": 0.05, "reflect_f0": 0.03, "flake": 0.0, "sheen": 0.6},
	"metallic": {"metallic": 0.5, "roughness": 0.3, "coat": 0.85, "coat_roughness": 0.05, "reflect_amount": 1.0, "reflect_f0": 0.06, "metal_tint": 0.35,
		"flake": 1.15, "flake_scale": 140.0, "flake_far": 10.0},
	"pearl": {"metallic": 0.3, "roughness": 0.32, "coat": 1.0, "coat_roughness": 0.04, "reflect_amount": 1.0, "reflect_f0": 0.05,
		"flake": 0.45, "flake_scale": 170.0, "flake_far": 6.0, "pearl": 1.0},
	"candy": {"metallic": 0.85, "roughness": 0.2, "coat": 1.0, "coat_roughness": 0.03, "reflect_amount": 1.2, "reflect_f0": 0.12, "metal_tint": 0.95, "flake": 0.9, "candy": 1.0},
	"chrome": {"metallic": 1.0, "roughness": 0.05, "coat": 0.0, "coat_roughness": 0.05, "reflect_amount": 1.15, "reflect_f0": 0.78, "metal_tint": 0.8, "flake": 0.0},
}


## The colour a pearlescent paint turns to at a glancing view: another hue, lighter (whites go warm, darks go blue-violet).
static func pearl_shift(c: Color) -> Color:
	if c.s < 0.14:
		return Color.from_hsv(0.07, 0.38, minf(1.0, c.v + 0.2)) if c.v > 0.45 else Color.from_hsv(0.72, 0.55, 0.5)
	return Color.from_hsv(fposmod(c.h + 0.08, 1.0), clampf(c.s * 0.85 + 0.05, 0.0, 1.0), clampf(c.v + 0.2, 0.0, 1.0))


## Paint in a colour and a finish (FINISH_LOOKS): gloss, semi-gloss, matte, metallic, pearlescent, candy or chrome.
static func paint(c: Color, finish := "gloss") -> Material:
	var look: Dictionary = FINISH_LOOKS.get(finish, FINISH_LOOKS.gloss)
	var params := {"base_color": c.darkened(0.04)}
	params.merge(look)
	if finish == "pearl":
		params["pearl_color"] = pearl_shift(c)
		params["base_color"] = c.lerp(Color("#f4efe8"), 0.1)  # (the pearl layer lifts the colour a little)
	elif finish == "chrome":
		params["base_color"] = c.lerp(Color("#e9edf0"), 0.45)  # (a mirror: the colour only tints what it reflects)
	elif finish == "candy":
		params["base_color"] = c
	elif finish == "metallic":
		params["base_color"] = c.lightened(0.08)  # (the metal in the paint takes some of the body colour out of it)
	elif finish == "matte":
		params["base_color"] = c.darkened(0.14)  # (flat paint is duller than the same colour with a gloss over it)
	return _car_shader_mat("paint|%s|%s" % [c.to_html(), finish if FINISH_LOOKS.has(finish) else "gloss"], params)


## Polished chrome: a mirror of the surroundings.
static func _chrome() -> Material:
	return _car_shader_mat("chrome", {"base_color": Color("#d9dde1"), "metallic": 1.0, "roughness": 0.12, "coat": 0.0,
		"reflect_amount": 1.0, "reflect_f0": 0.72, "metal_tint": 1.0})


## Alloy wheel finish in the rim colour: bright metal, or painted and lacquered.
static func _alloy(c: Color) -> Material:
	if c.to_html(false) == Data.RIM_CHROME.trim_prefix("#"):  # polished chrome: a mirror
		return _car_shader_mat("alloy|chrome", {"base_color": c, "metallic": 1.0, "roughness": 0.06, "coat": 0.0, "reflect_amount": 1.15,
			"reflect_f0": 0.8, "metal_tint": 0.3})
	var dark := c.get_luminance() < 0.3
	return _car_shader_mat("alloy|%s" % c.to_html(), {"base_color": c, "metallic": 0.55 if dark else 0.85, "roughness": 0.3 if dark else 0.24,
		"coat": 0.5 if dark else 0.0, "reflect_amount": 0.9, "reflect_f0": 0.06 if dark else 0.55, "metal_tint": 0.0 if dark else 1.0, "flake": 0.3})


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _meshes[key]


# ---------------------------------------------------------------- geometry helpers

## Adds a triangle, wound so its front face points along n (Godot: clockwise front faces).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n, n, n)
	_tri(st, a, c, d, n, n, n)


static func _face_n(a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> Vector3:
	var n := (b - a).cross(c - a).normalized()
	return -n if n.dot(hint) < 0.0 else n


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis()) -> void:
	var h := size / 2.0
	var axes := [basis.x, basis.y, basis.z]
	for ax in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = axes[ax] * sgn
			var u: Vector3 = axes[(ax + 1) % 3] * h[(ax + 1) % 3]
			var v: Vector3 = axes[(ax + 2) % 3] * h[(ax + 2) % 3]
			var c: Vector3 = center + n * h[ax]
			_quad(st, c - u - v, c + u - v, c + u + v, c - u + v, n)


## Cylinder along X (wheels) or Z (exhaust tips), with end caps.
static func _cyl(st: SurfaceTool, center: Vector3, r: float, length: float, axis: Vector3, segs := 14, caps := true) -> void:
	var a := axis.normalized()
	var u := Vector3.UP if absf(a.y) < 0.9 else Vector3.FORWARD
	var v := a.cross(u).normalized()
	u = v.cross(a).normalized()
	var h := a * length / 2.0
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var d0 := u * cos(t0) + v * sin(t0)
		var d1 := u * cos(t1) + v * sin(t1)
		var p0 := center + d0 * r
		var p1 := center + d1 * r
		_tri(st, p0 - h, p1 - h, p1 + h, d0, d1, d1)
		_tri(st, p0 - h, p1 + h, p0 + h, d0, d1, d0)
		if caps:
			_tri(st, center + h, p0 + h, p1 + h, a, a, a)
			_tri(st, center - h, p1 - h, p0 - h, -a, -a, -a)


## Wing aerofoil spanning x, centred at c: a cambered section (chord along
## z, leading edge forwards) tilted by `ang`, with closed ends.
static func _aerofoil(st: SurfaceTool, c: Vector3, span: float, chord: float, thick: float, ang: float) -> void:
	var n := 10
	var top: Array = []
	var bot: Array = []
	for i in n + 1:
		var u := 0.5 - 0.5 * cos(PI * i / n)  # close together at the edges
		var t := 5.0 * thick * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1015 * u * u * u * u)
		var camber := 0.06 * chord * 4.0 * u * (1.0 - u)
		top.append(Vector2(u, camber / chord + t / chord))
		bot.append(Vector2(u, camber / chord - t / chord))
	var rot := Basis(Vector3.RIGHT, ang)
	var pt := func(q: Vector2, x: float) -> Vector3:
		return c + rot * Vector3(x, q.y * chord, -chord * 0.5 + q.x * chord)
	for surface in [top, bot]:
		var up := 1.0 if surface == top else -1.0
		for i in n:
			var a: Vector2 = surface[i]
			var b: Vector2 = surface[i + 1]
			var x0 := -span / 2.0
			var x1 := span / 2.0
			var p0: Vector3 = pt.call(a, x0)
			var p1: Vector3 = pt.call(b, x0)
			var p2: Vector3 = pt.call(b, x1)
			var p3: Vector3 = pt.call(a, x1)
			var nn := _face_n(p0, p1, p2, rot * Vector3(0, up, 0))
			_quad(st, p0, p1, p2, p3, nn)
	for x in [-span / 2.0, span / 2.0]:
		for i in n:
			_tri(st, pt.call(top[i], x), pt.call(top[i + 1], x), pt.call(bot[i + 1], x), Vector3(signf(x), 0, 0), Vector3(signf(x), 0, 0), Vector3(signf(x), 0, 0))
			_tri(st, pt.call(top[i], x), pt.call(bot[i + 1], x), pt.call(bot[i], x), Vector3(signf(x), 0, 0), Vector3(signf(x), 0, 0), Vector3(signf(x), 0, 0))


## Ellipsoid with radii r round c (mirror housings, lamp lenses, nuts).
static func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, basis := Basis(), seg_u := 14, seg_v := 8, v0 := 0.0, v1 := PI) -> void:
	for j in seg_v:
		var a0 := lerpf(v0, v1, float(j) / seg_v)
		var a1 := lerpf(v0, v1, float(j + 1) / seg_v)
		for i in seg_u:
			var b0 := TAU * i / seg_u
			var b1 := TAU * (i + 1) / seg_u
			var pts: Array = []
			var nrm: Array = []
			for q in [[a0, b0], [a0, b1], [a1, b1], [a1, b0]]:
				var u := Vector3(sin(q[0]) * cos(q[1]), cos(q[0]), sin(q[0]) * sin(q[1]))
				pts.append(c + basis * (u * r))
				nrm.append((basis * Vector3(u.x / r.x, u.y / r.y, u.z / r.z)).normalized())
			_tri(st, pts[0], pts[1], pts[2], nrm[0], nrm[1], nrm[2])
			_tri(st, pts[0], pts[2], pts[3], nrm[0], nrm[2], nrm[3])


## Cross-section of the lower body at one station: rounded shoulders, tucked sill.
static func _ring(hw: float, top: float) -> Array:
	var b := minf(0.3, top - 0.3)
	var y2 := maxf(top - 0.2, b + 0.16)
	var y1 := minf(b + 0.14, y2 - 0.02)
	var rise := top - y2
	var right := [
		[Vector2(hw * 0.93, b), Vector2(0.3, -1)],
		[Vector2(hw, y1), Vector2(1, -0.2)],
		[Vector2(hw, y2), Vector2(1, 0.05)],
	]
	# rounded shoulder: quarter ellipse from the side up to the top surface
	for deg in [30.0, 60.0, 90.0]:
		var a := deg_to_rad(deg)
		right.append([Vector2(hw * (0.8 + 0.2 * cos(a)), y2 + rise * sin(a)), Vector2(cos(a) / 0.2, sin(a) * hw / maxf(rise, 0.05)).normalized()])
	right.append([Vector2(hw * 0.4, top + 0.014), Vector2(0.06, 1)])  # crowned bonnet and boot lid
	var ring := []
	for p in right:
		ring.append(p)
	for i in range(right.size() - 1, -1, -1):
		var p: Array = right[i]
		ring.append([Vector2(-p[0].x, p[0].y), Vector2(-p[1].x, p[1].y)])
	return ring


## Catmull-Rom resampling of body stations so the profile curves smoothly.
static func _smooth(st: Array, sub := 3) -> Array:
	var out := []
	var n := st.size()
	for i in n - 1:
		var p0: Array = st[maxi(i - 1, 0)]
		var p1: Array = st[i]
		var p2: Array = st[i + 1]
		var p3: Array = st[mini(i + 2, n - 1)]
		for k in sub:
			var t := float(k) / sub
			var row := []
			for c in 3:
				var a: float = p0[c]
				var b: float = p1[c]
				var cc: float = p2[c]
				var d: float = p3[c]
				row.append(0.5 * (2.0 * b + (-a + cc) * t + (2.0 * a - 5.0 * b + 4.0 * cc - d) * t * t + (-a + 3.0 * b - 3.0 * cc + d) * t * t * t))
			out.append(row)
	out.append(st[n - 1])
	return out


## Surface of revolution around X from a profile of (radius, x) points.
static func _lathe(st: SurfaceTool, profile: Array, segs: int) -> void:
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var dr := b.x - a.x
		var dx := b.y - a.y
		var nr := dx
		var nx := -dr
		var nl := sqrt(nr * nr + nx * nx)
		if nl < 0.00001:
			continue
		nr /= nl
		nx /= nl
		for k in segs:
			var t0 := TAU * k / segs
			var t1 := TAU * (k + 1) / segs
			var d0 := Vector3(0, cos(t0), sin(t0))
			var d1 := Vector3(0, cos(t1), sin(t1))
			var pa := Vector3(a.y, 0, 0) + d0 * a.x
			var pb := Vector3(a.y, 0, 0) + d1 * a.x
			var pc := Vector3(b.y, 0, 0) + d1 * b.x
			var pd := Vector3(b.y, 0, 0) + d0 * b.x
			var n0 := d0 * nr + Vector3(nx, 0, 0)
			var n1 := d1 * nr + Vector3(nx, 0, 0)
			_tri(st, pa, pb, pc, n0, n1, n1)
			_tri(st, pa, pc, pd, n0, n1, n0)


const RIM_STYLES := ["steel", "5spoke", "multi", "mesh", "turbine", "double", "split", "blade", "aero", "wire", "tri", "star", "vent", "deep"]


## A tapered spoke on the wheel face: from the hub (deeper, so the face is
## concave) out to the rim, twisted by `twist` radians between its ends.
static func _spoke(st: SurfaceTool, side: float, ang: float, twist: float, r0: float, r1: float, x0: float, x1: float,
		w0: float, w1: float, thick: float) -> void:
	var u0 := Vector3(0, cos(ang), sin(ang))
	var u1 := Vector3(0, cos(ang + twist), sin(ang + twist))
	var t0 := Vector3(0, -sin(ang), cos(ang))
	var t1 := Vector3(0, -sin(ang + twist), cos(ang + twist))
	var back := Vector3(-side * thick, 0, 0)
	var f := [Vector3(x0, 0, 0) + u0 * r0 - t0 * w0 / 2.0, Vector3(x0, 0, 0) + u0 * r0 + t0 * w0 / 2.0,
		Vector3(x1, 0, 0) + u1 * r1 + t1 * w1 / 2.0, Vector3(x1, 0, 0) + u1 * r1 - t1 * w1 / 2.0]
	var nf := _face_n(f[0], f[1], f[2], Vector3(side, 0, 0))
	_quad(st, f[0], f[1], f[2], f[3], nf)
	for e in 4:
		var a: Vector3 = f[e]
		var b: Vector3 = f[(e + 1) % 4]
		var mid: Vector3 = (a + b) * 0.5
		var hint: Vector3 = mid - (f[0] + f[1] + f[2] + f[3]) * 0.25
		hint.x = 0.0
		var ns := _face_n(a, b, b + back, hint)
		_quad(st, a, b, b + back, a + back, ns)


## Wheel and tyre, built once per size/design/colour and shared. Big alloy
## rims with concave spokes, centre cap and wheel nuts; a low-profile tyre
## with a rounded sidewall and tread grooves; a brake disc behind the spokes.
static func _wheel_mesh(r: float, width: float, style := "5spoke", rim_col := Color("#c3c8ce"), rim_frac := 0.66, lq := false) -> ArrayMesh:
	var key := "wheel%s_%s_%s_%s_%s_%s" % [r, width, style, rim_col.to_html(), rim_frac, lq]
	if _meshes.has(key):
		return _meshes[key]
	if lq:
		return _wheel_mesh_lq(key, r, width, rim_col if style != "steel" else Color("#6f7378"), rim_frac)
	var hw := width / 2.0
	var rr := r * rim_frac  # rim radius
	var tire := _new_st()
	var tp: Array = []
	# one side wall from the bead out to the tread shoulder...
	tp.append(Vector2(rr - 0.004, -hw + 0.03))
	tp.append(Vector2(rr + 0.012, -hw - 0.002))
	tp.append(Vector2(lerpf(rr, r, 0.5), -hw - 0.013))
	tp.append(Vector2(r - 0.028, -hw + 0.0))
	tp.append(Vector2(r - 0.007, -hw + 0.022))
	# ...the tread with three grooves...
	for gx in [-0.45, 0.0, 0.45]:
		tp.append(Vector2(r, hw * gx - 0.016))
		tp.append(Vector2(r - 0.009, hw * gx - 0.011))
		tp.append(Vector2(r - 0.009, hw * gx + 0.011))
		tp.append(Vector2(r, hw * gx + 0.016))
	# ...and the other side wall
	tp.append(Vector2(r - 0.007, hw - 0.022))
	tp.append(Vector2(r - 0.028, hw - 0.0))
	tp.append(Vector2(lerpf(rr, r, 0.5), hw + 0.013))
	tp.append(Vector2(rr + 0.012, hw + 0.002))
	tp.append(Vector2(rr - 0.004, hw - 0.03))
	_lathe(tire, tp, 32)
	var rim := _new_st()
	var brake := _new_st()
	var dark := _new_st()
	for side in [-1.0, 1.0]:
		var face: float = side * (hw - 0.012)
		# dark wheel well behind everything, so nothing shows through the spokes
		_cyl(dark, Vector3(face - side * 0.13, 0, 0), rr, 0.01, Vector3.RIGHT, 20)
		# brake disc with its darker hat
		_cyl(brake, Vector3(face - side * 0.085, 0, 0), rr * 0.8, 0.028, Vector3.RIGHT, 24)
		_cyl(dark, Vector3(face - side * 0.07, 0, 0), r * 0.2, 0.03, Vector3.RIGHT, 14)
		# rim lip and barrel
		_lathe(rim, [Vector2(rr - 0.03, face - side * 0.12), Vector2(rr - 0.026, face - side * 0.035), Vector2(rr - 0.016, face - side * 0.008),
			Vector2(rr + 0.004, face), Vector2(rr + 0.01, face - side * 0.012)], 30)
		var x_out: float = face - side * 0.008  # spoke ends at the lip
		var x_in: float = face - side * 0.05    # spoke roots at the hub, set back: a concave face
		var hub := r * 0.16
		match style:
			"steel":
				_lathe(rim, [Vector2(rr - 0.02, face - side * 0.02), Vector2(rr * 0.75, face - side * 0.04), Vector2(rr * 0.4, face - side * 0.03), Vector2(0.001, face - side * 0.012)], 24)
				for k in 6:
					var b := Basis(Vector3.RIGHT, TAU * k / 6.0)
					_cyl(dark, Vector3(face - side * 0.028, 0, 0) + b.y * rr * 0.6, rr * 0.08, 0.014, Vector3.RIGHT, 8)
			"multi":
				for k in 10:
					_spoke(rim, side, TAU * k / 10.0, 0.0, hub, rr - 0.018, x_in, x_out, 0.026, 0.036, 0.03)
			"mesh":
				for k in 10:
					for tw in [-0.32, 0.32]:
						_spoke(rim, side, TAU * k / 10.0, tw, hub, rr - 0.018, x_in, x_out, 0.018, 0.02, 0.026)
			"turbine":
				for k in 14:
					_spoke(rim, side, TAU * k / 14.0, 0.42, hub, rr - 0.018, x_in, x_out, 0.026, 0.05, 0.03)
			"double":  # five pairs of slim spokes
				for k in 5:
					for tw in [-0.11, 0.11]:
						_spoke(rim, side, TAU * k / 5.0 + tw * 0.4, tw * 0.6, hub, rr - 0.018, x_in, x_out, 0.026, 0.036, 0.034)
			"split":  # five Y spokes: a stem that forks near the rim
				var x_mid: float = lerpf(x_in, x_out, 0.55)
				for k in 5:
					var a := TAU * k / 5.0
					_spoke(rim, side, a, 0.0, hub, rr * 0.56, x_in, x_mid, 0.06, 0.044, 0.034)
					for tw in [-0.3, 0.3]:
						_spoke(rim, side, a, tw, rr * 0.54, rr - 0.018, x_mid, x_out, 0.034, 0.05, 0.03)
			"blade":  # seven swept blades
				for k in 7:
					_spoke(rim, side, TAU * k / 7.0, 0.75, hub, rr - 0.018, x_in, x_out, 0.03, 0.085, 0.03)
			"aero":  # a smooth dished disc with radial vents, like a wheel for an electric car
				_lathe(rim, [Vector2(rr - 0.012, face - side * 0.012), Vector2(rr * 0.72, face - side * 0.028), Vector2(rr * 0.3, face - side * 0.045), Vector2(0.001, face - side * 0.05)], 24)
				for k in 8:
					var ba := Basis(Vector3.RIGHT, TAU * k / 8.0)
					_box(dark, Vector3(face - side * 0.026, 0, 0) + ba.y * rr * 0.6, Vector3(0.012, rr * 0.3, rr * 0.075), ba)
			"wire":  # a laced wire wheel
				for k in 28:
					_spoke(rim, side, TAU * k / 28.0, 0.5 if k % 2 == 0 else -0.5, hub * 0.85, rr - 0.012, x_in, x_out, 0.011, 0.012, 0.012)
			"tri":  # three chunky spokes
				for k in 3:
					_spoke(rim, side, TAU * k / 3.0, 0.0, hub, rr - 0.018, x_in, x_out, 0.11, 0.2, 0.04)
			"star":  # eight straight spokes that widen towards the rim
				for k in 8:
					_spoke(rim, side, TAU * k / 8.0, 0.0, hub, rr - 0.018, x_in, x_out, 0.03, 0.08, 0.03)
			"vent":  # a plain disc drilled through with holes
				_lathe(rim, [Vector2(rr - 0.012, face - side * 0.014), Vector2(rr * 0.7, face - side * 0.03), Vector2(rr * 0.3, face - side * 0.04), Vector2(0.001, face - side * 0.045)], 24)
				for k in 12:
					var bo := Basis(Vector3.RIGHT, TAU * k / 12.0)
					_cyl(dark, Vector3(face - side * 0.03, 0, 0) + bo.y * rr * 0.72, rr * 0.075, 0.014, Vector3.RIGHT, 8)
				for k in 6:
					var bi := Basis(Vector3.RIGHT, TAU * k / 6.0 + 0.26)
					_cyl(dark, Vector3(face - side * 0.036, 0, 0) + bi.y * rr * 0.42, rr * 0.06, 0.014, Vector3.RIGHT, 8)
			"deep":  # deep dish: six spokes set well back inside a wide lip
				var x_back: float = face - side * 0.1
				for k in 6:
					_spoke(rim, side, TAU * k / 6.0, 0.0, hub, rr - 0.018, x_back, x_out, 0.06, 0.09, 0.05)
				_lathe(rim, [Vector2(rr - 0.01, face - side * 0.012), Vector2(rr - 0.01, face - side * 0.11)], 30)
			_:  # 5spoke
				for k in 5:
					_spoke(rim, side, TAU * k / 5.0, 0.0, hub, rr - 0.018, x_in, x_out, 0.05, 0.088, 0.036)
		# hub, centre cap and wheel nuts
		_cyl(rim, Vector3(x_in + side * 0.004, 0, 0), hub + 0.006, 0.03, Vector3.RIGHT, 16)
		_cyl(dark, Vector3(x_in + side * 0.02, 0, 0), r * 0.075, 0.012, Vector3.RIGHT, 14)
		for k in 5:
			var b := Basis(Vector3.RIGHT, TAU * k / 5.0 + 0.3)
			_cyl(brake, Vector3(x_in + side * 0.018, 0, 0) + b.y * r * 0.115, r * 0.022, 0.024, Vector3.RIGHT, 6)
	var m := ArrayMesh.new()
	tire.commit(m)
	rim.commit(m)
	brake.commit(m)
	dark.commit(m)
	m.surface_set_material(0, mat(Color("#121315"), 0.0, 0.88))
	m.surface_set_material(1, _alloy(rim_col) if style != "steel" else mat(Color("#6f7378"), 0.0, 0.5, 0.5))
	m.surface_set_material(2, mat(Color("#77797c"), 0.0, 0.42, 0.85))
	m.surface_set_material(3, mat(Color("#0d0e10"), 0.0, 0.9))
	_meshes[key] = m
	return m


## The far-away wheel: a plain tyre, a rim disc and a dark centre.
static func _wheel_mesh_lq(key: String, r: float, width: float, rim_col: Color, rim_frac: float) -> ArrayMesh:
	var hw := width / 2.0
	var rr := r * rim_frac
	var tire := _new_st()
	_lathe(tire, [Vector2(rr, -hw + 0.02), Vector2(lerpf(rr, r, 0.55), -hw - 0.01), Vector2(r, -hw + 0.03), Vector2(r, hw - 0.03),
		Vector2(lerpf(rr, r, 0.55), hw + 0.01), Vector2(rr, hw - 0.02)], 14)
	var rim := _new_st()
	var dark := _new_st()
	for side in [-1.0, 1.0]:
		_cyl(rim, Vector3(side * (hw - 0.03), 0, 0), rr, 0.02, Vector3.RIGHT, 14)
		_cyl(dark, Vector3(side * (hw - 0.018), 0, 0), rr * 0.45, 0.006, Vector3.RIGHT, 10)
	var m := ArrayMesh.new()
	tire.commit(m)
	rim.commit(m)
	dark.commit(m)
	m.surface_set_material(0, mat(Color("#121315"), 0.0, 0.88))
	m.surface_set_material(1, _alloy(rim_col))
	m.surface_set_material(2, mat(Color("#0d0e10"), 0.0, 0.9))
	_meshes[key] = m
	return m


## Brake caliper: a block curving round the top of the disc, fixed to the car.
static func _caliper_mesh(r_disc: float, thick: float) -> ArrayMesh:
	var key := "caliper%s_%s" % [r_disc, thick]
	if _meshes.has(key):
		return _meshes[key]
	var st := _new_st()
	var segs := 6
	var a0 := deg_to_rad(-30.0)
	var a1 := deg_to_rad(40.0)
	var ri := r_disc * 0.7
	var ro := r_disc * 1.1
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / segs)
		var t1 := lerpf(a0, a1, float(i + 1) / segs)
		var u0 := Vector3(0, cos(t0), sin(t0))
		var u1 := Vector3(0, cos(t1), sin(t1))
		for xs in [-thick / 2.0, thick / 2.0]:
			var n := Vector3(signf(xs), 0, 0)
			_quad(st, Vector3(xs, 0, 0) + u0 * ri, Vector3(xs, 0, 0) + u1 * ri, Vector3(xs, 0, 0) + u1 * ro, Vector3(xs, 0, 0) + u0 * ro, n)
		var hx := Vector3(thick / 2.0, 0, 0)
		_quad(st, u0 * ro - hx, u1 * ro - hx, u1 * ro + hx, u0 * ro + hx, (u0 + u1).normalized())
		_quad(st, u0 * ri - hx, u1 * ri - hx, u1 * ri + hx, u0 * ri + hx, -(u0 + u1).normalized())
	for t in [a0, a1]:
		var u := Vector3(0, cos(t), sin(t))
		var tn := Vector3(0, -sin(t), cos(t)) * (1.0 if t == a1 else -1.0)
		_quad(st, u * ri - Vector3(thick / 2.0, 0, 0), u * ro - Vector3(thick / 2.0, 0, 0), u * ro + Vector3(thick / 2.0, 0, 0), u * ri + Vector3(thick / 2.0, 0, 0), tn)
	var m := st.commit()
	_meshes[key] = m
	return m


## Interpolates a body station value (1 = top height, 2 = width scale) at a distance from the rear.
static func _station_at(stations: Array, d: float, idx: int) -> float:
	for i in stations.size() - 1:
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		if d <= b[0]:
			return lerpf(a[idx], b[idx], clampf((d - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0))
	return stations[stations.size() - 1][idx]


## Flat half-annulus (upper half) on a car side: wheel arches.
static func _arch(st: SurfaceTool, x: float, cy: float, cz: float, r0: float, r1: float, n: Vector3) -> void:
	var segs := 12
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(x, cy + sin(a0) * r0, cz + cos(a0) * r0)
		var p1 := Vector3(x, cy + sin(a1) * r0, cz + cos(a1) * r0)
		var q0 := Vector3(x, cy + sin(a0) * r1, cz + cos(a0) * r1)
		var q1 := Vector3(x, cy + sin(a1) * r1, cz + cos(a1) * r1)
		_quad(st, p0, p1, q1, q0, n)


# ---------------------------------------------------------------- per-type kits

## Builds (once) the shared meshes for a vehicle type.
## Body surfaces: 0 paint, 1 glass, 2 dark trim, 3 chrome, 4 plate, 5 headlights.
## Body options that change geometry. Anything else (rims, badges) is per instance.
const KIT_KEYS := ["stripes", "scoop", "intakes", "roofwing", "wiper", "lightbar", "splitter", "vents", "dome", "gills", "split_grille", "ltail", "halo", "lip", "crease", "m_bumper", "quad_diffuser"]


static func _kit(id: String, style := {}, lq := false) -> Dictionary:
	var key := id + ("|lq" if lq else "")
	for k in KIT_KEYS:
		if style.get(k, false):
			key += "|" + k
	if _kits.has(key):
		return _kits[key]
	var kit := {}
	if PROFILES.get(id, {}).has("mesh"):
		kit = _mesh_kit(id, PROFILES[id], Data.SHAPES[id], style, lq)
	elif id == "truck":
		kit = _truck_kit()
	else:
		kit = _car_kit(id, style, lq)
	_kits[key] = kit
	return kit


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	st.set_uv(Vector2.ZERO)
	return st


## Surfaces of a car body mesh, in commit order (empty ones are skipped).
const SURFACES := ["paint", "glass", "glass_solid", "dark", "gloss", "under", "chrome", "plate", "head", "headlens", "grille", "accent"]


static func _car_kit(id: String, style := {}, lq := false) -> Dictionary:
	var sh: Dictionary = Data.SHAPES[id]
	var pr: Dictionary = PROFILES[id]
	if pr.has("mesh"):
		return _mesh_kit(id, pr, sh, style, lq)
	var w: float = sh.w
	var l: float = sh.l
	var S := {}
	for k in SURFACES:
		S[k] = _new_st()
	var paint_st: SurfaceTool = S.paint
	var dark: SurfaceTool = S.dark
	var chrome: SurfaceTool = S.chrome
	var plate: SurfaceTool = S.plate
	var head: SurfaceTool = S.head
	var accent: SurfaceTool = S.accent
	var tails := _new_st()
	tails.set_uv(BodyBuilder.LED_UV)
	var sig_l := _new_st()
	var sig_r := _new_st()
	var bb: BodyBuilder = null
	var stations: Array
	var rear_top: float
	var rear_hw: float
	var front_top: float
	var front_hw: float
	var sill: float
	if pr.has("gh"):
		# smooth one-piece body with glass, lights and grille (scripts/body_builder.gd)
		bb = BodyBuilder.new(id, pr, sh, style, lq)
		bb.emit(S)
		bb.details(S, tails, sig_l, sig_r)
		bb.lights(S, tails, sig_l, sig_r)
		stations = bb.stations
		rear_top = bb.top(0.0)
		rear_hw = bb.hw(0.0)
		front_top = bb.top(l)
		front_hw = bb.hw(l)
		sill = bb.floor_y
	else:
		# vans: a lofted box body
		stations = _smooth(pr.body)
		var rings := []
		for st0 in stations:
			rings.append(_ring(w / 2.0 * st0[2], st0[1]))
		for i in stations.size() - 1:
			var z0: float = -stations[i][0]
			var z1: float = -stations[i + 1][0]
			var r0: Array = rings[i]
			var r1: Array = rings[i + 1]
			for j in r0.size():
				var j2 := (j + 1) % r0.size()
				var a := Vector3(r0[j][0].x, r0[j][0].y, z0)
				var b := Vector3(r0[j2][0].x, r0[j2][0].y, z0)
				var c := Vector3(r1[j2][0].x, r1[j2][0].y, z1)
				var d := Vector3(r1[j][0].x, r1[j][0].y, z1)
				var na := Vector3(r0[j][1].x, r0[j][1].y, 0).normalized()
				var nb := Vector3(r0[j2][1].x, r0[j2][1].y, 0).normalized()
				var nc := Vector3(r1[j2][1].x, r1[j2][1].y, 0).normalized()
				var nd := Vector3(r1[j][1].x, r1[j][1].y, 0).normalized()
				_tri(paint_st, a, b, c, na, nb, nc)
				_tri(paint_st, a, c, d, na, nc, nd)
		for e in [0, stations.size() - 1]:
			var rg: Array = rings[e]
			var z: float = -stations[e][0]
			var n := Vector3(0, 0, 1) if e == 0 else Vector3(0, 0, -1)
			var cy := 0.0
			for q in rg:
				cy += q[0].y
			var ctr := Vector3(0, cy / rg.size(), z)
			for j in rg.size():
				var j2 := (j + 1) % rg.size()
				_tri(paint_st, ctr, Vector3(rg[j][0].x, rg[j][0].y, z), Vector3(rg[j2][0].x, rg[j2][0].y, z), n, n, n)
		rear_top = stations[0][1]
		rear_hw = w / 2.0 * stations[0][2]
		front_top = stations[stations.size() - 1][1]
		front_hw = w / 2.0 * stations[stations.size() - 1][2]
		sill = minf(0.3, rear_top - 0.3)
		var glass: SurfaceTool = S.glass_solid
		var hw2 := w / 2.0
		_quad(glass, Vector3(-hw2 * 0.86, 1.4, 0.006), Vector3(-0.05, 1.4, 0.006), Vector3(-0.05, 2.0, 0.006), Vector3(-hw2 * 0.86, 2.0, 0.006), Vector3.BACK)
		_quad(glass, Vector3(0.05, 1.4, 0.006), Vector3(hw2 * 0.86, 1.4, 0.006), Vector3(hw2 * 0.86, 2.0, 0.006), Vector3(0.05, 2.0, 0.006), Vector3.BACK)
		_box(dark, Vector3(0, 1.2, 0.01), Vector3(0.03, 1.6, 0.02))
		var wn := Vector3(0, 0.88, -0.48).normalized()
		_quad(glass, Vector3(-hw2 * 0.86, 1.45, -4.6), Vector3(hw2 * 0.86, 1.45, -4.6), Vector3(hw2 * 0.86, 2.08, -4.33), Vector3(-hw2 * 0.86, 2.08, -4.33), wn)
		for sd in [-1.0, 1.0]:
			var x: float = sd * (hw2 + 0.006)
			_quad(glass, Vector3(x, 1.45, -3.55), Vector3(x, 1.45, -4.25), Vector3(x, 2.0, -4.25), Vector3(x, 2.0, -3.55), Vector3(sd, 0, 0))
			_box(paint_st, Vector3(sd * (hw2 + 0.1), 1.6, -4.4), Vector3(0.12, 0.2, 0.08))

	# --- rear details
	var bumper_y := sill + 0.07
	var plate_z := 0.012
	if bb:
		# bumpers wrap round the rounded corners: a body-colour bumper standing
		# proud of the tail, a black valance below it, black lower lip and sills
		var wrap_r: float = pr.wheel[1] - bb.R - 0.03
		var wrap_f: float = pr.wheel[2] + bb.R + 0.03
		bb.band(paint_st, 0.0, wrap_r, sill + 0.1, sill + 0.34, 0.028)
		bb.band(dark, 0.0, wrap_r, sill - 0.03, sill + 0.1, 0.014)
		bb.band(dark, l, wrap_f, sill - 0.03, sill + 0.035, 0.022)
		bb.side_strip(dark, pr.wheel[1] + bb.R + 0.02, pr.wheel[2] - bb.R - 0.02, sill - 0.02, sill + 0.055, 0.014)
		plate_z = 0.028 + 0.012
	else:
		_box(paint_st, Vector3(0, bumper_y + 0.05, -0.1), Vector3(rear_hw * 2.0 * 0.98, 0.2, 0.26))
		_box(dark, Vector3(0, bumper_y - 0.07, -0.1), Vector3(rear_hw * 2.0 * 0.9, 0.07, 0.25))
	_box(plate, Vector3(0, bumper_y + 0.2, plate_z), Vector3(0.52, 0.12, 0.02))
	if bb == null:
		var ty0 := 1.05
		var ty1 := 1.3
		var tz := 0.012
		for sd in [-1.0, 1.0]:
			var x0: float = sd * rear_hw * 0.66
			var x1: float = sd * rear_hw * 0.93
			var tcy := (ty0 + ty1) / 2.0
			var th := ty1 - ty0
			_box(dark, Vector3((x0 + x1) / 2.0 - sd * 0.02, tcy, tz - 0.004), Vector3(absf(x1 - x0) + 0.1, th + 0.03, 0.03))
			_box(head, Vector3(sd * rear_hw * 0.61, tcy, tz), Vector3(rear_hw * 0.1, th * 0.9, 0.028))
			_box(tails, Vector3((x0 + x1) / 2.0, tcy, tz + 0.004), Vector3(absf(x1 - x0), th * 0.8, 0.03))
			_box(sig_l if sd < 0 else sig_r, Vector3(sd * rear_hw * 0.5, tcy, tz), Vector3(0.12, th * 0.8, 0.032))
	var ex: int = pr.get("exhaust", 1)
	var ex_x: Array = [-rear_hw * 0.62] if ex == 1 else ([-rear_hw * 0.6, rear_hw * 0.6] if ex == 2 else [-0.22, -0.08, 0.08, 0.22])
	if pr.get("exhaust_pairs", false):
		ex_x = [-rear_hw * 0.66, -rear_hw * 0.66 + 0.12, rear_hw * 0.66 - 0.12, rear_hw * 0.66]
	for x in ex_x:
		# exhaust tips just proud of the valance: polished lip, dark pipe inside
		var r_tip := 0.045 if ex < 4 else 0.04
		_cyl(chrome, Vector3(x, bumper_y - 0.04, 0.015), r_tip, 0.1, Vector3.BACK, 16, false)
		_cyl(chrome, Vector3(x, bumper_y - 0.04, 0.015), r_tip - 0.006, 0.1, Vector3.BACK, 16, false)
		_cyl(dark, Vector3(x, bumper_y - 0.04, 0.03), r_tip - 0.008, 0.06, Vector3.BACK, 12, true)
	if pr.get("diffuser", false):
		for k in 5:
			_box(dark, Vector3(-0.5 + k * 0.25, sill - 0.02, -0.32), Vector3(0.03, 0.1, 0.5))
	match pr.get("spoiler", ""):
		"wing":
			# a real aerofoil on swan-neck mounts, with shaped end plates
			var wt: float = bb.top(0.3) if bb else rear_top
			var span := w - 0.16
			var wc := Vector3(0, wt + 0.34, -0.26)
			_aerofoil(S.gloss, wc, span, 0.4, 0.05, -0.14)
			for sd in [-1.0, 1.0]:
				var px: float = sd * span / 2.0
				var ep: Array = [Vector3(px, wc.y - 0.1, wc.z - 0.22), Vector3(px, wc.y - 0.1, wc.z + 0.24), Vector3(px, wc.y + 0.08, wc.z + 0.26), Vector3(px, wc.y + 0.05, wc.z - 0.2)]
				for q in [0.006, -0.006]:
					var off := Vector3(q, 0, 0)
					_quad(S.gloss, ep[0] + off, ep[1] + off, ep[2] + off, ep[3] + off, Vector3(signf(q) * sd, 0, 0))
				# pylon from the deck up to the wing: a thin blade, raked back
				var mx: float = sd * 0.42
				var deck: float = bb.surf_y(0.3, absf(mx)) if bb else wt
				var bz := wc.z - 0.02
				var pyl: Array = [Vector3(mx, deck, bz - 0.1), Vector3(mx, deck, bz + 0.12), Vector3(mx, wc.y - 0.01, bz + 0.1), Vector3(mx, wc.y - 0.01, bz - 0.02)]
				for q in [0.01, -0.01]:
					var off := Vector3(q, 0, 0)
					_quad(dark, pyl[0] + off, pyl[1] + off, pyl[2] + off, pyl[3] + off, Vector3(signf(q), 0, 0))
		"lip":
			var lt: float = bb.top(0.14) if bb else rear_top
			_box(paint_st, Vector3(0, lt + 0.035, -0.14), Vector3(w * 0.82, 0.05, 0.16), Basis(Vector3.RIGHT, 0.15))
		"ducktail":  # the tail edge kicks up into a short integrated spoiler
			var dt: float = bb.top(0.1) if bb else rear_top
			var dw: float = (bb.hw(0.1) * 2.0 - 0.12) if bb else w * 0.8
			_box(paint_st, Vector3(0, dt + 0.03, -0.1), Vector3(dw, 0.035, 0.2), Basis(Vector3.RIGHT, 0.35))
			_box(dark, Vector3(0, dt + 0.062, -0.012), Vector3(dw - 0.04, 0.012, 0.02))

	# --- front details (the smooth bodies get theirs from BodyBuilder.lights)
	if bb == null:
		var fz := -l - 0.012
		for sd in [-1.0, 1.0]:
			var hx: float = sd * front_hw * 0.68
			var hy := front_top - 0.1
			_box(dark, Vector3(hx, hy, fz + 0.035), Vector3(front_hw * 0.46, 0.13, 0.03))
			_box(head, Vector3(hx, hy, fz + 0.015), Vector3(front_hw * 0.42, 0.08, 0.03))
		_box(chrome, Vector3(0, front_top - 0.13, fz + 0.03), Vector3(front_hw * 0.62, 0.17, 0.03))
		_box(dark, Vector3(0, front_top - 0.13, fz + 0.015), Vector3(front_hw * 0.56, 0.13, 0.03))
		_box(dark, Vector3(0, sill + 0.12, fz + 0.03), Vector3(front_hw * 0.9, 0.14, 0.04))

	var r: float = pr.wheel[0]
	_style_extras(id, style, pr, stations, w, l, sill, rear_top, front_top, paint_st, dark, chrome, accent, S.glass, bb)
	if not lq:
		_details(id, pr, stations, w, l, sill, dark, paint_st, chrome, head, bb)
	if bb == null:
		for sd in [-1.0, 1.0]:
			var n := Vector3(sd, 0, 0)
			for ax in [pr.wheel[1], pr.wheel[2]]:
				var hx: float = w / 2.0 * _station_at(stations, ax, 2)
				_arch(dark, sd * (hx + 0.006), r, -ax, 0.0, r + 0.04, n)
				_arch(dark, sd * (hx + 0.008), r, -ax, r + 0.04, r + 0.085, n)

	var wheels: Array = [[-(w / 2.0 - 0.11), -pr.wheel[1]], [w / 2.0 - 0.11, -pr.wheel[1]], [-(w / 2.0 - 0.11), -pr.wheel[2]], [w / 2.0 - 0.11, -pr.wheel[2]]]
	if bb:
		# tyres sit flush with the (flared) body; sports cars run wider ones, widest at the back
		var tyre: Array = pr.get("tyre", [0.235, 0.225])
		wheels = []
		for k in 2:
			var ax: float = pr.wheel[1 + k]
			var tw: float = tyre[k]
			var x: float = bb.hw(ax) - tw / 2.0 - 0.012
			wheels.append([-x, -ax, tw])
			wheels.append([x, -ax, tw])
	var kit := {
		"tails": tails.commit(), "sig_l": sig_l.commit(), "sig_r": sig_r.commit(),
		"wheels": wheels, "rim_frac": pr.get("rim_frac", 0.66),
		"r": r, "ww": 0.24, "plate_y": bumper_y + 0.2, "plate_z": plate_z + 0.012,
	}
	var body := ArrayMesh.new()
	var names: Array = []
	for k in SURFACES:
		(S[k] as SurfaceTool).index()  # share vertices between neighbouring quads: far less for the GPU to process
		var arr: Array = (S[k] as SurfaceTool).commit_to_arrays()
		var verts: Variant = arr[Mesh.ARRAY_VERTEX]
		if verts == null or (verts as PackedVector3Array).is_empty():
			continue
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		names.append(k)
	kit["body"] = body
	kit["surfaces"] = names
	if bb:
		kit["cabin"] = bb.cabin_mesh()
	return kit


## A car body from an imported model. The converter (see README) has already
## split it into surfaces in car space: paint, glass, dark trim, wheel wells,
## chrome, and the head and tail lamps. Tail lamps go to their own mesh so
## they brighten under braking; the outer ends of the lamps double as the
## indicators. The cabin, wheels and interior come from the profile as usual.
static func _mesh_kit(id: String, pr: Dictionary, sh: Dictionary, style: Dictionary, lq := false) -> Dictionary:
	var f := FileAccess.open(pr.mesh_lq if lq and pr.has("mesh_lq") else pr.mesh, FileAccess.READ)
	var body := ArrayMesh.new()
	var names: Array = []
	var kit := {}
	var sig_l := _new_st()
	var sig_r := _new_st()
	if f == null or f.get_buffer(4).get_string_from_ascii() != "CPE2":
		push_error("car mesh missing: %s" % pr.mesh)
		return {}
	var n_surf := f.get_32()
	for si in n_surf:
		var sname := f.get_buffer(f.get_32()).get_string_from_utf8()
		var nv := f.get_32()
		var pos := f.get_buffer(nv * 12).to_float32_array()
		var nor := f.get_buffer(nv * 12).to_float32_array()
		var idx := f.get_buffer(f.get_32() * 4).to_int32_array()
		for t in range(0, idx.size(), 3):  # glTF winds front faces anticlockwise, Godot clockwise
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
		var P := PackedVector3Array()
		var N := PackedVector3Array()
		P.resize(nv)
		N.resize(nv)
		for i in nv:
			P[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
			N[i] = Vector3(nor[i * 3], nor[i * 3 + 1], nor[i * 3 + 2])
		var C := PackedColorArray()
		C.resize(nv)
		C.fill(Color.WHITE)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = P
		arr[Mesh.ARRAY_NORMAL] = N
		arr[Mesh.ARRAY_COLOR] = C
		arr[Mesh.ARRAY_INDEX] = idx
		if sname == "head" or sname == "tail":
			# outer ends of the lamps: amber indicators laid just over them
			for t in range(0, idx.size(), 3):
				var a := P[idx[t]]
				var b := P[idx[t + 1]]
				var c := P[idx[t + 2]]
				var cx := (a.x + b.x + c.x) / 3.0
				if absf(cx) < (0.6 if sname == "head" else 0.5):
					continue
				var st: SurfaceTool = sig_l if cx < 0.0 else sig_r
				var na := N[idx[t]]
				var nb := N[idx[t + 1]]
				var nc := N[idx[t + 2]]
				_tri(st, a + na * 0.003, b + nb * 0.003, c + nc * 0.003, na, nb, nc)
		if sname == "tail":
			var uv := PackedVector2Array()
			uv.resize(nv)
			uv.fill(BodyBuilder.LED_UV)
			arr[Mesh.ARRAY_TEX_UV] = uv
			var tm := ArrayMesh.new()
			tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			kit["tails"] = tm
			continue
		if sname == "headlens":
			sname = "head"
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		names.append(sname)
	# number plate on the tail
	var bbm := BodyBuilder.new(id, pr, sh, style)
	var plate_y: float = pr.get("plate_y", bbm.floor_y + 0.29)
	var plate := _new_st()
	_box(plate, Vector3(0, plate_y, 0.006), Vector3(0.52, 0.12, 0.016))
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plate.commit_to_arrays())
	names.append("plate")
	var tyre: Array = pr.tyre
	var wheels: Array = []
	var axle_ds: Array = [pr.wheel[1], pr.wheel[2]]
	axle_ds.append_array(pr.get("extra_axles", []))
	for k in axle_ds.size():
		var ax: float = axle_ds[k]
		# flush with the (flared) body side unless the model says where
		var x: float = float(pr.wheel_x[mini(k, 1)]) if pr.has("wheel_x") else bbm.hw(ax) - float(tyre[mini(k, 1)]) / 2.0 - 0.012
		wheels.append([-x, -ax, tyre[mini(k, 1)]])
		wheels.append([x, -ax, tyre[mini(k, 1)]])
	kit.merge({"sig_l": sig_l.commit(), "sig_r": sig_r.commit(), "wheels": wheels, "rim_frac": pr.get("rim_frac", 0.66),
		"r": pr.wheel[0], "ww": tyre[0], "plate_y": plate_y, "plate_z": 0.02, "body": body, "surfaces": names, "lod_near": float(pr.get("lod_near", 22.0))})
	if pr.get("truck", false):
		kit["truck"] = true
	if not kit.has("tails"):
		kit["tails"] = ArrayMesh.new()
	if not pr.get("no_cabin", false):
		# the simple seats and dash seen through the glass, kept inside the real body
		kit["cabin"] = _clamp_mesh(bbm.cabin_mesh(), _shell_of(body, names, sh))
	return kit


## Details every car has: bonnet and boot shut lines, fuel filler, roof rails,
## fog lights and the number-plate light.
static func _details(id: String, pr: Dictionary, stations: Array, w: float, l: float, sill: float,
		dark: SurfaceTool, paint_st: SurfaceTool, chrome: SurfaceTool, head: SurfaceTool, bb: BodyBuilder = null) -> void:
	var g: Array = pr.get("gh", [])
	var fz := -l - 0.012
	var front_hw: float = w / 2.0 * stations[stations.size() - 1][2]
	if bb == null:
		for s in [-1.0, 1.0]:
			_box(head, Vector3(s * front_hw * 0.72, sill + 0.1, fz + 0.012), Vector3(0.12, 0.045, 0.02))  # fog lights
		_box(head, Vector3(0, sill + 0.36, 0.03), Vector3(0.12, 0.012, 0.02))  # plate light
	if not g.is_empty():
		var lines := func(d0: float, d1: float, across: float) -> void:
			# shut lines sampled every few centimetres so they hug the curved panel
			# (straight runs between body stations dipped under it and looked dashed)
			var n_seg := maxi(4, int((d1 - d0) / 0.05))
			for k in n_seg:
				var da := lerpf(d0, d1, float(k) / n_seg)
				var db := lerpf(d0, d1, float(k + 1) / n_seg)
				for sx in [-1.0, 1.0]:
					var xa: float = sx * w / 2.0 * _station_at(stations, da, 2) * 0.78
					var xb: float = sx * w / 2.0 * _station_at(stations, db, 2) * 0.78
					var ya: float = (bb.surf_y(da, xa) + 0.004) if bb else (_station_at(stations, da, 1) + 0.006)
					var yb: float = (bb.surf_y(db, xb) + 0.004) if bb else (_station_at(stations, db, 1) + 0.006)
					_quad(dark, Vector3(xa - 0.004, ya, -da), Vector3(xa + 0.004, ya, -da), Vector3(xb + 0.004, yb, -db), Vector3(xb - 0.004, yb, -db), Vector3.UP)
			var hw: float = w / 2.0 * _station_at(stations, across, 2) * 0.78
			for k in 16:
				var xa := lerpf(-hw, hw, k / 16.0)
				var xb := lerpf(-hw, hw, (k + 1) / 16.0)
				var ya: float = (bb.surf_y(across, xa) + 0.004) if bb else (_station_at(stations, across, 1) + 0.015)
				var yb: float = (bb.surf_y(across, xb) + 0.004) if bb else (_station_at(stations, across, 1) + 0.015)
				_quad(dark, Vector3(xa, ya, -across - 0.004), Vector3(xb, yb, -across - 0.004), Vector3(xb, yb, -across + 0.004), Vector3(xa, ya, -across + 0.004), Vector3.UP)
		lines.call(g[1] + 0.06, l - 0.24, l - 0.24)   # bonnet
		if g[0] > 0.5:
			lines.call(0.14, g[0] - 0.06, 0.14)        # boot lid
		# fuel filler on the right rear quarter (BodyBuilder adds its own)
		var fd: float = pr.wheel[1] + pr.wheel[0] + 0.3
		if bb:
			fd = -10.0
		if fd > 0.0:
			var fx: float = w / 2.0 * _station_at(stations, fd, 2)
			_box(dark, Vector3(fx + 0.004, g[4] - 0.17, -fd), Vector3(0.01, 0.15, 0.15))
			_box(paint_st, Vector3(fx + 0.008, g[4] - 0.17, -fd), Vector3(0.01, 0.135, 0.135))
		if id == "suv":
			var hr: float = w / 2.0 * g[7]
			for sx in [-1.0, 1.0]:
				_box(dark, Vector3(sx * (hr - 0.08), g[5] + 0.08, -(g[2] + g[3]) / 2.0), Vector3(0.04, 0.035, g[3] - g[2] - 0.1))
				for t in 3:
					_box(dark, Vector3(sx * (hr - 0.08), g[5] + 0.035, -lerpf(g[2] + 0.1, g[3] - 0.1, t / 2.0)), Vector3(0.05, 0.07, 0.06))
	elif pr.get("van", false):
		for sx in [-1.0, 1.0]:
			_box(dark, Vector3(sx * w * 0.4, 2.33, -2.2), Vector3(0.05, 0.04, 3.6))
			for t in 4:
				_box(dark, Vector3(sx * w * 0.4, 2.28, -0.6 - t * 1.1), Vector3(0.06, 0.08, 0.08))


## Geometry for a car's styling kit: racing stripes, bonnet scoop, side
## intakes, roof spoiler, rear wiper, splitter and skirts, bonnet vents.
static func _style_extras(id: String, style: Dictionary, pr: Dictionary, stations: Array, w: float, l: float, sill: float,
		rear_top: float, front_top: float, paint_st: SurfaceTool, dark: SurfaceTool, chrome: SurfaceTool, accent: SurfaceTool, glass: SurfaceTool, bb: BodyBuilder = null) -> void:
	var g: Array = pr.get("gh", [])
	# body side x at a height (smooth bodies), or the profile width
	var side_x := func(d: float, y: float) -> float:
		return (bb.side_pn(d, y)[0] as Vector3).x if bb else w / 2.0 * _station_at(stations, d, 2)
	var top_at := func(d: float, x: float, lift: float) -> float:
		return bb.surf_y(d, x) + 0.004 if bb else _station_at(stations, d, 1) + lift
	if style.get("stripes", false):
		# twin stripes over boot and bonnet, following the crowned top surface
		for i in stations.size() - 1:
			var a: Array = stations[i]
			var b: Array = stations[i + 1]
			if not g.is_empty() and a[0] >= g[0] - 0.05 and b[0] <= g[1] + 0.05:
				continue  # the greenhouse covers this part
			for sx in [-1.0, 1.0]:
				var ya: float = top_at.call(a[0], 0.17, 0.018)
				var yb: float = top_at.call(b[0], 0.17, 0.018)
				_quad(accent, Vector3(sx * 0.07, ya, -a[0]), Vector3(sx * 0.27, ya, -a[0]),
					Vector3(sx * 0.27, yb, -b[0]), Vector3(sx * 0.07, yb, -b[0]), Vector3.UP)
		for sx in [-1.0, 1.0]:  # down the rear panel
			_box(accent, Vector3(sx * 0.17, rear_top - 0.15, 0.014), Vector3(0.2, 0.3, 0.01))
	if style.get("scoop", false) and not g.is_empty() and bb:
		# the scoop is shaped into the bonnet (BodyBuilder.hood_lift); this is its open mouth
		var d1: float = l - 0.38 - 0.33
		var y0: float = bb.surf_y(d1 + 0.04, 0.0) - 0.004
		var lift := bb.hood_lift(d1 - 0.02, 0.0)
		_quad(dark, Vector3(-0.23, y0, -d1 - 0.012), Vector3(0.23, y0, -d1 - 0.012),
			Vector3(0.23, y0 + lift, -d1 - 0.012), Vector3(-0.23, y0 + lift, -d1 - 0.012), Vector3.FORWARD)
	elif style.get("scoop", false) and not g.is_empty():
		var d: float = g[1] + 0.55
		var top := _station_at(stations, d, 1)
		_box(paint_st, Vector3(0, top + 0.04, -d), Vector3(0.62, 0.08, 0.8))
		_box(dark, Vector3(0, top + 0.05, -d - 0.405), Vector3(0.5, 0.05, 0.02))
	if style.get("dome", false) and not g.is_empty() and bb == null:  # raised power dome down the bonnet
		var d0: float = g[1] + 0.12
		var d1: float = l - 0.4
		var mid := (d0 + d1) / 2.0
		var top := _station_at(stations, mid, 1)
		_box(paint_st, Vector3(0, top + 0.022, -mid), Vector3(0.46, 0.04, d1 - d0), Basis(Vector3.RIGHT, -0.06))
	if style.get("gills", false) and not g.is_empty():  # vents behind the front wheels
		var gd: float = pr.wheel[2] - pr.wheel[0] - 0.22
		for sx in [-1.0, 1.0]:
			var hx: float = side_x.call(gd, g[4] - 0.2)
			_box(chrome, Vector3(sx * (hx + 0.006), g[4] - 0.2, -gd), Vector3(0.012, 0.08, 0.2))
			for k in 2:
				_box(dark, Vector3(sx * (hx + 0.01), g[4] - 0.22 + k * 0.035, -gd), Vector3(0.012, 0.012, 0.17))
	if style.get("crease", false) and not g.is_empty():  # shoulder line running from the front wheel to the tail light
		for sx in [-1.0, 1.0]:
			var d0 := 0.3
			var d1: float = pr.wheel[2] - pr.wheel[0] - 0.05
			var steps := 6
			for k in steps:
				var da := lerpf(d0, d1, float(k) / steps)
				var db := lerpf(d0, d1, float(k + 1) / steps)
				var ya: float = g[4] - 0.11 - 0.03 * float(k) / steps
				var yb2: float = g[4] - 0.11 - 0.03 * float(k + 1) / steps
				var xa: float = sx * (side_x.call(da, ya) + 0.004)
				var xb: float = sx * (side_x.call(db, yb2) + 0.004)
				_quad(dark, Vector3(xa, ya - 0.005, -da), Vector3(xb, yb2 - 0.005, -db), Vector3(xb, yb2 + 0.005, -db), Vector3(xa, ya + 0.005, -da), Vector3(sx, 0, 0))
	if style.get("m_bumper", false):  # deep front bumper: big outer intakes either side of the centre intake
		var fz2 := -l - 0.01
		var fhw: float = bb.hw(l) * 1.0 if bb else w / 2.0 * stations[stations.size() - 1][2]
		for sx in [-1.0, 1.0]:
			_box(dark, Vector3(sx * fhw * 0.66, sill + 0.17, fz2 + 0.02), Vector3(0.24, 0.2, 0.04))
			_box(chrome, Vector3(sx * fhw * 0.66, sill + 0.27, fz2 + 0.025), Vector3(0.24, 0.012, 0.03))
	if style.get("quad_diffuser", false):  # black rear valance framing the four exhausts
		var rhw: float = w / 2.0 * stations[0][2]
		if bb == null:  # smooth bodies already have a black valance
			_box(dark, Vector3(0, sill + 0.03, 0.025), Vector3(rhw * 1.9, 0.14, 0.04))
		for k in 4:
			_box(dark, Vector3(-0.18 + k * 0.12, sill - 0.02, -0.1), Vector3(0.025, 0.08, 0.3))
	if style.get("lip", false) and not g.is_empty():  # small boot-lid spoiler
		var lt: float = bb.top(0.1) if bb else rear_top
		_box(paint_st, Vector3(0, lt + 0.03, -0.1), Vector3(w * 0.7, 0.03, 0.1), Basis(Vector3.RIGHT, 0.18))
	if style.get("vents", false) and not g.is_empty():
		for sx in [-1.0, 1.0]:
			var d2: float = g[1] + 0.35
			for k in 4:
				var t2: float = top_at.call(d2 + k * 0.07, 0.32, 0.012)
				_box(dark, Vector3(sx * 0.32, t2 + 0.002, -d2 - k * 0.07), Vector3(0.3, 0.012, 0.035))
	if style.get("intakes", false):
		var rz: float = pr.wheel[0] + pr.wheel[1] + 0.15
		for sx in [-1.0, 1.0]:
			var hx: float = side_x.call(rz + 0.3, sill + 0.38)
			_box(dark, Vector3(sx * (hx - 0.01), sill + 0.38, -rz - 0.3), Vector3(0.04, 0.24, 0.55))
			for k in 3:
				_box(chrome, Vector3(sx * (hx + 0.005), sill + 0.3 + k * 0.08, -rz - 0.3), Vector3(0.012, 0.012, 0.52))
	if style.get("roofwing", false) and not g.is_empty():
		_box(paint_st, Vector3(0, g[5] + 0.015, -g[2] + 0.06), Vector3(w * 0.78, 0.035, 0.26), Basis(Vector3.RIGHT, -0.12))
		_box(dark, Vector3(0, g[5] - 0.02, -g[2] + 0.12), Vector3(w * 0.7, 0.03, 0.04))
	if style.get("wiper", false) and not g.is_empty():
		var base := Vector3(0, g[4] + 0.1, -g[0] - 0.04)
		var tip := Vector3(-0.42, g[4] + 0.32, -g[0] - 0.12)
		if bb:
			base = Vector3(0, bb.surf_y(g[0] + 0.05, 0.0) + 0.02, -g[0] - 0.05)
			tip = Vector3(-0.42, bb.surf_y(g[0] + 0.12, 0.42) + 0.018, -g[0] - 0.12)
		_strap(dark, base, tip, 0.02, 0.015)
	if style.get("splitter", false):
		if bb:
			# a carbon splitter following the nose, and deeper side skirts
			bb.band(dark, l, pr.wheel[2] + bb.R + 0.03, sill - 0.075, sill - 0.045, 0.075, 0.3)
			bb.side_strip(dark, pr.wheel[1] + bb.R + 0.02, pr.wheel[2] - bb.R - 0.02, sill - 0.05, sill + 0.07, 0.032)
		else:
			_box(dark, Vector3(0, sill - 0.06, -l + 0.12), Vector3(w * 0.96, 0.03, 0.3))
			var a0: float = pr.wheel[1] + pr.wheel[0] + 0.1
			var a1: float = pr.wheel[2] - pr.wheel[0] - 0.1
			for sx in [-1.0, 1.0]:
				var hx3: float = side_x.call((a0 + a1) / 2.0, sill + 0.03)
				_box(dark, Vector3(sx * (hx3 - 0.02), sill + 0.02, -(a0 + a1) / 2.0), Vector3(0.08, 0.09, a1 - a0))


static func _truck_kit() -> Dictionary:
	# Articulated lorry: a cab-over tractor with a sleeper and roof fairing,
	# pulling a box trailer. Surfaces, in commit order: trailer (box colour),
	# cab (cab colour), glass, dark trim, chrome, plate/reflectors, head lamps,
	# livery stripe (accent), amber marker lamps.
	var sh: Dictionary = Data.SHAPES.truck
	var w: float = sh.w
	var l: float = sh.l
	var hw := w / 2.0
	var box := _new_st()
	var cab := _new_st()
	var glass := _new_st()
	var dark := _new_st()
	var chrome := _new_st()
	var plate := _new_st()
	var head := _new_st()
	var accent := _new_st()
	var amber := _new_st()
	var tails := _new_st()
	tails.set_uv(BodyBuilder.LED_UV)
	var sig_l := _new_st()
	var sig_r := _new_st()

	# --- trailer: a box on a chassis, from the rear bumper to just behind the cab
	var tf := -(l - 3.05)  # trailer front
	var tl := -tf
	var floor := 1.22
	var top: float = sh.t
	_box(box, Vector3(0, (floor + top) / 2.0, tf / 2.0), Vector3(w, top - floor, tl))
	for k in int(tl / 0.55):  # corrugated side posts
		for s in [-1.0, 1.0]:
			_box(box, Vector3(s * (hw + 0.012), (floor + top) / 2.0, -0.3 - k * 0.55), Vector3(0.025, top - floor - 0.12, 0.07))
	for s in [-1.0, 1.0]:
		_box(chrome, Vector3(s * (hw + 0.02), top - 0.04, tf / 2.0), Vector3(0.05, 0.08, tl))     # top rail
		_box(dark, Vector3(s * (hw + 0.02), floor + 0.04, tf / 2.0), Vector3(0.06, 0.1, tl))      # bottom rail
		_box(accent, Vector3(s * (hw + 0.03), floor + 0.75, tf / 2.0 - 0.3), Vector3(0.012, 0.42, tl - 0.8))  # livery band
		# side guard between the landing legs and the rear wheels
		_box(dark, Vector3(s * (hw - 0.06), floor - 0.35, -4.6), Vector3(0.04, 0.42, 3.6))
		for k in 4:
			_box(dark, Vector3(s * (hw - 0.25), floor - 0.35, -3.0 - k * 1.1), Vector3(0.36, 0.05, 0.05))
		# landing legs and their feet
		_box(dark, Vector3(s * 0.85, 0.75, tf + 1.0), Vector3(0.12, 0.95, 0.12))
		_box(dark, Vector3(s * 0.85, 0.27, tf + 1.0), Vector3(0.3, 0.06, 0.3))
		# mud flaps behind the trailer wheels
		_box(dark, Vector3(s * (hw - 0.3), 0.55, -0.55), Vector3(0.55, 0.6, 0.02))
		# reflective tape along the sides, red and white
		for k in int(tl / 1.2):
			_box(tails if k % 2 == 0 else plate, Vector3(s * (hw + 0.034), floor + 0.22, -0.5 - k * 1.2), Vector3(0.01, 0.06, 0.55))
	_box(dark, Vector3(0, floor - 0.12, tf / 2.0), Vector3(w - 0.3, 0.22, tl))  # chassis under the box
	# rear: split doors, hinges, lock bars, lamps, reflectors and the underride bar
	_box(dark, Vector3(0, (floor + top) / 2.0, 0.012), Vector3(0.035, top - floor - 0.1, 0.02))
	for x in [-0.95, -0.55, 0.55, 0.95]:
		_box(chrome, Vector3(x, (floor + top) / 2.0, 0.035), Vector3(0.035, top - floor - 0.3, 0.035))
		for y in [floor + 0.45, top - 0.45]:
			_box(chrome, Vector3(x, y, 0.045), Vector3(0.09, 0.07, 0.03))
	for s in [-1.0, 1.0]:
		for y in [floor + 0.3, (floor + top) / 2.0, top - 0.3]:
			_box(dark, Vector3(s * (hw - 0.04), y, 0.03), Vector3(0.08, 0.16, 0.04))   # hinges
	for k in 10:
		var x := -hw + 0.12 + k * (w - 0.24) / 9.0
		_box(tails if k % 2 == 0 else plate, Vector3(x, floor + 0.05, 0.026), Vector3(0.2, 0.05, 0.01))
	_box(dark, Vector3(0, 0.58, 0.05), Vector3(w - 0.3, 0.12, 0.12))
	for s in [-1.0, 1.0]:
		_box(dark, Vector3(s * 0.8, 0.85, 0.02), Vector3(0.08, 0.45, 0.08))
		_box(dark, Vector3(s * (hw - 0.32), 0.98, 0.03), Vector3(0.46, 0.24, 0.04))
		_box(tails, Vector3(s * (hw - 0.36), 0.98, 0.05), Vector3(0.24, 0.16, 0.02))
		_box(sig_l if s < 0 else sig_r, Vector3(s * (hw - 0.17), 0.98, 0.05), Vector3(0.1, 0.16, 0.02))
	_box(plate, Vector3(0, 0.82, 0.04), Vector3(0.5, 0.12, 0.02))

	# --- tractor chassis, wheels' mudguards, fuel tanks and the fifth wheel
	var cf := -l          # cab front
	var cb := -l + 2.25   # cab back
	_box(dark, Vector3(0, 0.95, (cb + tf) / 2.0 - 0.5), Vector3(0.95, 0.25, absf(tf - cb) + 3.0))
	_box(dark, Vector3(0, 1.12, tf + 1.8), Vector3(1.2, 0.08, 1.2))
	for s in [-1.0, 1.0]:
		_cyl(chrome, Vector3(s * (hw - 0.38), 0.72, cb + 0.85), 0.3, 1.2, Vector3.BACK, 16)      # fuel tank
		for dz in [-0.4, 0.4]:
			_box(dark, Vector3(s * (hw - 0.38), 0.72, cb + 0.85 + dz), Vector3(0.64, 0.64, 0.05))
		_box(dark, Vector3(s * (hw - 0.3), 1.1, -6.0), Vector3(0.62, 0.05, 2.0))                # mudguard over the drive axles
		_box(dark, Vector3(s * (hw - 0.3), 0.95, -7.05), Vector3(0.62, 0.35, 0.05))

	# --- cab: raked windscreen, sleeper and a roof fairing up to the trailer
	var cab_top := 3.15
	var y0 := 0.95
	var rake := 0.3  # the windscreen leans back this far
	var p := [Vector3(-hw + 0.06, y0, cf), Vector3(hw - 0.06, y0, cf), Vector3(hw - 0.06, 2.0, cf), Vector3(-hw + 0.06, 2.0, cf)]
	_quad(cab, p[0], p[1], p[2], p[3], Vector3.FORWARD)                                       # lower front
	var wn := Vector3(0, rake, -(cab_top - 2.0)).normalized()
	var wtl := Vector3(-hw + 0.06, cab_top, cf + rake)
	var wtr := Vector3(hw - 0.06, cab_top, cf + rake)
	_quad(cab, p[3], p[2], wtr, wtl, wn)                                                      # windscreen frame
	for s in [-1.0, 1.0]:  # two panes either side of a slim pillar
		var x0: float = s * 0.04
		var x1: float = s * (hw - 0.16)
		_quad(glass, Vector3(x0, 2.1, cf - 0.006 + rake * 0.09), Vector3(x1, 2.1, cf - 0.006 + rake * 0.09),
			Vector3(x1, cab_top - 0.12, cf - 0.006 + rake * 0.9), Vector3(x0, cab_top - 0.12, cf - 0.006 + rake * 0.9), wn)
	_box(cab, Vector3(0, (y0 + cab_top) / 2.0, (cf + rake + cb) / 2.0), Vector3(w - 0.12, cab_top - y0, cb - cf - rake))  # cab sides and back
	for s in [-1.0, 1.0]:  # the lower front corners carry round onto the sides
		var sx: float = s * (hw - 0.06)
		_box(cab, Vector3(sx, (y0 + 2.0) / 2.0, cf + rake / 2.0), Vector3(0.02, 2.0 - y0, rake))
		_tri(cab, Vector3(sx, 2.0, cf), Vector3(sx, cab_top, cf + rake), Vector3(sx, 2.0, cf + rake), Vector3(s, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, 0))
	_box(cab, Vector3(0, cab_top + 0.04, (cf + rake + cb) / 2.0), Vector3(w - 0.2, 0.08, cb - cf - rake - 0.1))
	# fairing: a wedge from the cab roof to the trailer's top edge
	var fz0: float = cf + rake + 0.5
	var fz1: float = tf - 0.3
	var fl := [Vector3(-hw + 0.12, cab_top, fz0), Vector3(hw - 0.12, cab_top, fz0), Vector3(hw - 0.08, top - 0.05, fz1), Vector3(-hw + 0.08, top - 0.05, fz1)]
	_quad(cab, fl[0], fl[1], fl[2], fl[3], Vector3(0, 0.9, -0.4).normalized())
	for s in [-1.0, 1.0]:
		var x: float = s * (hw - 0.1)
		_tri(cab, Vector3(x, cab_top, fz0), Vector3(x, top - 0.05, fz1), Vector3(x, cab_top, fz1), Vector3(s, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, 0))
		# side fairing on the sleeper, closing the gap to the trailer
		_box(cab, Vector3(s * (hw - 0.04), 2.1, (cb + tf) / 2.0), Vector3(0.04, 2.0, absf(tf - cb) - 0.05))
	_box(cab, Vector3(0, (cab_top + top) / 2.0 - 0.1, fz1 + 0.02), Vector3(w - 0.2, top - cab_top - 0.1, 0.04))
	# grille, lamps, bumper, steps
	_box(chrome, Vector3(0, 1.45, cf - 0.02), Vector3(1.5, 0.95, 0.04))
	_box(dark, Vector3(0, 1.45, cf - 0.035), Vector3(1.38, 0.83, 0.03))
	for k in 6:
		_box(chrome, Vector3(0, 1.1 + k * 0.14, cf - 0.05), Vector3(1.36, 0.035, 0.03))
	for s in [-1.0, 1.0]:
		_box(dark, Vector3(s * (hw - 0.32), 1.12, cf - 0.025), Vector3(0.48, 0.3, 0.05))
		_box(head, Vector3(s * (hw - 0.36), 1.12, cf - 0.05), Vector3(0.36, 0.2, 0.02))
		_box(sig_l if s < 0 else sig_r, Vector3(s * (hw - 0.1), 1.12, cf - 0.05), Vector3(0.1, 0.2, 0.03))
		_box(dark, Vector3(s * (hw - 0.02), 0.55, cf + 0.75), Vector3(0.12, 0.05, 0.42))   # steps
		_box(dark, Vector3(s * (hw - 0.02), 0.85, cf + 0.75), Vector3(0.12, 0.05, 0.42))
		# door: window, outline and handle
		var dx: float = s * (hw - 0.055)
		_quad(glass, Vector3(dx + s * 0.003, 2.05, cf + 0.45), Vector3(dx + s * 0.003, 2.05, cf + 1.45),
			Vector3(dx + s * 0.003, 2.9, cf + 1.4), Vector3(dx + s * 0.003, 2.9, cf + 0.65), Vector3(s, 0, 0))
		_box(dark, Vector3(dx, 1.5, cf + 1.5), Vector3(0.015, 1.45, 0.02))
		_box(chrome, Vector3(dx + s * 0.01, 1.85, cf + 1.35), Vector3(0.02, 0.04, 0.18))
		# big mirrors on arms
		_strap(dark, Vector3(dx, 2.6, cf + 0.35), Vector3(s * (hw + 0.32), 2.75, cf + 0.25), 0.04, 0.04)
		_box(dark, Vector3(s * (hw + 0.36), 2.55, cf + 0.25), Vector3(0.1, 0.55, 0.26))
		_box(chrome, Vector3(s * (hw + 0.36), 2.55, cf + 0.385), Vector3(0.08, 0.5, 0.01))
		# exhaust stack behind the cab
		_cyl(chrome, Vector3(s * (hw - 0.22), 2.6, cb + 0.15), 0.08, 2.6, Vector3.UP, 12)
	_box(dark, Vector3(0, 0.72, cf + 0.05), Vector3(w + 0.04, 0.42, 0.22))        # bumper
	for s in [-1.0, 1.0]:
		_box(head, Vector3(s * 0.85, 0.72, cf - 0.065), Vector3(0.2, 0.08, 0.02))  # fog lamps
	_box(plate, Vector3(0, 0.72, cf - 0.065), Vector3(0.5, 0.12, 0.02))
	_box(dark, Vector3(0, cab_top - 0.04, cf + rake - 0.08), Vector3(w - 0.1, 0.06, 0.22))  # sun visor
	for k in 5:  # amber marker lamps along the roof
		_box(amber, Vector3(-0.6 + k * 0.3, cab_top + 0.1, cf + rake + 0.05), Vector3(0.12, 0.06, 0.06))

	var body := ArrayMesh.new()
	for st in [box, cab, glass, dark, chrome, plate, head, accent, amber]:
		st.commit(body)
	# wheels: steer axle, twin drive axles, twin trailer axles (x, z, tyre width)
	var wheels := []
	for z in [-(l - 0.95), -6.55, -5.45, -2.55, -1.35]:
		for s in [-1.0, 1.0]:
			wheels.append([s * (hw - 0.3), z, 0.5])
	return {"body": body, "tails": tails.commit(), "sig_l": sig_l.commit(), "sig_r": sig_r.commit(),
		"wheels": wheels, "r": 0.5, "ww": 0.5, "truck": true, "rim_frac": 0.62}


# ---------------------------------------------------------------- instance

var shape: Dictionary
var _tails: MeshInstance3D
var _body_mi: MeshInstance3D      # the shell's detailed mesh (and its light version, _far_mi): what a crash dents
var _far_mi: MeshInstance3D
var _surface_names: Array = []
var _surface_names_far: Array = []
var _plate_label: Label3D
var _calipers: Array = []         # by wheel: its brake caliper (or null)
var _gone: Array[bool] = []       # by wheel: it has come off
var _cracks := 0
var _glass_cracked: ShaderMaterial   # this car's own glass once a window of it has cracked (see crack_glass)
var _crack_vals: Array = [Vector4.ZERO, Vector4.ZERO]  # where the two cracked windows were hit and how badly (see crack_glass)
var _plate_lost := false
var _glass_cracked_key := ""
var _lamps_out := false
var _smoke_fx: CPUParticles3D
var _fire_fx: CPUParticles3D
var dmg: CarDamage                # what crashes have done to it (null while untouched)
var paint_color := Color(0.8, 0.8, 0.82)  # its body colour (the bits that fly off in a crash take it)
var _sig_l: MeshInstance3D
var _sig_r: MeshInstance3D
var _body: Node3D
var _wheels: Array[Node3D] = []
var _wheel_steer := 0.0  # road-wheel angle of the front wheels, radians (+ = right)
var _wheel_r := 0.32
var _spin := 0.0
var _wheel_front: Array[bool] = []  # which of the wheels steer
var _applied_spin := INF            # what the wheels were last turned to
var _applied_steer := INF
var _road := 0.0
var _phase := randf() * TAU
var _braking := false
var _shape_id := ""
var _needles: Array[Node3D] = []
var _needle_shadows: Array[Node3D] = []
var _steer_node: Node3D
var _display: Label3D          # the speed, big, in the window between the dials
var _display_gear: Label3D
var _display_unit: Label3D
var _screen: Label3D
var _lever: Node3D
var _lever_base := Vector3.ZERO
var _lever_target := Vector3.ZERO
var _last_screen := ""
var _d_gear := -1          # what the gear display and the infotainment screen were last built from
var _d_speed := ""
var _d_unit := ""
var _screen_id := ""
var _screen_name := ""
var _screen_trip: Variant = null
var _cabin_mi: MeshInstance3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _msg: Label3D
var _msg_until := 0
var _hands: Array[MeshInstance3D] = []
var _arms: Array = []
var _shoulders: Array = []
var _shadow_mi: MeshInstance3D


## Cars further away than this are fully hidden by haze, so they are not drawn.
const DRAW_DISTANCE := 360.0
## Beyond this a car is a few dozen pixels wide: the light body and wheels take over.
const LOD_NEAR := 40.0


## style (optional): {"rim", "rim_color", "caliper", "accent", "badge", "plate"} plus
## any KIT_KEYS flags. Traffic passes only a rim; the player and bosses get full kits.
func build(shape_id: String, color: Color, cab_color := Color("#b5322a"), style := {}) -> void:
	shape = Data.SHAPES[shape_id]
	_shape_id = shape_id
	paint_color = color
	var kit := _kit(shape_id, style)
	_body = Node3D.new()
	add_child(_body)

	var body := MeshInstance3D.new()
	body.mesh = kit.body
	_body_mi = body
	var M := {}
	if kit.has("surfaces"):
		M = {
			"paint": paint(color, String(style.get("finish", "gloss"))), "glass": _glass(), "glass_solid": _glass_solid(),
			"dark": mat(Color("#18191b"), 0.0, 0.6), "gloss": _gloss(), "under": mat(Color("#0b0c0e"), 0.0, 0.95),
			"chrome": _chrome(), "plate": mat(Color("#e8e6dc"), 0.0, 0.6),
			"head": lamp(Color("#fff6d8"), 2.0), "headlens": _headlens_mat(style.get("halo", false)), "grille": _grille_mat(),
			"accent": paint(Color(style.get("accent", "#f3f5ef"))),
		}
		M["cargo"] = M.paint
		if kit.get("truck", false):
			M["paint"] = paint(cab_color)  # tractor unit; the box keeps the main colour
		var names: Array = kit.surfaces
		_surface_names = names
		for i in names.size():
			body.set_surface_override_material(i, M[names[i]])
		# the light version of the body takes over beyond LOD_NEAR
		var kit_lq := _kit(shape_id, style, true)
		var far := MeshInstance3D.new()
		_far_mi = far
		far.mesh = kit_lq.body
		var names_lq: Array = kit_lq.surfaces
		_surface_names_far = names_lq
		for i in names_lq.size():
			far.set_surface_override_material(i, M[names_lq[i]])
		var near: float = kit.get("lod_near", LOD_NEAR)  # detailed imported/forged bodies hand over sooner
		_lod(body, 0.0, near)
		_lod(far, near, DRAW_DISTANCE)
		_body.add_child(far)
	else:
		var mats: Array[Material] = [mat(color, 0.0, 0.55, 0.1), paint(cab_color), _glass_solid(), mat(Color("#18191b"), 0.0, 0.7),
			_chrome(), mat(Color("#e8e6dc"), 0.0, 0.6), lamp(Color("#fff6d8"), 2.0), paint(Color(style.get("accent", "#f3f5ef"))),
			lamp(Color("#ffaa18"), 3.0)]
		for i in mats.size():
			body.set_surface_override_material(i, mats[i])
	_body.add_child(body)
	if kit.has("cabin"):
		_cabin_mi = MeshInstance3D.new()
		_cabin_mi.mesh = kit.cabin
		_cabin_mi.material_override = mat(Color("#222327"), 0.0, 0.85)
		_cabin_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(_cabin_mi)

	_tails = _light(kit.tails, _tail_mat(false))
	_sig_l = _light(kit.sig_l, lamp(Color("#ffaa18"), 5.0))
	_sig_r = _light(kit.sig_r, lamp(Color("#ffaa18"), 5.0))
	_sig_l.visible = false
	_sig_r.visible = false

	_wheel_r = kit.r
	var rim_style: String = style.get("rim", "steel" if kit.get("truck", false) else "5spoke")
	var rim_col := Color(style.get("rim_color", "#c3c8ce"))
	var rim_frac: float = kit.get("rim_frac", 0.66)
	var cal_col: String = style.get("caliper", "#55595e")
	for p in kit.wheels:
		var ww: float = p[2] if p.size() > 2 else kit.ww
		var wn := Node3D.new()
		wn.position = Vector3(p[0], kit.r, p[1])
		var mi := MeshInstance3D.new()
		mi.mesh = _wheel_mesh(kit.r, ww, rim_style, rim_col, rim_frac)
		wn.add_child(mi)
		if true:
			var mf := MeshInstance3D.new()
			mf.mesh = _wheel_mesh(kit.r, ww, rim_style, rim_col, rim_frac, true)
			wn.add_child(mf)
			_lod(mi, 0.0, LOD_NEAR)
			_lod(mf, LOD_NEAR, DRAW_DISTANCE)
		add_child(wn)  # wheels stay level when the body rolls
		_wheels.append(wn)
		_gone.append(false)
		_calipers.append(null)
		if not kit.get("truck", false):
			# brake caliper: fixed to the car, curving round the disc behind the spokes
			var cal := MeshInstance3D.new()
			cal.mesh = _caliper_mesh(kit.r * rim_frac * 0.8, 0.055)
			cal.material_override = _car_shader_mat("caliper|" + cal_col, {"base_color": Color(cal_col), "metallic": 0.1,
				"roughness": 0.3, "coat": 0.8, "reflect_amount": 0.7, "reflect_f0": 0.05})
			var outward := signf(p[0])
			cal.position = Vector3(p[0] + outward * (ww / 2.0 - 0.012 - 0.085 + 0.045), kit.r, p[1])
			cal.rotation.x = 0.35
			_lod(cal, 0.0, LOD_NEAR)
			add_child(cal)
			_calipers[_calipers.size() - 1] = cal

	if style.has("plate") or style.has("badge"):
		var py: float = kit.get("plate_y", 0.6)
		if style.has("plate"):
			var pl := Label3D.new()
			pl.text = style.plate
			pl.font_size = 48
			pl.pixel_size = 0.0019
			pl.modulate = Color("#1b2a4a")
			pl.outline_size = 0
			pl.position = Vector3(0, py, kit.get("plate_z", 0.024))
			if kit.get("truck", false):
				pl.position = Vector3(0, 0.82, 0.055)
			_body.add_child(pl)
			_plate_label = pl
			_lod(pl, 0.0, 45.0)
		if style.has("badge"):
			var bd := Label3D.new()
			bd.text = style.badge
			bd.font_size = 40
			bd.pixel_size = 0.0018
			bd.modulate = Color("#d9dde1")
			bd.outline_size = 0
			bd.position = Vector3(0.0, PROFILES.get(shape_id, {}).get("badge_y", (PROFILES.get(shape_id, {}).get("body", [[0, 0.8]])[0][1]) - 0.34), 0.02)
			_body.add_child(bd)
			_lod(bd, 0.0, 45.0)
	if style.has("fleet") and kit.get("truck", false):
		for s in [-1.0, 1.0]:  # the haulier's name along both sides of the trailer
			var fl := Label3D.new()
			fl.text = style.fleet
			fl.font_size = 96
			fl.pixel_size = 0.0058
			fl.double_sided = false  # only readable from its own side
			fl.modulate = Color(style.get("accent", "#f3f5ef")).lightened(0.2) if Color(style.get("accent", "#f3f5ef")).get_luminance() < 0.5 else Color("#1b1e23")
			fl.outline_size = 0
			fl.position = Vector3(s * (shape.w / 2.0 + 0.04), 2.95, -3.9)
			fl.rotation.y = s * PI / 2.0
			_body.add_child(fl)
			_lod(fl, 0.0, 140.0)

	# soft contact shadow so cars sit on the road even beyond the shadow distance
	var sh := MeshInstance3D.new()
	sh.mesh = _shadow()
	sh.material_override = _shadow_mat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.scale = Vector3(shape.w + 0.7, 1.0, shape.l + 0.9)
	sh.position = Vector3(0, 0.02, -shape.l / 2.0)
	add_child(sh)
	_shadow_mi = sh
	# headlight pool on the road ahead, shown at dusk (shared material, see set_night)
	var beam := MeshInstance3D.new()
	beam.mesh = _beam()
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.scale = Vector3(shape.w * 6.5, 1.0, 36.0)
	beam.position = Vector3(0, 0.035, -shape.l + 0.1)  # starts at the lamps, reaches forward
	beam.visible = night > 0.01
	beam.add_to_group("car_beams")
	add_child(beam)
	_set_draw_distance(self)


static func _beam() -> ArrayMesh:
	if _beam_mesh == null:
		# a flat strip from the front bumper (z = 0, v = 0) forward to z = -1
		# (v = 1); scaled per car. UVs set by hand so the cone's narrow end is
		# always at the lamps.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var vs := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, -1)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uvs[k])
			st.add_vertex(vs[k])
		_beam_mesh = st.commit()
		# soft beam: fades out to both sides and towards the far end, brightest
		# a few metres ahead of the bumper
		var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
		for y in 256:
			var along := float(y) / 255.0  # image row = v: 0 at the lamps .. 1 at the far end
			var fz := smoothstep(0.0, 0.06, along) * (1.0 - smoothstep(0.55, 1.0, along))
			var half := lerpf(0.1, 1.0, pow(along, 0.6))  # a cone: narrow at the lamps, fanning out ahead
			for x in 64:
				var across := absf(float(x) / 63.0 - 0.5) * 2.0
				var fx := 1.0 - smoothstep(half * 0.45, half, across)
				img.set_pixel(x, y, Color(1.0, 0.92, 0.76, 0.42 * fx * fz))
		var tex := ImageTexture.create_from_image(img)
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.albedo_texture = tex
		_beam_mat.albedo_color = Color(1, 1, 1, night)
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _beam_mesh


const DAY_ENV := {"env_zenith": Color(0.16, 0.33, 0.58), "env_horizon": Color(0.93, 0.9, 0.84)}
const DUSK_ENV := {"env_zenith": Color(0.1, 0.11, 0.22), "env_horizon": Color(0.86, 0.48, 0.32)}


## Dusk for every car at once: k = 0 (day) .. 1 (dusk). Headlights and tail
## lights glow brighter, light pools appear on the road ahead of every car,
## and the paint and glass reflect a dusk sky. sun_dir points at the sun.
static var _sun_dir := Vector3(-0.545, 0.53, 0.65)


static var _env_zenith: Color = DAY_ENV.env_zenith
static var _env_horizon: Color = DAY_ENV.env_horizon


static func _dusk_params(m: ShaderMaterial) -> void:
	if m.shader != _paint_shader and m.shader != _glass_shader and m.shader != _glass_cracked_shader:
		return
	m.set_shader_parameter("env_zenith", _env_zenith)
	m.set_shader_parameter("env_horizon", _env_horizon)
	m.set_shader_parameter("env_sun_dir", _sun_dir)


## The time of day for every car at once: k = how far the lights are on
## (0 day .. 1 night), sun_dir points at the sun (or moon), and the paint and
## glass reflect a sky of zenith/horizon colours.
static func set_night(k: float, sun_dir: Vector3, zenith: Color = DAY_ENV.env_zenith, horizon: Color = DAY_ENV.env_horizon) -> void:
	var was_on := night > 0.01
	night = k
	_sun_dir = sun_dir
	_env_zenith = zenith
	_env_horizon = horizon
	_beam()
	_beam_mat.albedo_color = Color(1, 1, 1, k)
	lamp(Color("#fff6d8"), 2.0).emission_energy_multiplier = lerpf(2.0, 7.0, k)
	_tail_mat(false).emission_energy_multiplier = lerpf(0.9, 2.6, k)
	for halo in [false, true]:
		_headlens_mat(halo).emission_energy_multiplier = lerpf(2.2, 6.0, k)
	if _mirror_mat:
		_mirror_mat.albedo_color = Color.WHITE.lerp(Color(0.22, 0.22, 0.25), k)
	for key in _mats:
		var m: Variant = _mats[key]
		if m is ShaderMaterial:
			_dusk_params(m as ShaderMaterial)
			if (m as ShaderMaterial).shader == _inner_shader:
				(m as ShaderMaterial).set_shader_parameter("dim", lerpf(1.0, 0.2, k))
	if was_on != (k > 0.01):
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			for n in tree.get_nodes_in_group("car_beams"):
				(n as Node3D).visible = k > 0.01


## Keep the full-detail body and wheels at any distance (the player's car:
## the replay's trackside camera zooms in on it from far away).
func force_detail() -> void:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D and n.has_meta("lod"):
			var gi := n as GeometryInstance3D
			if gi.visibility_range_begin > 0.0:
				gi.visible = false  # the light version is never needed
			else:
				gi.visibility_range_end = DRAW_DISTANCE
		for c in n.get_children():
			stack.append(c)


const FLEETS := ["NORTHLINE FREIGHT", "PRAIRIE HAULAGE", "BLUE RIDGE LOGISTICS", "IRONWAY CARGO", "COASTAL MOVERS", "SUMMIT EXPRESS", "REDROCK TRANSPORT"]
const MAKES := ["ARCO", "NOVA", "CIVITA", "LUMEN", "VEGA", "ORIX", "TERRA", "KITE", "MERIT", "AXON"]


## The look of one traffic vehicle: its wheels, number plate and badge (and
## a haulier's livery on lorries), so no two cars on the road are identical.
static func traffic_style(shape: String) -> Dictionary:
	var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
	var plate_text := ""
	for k in 3:
		plate_text += letters[randi() % letters.length()]
	plate_text += " %03d" % (randi() % 1000)
	var st := {"plate": plate_text}
	match shape:
		"truck":
			st.rim = "steel"
			st.accent = ["#f3f5ef", "#d9a21b", "#b5322a", "#1f4e8c", "#2e7d32", "#1b1e23"].pick_random()
			st.fleet = FLEETS.pick_random()
		"van":
			st.rim = ["steel", "5spoke"].pick_random()
			st.badge = MAKES.pick_random()
		_:
			st.rim = ["steel", "5spoke", "5spoke", "multi", "multi", "double", "mesh"].pick_random()
			st.rim_color = ["#c3c8ce", "#c3c8ce", "#9aa0a6", "#2a2c30", "#d6d9dc", "#5b5f64"].pick_random()
			st.caliper = ["#55595e", "#55595e", "#2a2c30", "#9b1c1c"].pick_random()
			st.badge = MAKES.pick_random()
	return st


## Draw gi only between `begin` and `end` metres from the camera.
func _lod(gi: GeometryInstance3D, begin: float, end: float) -> void:
	gi.visibility_range_begin = begin
	gi.visibility_range_end = end
	gi.set_meta("lod", true)


func _set_draw_distance(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D and not c.has_meta("lod"):
			var gi := c as GeometryInstance3D
			gi.visibility_range_end = DRAW_DISTANCE
			gi.visibility_range_end_margin = 0.0  # fully hidden by the depth fog there anyway
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_set_draw_distance(c)


func _light(m: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)
	return mi


## Tinted car glass: see-through head-on, a mirror of the sky at an angle.
static func _glass() -> Material:
	var key := "glass"
	if not _mats.has(key):
		if _glass_shader == null:
			_glass_shader = load("res://shaders/car_glass.gdshader")
		var m := ShaderMaterial.new()
		m.shader = _glass_shader
		_mats[key] = m
	return _mats[key]


## Opaque dark glass for vans and trucks, whose bodies are closed boxes.
static func _glass_solid() -> Material:
	return _car_shader_mat("glass_solid", {"base_color": Color("#0c1116"), "metallic": 0.0, "roughness": 0.05, "coat": 0.5,
		"reflect_amount": 1.25, "reflect_f0": 0.07})


static var _shells := {}
const SHELL_STEP := 0.04


## The inside of an imported body, measured from its mesh: for each spot on
## the floor plan the lowest roof (or glass) overhead, and for each height
## along the car how far out the side walls are. Used to keep the cockpit
## inside bodywork it was not built for.
static func _shell(id: String) -> Dictionary:
	if _shells.has(id):
		return _shells[id]
	var kit := _kit(id, {})
	var shell := _shell_of(kit.body, kit.surfaces, Data.SHAPES[id])
	_shells[id] = shell
	return shell


## Every vertex of a mesh moved inside a measured shell.
static func _clamp_mesh(m: ArrayMesh, shell: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for vi in vs.size():
			vs[vi] = _inside_shell(vs[vi], shell)
		arr[Mesh.ARRAY_VERTEX] = vs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


static func _shell_of(body: ArrayMesh, names: Array, sh: Dictionary) -> Dictionary:
	var L: float = sh.l
	var hw: float = sh.w / 2.0
	var nd := int(L / SHELL_STEP) + 2
	var nx := int(hw / SHELL_STEP) + 2
	var ny := int(2.4 / SHELL_STEP) + 2
	var top := PackedFloat32Array()
	top.resize(nd * nx)
	top.fill(99.0)
	var side := PackedFloat32Array()
	side.resize(nd * ny)
	side.fill(99.0)
	var back := PackedFloat32Array()  # per (x, height): where the tail panel or rear window is
	back.resize(nx * ny)
	back.fill(-99.0)
	for si in body.get_surface_count():
		if not names[si] in ["paint", "cargo", "glass", "gloss", "dark"]:
			continue  # wheel wells, lamps and plates are not cabin walls
		var arr := body.surface_get_arrays(si)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var Nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, I.size(), 3):
			var a := V[I[t]]
			var b := V[I[t + 1]]
			var c := V[I[t + 2]]
			var n := (Nn[I[t]] + Nn[I[t + 1]] + Nn[I[t + 2]]).normalized()
			var ymin := minf(a.y, minf(b.y, c.y))
			var ymax := maxf(a.y, maxf(b.y, c.y))
			if ymax < 0.7:
				continue
			var d0 := int(-maxf(a.z, maxf(b.z, c.z)) / SHELL_STEP)
			var d1 := int(-minf(a.z, minf(b.z, c.z)) / SHELL_STEP) + 1
			if n.y > 0.55:  # roof, windscreen and bonnet seen from inside (side glass is a wall)
				var x0 := int(minf(absf(a.x), minf(absf(b.x), absf(c.x))) / SHELL_STEP)
				var x1 := int(maxf(absf(a.x), maxf(absf(b.x), absf(c.x))) / SHELL_STEP) + 1
				for di in range(maxi(d0, 0), mini(d1, nd - 1) + 1):
					for xi in range(maxi(x0, 0), mini(x1, nx - 1) + 1):
						var k := di * nx + xi
						top[k] = minf(top[k], ymin)
			if n.z > 0.4 and d1 * SHELL_STEP < 1.3:  # tail panel and rear window, seen from inside
				var dmax := -minf(a.z, minf(b.z, c.z))
				var bx0 := int(minf(absf(a.x), minf(absf(b.x), absf(c.x))) / SHELL_STEP)
				var bx1 := int(maxf(absf(a.x), maxf(absf(b.x), absf(c.x))) / SHELL_STEP) + 1
				var by0 := int(ymin / SHELL_STEP)
				var by1 := int(ymax / SHELL_STEP) + 1
				for xi in range(maxi(bx0, 0), mini(bx1, nx - 1) + 1):
					for yi in range(maxi(by0, 0), mini(by1, ny - 1) + 1):
						var k3 := xi * ny + yi
						back[k3] = maxf(back[k3], dmax)
			if absf(n.x) > 0.45:  # side walls and side glass
				var ax := minf(absf(a.x), minf(absf(b.x), absf(c.x)))
				var y0 := int(ymin / SHELL_STEP)
				var y1 := int(ymax / SHELL_STEP) + 1
				for di in range(maxi(d0, 0), mini(d1, nd - 1) + 1):
					for yi in range(maxi(y0, 0), mini(y1, ny - 1) + 1):
						var k2 := di * ny + yi
						side[k2] = minf(side[k2], ax)
	return {"top": top, "side": side, "back": back, "nd": nd, "nx": nx, "ny": ny}


## The lowest roof or glass overhead within `r` of a point `x` across the car and
## `d` from the rear bumper (99 where there is none).
static func _top_over(shell: Dictionary, x: float, d: float, r := 0.1) -> float:
	var top: PackedFloat32Array = shell.top
	var nx: int = shell.nx
	var nd: int = shell.nd
	var best := 99.0
	for di in range(maxi(int((d - r) / SHELL_STEP), 0), mini(int((d + r) / SHELL_STEP) + 1, nd - 1) + 1):
		for xi in range(maxi(int((absf(x) - r) / SHELL_STEP), 0), mini(int((absf(x) + r) / SHELL_STEP) + 1, nx - 1) + 1):
			best = minf(best, top[di * nx + xi])
	return best


## How far in the side wall (or window) is, within `r` of height `y`, `d` from the rear.
static func _side_at(shell: Dictionary, d: float, y: float, r := 0.1) -> float:
	var side: PackedFloat32Array = shell.side
	var ny: int = shell.ny
	var nd: int = shell.nd
	var best := 99.0
	for di in range(maxi(int((d - r) / SHELL_STEP), 0), mini(int((d + r) / SHELL_STEP) + 1, nd - 1) + 1):
		for yi in range(maxi(int((y - r) / SHELL_STEP), 0), mini(int((y + r) / SHELL_STEP) + 1, ny - 1) + 1):
			best = minf(best, side[di * ny + yi])
	return best


## A cockpit point moved inside the measured shell (with a little clearance).
static func _inside_shell(v: Vector3, shell: Dictionary, m := 0.025) -> Vector3:
	var nd: int = shell.nd
	var nx: int = shell.nx
	var ny: int = shell.ny
	var di := clampi(int(-v.z / SHELL_STEP), 0, nd - 1)
	var xi := clampi(int(absf(v.x) / SHELL_STEP), 0, nx - 1)
	var t: float = (shell.top as PackedFloat32Array)[di * nx + xi]
	if t < 90.0 and v.y > t - m:
		v.y = t - m
	var yi := clampi(int(v.y / SHELL_STEP), 0, ny - 1)
	var sd: float = (shell.side as PackedFloat32Array)[di * ny + yi]
	if sd < 90.0 and absf(v.x) > sd - m:
		v.x = signf(v.x) * maxf(sd - m, 0.0)
	# and in front of the tail panel / rear window
	var xi2 := clampi(int(absf(v.x) / SHELL_STEP), 0, nx - 1)
	var bk: float = (shell.back as PackedFloat32Array)[xi2 * ny + yi]
	if bk > -90.0 and -v.z < bk + m + 0.005 and -v.z < 1.3:
		v.z = -(bk + m + 0.005)
	return v


## Gloss-black trim: window surrounds, B-pillars, mirror arms.
static func _gloss() -> Material:
	return _car_shader_mat("gloss", {"base_color": Color("#0b0c0e"), "metallic": 0.0, "roughness": 0.18, "coat": 0.8,
		"coat_roughness": 0.04, "reflect_amount": 1.0, "reflect_f0": 0.05})


## Textured lamp lens (CarTextures) that glows and fades out with distance.
static func _lens(key: String, tex: Array, energy: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex[0]
	m.emission_enabled = true
	m.emission_texture = tex[1]
	m.emission = Color.WHITE
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # glow only where the texture has LEDs
	m.emission_energy_multiplier = energy
	# satin lens: a glossy one mirrors the bright sky and washes the colour out to white
	m.roughness = 0.35
	m.metallic = 0.0
	m.metallic_specular = 0.25
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 230.0
	m.distance_fade_max_distance = 110.0
	_mats[key] = m
	return m


static func _headlens_mat(halo := false) -> StandardMaterial3D:
	return _lens("headlens%s" % halo, CarTextures.headlight(halo), 2.2)


static func _grille_mat() -> StandardMaterial3D:
	var key := "grille"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = CarTextures.grille()[0]
		m.roughness = 0.45
		m.metallic = 0.35
		_mats[key] = m
	return _mats[key]


static func _tail_mat(on: bool) -> StandardMaterial3D:
	return _lens("tail_on", CarTextures.taillight(), 5.0) if on else _lens("tail_off", CarTextures.taillight(), 0.9)


static func _shadow() -> PlaneMesh:
	if _shadow_mesh == null:
		_shadow_mesh = PlaneMesh.new()
		_shadow_mesh.size = Vector2(1, 1)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.62))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.45))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.albedo_texture = tex
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _shadow_mesh


func set_brake(on: bool) -> void:
	if on == _braking:
		return
	_braking = on
	_tails.material_override = _tail_mat(on)


## dir: -1 left, 1 right, 0 off. lit toggles the blink phase.
func set_signal(dir: int, lit: bool) -> void:
	var l := dir < 0 and lit
	var r := dir > 0 and lit
	if l != _sig_l.visible:
		_sig_l.visible = l
	if r != _sig_r.visible:
		_sig_r.visible = r


## Lean the body (not the wheels) for a sense of weight when steering.
var _roll := 0.0
var _pitch := 0.0
var _bob := 0.0
var _droop := Vector2.ZERO  # (pitch, roll) the body sags by when a wheel is missing
var _body_xf := Transform3D(Basis(Vector3.INF, Vector3.INF, Vector3.INF), Vector3.INF)  # what the body node was last given (nothing yet)


func set_roll(r: float) -> void:
	_roll = r
	_pose_body()


## Roll and pitch about the car's middle at wheel-hub height (like real
## suspension), so the arches stay round the wheels instead of the whole
## body swinging about its rear bumper on the ground.
func _pose_body() -> void:
	if _body == null or shape.is_empty():
		return
	var xf: Transform3D
	var pitch := _pitch + _droop.x
	var roll := _roll + _droop.y
	if pitch == 0.0 and roll == 0.0:
		xf = Transform3D(Basis.IDENTITY, Vector3(0, _bob, 0))  # (what the general case comes to, without the trigonometry: traffic never leans)
	else:
		var pivot := Vector3(0.0, _wheel_r, -float(shape.l) * 0.5)
		var b := Basis.from_euler(Vector3(-pitch, 0.0, roll))
		xf = Transform3D(b, pivot - b * pivot + Vector3(0, _bob, 0))
	if xf != _body_xf:  # a car standing still is not moved again every frame
		_body_xf = xf
		_body.transform = xf


var _tag_pop: Label3D
var _tag_tween: Tween


## A boss's score message, floating above its name tag.
func show_tag_pop(text: String) -> void:
	if _tag_pop == null:
		_tag_pop = Label3D.new()
		_tag_pop.font_size = 56
		_tag_pop.pixel_size = 0.011
		_tag_pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag_pop.no_depth_test = true
		_tag_pop.modulate = Color("#ffb347")
		_tag_pop.outline_modulate = Color("#3a0d0d")
		_tag_pop.outline_size = 14
		add_child(_tag_pop)
	_tag_pop.text = text
	_tag_pop.position = Vector3(0, shape.t + 2.3, -shape.l / 2.0)
	_tag_pop.modulate.a = 1.0
	_tag_pop.outline_modulate.a = 1.0
	if _tag_tween:
		_tag_tween.kill()
	_tag_tween = create_tween()
	_tag_tween.tween_interval(0.9)
	_tag_tween.tween_property(_tag_pop, "modulate:a", 0.0, 0.5)
	_tag_tween.parallel().tween_property(_tag_pop, "outline_modulate:a", 0.0, 0.5)


## Crash pose: the whole car (body and wheels) turned by `heading` (radians,
## + = nose to the right) and rolled by `roll` (radians, + = right side up),
## pivoting on its centre so it never sinks into the road. `air` lifts it.
## `x` is where the middle of the car is across the road and `z0` where its rear
## bumper is along the scene's z (0 for the player, who is always at the origin).
func set_crash_pose(x: float, heading: float, roll: float, air: float, z0 := 0.0) -> void:
	var hw: float = shape.w / 2.0
	var hh: float = shape.t / 2.0
	var b := Basis(Vector3.UP, -heading) * Basis(Vector3.BACK, roll)
	var cy := hw * absf(sin(roll)) + hh * absf(cos(roll)) + air
	var centre := Vector3(0, hh, -shape.l / 2.0)
	transform = Transform3D(b, Vector3(x, cy, z0 - shape.l / 2.0) - b * centre)
	_roll = 0.0
	_pitch = 0.0
	_pose_body()
	if _shadow_mi:  # the contact shadow only suits a car standing on its wheels
		_shadow_mi.visible = absf(roll) < 0.3 and air < 0.1


## Back on its wheels after a crash pose.
func clear_crash_pose() -> void:
	rotation = Vector3.ZERO
	if _shadow_mi:
		_shadow_mi.visible = true


## World positions of the four tyre contact patches.
func wheel_contacts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in _wheels.size():
		if not _gone[i]:
			out.append(_wheels[i].global_position - global_transform.basis.y * _wheel_r)
	return out


# ---------------------------------------------------------------- damage

## The meshes of the shell that a crash dents (the body, its light version, the tail and signal lamps).
func damage_targets() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in [_body_mi, _far_mi, _tails, _sig_l, _sig_r, _cabin_mi]:
		if mi != null and is_instance_valid(mi):
			out.append(mi)
	return out


## What crashes have done to this car (made at the first knock).
func damage() -> CarDamage:
	if dmg == null:
		dmg = CarDamage.new(self)
	return dmg


## Where the glass is, in the car's space: "front" (the windscreen), "rear" or "side" (+1 right, -1 left).
func glass_spot(which: String, side := 1.0) -> Vector3:
	var pr: Dictionary = PROFILES.get(_shape_id, {})
	var w: float = shape.w
	var l: float = shape.l
	var t: float = shape.t
	if pr.has("gh"):
		var g: Array = pr.gh
		var mid: float = (float(g[4]) + float(g[5])) * 0.5
		match which:
			"front":
				return Vector3(0.0, mid - 0.04, -(float(g[1]) - 0.4))
			"rear":
				return Vector3(0.0, float(g[4]) + 0.14, -(float(g[0]) + 0.1))
			_:
				return Vector3(side * w * 0.5 * float(g[6]), mid, -(float(g[0]) + float(g[1])) * 0.5)
	match which:
		"front":
			return Vector3(0.0, t * 0.78, -l * 0.4)
		"rear":
			return Vector3(0.0, t * 0.78, -l * 0.12)
		_:
			return Vector3(side * w * 0.5, t * 0.75, -l * 0.28)


## A window cracks round `p` (0.2 a star, 1 shattered). Two can be cracked at once (the cracked-glass shader draws
## both). The first crack gives this car glass of its own, with the cracked-glass shader; until then every car's glass
## is the one plain shared material, with no per-car parameters in it.
func crack_glass(p: Vector3, amount: float) -> void:
	if _glass_cracked == null:
		if _glass_cracked_shader == null:
			_glass_cracked_shader = load("res://shaders/car_glass_cracked.gdshader")
		_glass_cracked = ShaderMaterial.new()
		_glass_cracked.shader = _glass_cracked_shader
		_dusk_params(_glass_cracked)  # (the sky it reflects is the one the shared glass reflects now)
		_glass_cracked_key = "glass_cracked|%d" % get_instance_id()
		_mats[_glass_cracked_key] = _glass_cracked  # (so set_night keeps its sky up to date)
		for pair in [[_body_mi, _surface_names], [_far_mi, _surface_names_far]]:
			var mi: MeshInstance3D = pair[0]
			if mi == null:
				continue
			var names: Array = pair[1]
			for i in names.size():
				if String(names[i]) == "glass":
					mi.set_surface_override_material(i, _glass_cracked)
	var slot := "crack_a" if _cracks % 2 == 0 else "crack_b"
	var cv := Vector4(p.x, p.y, p.z, clampf(amount, 0.0, 1.0))
	_crack_vals[_cracks % 2] = cv
	_cracks += 1
	_glass_cracked.set_shader_parameter(slot, cv)


func _exit_tree() -> void:
	if _glass_cracked_key != "":
		_mats.erase(_glass_cracked_key)


func _enter_tree() -> void:
	if _glass_cracked_key != "":
		_mats[_glass_cracked_key] = _glass_cracked


## A smashed front: the headlamps and the tail lamps go dark and dull.
func break_lamps() -> void:
	if _lamps_out:
		return
	_lamps_out = true
	var dull := mat(Color("#2a1f1c"), 0.0, 0.5)
	for pair in [[_body_mi, _surface_names], [_far_mi, _surface_names_far]]:
		var mi: MeshInstance3D = pair[0]
		if mi == null:
			continue
		var names: Array = pair[1]
		for i in names.size():
			if String(names[i]) in ["head", "headlens"]:
				mi.set_surface_override_material(i, dull)
	if _tails:
		_tails.material_override = mat(Color("#3a1210"), 0.0, 0.5)


## The number plate comes off with a hard knock.
func lose_plate() -> void:
	_plate_lost = true
	if _plate_label:
		_plate_label.visible = false


## What crashes have done to this car, as plain numbers that can be saved: the dents, the cracked windows, whether
## the lamps are out and the number plate gone, and which wheels have come off. (Empty: not a mark on it.)
func damage_state() -> Dictionary:
	var out := {}
	if dmg != null and not dmg.dents.is_empty():
		out["dents"] = dmg.state()
	var cracks: Array = []
	for cv: Vector4 in _crack_vals:
		if cv.w > 0.0:
			cracks.append([CarDamage._q(cv.x), CarDamage._q(cv.y), CarDamage._q(cv.z), CarDamage._q(cv.w)])
	if not cracks.is_empty():
		out["glass"] = cracks
	if _lamps_out:
		out["lamps"] = true
	if _plate_lost:
		out["plate"] = true
	var gone: Array = []
	for i in _gone.size():
		if _gone[i]:
			gone.append(i)
	if not gone.is_empty():
		out["wheels"] = gone
	return out


## Put saved damage back on a freshly built car (a record as Save keeps it: damage_state's numbers and `wear`). The
## dents are pressed in on the worker threads, so they show a moment after the car does. `smoke`: a badly damaged
## car smokes under the bonnet (for a car that is about to drive).
func restore_damage(rec: Dictionary, smoke := false) -> void:
	if rec.is_empty():
		return
	var wear := clampf(CarDamage.num(rec.get("wear")), 0.0, 1.0)
	if rec.get("dents") is Array:
		var d := damage()
		d.restore(rec.dents as Array)
		d.level = maxf(d.level, wear * 2.0)
	if rec.get("glass") is Array:
		for row in (rec.glass as Array):
			if row is Array and (row as Array).size() >= 4:
				var f: Array = row
				crack_glass(Vector3(CarDamage.num(f[0]), CarDamage.num(f[1]), CarDamage.num(f[2])), clampf(CarDamage.num(f[3]), 0.0, 1.0))
	if rec.get("lamps", false):
		break_lamps()
	if rec.get("plate", false):
		lose_plate()
	if rec.get("wheels") is Array:
		for i in (rec.wheels as Array):
			if i is float or i is int:
				set_wheel_gone(int(i))
	if smoke and wear >= 0.6:
		start_smoke(false)


func wheel_count() -> int:
	return _wheels.size()


func wheel_gone(i: int) -> bool:
	return i >= 0 and i < _gone.size() and _gone[i]


## The wheel nearest a point in the car's space (-1 if they have all come off).
func nearest_wheel(p: Vector3) -> int:
	var best := -1
	var best_d := 1e9
	for i in _wheels.size():
		if _gone[i]:
			continue
		var d := Vector2(_wheels[i].position.x - p.x, _wheels[i].position.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## Take wheel i off the car. Returns it (a node with its tyre and rim, in the car's own space, its world
## transform kept) for the game to fling down the road, or null. The car sags at that corner.
func detach_wheel(i: int) -> Node3D:
	if i < 0 or i >= _wheels.size() or _gone[i]:
		return null
	var wn := _wheels[i]
	var gone_front: bool = wn.position.z < -float(shape.l) * 0.5
	var side := signf(wn.position.x)
	_gone[i] = true
	var xf := wn.global_transform
	remove_child(wn)
	if _calipers[i]:
		(_calipers[i] as Node3D).visible = false
	# the body sags towards the corner that has lost its wheel
	_droop += Vector2((-0.03 if gone_front else 0.03), side * 0.035)
	_pose_body()
	wn.transform = xf  # (outside the tree: the game puts it in the world and keeps this transform)
	return wn


## A wheel that came off in an earlier crash (see restore_damage): out of sight, and the car sags at that corner.
func set_wheel_gone(i: int) -> void:
	if i < 0 or i >= _wheels.size() or _gone[i]:
		return
	var wn := _wheels[i]
	var gone_front: bool = wn.position.z < -float(shape.l) * 0.5
	var side := signf(wn.position.x)
	_gone[i] = true
	wn.visible = false
	if _calipers[i]:
		(_calipers[i] as Node3D).visible = false
	_droop += Vector2((-0.03 if gone_front else 0.03), side * 0.035)
	_pose_body()


## Smoke (and, when badly damaged, flames) from under the bonnet.
func start_smoke(heavy: bool) -> void:
	if _smoke_fx == null:
		_smoke_fx = _make_engine_smoke()
		add_child(_smoke_fx)
		_smoke_fx.position = Vector3(0.0, float(shape.t) * 0.66, -float(shape.l) * 0.78)
	_smoke_fx.emitting = true
	if heavy and _fire_fx == null:
		_fire_fx = _make_engine_fire()
		add_child(_fire_fx)
		_fire_fx.position = _smoke_fx.position
		_fire_fx.emitting = true


static var _puff_tex: Texture2D


static func _puff() -> Texture2D:
	if _puff_tex == null:
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		g.width = 64
		g.height = 64
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		g.gradient = gr
		_puff_tex = g
	return _puff_tex


func _make_engine_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.7
	p.local_coords = false  # the smoke is left behind as the car drives on
	p.direction = Vector3(0, 1, 0.5)
	p.spread = 18.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, 0.9, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.7))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.16, 0.17, 0.7))
	grad.set_color(1, Color(0.35, 0.35, 0.36, 0.0))
	p.color_ramp = grad
	var m := QuadMesh.new()
	m.size = Vector2(1.1, 1.1)
	p.mesh = m
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.vertex_color_use_as_albedo = true
	mt.albedo_texture = _puff()
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mt.billboard_keep_scale = true
	mt.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.material_override = mt
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_engine_fire() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.55
	p.local_coords = true
	p.direction = Vector3(0, 1, 0.2)
	p.spread = 14.0
	p.initial_velocity_min = 0.9
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.78, 0.25, 0.95))
	grad.add_point(0.45, Color(1.0, 0.36, 0.08, 0.7))
	grad.set_color(1, Color(0.2, 0.05, 0.02, 0.0))
	p.color_ramp = grad
	var m := QuadMesh.new()
	m.size = Vector2(0.8, 0.8)
	p.mesh = m
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.vertex_color_use_as_albedo = true
	mt.albedo_texture = _puff()
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mt.billboard_keep_scale = true
	mt.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.material_override = mt
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Pitch the body: positive dips the nose (braking), negative squats (accelerating).
func set_pitch(p: float) -> void:
	_pitch = p
	_pose_body()


## Turn the wheels for a car travelling at v m/s.
func spin(v: float, dt: float) -> void:
	_spin = fmod(_spin - v / _wheel_r * dt, TAU)
	if _body:
		_road += v * dt
		var k := minf(v / 30.0, 1.0)
		_bob = (0.005 * sin(_road * 1.3 + _phase) + 0.0025 * sin(_road * 4.1 + _phase * 2.0)) * k
		_pose_body()
	if _wheel_front.size() != _wheels.size():
		var front_z := 0.0  # the wheels at the front axle are the ones that steer
		for wn in _wheels:
			front_z = minf(front_z, wn.position.z)
		_wheel_front.clear()
		for wn in _wheels:
			_wheel_front.append(wn.position.z < front_z + 0.6)
	if _spin == _applied_spin and _wheel_steer == _applied_steer:
		return  # nothing turned since last time
	_applied_spin = _spin
	_applied_steer = _wheel_steer
	# (the same turn as setting rotation.x and rotation.y on each wheel, in one go, worked out once for the
	# wheels that steer and once for the ones that do not)
	var b_front := Basis.from_euler(Vector3(_spin, -_wheel_steer, 0.0))
	var b_rear := Basis.from_euler(Vector3(_spin, 0.0, 0.0))
	for i in _wheels.size():
		if _gone[i]:
			continue
		var wn := _wheels[i]
		wn.transform = Transform3D(b_front if _wheel_front[i] else b_rear, wn.position)


## Turn the front wheels to a road-wheel angle (radians, + = right).
func set_wheel_steer(a: float) -> void:
	_wheel_steer = a


# ---------------------------------------------------------------- first-person

## The body node, which carries roll and pitch. First-person cameras ride on it.
func body_node() -> Node3D:
	return _body


var _eye_cache := Vector3.INF


## Driver's eye position in car space. The seat goes where the roof is highest
## and the head just clears it (with room to spare for the body to pitch), as
## far forward as it takes to see a good stretch of road over the dash.
func cockpit_eye() -> Vector3:
	if _eye_cache != Vector3.INF:
		return _eye_cache
	var pr: Dictionary = PROFILES.get(_shape_id, PROFILES.sedan)
	if not pr.has("gh"):
		return Vector3(-0.42, 1.72, -3.95)
	var g: Array = pr.gh
	var ex: float = -0.36 * float(shape.w) / 1.84
	var shell := _shell(_shape_id)
	var best := Vector3.INF
	var best_score := -1e9
	for k in 36:
		var dist := 0.9 + 0.05 * (k % 12)            # from the eye to the windscreen base
		var xs: float = [1.0, 0.85, 0.7][k / 12]     # seat a little towards the middle if the roof is domed
		var d: float = g[1] - dist                   # from the rear bumper
		var roof := _top_over(shell, ex * xs, d, 0.11)
		if roof > 90.0:
			continue
		var y_head := roof - 0.15                    # the head is 10 cm above the eye, with 5 cm to spare
		var y_cowl: float = float(g[4]) - 0.03 + tan(deg_to_rad(6.5)) * dist  # eye height for a 6.5 degree view over the cowl
		# in a low car sit as high as the roof allows (1 cm to spare for the head) rather than lose the road behind the dash
		var y := y_head if y_head >= y_cowl else minf(y_cowl, roof - 0.11)
		var score: float = y - 3.0 * maxf(y_cowl - y, 0.0) - 0.2 * absf(dist - 1.15) - 1.2 * (1.0 - xs) * absf(ex)
		if score > best_score:
			best_score = score
			best = Vector3(ex * xs, y, -d)
	if best == Vector3.INF:
		var y: float = float(pr.eye_y) + 0.035 if pr.has("eye_y") else minf(g[4] + 0.38, g[5] - 0.16)
		best = Vector3(ex, y, -(g[1] - float(pr.get("eye_back", 1.2))))
	# and clear of the door and pillar beside it
	var sd := _side_at(shell, -best.z, best.y, 0.1)
	if sd < 90.0 and absf(best.x) > sd - 0.14:
		best.x = -maxf(sd - 0.14, 0.25)
	_eye_cache = best
	return best


## Bonnet camera position in car space.
func hood_eye() -> Vector3:
	var pr: Dictionary = PROFILES.get(_shape_id, PROFILES.sedan)
	if not pr.has("gh"):
		return Vector3(0, 1.62, -4.75)
	var d: float = pr.gh[1] + 0.3
	return Vector3(0, _station_at(pr.body, d, 1) + 0.2, -d)


## A prism along x: the convex polygon `pts` (z, y pairs) swept from x0 to x1, closed at both ends.
static func _prism(st: SurfaceTool, pts: Array, x0: float, x1: float) -> void:
	var n := pts.size()
	var c := Vector2.ZERO
	for p in pts:
		c += p as Vector2
	c /= n
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var e := b - a
		var nz := Vector2(e.y, -e.x)
		if nz.dot((a + b) / 2.0 - c) < 0.0:
			nz = -nz
		nz = nz.normalized()
		_quad(st, Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x), Vector3(0, nz.y, nz.x))
	var p0: Vector2 = pts[0]
	for k in range(1, n - 1):
		var pa: Vector2 = pts[k]
		var pb: Vector2 = pts[k + 1]
		_tri(st, Vector3(x0, p0.y, p0.x), Vector3(x0, pa.y, pa.x), Vector3(x0, pb.y, pb.x), Vector3.LEFT, Vector3.LEFT, Vector3.LEFT)
		_tri(st, Vector3(x1, p0.y, p0.x), Vector3(x1, pa.y, pa.x), Vector3(x1, pb.y, pb.x), Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)


## An arched hood over the instrument dials: a squared-off arch (a superellipse)
## standing on y0, swept from z_near (the face the dials sit on) back to z_far,
## its crown at top_near / top_far.
static func _pod(st: SurfaceTool, cx: float, hw: float, z_near: float, z_far: float, y0: float, top_near: float, top_far: float) -> void:
	var rings := 4
	var segs := 14
	var prev: Array = []
	for r in rings + 1:
		var f := float(r) / rings
		var z := lerpf(z_near, z_far, f)
		var h := maxf(lerpf(top_near, top_far, f) - y0, 0.02)
		var ring: Array = []
		for s in segs + 1:
			var th := PI * s / segs
			var cs := cos(th)
			ring.append(Vector3(cx + hw * signf(cs) * pow(absf(cs), 0.571), y0 + h * pow(sin(th), 0.571), z))
		if r == 0:  # the face the dials sit on
			for s in segs:
				_tri(st, Vector3(cx, y0, z), ring[s], ring[s + 1], Vector3.BACK, Vector3.BACK, Vector3.BACK)
		else:
			for s in segs:
				var a: Vector3 = prev[s]
				var b: Vector3 = prev[s + 1]
				var c: Vector3 = ring[s + 1]
				var d: Vector3 = ring[s]
				var mid := (a + b + c + d) / 4.0
				_quad(st, a, b, c, d, Vector3((mid.x - cx) / hw, (mid.y - y0) / h, 0.0).normalized())
		prev = ring


## Box oriented along a segment (seat belts, levers).
static func _strap(st: SurfaceTool, a: Vector3, b: Vector3, w: float, t: float) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_box(st, (a + b) / 2.0, Vector3(w, (b - a).length(), t), Basis(x, y, z))


## Each car's own cabin (by body type). Colours: leather, insert (seat
## centres), stitch, ambient (light lines), trim (door cards and console),
## dash, strip (the dash trim strip: aluminium, wood, carbon...), carpet,
## liner (headliner), accent (cage, wheel marker). seats: "comfort" or
## "bucket". wheel: "round", "flat" (flat-bottomed) or "yoke" (flat top and
## bottom); spokes = spoke angles; hub = "box" or "round". screen: "wide",
## "tablet" (a tall floating tablet) or "retro" (a small radio); pods = small
## extra gauges on the dash top; two_tone = lower dash in the leather colour;
## cage = a roll hoop behind the seats. dials = [accent (rings, mph scale), numerals, needle]. vents: "rect", "round"
## or "strip"; strip_kind: the finish of the dash strip ("brushed", "carbon", "wood" or "paint"); bezel: "chrome" or "dark"
## dial rings. The dial faces and the screen's map are baked art (tools/make_cockpit_art.py), the rest is CabinParts.
## Imported cars keep the cabin style of the generated body they replaced.
const CABIN_ALIAS := {"kestrel": "hatch", "bruiser": "muscle", "copperhead": "fastback", "halcyon": "super", "static": "rcoupe", "marshal": "msedan", "lastexit": "hyper", "vanta": "sedan"}
const CABINS := {
	"hot_hatch": {"vents": "round", "strip_kind": "carbon", "leather": "#23262b", "insert": "#2f62b0", "stitch": "#5a9bff", "ambient": "#3d8bff", "strip": "#3b4047", "wheel": "flat", "screen": "tablet",
		"dials": ["#5a9bff", "#e6e6e6", "#ff4a2a"], "accent": "#5a9bff"},
	"sport_sedan": {"vents": "round", "strip_kind": "brushed", "leather": "#1b1b1d", "insert": "#2a2a2d", "stitch": "#d0202a", "ambient": "#ff3b30", "strip": "#8d939a", "wheel": "round", "marker": "#d0202a", "screen": "wide",
		"dials": ["#ff3b30", "#e6e6e6", "#ff3b30"], "seats": "bucket", "accent": "#d0202a"},
	"compact": {"vents": "round", "strip_kind": "paint", "leather": "#1c1c1e", "insert": "#d9a21b", "stitch": "#f5c52e", "ambient": "#f5c52e", "strip": "#d9a21b", "wheel": "flat", "marker": "#f5c52e", "screen": "wide",
		"dials": ["#f5c52e", "#f5c52e", "#ffffff"], "seats": "bucket", "accent": "#f5c52e"},
	"coupe": {"vents": "rect", "strip_kind": "brushed", "bezel": "chrome", "leather": "#8a6038", "insert": "#a67848", "stitch": "#e8d8b8", "ambient": "#ffe2b0", "strip": "#b9bfc5", "trim": "#4a382a", "carpet": "#2a221c", "wheel": "round", "spokes": [0.0, 3.14159], "hub": "round",
		"screen": "wide", "dials": ["#e8d8b8", "#e8d8b8", "#ff7a2a"], "two_tone": true, "liner": "#6a6258"},
	"hatch": {"vents": "rect", "strip_kind": "paint", "leather": "#4a4e55", "insert": "#6a7078", "stitch": "#2aa198", "ambient": "#2aa198", "strip": "#5a5f66", "trim": "#3a3d42", "dash": "#25272b", "wheel": "round", "spokes": [0.35, 2.79, 1.5708, 1.5708],
		"screen": "retro", "dials": ["#e6e6e6", "#e6e6e6", "#ff4a2a"], "liner": "#7a7c80"},
	"sedan": {"vents": "rect", "strip_kind": "wood", "bezel": "chrome", "leather": "#b8a488", "insert": "#c8b69a", "stitch": "#8a7458", "ambient": "#fff2d8", "strip": "#6b4a2e", "trim": "#8a7860", "carpet": "#3a3228", "wheel": "round", "spokes": [0.3, 2.84, 1.2, 1.94], "hub": "round",
		"screen": "wide", "dials": ["#fff2d8", "#fff2d8", "#ff4a2a"], "two_tone": true, "liner": "#a8a090"},
	"muscle": {"vents": "round", "strip_kind": "brushed", "bezel": "chrome", "leather": "#161616", "insert": "#1e1e1e", "stitch": "#e8e8e8", "ambient": "#ffb02e", "strip": "#c9ced3", "wheel": "round", "spokes": [0.0, 3.14159, 1.5708], "spoke_metal": true, "hub": "round", "thin_rim": true,
		"screen": "retro", "pods": 3, "dials": ["#e8e8e8", "#e8e8e8", "#ff3b2a"], "accent": "#e8e8e8"},
	"super": {"vents": "strip", "strip_kind": "carbon", "leather": "#d8dce2", "insert": "#aab8c8", "stitch": "#2ad0e8", "ambient": "#2ad0e8", "strip": "#1c1e22", "trim": "#2a2d32", "wheel": "flat", "marker": "#2ad0e8", "screen": "tablet",
		"dials": ["#2ad0e8", "#e6e6e6", "#2ad0e8"], "seats": "bucket", "liner": "#3a3c40", "accent": "#2ad0e8"},
	"fastback": {"vents": "round", "strip_kind": "brushed", "bezel": "chrome", "leather": "#6a3a1e", "insert": "#7c4826", "stitch": "#f08a2a", "ambient": "#f08a2a", "strip": "#3a3d42", "trim": "#2c2420", "wheel": "round", "spokes": [0.0, 3.14159, 1.5708], "spoke_metal": true, "hub": "round",
		"screen": "retro", "pods": 3, "dials": ["#f08a2a", "#e8e8e8", "#ff3b2a"], "accent": "#f08a2a"},
	"msedan": {"vents": "strip", "strip_kind": "carbon", "leather": "#17181b", "insert": "#22252b", "stitch": "#2f7fe8", "ambient": "#2f7fe8", "strip": "#1c1e22", "wheel": "flat", "marker": "#2f7fe8", "screen": "wide",
		"dials": ["#e6e6e6", "#e6e6e6", "#ff3b2a"], "seats": "bucket", "accent": "#2f7fe8"},
	"rcoupe": {"vents": "strip", "strip_kind": "paint", "leather": "#1a1b1e", "insert": "#1f8fe8", "stitch": "#1fa3ff", "ambient": "#1fa3ff", "strip": "#1fa3ff", "wheel": "flat", "marker": "#f3f5ef", "screen": "tablet", "pods": 1,
		"dials": ["#1fa3ff", "#f3f5ef", "#f3f5ef"], "seats": "bucket", "liner": "#2a2c30", "accent": "#1fa3ff"},
	"hyper": {"vents": "round", "strip_kind": "carbon", "leather": "#8e1420", "insert": "#1a1a1c", "stitch": "#e8c84a", "ambient": "#ff2a2a", "strip": "#1c1e22", "trim": "#1e1f22", "wheel": "yoke", "marker": "#e8c84a", "screen": "tablet",
		"dials": ["#ff2a2a", "#e8c84a", "#e8c84a"], "seats": "bucket", "cage": true, "liner": "#1e1f22", "accent": "#b0122a"},
}


## A swept tube along a closed loop in the wheel's plane: the steering-wheel
## rim. "flat" squares off the bottom, "yoke" the top as well.
static func _rim_mesh(kind: String, thin := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	var m := 8
	var rr := 0.012 if thin else 0.0165
	var path: Array[Vector3] = []
	for i in n:
		var th := TAU * i / n
		var p := Vector3(cos(th), 0, sin(th)) * 0.172
		if kind == "flat" or kind == "yoke":
			p.z = minf(p.z, 0.118)
		if kind == "yoke":
			p.z = maxf(p.z, -0.105)
		path.append(p)
	for i in n:
		var p0 := path[i]
		var p1 := path[(i + 1) % n]
		var t0 := (path[(i + 1) % n] - path[(i - 1 + n) % n]).normalized()
		var t1 := (path[(i + 2) % n] - path[i]).normalized()
		var b0 := t0.cross(Vector3.UP).normalized()
		var b1 := t1.cross(Vector3.UP).normalized()
		for j in m:
			var a0 := TAU * j / m
			var a1 := TAU * (j + 1) / m
			var n00 := b0 * cos(a0) + Vector3.UP * sin(a0)
			var n01 := b0 * cos(a1) + Vector3.UP * sin(a1)
			var n10 := b1 * cos(a0) + Vector3.UP * sin(a0)
			var n11 := b1 * cos(a1) + Vector3.UP * sin(a1)
			_tri(st, p0 + n00 * rr, p0 + n01 * rr, p1 + n11 * rr, n00, n01, n11)
			_tri(st, p0 + n00 * rr, p1 + n11 * rr, p1 + n10 * rr, n00, n11, n10)
	return st.commit()


## A full cabin for the player's car, built for the driver's-eye view. The roof,
## pillars and door tops are the body's own inner faces (see _inner_shell), so
## they sit exactly where the bodywork is. Everything else is laid out from the
## driver's eye so the road stays in view: the dash ends at the cowl's sight
## line, the instrument pod sits under that line and the wheel under the pod.
func build_interior() -> void:
	var pr: Dictionary = PROFILES.get(_shape_id, {})
	if pr.is_empty() or not pr.has("gh") or _steer_node:
		return
	if _cabin_mi:  # the simple see-through cabin is replaced by the real one
		_cabin_mi.queue_free()
		_cabin_mi = null
	var g: Array = pr.gh
	var w: float = shape.w
	var hb: float = w / 2.0 * g[6] - 0.03     # inner half-width of the cabin
	var yb: float = g[4]                       # belt line
	var yr: float = g[5]                       # roof
	var rear_top: float = pr.body[0][1]
	var floor_y: float = minf(0.3, rear_top - 0.3) + 0.08
	var eye := cockpit_eye()
	var ex := eye.x
	var ez := eye.z
	var dz: float = -(g[1] - 0.05)            # windscreen base
	var zr: float = -g[0]                     # rear of the cabin
	var shell := _shell(_shape_id)
	# the real roof (or glass) height overhead at (x, z), measured from the body mesh
	var roof_at := func(x: float, z: float) -> float:
		var t := _top_over(shell, x, -z, 0.05)
		return t if t < 90.0 else yr

	var S := {}
	var cab: Dictionary = CABINS.get(CABIN_ALIAS.get(_shape_id, _shape_id), {})
	var bucket: bool = cab.get("seats", "comfort") == "bucket"
	var scr: String = cab.get("screen", "wide")
	var keys := ["carpet", "trim", "dash", "pad", "leather", "insert", "chrome", "alu", "vent", "screen", "red", "stitch", "ambient", "map", "route", "accent"]
	for k in keys:
		S[k] = _new_st()

	# --- shell: floor, firewall, rear wall, door cards
	_quad(S.carpet, Vector3(-hb, floor_y, zr), Vector3(hb, floor_y, zr), Vector3(hb, floor_y, dz + 0.15), Vector3(-hb, floor_y, dz + 0.15), Vector3.UP)
	_quad(S.carpet, Vector3(-hb, floor_y, dz + 0.15), Vector3(hb, floor_y, dz + 0.15), Vector3(hb, yb - 0.2, dz + 0.15), Vector3(-hb, yb - 0.2, dz + 0.15), Vector3.BACK)
	_quad(S.trim, Vector3(-hb, floor_y, zr - 0.01), Vector3(hb, floor_y, zr - 0.01), Vector3(hb, yb + 0.02, zr - 0.01), Vector3(-hb, yb + 0.02, zr - 0.01), Vector3.FORWARD)
	for sd in [-1.0, 1.0]:
		var x: float = sd * hb
		var inward := Vector3(-sd, 0, 0)
		_quad(S.trim, Vector3(x, floor_y, zr), Vector3(x, floor_y, dz + 0.1), Vector3(x, yb + 0.02, dz + 0.1), Vector3(x, yb + 0.02, zr), inward)
		_box(S.leather, Vector3(x - sd * 0.02, yb - 0.02, (zr + dz) / 2.0), Vector3(0.07, 0.09, absf(dz - zr)))      # upper door trim
		_box(S.leather, Vector3(x - sd * 0.05, yb - 0.27, ez + 0.05), Vector3(0.1, 0.05, 0.6))                      # armrest
		_box(S.dash, Vector3(x - sd * 0.075, yb - 0.24, ez - 0.12), Vector3(0.05, 0.02, 0.16))                      # window switches
		_box(S.chrome, Vector3(x - sd * 0.02, yb - 0.12, ez - 0.32), Vector3(0.03, 0.04, 0.12))                     # door handle
		_box(S.alu, Vector3(x - sd * 0.005, yb - 0.17, (ez + dz) / 2.0 + 0.2), Vector3(0.01, 0.015, absf(dz - ez) * 0.9))  # trim line
		_cyl(S.vent, Vector3(x - sd * 0.008, floor_y + 0.2, ez - 0.45), 0.09, 0.012, Vector3.RIGHT, 14)                  # speaker

	# --- dashboard
	var D := ez - dz                               # eye to the windscreen base
	var ypad := yb - 0.035                         # top of the dash where it meets the windscreen
	var zf := maxf(ez - 0.72, dz + 0.18)           # the instrument panel's face, towards the driver
	var yd := ypad - 0.14                          # level of the panel's fittings
	var hd: float = minf(hb, float(pr.get("dash_hw", hb)))
	var pad_y := func(z: float) -> float:
		return ypad - 0.07 * clampf((z - dz) / (zf - dz), 0.0, 1.0)
	var lower: SurfaceTool = S.leather if cab.get("two_tone", false) else S.dash
	# a soft-touch pad on top, sloping down towards the driver, over the dash body
	_prism(S.pad, [Vector2(dz, ypad), Vector2(zf, ypad - 0.07), Vector2(zf, ypad - 0.115), Vector2(dz, ypad - 0.045)], -hd, hd)
	_prism(S.dash, [Vector2(dz, ypad - 0.045), Vector2(zf, ypad - 0.115), Vector2(zf, ypad - 0.46), Vector2(dz, ypad - 0.46)], -hd, hd)
	var zs: float = dz + (zf - dz) * 0.9
	_box(S.stitch, Vector3(0, pad_y.call(zs) + 0.003, zs), Vector3(hd * 2.0 - 0.06, 0.004, 0.006))
	_box(lower, Vector3(0, yd - 0.3, zf - 0.2), Vector3(hb * 2.0, 0.18, 0.4))                  # lower dash
	CabinParts.trim_strip(_body, String(cab.get("strip_kind", "paint")), Color(String(cab.get("strip", "#8d939a"))), Vector3(0, yd - 0.11, zf + 0.005), Vector3(hb * 2.0 - 0.1, 0.025, 0.012))      # trim strip
	_box(S.ambient, Vector3(0, yd - 0.126, zf + 0.007), Vector3(hb * 2.0 - 0.12, 0.004, 0.006))  # ambient light line
	for sd in [-1.0, 1.0]:
		_box(S.ambient, Vector3(sd * (hb - 0.062), yd - 0.07, (zr + dz) / 2.0), Vector3(0.004, 0.004, absf(dz - zr) * 0.9))
	# infotainment: a wide screen in the dash, a tall floating tablet, or a small radio
	var sw := 0.25
	var shh := 0.145
	var sy := yd - 0.13
	var sz := zf + 0.021
	if scr == "tablet":
		sw = 0.17
		shh = 0.25
		sy = yd - 0.085
		sz = zf + 0.032
		_box(S.dash, Vector3(0, sy, sz - 0.008), Vector3(sw + 0.03, shh + 0.03, 0.014))  # the tablet's body, proud of the dash
	elif scr == "retro":
		sw = 0.17
		shh = 0.06
		sy = yd - 0.12
		for sd in [-1.0, 1.0]:  # tuning and volume knobs
			_cyl(S.chrome, Vector3(sd * 0.115, sy, sz + 0.012), 0.017, 0.024, Vector3.BACK, 12)
		for k in 5:  # preset buttons
			_box(S.chrome, Vector3(-0.064 + k * 0.032, sy - 0.05, sz + 0.004), Vector3(0.024, 0.014, 0.008))
	_box(S.trim, Vector3(-ex, yd - 0.3, zf - 0.04), Vector3(0.46, 0.16, 0.02))               # glovebox lid
	_box(S.chrome, Vector3(-ex + 0.17, yd - 0.25, zf - 0.025), Vector3(0.06, 0.015, 0.015))  # glovebox latch
	for sd in [-1.0, 1.0]:
		_box(S.dash, Vector3(sd * 0.36, yd - 0.32, zf - 0.02), Vector3(0.34, 0.14, 0.08))      # knee bolsters
	var vent_kind: String = cab.get("vents", "rect")
	if vent_kind == "strip":  # one slim vent right across the dash
		CabinParts.vent_strip(S, -(hb - 0.12), hb - 0.12, yd - 0.015, zf + 0.005)
	else:
		for vx in [-0.1, 0.1, -(hb - 0.14), hb - 0.14]:
			var c := Vector3(vx, yd - 0.02, zf + 0.005)
			if vent_kind == "round":
				CabinParts.vent_round(S, c, 0.04)
			else:
				CabinParts.vent_rect(S, c, 0.16, 0.075)
	CabinParts.defrost(S, hd - 0.12, pad_y.call(dz + 0.075) + 0.001, dz + 0.075)  # the demister slot against the windscreen
	# centre stack with screen, climate knobs and hazard switch
	_box(S.dash, Vector3(0, yd - 0.27, zf - 0.06), Vector3(0.32, 0.44, 0.16))
	_box(S.chrome, Vector3(0, sy, sz), Vector3(sw + 0.02, shh + 0.02, 0.004))
	CabinParts.screen(_body, Vector3(0, sy, sz + 0.0056), Vector2(sw, shh), _shape_id)  # the lit glass: a map, and the card the radio text prints on
	var knob_y := yd - 0.33 if scr != "tablet" else yd - 0.36
	for k in 3:
		CabinParts.knob(S, Vector3(-0.08 + k * 0.08, knob_y, zf + 0.025), 0.026)
	CabinParts.button_row(S, 0.0, knob_y - 0.065, zf + 0.022, 5, 0.052)
	_box(S.red, Vector3(0, knob_y + 0.075 if scr != "tablet" else knob_y + 0.05, zf + 0.024), Vector3(0.04, 0.025, 0.01))
	# extra gauges in small pods on the dash top (oil, volts, boost), kept low
	var pods: int = cab.get("pods", 0)
	for k in pods:
		var px := (k - (pods - 1) / 2.0) * 0.07
		var pz := zf - 0.1
		var pc := Vector3(px, pad_y.call(pz) + 0.004, pz)
		_cyl(S.dash, pc, 0.026, 0.05, Vector3.BACK, 14)
		_cyl(S.chrome, pc + Vector3(0, 0, 0.026), 0.025, 0.004, Vector3.BACK, 14)
		_cyl(S.vent, pc + Vector3(0, 0, 0.028), 0.021, 0.004, Vector3.BACK, 14)
		_box(S.red, pc + Vector3(0.005, 0.005, 0.032), Vector3(0.003, 0.018, 0.002), Basis(Vector3.BACK, -0.6 + k * 0.5))

	# --- the instrument pod: an arch over the dials, never rising above the sight
	# line from the eye over the cowl, so it cannot hide the road or the bonnet
	var tan_c := maxf((eye.y - ypad) / D, 0.06)
	var sight := func(z: float) -> float:
		return eye.y - tan_c * (ez - z) - 0.014
	var pod_y0: float = pad_y.call(zf) - 0.03
	_pod(S.dash, ex, 0.25, zf, zf - 0.3, pod_y0, sight.call(zf), sight.call(zf - 0.3))
	var y_dial: float = minf(eye.y - 0.72 * 0.33, float(sight.call(zf)) - 0.052 - 0.012)  # about 18 degrees below the eye
	var dial_tilt := atan2(eye.y - y_dial, ez - zf)   # the dials face the driver's eye
	# the steering column, rising from the dash to the wheel hub
	var hub := Vector3(ex, eye.y - 0.30 - (0.05 if cab.get("wheel", "round") == "yoke" else 0.0), ez - 0.55)  # (a yoke sits lower, so its top bar does not hide the speed readout)
	_strap(S.dash, Vector3(ex, ypad - 0.2, zf + 0.01), hub + Vector3(0, -0.04, -0.03), 0.1, 0.1)
	for sd in [-1.0, 1.0]:
		_strap(S.dash, hub + Vector3(sd * 0.05, -0.09, 0.0), hub + Vector3(sd * 0.17, -0.07, 0.03), 0.018, 0.018)  # stalks
	for k in 3:
		_box(S.alu, Vector3(ex - 0.12 + k * 0.1, floor_y + 0.12, ez - 0.7), Vector3(0.07, 0.1, 0.02), Basis(Vector3.RIGHT, -0.5))

	# --- centre console
	var cz0: float = zf + 0.02
	var cz1: float = ez + 0.5
	_box(S.trim, Vector3(0, (floor_y + yb - 0.42) / 2.0, (cz0 + cz1) / 2.0), Vector3(0.24, yb - 0.42 - floor_y, absf(cz1 - cz0)))
	_box(S.alu, Vector3(0, yb - 0.415, (cz0 + cz1) / 2.0), Vector3(0.25, 0.01, absf(cz1 - cz0)))
	_box(S.leather, Vector3(0, yb - 0.36, ez + 0.28), Vector3(0.22, 0.09, 0.42))  # armrest lid
	for k in 2:
		_cyl(S.vent, Vector3(-0.045 + k * 0.09, yb - 0.405, cz0 + 0.14), 0.035, 0.01, Vector3.UP, 12)  # cup holders
	_box(S.leather, Vector3(0, yb - 0.39, ez - 0.32), Vector3(0.13, 0.04, 0.16))  # shifter boot
	_strap(S.dash, Vector3(0.0, yb - 0.4, ez - 0.02), Vector3(0.0, yb - 0.3, ez + 0.16), 0.045, 0.06)  # handbrake
	_box(S.chrome, Vector3(0.0, yb - 0.27, ez + 0.2), Vector3(0.02, 0.02, 0.03))

	# --- front seats
	var cushion_top: float = floor_y + 0.27
	for sx in [ex, -ex]:
		_box(S.dash, Vector3(sx, floor_y + 0.06, ez + 0.05), Vector3(0.4, 0.06, 0.45))                      # rails and base
		_box(S.leather, Vector3(sx, cushion_top - 0.07, ez + 0.03), Vector3(0.46, 0.14, 0.5))
		_box(S.insert, Vector3(sx, cushion_top + 0.005, ez + 0.03), Vector3(0.28, 0.01, 0.44))               # insert
		for q in 5:  # quilting
			_box(S.stitch, Vector3(sx, cushion_top + 0.011, ez - 0.17 + q * 0.1), Vector3(0.28, 0.002, 0.006))
		for sd in [-1.0, 1.0]:
			_box(S.leather, Vector3(sx + sd * 0.21, cushion_top - 0.01 + (0.025 if bucket else 0.0), ez + 0.03),
				Vector3(0.07, 0.17 if bucket else 0.12, 0.48))  # cushion bolster (deeper on bucket seats)
		var back := Basis(Vector3.RIGHT, 0.2)
		# fit the seat under the roof or rear window: the backrest and headrest shrink on low cars
		var room: float = minf(yr - 0.08, float(roof_at.call(sx, ez + 0.46)) - 0.05) - cushion_top
		var hh: float = clampf(room * 0.27, 0.1, 0.19)
		var bh: float = clampf(room - hh - 0.08, 0.3, 0.62)
		var bc := Vector3(sx, cushion_top + bh / 2.0 - 0.01, ez + 0.3)
		_box(S.leather, bc, Vector3(0.48, bh, 0.12), back)
		_box(S.insert, bc + back.z * -0.065, Vector3(0.28, bh - 0.12, 0.01), back)
		for q in 6:
			_box(S.stitch, bc + back.z * -0.071 + back.y * (-bh / 2.0 + 0.08 + q * (bh - 0.16) / 5.0), Vector3(0.28, 0.006, 0.002), back)
		for sd in [-1.0, 1.0]:
			_box(S.leather, bc + back.x * sd * 0.22 + back.z * (-0.075 if bucket else -0.05), Vector3(0.07, bh - 0.06, 0.15 if bucket else 0.1), back)  # back bolster
		var top: Vector3 = bc + back.y * (bh / 2.0)
		if bucket:
			# one-piece shell: the headrest grows out of the backrest, with harness slots and shoulder wings
			_box(S.leather, top + back.y * (hh / 2.0 + 0.01), Vector3(0.3, hh + 0.04, 0.11), back)
			_box(S.insert, top + back.y * (hh / 2.0 + 0.01) + back.z * -0.058, Vector3(0.18, hh - 0.03, 0.006), back)
			for sd in [-1.0, 1.0]:
				_box(S.vent, top + back.y * -0.05 + back.x * sd * 0.085 + back.z * -0.068, Vector3(0.06, 0.03, 0.012), back)
				_box(S.leather, top + back.y * -0.1 + back.x * sd * 0.25 + back.z * -0.06, Vector3(0.05, 0.16, 0.13), back)
		else:
			for sd in [-1.0, 1.0]:
				_box(S.chrome, top + back.y * 0.035 + Vector3(sd * 0.07, 0, 0), Vector3(0.012, 0.07, 0.012), back)
			_box(S.leather, top + back.y * (0.06 + hh / 2.0), Vector3(0.26, hh, 0.1), back)                       # headrest
	# seat belt across the (empty) driver seat, from the B-pillar to the buckle
	var belt_top := minf(yb + 0.32, float(roof_at.call(hb - 0.08, ez + 0.4)) - 0.1)  # anchored below the roof on low cars
	_strap(S.dash, Vector3(signf(ex) * (hb - 0.08), belt_top, ez + 0.4), Vector3(ex - signf(ex) * 0.22, cushion_top + 0.05, ez + 0.1), 0.045, 0.006)

	# --- rear bench, tucked under the rear window (the cabin runs from zr forward to -z)
	var glass_z := func(h: float) -> float:
		return -(g[0] + (g[2] - g[0]) * clampf((h - yb) / (yr - yb), 0.0, 1.0))
	var rb := Basis(Vector3.RIGHT, 0.22)
	var back_top: float = cushion_top + 0.46
	var back_z: float = minf(zr - 0.16, glass_z.call(back_top + 0.15) - 0.13)
	var cush_z: float = back_z - 0.3
	if cush_z - 0.2 > ez + 0.27:  # only if there is legroom behind the front seats
		_box(S.leather, Vector3(0, cushion_top - 0.1, cush_z), Vector3(hb * 2.0 - 0.06, 0.14, 0.4))
		_box(S.insert, Vector3(0, cushion_top - 0.025, cush_z), Vector3(hb * 2.0 - 0.3, 0.01, 0.34))
		_box(S.leather, Vector3(0, cushion_top + 0.2, back_z), Vector3(hb * 2.0 - 0.06, 0.46, 0.12), rb)
		for k in 3:
			var hx: float = (k - 1) * hb * 0.62
			_box(S.leather, Vector3(hx, back_top + 0.07, back_z + 0.06), Vector3(0.22, 0.12, 0.09), rb)
		# parcel shelf behind the bench, at the base of the rear window
		var shelf_len: float = absf(back_z - zr) - 0.02
		if shelf_len > 0.06:
			_box(S.trim, Vector3(0, yb - 0.01, (zr + back_z) / 2.0 + 0.01), Vector3(hb * 2.0, 0.03, shelf_len))

	if cab.get("cage", false):
		# roll hoop behind the seats, braced back to the rear bulkhead
		var hz: float = ez + 0.62
		var hx: float = hb - 0.1
		var htop: float = minf(yr - 0.06, float(roof_at.call(hx, hz)) - 0.07)
		for sd in [-1.0, 1.0]:
			_strap(S.accent, Vector3(sd * hx, floor_y, hz), Vector3(sd * (hx - 0.06), htop, hz), 0.045, 0.045)
			_strap(S.accent, Vector3(sd * (hx - 0.06), htop - 0.02, hz), Vector3(sd * (hx - 0.1), yb - 0.1, minf(zr - 0.06, hz + 0.5)), 0.04, 0.04)
		_box(S.accent, Vector3(0, htop, hz), Vector3((hx - 0.06) * 2.0, 0.045, 0.045))
		_strap(S.accent, Vector3(-(hx - 0.08), floor_y + 0.25, hz), Vector3(hx - 0.08, htop - 0.05, hz), 0.035, 0.035)

	var interior := ArrayMesh.new()
	var cc := func(key: String, def: String) -> Color: return Color(String(cab.get(key, def)))
	var strip_col: Color = cc.call("strip", "#8d939a")
	var mats := {
		"carpet": mat(cc.call("carpet", "#232427"), 0.0, 1.0), "trim": mat(cc.call("trim", "#34363a"), 0.0, 0.62),
		"dash": mat(cc.call("dash", "#1d1f23"), 0.0, 0.5), "pad": mat(cc.call("dash", "#1d1f23").lightened(0.06), 0.0, 0.46),
		"leather": mat(cc.call("leather", "#2b2624"), 0.0, 0.55), "insert": mat(cc.call("insert", "#3a3a3d"), 0.0, 0.85),
		"chrome": mat(Color("#c9ced3"), 0.0, 0.3, 0.35),
		# the dash strip: bright metal, or dark gloss for wood and carbon
		"alu": mat(strip_col, 0.0, 0.3 if strip_col.get_luminance() < 0.2 else 0.45, 0.25), "vent": mat(Color("#0d0e10"), 0.0, 0.8),
		"screen": mat(Color("#20425e"), 1.2, 0.2), "red": mat(Color("#d02a1a"), 1.0), "stitch": mat(cc.call("stitch", "#b3462c"), 0.0, 0.6),
		"ambient": mat(cc.call("ambient", "#ff7a3a"), 1.4), "map": mat(Color("#0c1a26"), 0.6), "route": mat(Color("#f5b52e"), 2.5),
		"accent": mat(cc.call("accent", "#b5322a"), 0.0, 0.4, 0.2),
	}
	var order: Array = []
	for k in keys:
		var arrays: Array = (S[k] as SurfaceTool).commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		# squash anything that would cross the real roof or sides of the body
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vi in vs.size():
			vs[vi] = _inside_shell(vs[vi], shell)
		arrays[Mesh.ARRAY_VERTEX] = vs
		interior.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		order.append(k)
	var mi := MeshInstance3D.new()
	mi.mesh = interior
	for i in order.size():
		mi.set_surface_override_material(i, mats[order[i]])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)

	# the roof, pillars and door tops, seen from the driver's seat
	var liner := Color(String(cab.get("liner", "#5c5e63")))
	_inner = _inner_shell(liner)
	if _inner:
		_inner.visible = false
		_body.add_child(_inner)

	# soft bounce light inside the cabin, as daylight would reflect off the seats and dash
	var fill := OmniLight3D.new()
	fill.light_color = Color("#ffeedd")
	fill.light_energy = 0.7
	fill.omni_range = 1.9
	fill.omni_attenuation = 1.4
	fill.shadow_enabled = false
	fill.light_specular = 0.2
	fill.position = Vector3(0, yr - 0.25, ez - 0.25)
	_body.add_child(fill)

	# rear-view mirror, hung from the top of the windscreen and turned towards the driver
	var md: float = float(pr.get("mirror_d", g[3] - 0.08))
	var mt := _top_over(shell, 0.0, md, 0.03)
	var m_top: float = mt if mt < 90.0 else yr
	var mpos := Vector3(0, m_top - 0.105, -md)
	var mirror := Node3D.new()
	mirror.position = mpos
	mirror.basis = Basis.from_euler(Vector3(atan2(mpos.y - eye.y, absf(ez - mpos.z)), atan2(ex - mpos.x, ez - mpos.z) * 0.8, 0.0))
	_body.add_child(mirror)
	var housing := MeshInstance3D.new()
	housing.mesh = box_mesh(Vector3(0.2, 0.055, 0.028))
	housing.material_override = mats.dash
	mirror.add_child(housing)
	var glassm := MeshInstance3D.new()
	glassm.mesh = box_mesh(Vector3(0.185, 0.043, 0.004))
	glassm.material_override = _mirror_glass()
	glassm.position = Vector3(0, 0, 0.0145)
	mirror.add_child(glassm)
	var stem := MeshInstance3D.new()
	stem.mesh = box_mesh(Vector3(0.02, 0.06, 0.02))
	stem.material_override = mats.dash
	stem.position = mpos + Vector3(0, 0.05, -0.012)  # joins the mirror to the roof above it
	_body.add_child(stem)

	# instrument cluster: the baked panel (numbered dials, redline, warning lamps) with real needles standing off it,
	# and the gear and speed readout in the window between the dials
	var dial_cols: Array = cab.get("dials", ["#f5b52e", "#e6e6e6", "#ff4a2a"])
	var cluster_node := CabinParts.cluster(_body, Vector3(ex, y_dial, zf + 0.012), dial_tilt, _shape_id, cab, _needles, _needle_shadows)
	var readout := Color(String(dial_cols[0])).lightened(0.3)
	_display = Label3D.new()
	_display.font_size = 64
	_display.pixel_size = 0.00033
	_display.modulate = Color(String(dial_cols[1])).lerp(Color.WHITE, 0.35)
	_display.outline_size = 0
	_display.position = Vector3(0.0, 0.0, 0.0035)
	_display.text = "0"
	cluster_node.add_child(_display)
	_display_gear = Label3D.new()
	_display_gear.font_size = 30
	_display_gear.pixel_size = 0.00033
	_display_gear.modulate = readout
	_display_gear.outline_size = 0
	_display_gear.position = Vector3(0.0, 0.0158, 0.0035)
	cluster_node.add_child(_display_gear)
	_display_unit = Label3D.new()
	_display_unit.font_size = 30
	_display_unit.pixel_size = 0.00033
	_display_unit.modulate = readout
	_display_unit.outline_size = 0
	_display_unit.position = Vector3(0.0, -0.0185, 0.0035)
	cluster_node.add_child(_display_unit)
	_screen = Label3D.new()
	_screen.font_size = 30
	_screen.pixel_size = 0.0008
	_screen.modulate = Color("#cfe8ff")
	_screen.outline_size = 0
	_screen.position = Vector3(0, sy + shh * 0.281, sz + 0.0085)  # on the card at the top of the screen's art
	_screen.font_size = 26
	_screen.pixel_size = 0.0006
	if scr == "tablet":
		_screen.position.y = sy + shh * 0.311
	elif scr == "retro":
		_screen.pixel_size = 0.00042
		_screen.modulate = Color("#ffd49a")
		_screen.position.y = sy + 0.006
	_body.add_child(_screen)

	# steering wheel: tilted column with a spinning rim, spokes, airbag hub and paddles
	var tilt := Node3D.new()
	tilt.position = hub
	tilt.rotation.x = 1.15  # wheel face points back at the driver and up
	_body.add_child(tilt)
	_steer_node = Node3D.new()
	tilt.add_child(_steer_node)
	var wheel_kind: String = cab.get("wheel", "round")
	var spoke_mat: Material = mat(Color("#8a9098"), 0.0, 0.34, 0.9) if cab.get("spoke_metal", false) else mats.dash
	CabinParts.wheel(_steer_node, cab, mats.leather, spoke_mat, mats.chrome, mats.vent, mats.stitch)

	# the driver: gloved hands on the rim at a quarter to three, arms that follow the wheel
	var glove := mat(Color("#2b2d31"), 0.0, 0.5)
	var sleeve := mat(Color("#2a2f38"), 0.0, 0.85)
	for sd in [-1.0, 1.0]:
		var hand := MeshInstance3D.new()
		hand.mesh = CabinParts.hand_mesh(sd)
		hand.material_override = glove
		hand.position = Vector3(sd * 0.168, 0.01, -0.045)
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_steer_node.add_child(hand)
		_hands.append(hand)
		var arm := []
		for k in 2:
			var seg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.022 if k == 0 else 0.027
			cyl.bottom_radius = 0.025 if k == 0 else 0.03
			cyl.height = 1.0
			cyl.radial_segments = 10
			seg.mesh = cyl
			seg.material_override = sleeve
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body.add_child(seg)
			arm.append(seg)
		_arms.append(arm)
	_shoulders = [Vector3(ex - 0.19, eye.y - 0.27, ez + 0.12), Vector3(ex + 0.19, eye.y - 0.27, ez + 0.12)]
	_update_arms()

	# gear lever on an H-pattern gate
	_lever = Node3D.new()
	_lever_base = Vector3(0, yb - 0.37, ez - 0.32)
	_lever.position = _lever_base
	_body.add_child(_lever)
	var rod := MeshInstance3D.new()
	rod.mesh = box_mesh(Vector3(0.018, 0.14, 0.018))
	rod.position = Vector3(0, 0.07, 0)
	rod.material_override = mats.chrome
	_lever.add_child(rod)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.03
	km.height = 0.06
	knob.mesh = km
	knob.position = Vector3(0, 0.15, 0)
	knob.material_override = mats.leather
	_lever.add_child(knob)


var _inner: MeshInstance3D
static var _inner_data := {}
static var _inner_shader: Shader


## Show the roof, pillars and door tops from inside: only in the cockpit view.
func set_cabin_view(on: bool) -> void:
	if _inner and _inner.visible != on:
		_inner.visible = on


## The body's own inner faces around the cabin, drawn from the driver's side:
## the back faces of the roof, pillars and door panels, in headliner and trim.
## Because they are the real bodywork they sit exactly where the car has them,
## whatever the model, so nothing can poke through the roof or leave a gap.
## tools/make_inner.py prepares the mesh and a smooth mask for each of the three
## openings the driver looks out of (windscreen and the two front side windows),
## so the shell is cut open along clean curves, not along the ragged edge of the
## model's glass.
func _inner_shell(liner: Color) -> MeshInstance3D:
	if not _inner_data.has(_shape_id):
		_inner_data[_shape_id] = _inner_load(_shape_id)
	var data: Dictionary = _inner_data[_shape_id]
	if data.is_empty():
		return null
	if _inner_shader == null:
		_inner_shader = Shader.new()
		_inner_shader.code = """shader_type spatial;
render_mode cull_front, unshaded;
uniform vec3 roof : source_color = vec3(0.25);
uniform vec3 wall : source_color = vec3(0.12);
uniform float dim = 1.0;
uniform vec3 wc[3];
uniform vec3 wn[3];
uniform vec3 wu[3];
uniform vec3 wv[3];
uniform vec4 wr[3];
uniform sampler2D mask0 : filter_linear, repeat_disable;
uniform sampler2D mask1 : filter_linear, repeat_disable;
uniform sampler2D mask2 : filter_linear, repeat_disable;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float opening(sampler2D m, vec3 p, int i) {
	vec3 q = p - wc[i];
	if (abs(dot(q, wn[i])) > 0.1) { return 0.0; }
	vec2 t = vec2((dot(q, wu[i]) - wr[i].x) * wr[i].z, (dot(q, wv[i]) - wr[i].y) * wr[i].w);
	if (t.x < 0.0 || t.y < 0.0 || t.x > 1.0 || t.y > 1.0) { return 0.0; }
	return textureLod(m, t, 0.0).r;
}
void fragment() {
	float w = max(opening(mask0, lp, 0), max(opening(mask1, lp, 1), opening(mask2, lp, 2)));
	if (w > 0.5) { discard; }                               // a window opening
	float seal = 1.0 - 0.5 * smoothstep(0.04, 0.5, w);      // dark where the glass meets the trim: a seal in shadow
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));  // the face's own normal
	float d = -abs(dot(fn, up));                            // about -1 on the roof, 0 on the pillars and doors
	vec3 base = mix(wall, roof, 1.0 - smoothstep(-0.75, -0.25, d));
	float lit = 0.8 + 0.25 * (1.0 - smoothstep(-3.2, -0.8, lp.z));  // brighter towards the windscreen
	lit *= 0.82 + 0.18 * smoothstep(0.7, 1.15, lp.y);       // darker down by the door sills
	ALBEDO = pow(base * lit, vec3(0.72)) * dim * seal;      // lifted a little (the tone mapping crushes dark trim to black), dimmed at night
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = _inner_shader
	sm.set_shader_parameter("roof", liner)
	sm.set_shader_parameter("wall", liner.darkened(0.45))
	sm.set_shader_parameter("dim", lerpf(1.0, 0.2, night))
	_mats["inner|%s" % _shape_id] = sm  # set_night dims it with the daylight
	var wc := PackedVector3Array()
	var wn := PackedVector3Array()
	var wu := PackedVector3Array()
	var wv := PackedVector3Array()
	var wr := PackedVector4Array()
	for k in 3:
		var w = data.win[k]
		if w == null:
			wc.append(Vector3.ZERO)
			wn.append(Vector3.ZERO)
			wu.append(Vector3.ZERO)
			wv.append(Vector3.ZERO)
			wr.append(Vector4.ZERO)
			sm.set_shader_parameter("mask%d" % k, _blank_mask())
		else:
			wc.append(w.c)
			wn.append(w.n)
			wu.append(w.u)
			wv.append(w.v)
			wr.append(w.r)
			sm.set_shader_parameter("mask%d" % k, w.tex)
	sm.set_shader_parameter("wc", wc)
	sm.set_shader_parameter("wn", wn)
	sm.set_shader_parameter("wu", wu)
	sm.set_shader_parameter("wv", wv)
	sm.set_shader_parameter("wr", wr)
	var mi := MeshInstance3D.new()
	mi.mesh = data.mesh
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _mirror_mat: StandardMaterial3D


## The interior mirror's glass: pale sky over a dark road, with the horizon between.
static func _mirror_glass() -> Material:
	if _mirror_mat == null:
		var img := Image.create(8, 24, false, Image.FORMAT_RGB8)
		for y in 24:
			var t := float(y) / 23.0
			var c := Color("#8fa0b0").lerp(Color("#b4bec6"), t / 0.5) if t < 0.5 else Color("#4a4e54").lerp(Color("#2a2d32"), (t - 0.5) / 0.5)
			if absf(t - 0.5) < 0.03:
				c = Color("#8e979c")
			for x in 8:
				img.set_pixel(x, y, c)
		_mirror_mat = StandardMaterial3D.new()
		_mirror_mat.albedo_texture = ImageTexture.create_from_image(img)
		_mirror_mat.albedo_color = Color.WHITE.lerp(Color(0.22, 0.22, 0.25), night)
		_mirror_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _mirror_mat


static var _blank: ImageTexture


static func _blank_mask() -> ImageTexture:
	if _blank == null:
		_blank = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_R8))
	return _blank


## Loads a car's prepared inner shell (assets/models/inner/NAME.inner): its mesh
## and the three window masks. Empty if the file is missing.
static func _inner_load(id: String) -> Dictionary:
	var path := "res://assets/models/inner/%s.inner" % String(PROFILES[id].mesh).get_file().get_basename()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("inner shell missing: %s" % path)
		return {}
	var nv := f.get_32()
	var ni := f.get_32()
	var pf := f.get_buffer(nv * 12).to_float32_array()
	var P := PackedVector3Array()
	P.resize(nv)
	for i in nv:
		P[i] = Vector3(pf[i * 3], pf[i * 3 + 1], pf[i * 3 + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = P
	arrays[Mesh.ARRAY_INDEX] = f.get_buffer(ni * 4).to_int32_array()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var wins: Array = []
	for k in 3:
		if f.get_32() == 0:
			wins.append(null)
			continue
		var v: PackedFloat32Array = PackedFloat32Array()
		for j in 16:
			v.append(f.get_float())
		var w := f.get_16()
		var h := f.get_16()
		var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, f.get_buffer(w * h))
		wins.append({"c": Vector3(v[0], v[1], v[2]), "n": Vector3(v[3], v[4], v[5]), "u": Vector3(v[6], v[7], v[8]), "v": Vector3(v[9], v[10], v[11]),
			"r": Vector4(v[12], v[13], 1.0 / v[14], 1.0 / v[15]), "tex": ImageTexture.create_from_image(img)})
	return {"mesh": m, "win": wins}


## speed and rpm as 0..1 fractions of full scale.
func set_gauges(speed_frac: float, rpm_frac: float) -> void:
	if _needles.size() < 2:
		return
	var a0 := lerpf(2.2, -2.2, clampf(speed_frac, 0.0, 1.0))
	var a1 := lerpf(2.2, -2.2, clampf(rpm_frac, 0.0, 1.0))
	_needles[0].rotation.z = a0
	_needles[1].rotation.z = a1
	if _needle_shadows.size() >= 2:
		_needle_shadows[0].rotation.z = a0
		_needle_shadows[1].rotation.z = a1


## Steering wheel angle in radians (positive turns right).
func set_steer(angle: float) -> void:
	if _steer_node:
		_steer_node.rotation.y = -angle
		_update_arms()


## Upper arm from the shoulder to an elbow below and outside, forearm to the glove.
func _update_arms() -> void:
	for i in _hands.size():
		var hand: Vector3 = _body.to_local(_hands[i].global_position)
		var sh: Vector3 = _shoulders[i]
		var sd := -1.0 if i == 0 else 1.0
		var elbow: Vector3 = sh.lerp(hand, 0.52) + Vector3(sd * 0.07, -0.13, 0.02)
		_segment(_arms[i][1], sh, elbow)
		_segment(_arms[i][0], elbow, hand)


func _segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * d.length(), z), (a + b) / 2.0)


var _bar_l: MeshInstance3D
var _bar_r: MeshInstance3D


## Police light bar on the roof (roof_y: roof height).
func add_lightbar(roof_y: float) -> void:
	var base := MeshInstance3D.new()
	base.mesh = box_mesh(Vector3(1.1, 0.08, 0.26))
	base.material_override = mat(Color("#1b1d21"), 0.0, 0.5)
	var z: float = -shape.l * 0.5 + 0.15
	base.position = Vector3(0, roof_y + 0.08, z)
	_body.add_child(base)
	_bar_l = MeshInstance3D.new()
	_bar_l.mesh = box_mesh(Vector3(0.5, 0.09, 0.22))
	_bar_l.position = Vector3(-0.28, roof_y + 0.16, z)
	_body.add_child(_bar_l)
	_bar_r = MeshInstance3D.new()
	_bar_r.mesh = box_mesh(Vector3(0.5, 0.09, 0.22))
	_bar_r.position = Vector3(0.28, roof_y + 0.16, z)
	_body.add_child(_bar_r)
	flash_lightbar(0.0)


## Alternating red and blue flashes.
func flash_lightbar(t: float) -> void:
	if _bar_l == null:
		return
	var phase := int(t * 6.0) % 2 == 0
	_bar_l.material_override = mat(Color("#ff2a2a"), 6.0 if phase else 0.4)
	_bar_r.material_override = mat(Color("#2a6bff"), 0.4 if phase else 6.0)


## Invulnerability glow: a soft amber halo pulsing on the road under the car.
func set_ghost(on: bool, t: float) -> void:
	if not on:
		if _halo:
			_halo.visible = false
		return
	if _halo == null:
		_shadow()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.6))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.albedo_texture = tex
		_halo_mat.albedo_color = Color(1.0, 0.72, 0.2, 0.0)
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_halo = MeshInstance3D.new()
		_halo.mesh = _shadow_mesh
		_halo.material_override = _halo_mat
		_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_halo.scale = Vector3(shape.w + 1.8, 1.0, shape.l + 2.2)
		_halo.position = Vector3(0, 0.03, -shape.l / 2.0)
		add_child(_halo)
	_halo.visible = true
	_halo_mat.albedo_color = Color(1.0, 0.72, 0.2, 0.55 + 0.35 * sin(t * 7.0))


## Shows a scoring or crash message on the infotainment screen for a moment.
func show_message(text: String, kind := "") -> void:
	if _screen == null:
		return
	if _msg == null:
		_msg = Label3D.new()
		_msg.font_size = 32
		_msg.pixel_size = 0.0007
		_msg.outline_size = 0
		_msg.width = 300
		_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_msg.position = _screen.position + Vector3(0, 0.004, 0.002)
		_body.add_child(_msg)
	_msg.text = text
	_msg.modulate = Color("#f5b52e") if kind == "hot" else (Color("#ff5a45") if kind == "bad" else Color("#ffffff"))
	_msg.visible = true
	_screen.visible = false
	_msg_until = Time.get_ticks_msec() + 1500


## Cockpit readouts: gear and speed on the cluster, radio and trip on the screen.
func set_display(gear: int, speed: String, unit: String, trip: String) -> void:
	if _msg and _msg.visible and Time.get_ticks_msec() > _msg_until:
		_msg.visible = false
		_screen.visible = true
	if _display and (gear != _d_gear or speed != _d_speed or unit != _d_unit):  # (only when it shows something different)
		_d_gear = gear
		_d_speed = speed
		_d_unit = unit
		_display.text = speed
		_display_gear.text = "GEAR %d" % gear
		_display_unit.text = unit
	if _screen:
		var sid: String = Save.data.selected
		if sid != _screen_id:
			_screen_id = sid
			_screen_name = Data.car_by_id(sid).name
			_screen_trip = null  # (the screen is built again below)
		if trip != _screen_trip:
			_screen_trip = trip
			var t := "REDLINE FM  98.4\n%s\nTrip %s" % [_screen_name, trip]
			if t != _last_screen:
				_last_screen = t
				_screen.text = t


## Moves the gear lever through an H pattern (1-2 left, 3-4 middle, 5-6 right).
func set_gear(gear: int, dt: float) -> void:
	if _lever == null:
		return
	var col := (clampi(gear, 1, 6) - 1) / 2
	var fwd := gear % 2 == 1
	_lever_target = _lever_base + Vector3((col - 1) * 0.035, 0, -0.035 if fwd else 0.035)
	_lever.position = _lever.position.lerp(_lever_target, minf(1.0, dt * 14.0))
	_lever.rotation.x = (-0.25 if fwd else 0.25)

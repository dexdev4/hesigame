class_name RearMirror
extends Control
## On-screen rear-view mirror: a second camera looking back from the player's
## car, rendered small into its own viewport and shown flipped like a real
## mirror. Drag it in the layout editor; Mirror size in Settings scales it.

const BASE := Vector2(300, 92)

var cam: Camera3D
var _vp: SubViewport
var _tex: TextureRect
var _alt := false  # on Medium and Low graphics the mirror redraws every other frame
var half_rate := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = Vector2i(BASE)
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	cam = Camera3D.new()
	cam.fov = 26.0
	cam.near = 0.3
	cam.far = 300.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(cam)
	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.flip_h = true  # a mirror shows the world left-right reversed
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)
	resized.connect(_fit)


func _fit() -> void:
	var inset := 5.0
	_tex.position = Vector2(inset, inset)
	_tex.size = size - Vector2(inset, inset) * 2.0
	_vp.size = Vector2i(maxi(64, int(_tex.size.x)), maxi(24, int(_tex.size.y)))


## Look back from `xf` (the camera's place on the car); call every frame.
func update_view(xf: Transform3D) -> void:
	if not is_visible_in_tree():
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	cam.global_transform = xf
	_alt = not _alt
	if half_rate:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _alt else SubViewport.UPDATE_DISABLED
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#101215")
	frame.set_corner_radius_all(int(minf(size.y * 0.32, 26.0)))
	frame.border_color = Color("#2a2d33")
	frame.set_border_width_all(2)
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 6
	draw_style_box(frame, r)

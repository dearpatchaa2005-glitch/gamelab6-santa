@tool
extends Node3D
## =====================================================================
##  แบบฝึกหัดที่ 6 — Scene Demo: ตัวละคร 3D ซานต้า ธีมคริสต์มาส
##
##  ทุกอย่างสร้างด้วยโค้ด: ตัวละคร + ชุดซานต้า + หิมะตก + ต้นคริสต์มาส
##  + กล่องของขวัญ + ตุ๊กตาหิมะ + กล้องหมุนรอบ + UI
##
##  วิธีใช้
##    1. วางไฟล์นี้ + demo.tscn + project.godot + FBX 4 ตัว ในโฟลเดอร์เดียวกัน
##    2. เปิด Godot > Import > เลือก project.godot
##    3. กด F5
##
##  ปุ่ม:  ←  →  เปลี่ยนท่า      Space  เล่น/หยุดวนอัตโนมัติ
## =====================================================================

@export_group("ไฟล์ท่าทาง (เว้นว่างไว้ได้ โค้ดจะหาให้เอง)")
@export_file("*.fbx", "*.glb", "*.gltf") var idle_file: String = ""
@export_file("*.fbx", "*.glb", "*.gltf") var walk_file: String = ""
@export_file("*.fbx", "*.glb", "*.gltf") var run_file: String = ""
@export_file("*.fbx", "*.glb", "*.gltf") var jump_file: String = ""

@export_group("การแสดงผล")
@export var seconds_per_anim: float = 3.0
@export var orbit_camera: bool = true
@export var orbit_speed_deg: float = 8.0
@export var build_scenery: bool = true
@export var snow_enabled: bool = true
## ปล่อย 0 ไว้ = ปรับขนาดตัวละครให้เองอัตโนมัติ / ใส่ตัวเลขถ้าอยากกำหนดเอง
@export var character_scale: float = 0.0
## แสดงตัวละครพร้อมชุดซานต้าใน Godot Editor เลย (ไม่ต้องกด F5)
@export var preview_in_editor: bool = true

@export_group("เครื่องมือ")
## ติ๊กช่องนี้ = เปลี่ยนโหนดที่โค้ดสร้าง (ต้นไม้ ของขวัญ ไฟ กล้อง UI)
## ให้เป็นโหนดจริงใน Scene tree แล้วกด Ctrl+S บันทึก
@export var bake_nodes_to_scene: bool = false:
	set(value):
		bake_nodes_to_scene = false
		if Engine.is_editor_hint():
			call_deferred("_bake")

@export_group("ชุดซานต้า (ปรับถ้าหมวก/หน้าไม่เข้าที่)")
@export var santa_outfit: bool = true
## ขยับหมวกขึ้น-ลง / หน้า-หลัง (หน่วยเมตร)
@export var hat_offset: Vector3 = Vector3(0.0, 0.10, 0.0)
## ขยับหน้า+เคราทั้งชุด
@export var face_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## ถ้าหน้าหันผิดด้าน ลองใส่ 90 / 180 / -90
@export var face_yaw_deg: float = 0.0
## ขนาดหัวซานต้า
@export var face_radius: float = 0.125

const TARGET_HEIGHT := 1.8
const STAGE_TOP := 0.08

# ---- สีธีมคริสต์มาส ----
const SUIT_RED := Color(0.72, 0.11, 0.14)
const TRIM_DARK := Color(0.13, 0.12, 0.14)
const FUR_WHITE := Color(0.97, 0.97, 0.96)
const SKIN := Color(0.98, 0.81, 0.69)
const BELT_BLACK := Color(0.10, 0.09, 0.10)
const GOLD := Color(0.95, 0.78, 0.25)
const SNOW := Color(0.93, 0.95, 0.99)
const PINE_DARK := Color(0.09, 0.30, 0.18)
const GIFT_COLORS := [
	Color(0.85, 0.20, 0.24), Color(0.15, 0.48, 0.32),
	Color(0.24, 0.36, 0.72), Color(0.86, 0.60, 0.20),
]
const ORNAMENTS := [
	Color(0.90, 0.18, 0.22), Color(0.95, 0.80, 0.28),
	Color(0.35, 0.60, 0.92), Color(0.90, 0.90, 0.95),
]

var _anim_player: AnimationPlayer
var _anim_names: Array[String] = []
var _index: int = 0
var _timer: float = 0.0
var _auto: bool = true
var _label: Label
var _cam_pivot: Node3D
var _character: Node3D
var _unit: float = 1.0   # 1 เมตรในโลก = กี่หน่วยในโมเดล


# ---------------------------------------------------------------- ready
func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return

	# เคยกด Bake ไว้หรือยัง — ถ้าเคย โหนดฉากถูกบันทึกอยู่ใน demo.tscn แล้ว
	var baked := get_node_or_null("WorldEnvironment") != null

	# ตัวละครสร้างสดทุกครั้ง (ไม่บันทึกลง scene) — ลบของรอบก่อนกันซ้อน
	var old := get_node_or_null("Santa")
	if old != null:
		remove_child(old)
		old.free()

	if baked:
		_cam_pivot = get_node_or_null("CamPivot")
		_label = get_node_or_null("UI/AnimLabel")
	else:
		_build_sky_and_light()
		if build_scenery:
			_build_scenery()
		if snow_enabled:
			_build_snowfall()

	_build_character()

	if not baked:
		_build_camera()
		_build_ui()

	if _anim_names.is_empty():
		if _label != null:
			_label.text = "ไม่พบ animation\nเช็กชื่อไฟล์ใน Inspector"
		push_error("ไม่พบ animation — ตรวจชื่อไฟล์ FBX ใน Inspector")
		return

	print("โหลดท่าได้ ", _anim_names.size(), " ท่า: ", _anim_names)
	_play_index(0)


## เปลี่ยนโหนดที่โค้ดสร้าง ให้เป็นโหนดจริงที่บันทึกลง demo.tscn ได้
func _bake() -> void:
	var root := get_tree().edited_scene_root
	if root == null:
		push_warning("เปิด demo.tscn ก่อน แล้วค่อยติ๊ก Bake")
		return
	var n := 0
	for c in get_children():
		if c.name == "Santa":
			continue        # ตัวละครสร้างสดตอนรัน ไม่ต้องบันทึก
		n += _own(c, root)
	print("ใส่ ", n, " โหนดเข้า Scene เรียบร้อย — กด Ctrl+S เพื่อบันทึก")


func _own(node: Node, root: Node) -> int:
	node.owner = root
	var count := 1
	for c in node.get_children():
		count += _own(c, root)
	return count


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return          # ใน Editor ให้ยืนนิ่ง ๆ จะได้แคปภาพง่าย
	if orbit_camera and _cam_pivot != null:
		_cam_pivot.rotate_y(deg_to_rad(orbit_speed_deg) * delta)
	if _anim_names.is_empty():
		return
	if _auto:
		_timer += delta
		if _timer >= seconds_per_anim:
			_timer = 0.0
			_play_index(_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _anim_names.is_empty():
		return
	if event.is_action_pressed("ui_right"):
		_timer = 0.0
		_play_index(_index + 1)
	elif event.is_action_pressed("ui_left"):
		_timer = 0.0
		_play_index(_index - 1)
	elif event.is_action_pressed("ui_accept"):
		_auto = not _auto
		_update_label()


# ------------------------------------------------------------ character
func _build_character() -> void:
	# หาไฟล์จริงให้เอง รองรับหลายแบบที่ Mixamo ตั้งชื่อมา
	idle_file = _resolve("Idle", idle_file)
	walk_file = _resolve("Walk", walk_file)
	run_file = _resolve("Run", run_file)
	jump_file = _resolve("Jump", jump_file)

	var packed := _safe_load(idle_file)
	if packed == null:
		push_error("โหลดไฟล์ตัวละครไม่ได้ — ตรวจว่ามีไฟล์ Idle อยู่ในโปรเจกต์")
		return

	_character = packed.instantiate()
	_character.name = "Santa"
	add_child(_character)

	_anim_player = _find_anim_player(_character)
	if _anim_player == null:
		push_error("ไม่พบ AnimationPlayer ในไฟล์ " + idle_file)
		return

	var lib := AnimationLibrary.new()
	var sources := {
		"Idle": idle_file,
		"Walk": walk_file,
		"Run": run_file,
		"Jump": jump_file,
	}
	for key in sources.keys():
		var anim := _extract_animation(sources[key])
		if anim == null:
			push_warning("ข้ามท่า " + key + " — โหลดไม่ได้: " + str(sources[key]))
			continue
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, anim)
		_anim_names.append(key)

	for lib_name in _anim_player.get_animation_library_list():
		_anim_player.remove_animation_library(lib_name)
	_anim_player.add_animation_library("", lib)

	_normalize_character()
	if santa_outfit:
		_paint_suit()
		_add_santa_gear()


func _extract_animation(path: String) -> Animation:
	var packed := _safe_load(path)
	if packed == null:
		return null
	var inst := packed.instantiate()
	var ap := _find_anim_player(inst)
	var out: Animation = null
	if ap != null:
		var list := ap.get_animation_list()
		for n in list:
			if String(n).to_lower().contains("mixamo"):
				out = ap.get_animation(n)
				break
		if out == null:
			for n in list:
				if String(n) != "RESET":
					out = ap.get_animation(n)
					break
	if out != null:
		out = out.duplicate(true)
	inst.free()
	return out


func _normalize_character() -> void:
	if character_scale > 0.0:
		_character.scale = Vector3.ONE * character_scale
	else:
		# วัดแล้วปรับ 2 รอบ ให้ลู่เข้าความสูงเป้าหมายแน่ ๆ
		for i in 2:
			var h := _model_height()
			if h > 0.0001:
				_character.scale *= clampf(TARGET_HEIGHT / h, 0.00001, 100000.0)

	_unit = 1.0 / maxf(_character.scale.y, 0.0001)
	print("ความสูงตัวละครหลังปรับ = %.2f m  (scale %.4f)" % [_model_height(), _character.scale.y])

	var foot := _lowest_point()
	if is_finite(foot):
		_character.position.y += STAGE_TOP - foot
	else:
		_character.position.y = STAGE_TOP


## วัดความสูงจากตำแหน่งกระดูก — เชื่อถือได้กว่า AABB ของ mesh ที่ผูกกับ skeleton
func _model_height() -> float:
	var span := _bone_span()
	if span.y > 0.0001:
		return span.y / 0.83          # กระดูกบนสุดอยู่แค่โคนหัว ชดเชยส่วนกบาล
	var box := _measure(_character)
	return box.size.y


func _lowest_point() -> float:
	var span := _bone_span()
	if span.y > 0.0001:
		return span.x - TARGET_HEIGHT * 0.04    # เผื่อฝ่าเท้าที่อยู่ใต้ข้อเท้า
	return _measure(_character).position.y


## คืน Vector2(ต่ำสุด, ช่วงความสูง) ของกระดูกทั้งหมดในพิกัดโลก
func _bone_span() -> Vector2:
	var skel := _find_skeleton(_character)
	if skel == null or skel.get_bone_count() == 0:
		return Vector2.ZERO
	var xf := skel.global_transform
	var top := -INF
	var bot := INF
	for i in skel.get_bone_count():
		var y: float = (xf * skel.get_bone_global_rest(i).origin).y
		top = maxf(top, y)
		bot = minf(bot, y)
	if not is_finite(top) or not is_finite(bot):
		return Vector2.ZERO
	return Vector2(bot, top - bot)


func _measure(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in _walk(root):
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var world_box: AABB = vi.global_transform * vi.get_aabb()
			if first:
				box = world_box
				first = false
			else:
				box = box.merge(world_box)
	if first:
		box = AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, TARGET_HEIGHT, 0.8))
	return box


# --------------------------------------------------------- santa outfit
## ทาสีตัวละครเป็นชุดซานต้าสีแดง
func _paint_suit() -> void:
	for n in _walk(_character):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var is_joint := mi.name.to_lower().contains("joint")
		var c: Color = TRIM_DARK if is_joint else SUIT_RED
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _mat(c))


## หมวก เครา เข็มขัด ปลายแขน-ขาขนสีขาว — ติดกับกระดูกจริง จึงขยับตามท่าทาง
func _add_santa_gear() -> void:
	var skel := _find_skeleton(_character)
	if skel == null:
		push_warning("ไม่พบ Skeleton3D — ข้ามการใส่ชุดซานต้า")
		return

	# ---- หมวก + เครา ที่หัว ----
	var head := _slot(skel, "head")
	if head != null:
		# ขอบหมวกขนสีขาว
		var brim := _torus(0.105, 0.145, FUR_WHITE)
		brim.position = hat_offset
		head.add_child(brim)
		# ตัวหมวกทรงกรวยแดง เอียงไปข้างหลังนิดหน่อย
		var cone := _cone(0.115, 0.34, SUIT_RED)
		cone.position = hat_offset + Vector3(0.0, 0.18, -0.02)
		cone.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
		head.add_child(cone)
		# ปอมปอมสีขาวปลายหมวก
		var pom := _ball(0.055, FUR_WHITE)
		pom.position = hat_offset + Vector3(0.0, 0.33, -0.12)
		head.add_child(pom)
		# หน้า + เครา
		_build_face(head)

	# ---- เข็มขัดดำ + หัวเข็มขัดทอง ที่เอว ----
	var hips := _slot(skel, "hips")
	if hips != null:
		var belt := _torus(0.115, 0.165, BELT_BLACK)
		belt.position = Vector3(0.0, 0.05, 0.0)
		hips.add_child(belt)
		var buckle := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.09, 0.04)
		buckle.mesh = bm
		buckle.position = Vector3(0.0, 0.05, 0.14)
		buckle.material_override = _mat(GOLD)
		hips.add_child(buckle)

	# ---- ปลายแขนขนขาว ----
	for side in ["lefthand", "righthand"]:
		var hand := _slot(skel, side)
		if hand != null:
			var cuff := _torus(0.045, 0.085, FUR_WHITE)
			hand.add_child(cuff)

	# ---- รองเท้าบู๊ตดำ ----
	for side in ["leftfoot", "rightfoot"]:
		var foot := _slot(skel, side)
		if foot != null:
			var boot := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.13, 0.11, 0.25)
			boot.mesh = bm2
			boot.position = Vector3(0.0, 0.0, 0.05)
			boot.material_override = _mat(BELT_BLACK)
			foot.add_child(boot)


## หน้าซานต้า: หัวสีผิว ตา คิ้วขาว จมูกแดง แก้มชมพู หนวด เครา
func _build_face(head: Node3D) -> void:
	var rig := Node3D.new()
	rig.position = face_offset
	rig.rotation_degrees = Vector3(0.0, face_yaw_deg, 0.0)
	head.add_child(rig)

	var r := face_radius
	var fz := r * 0.78          # ระยะจากกลางหัวถึงผิวหน้า

	# หัวสีผิว ครอบหุ่นสีแดงเดิม
	var face := _ball(r, SKIN)
	rig.add_child(face)

	# ตา (ตาขาว + ตาดำ)
	for sx in [-1.0, 1.0]:
		var white := _ball(r * 0.23, Color(0.97, 0.97, 0.98))
		white.position = Vector3(sx * r * 0.36, r * 0.16, fz * 0.92)
		rig.add_child(white)
		var pupil := _ball(r * 0.13, Color(0.08, 0.07, 0.10))
		pupil.position = Vector3(sx * r * 0.36, r * 0.16, fz * 1.06)
		rig.add_child(pupil)

	# คิ้วขาวหนา ๆ
	for sx in [-1.0, 1.0]:
		var brow := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 0.46, r * 0.14, r * 0.18)
		brow.mesh = bm
		brow.position = Vector3(sx * r * 0.36, r * 0.44, fz * 0.88)
		brow.rotation_degrees = Vector3(0.0, 0.0, -8.0 * sx)
		brow.material_override = _mat(FUR_WHITE)
		rig.add_child(brow)

	# จมูกแดงกลม
	var nose := _ball(r * 0.27, Color(0.89, 0.44, 0.39))
	nose.position = Vector3(0.0, -r * 0.06, fz * 1.02)
	rig.add_child(nose)

	# แก้มชมพู
	for sx in [-1.0, 1.0]:
		var cheek := _ball(r * 0.26, Color(0.93, 0.56, 0.53))
		cheek.scale = Vector3(1.1, 0.75, 0.45)
		cheek.position = Vector3(sx * r * 0.58, -r * 0.18, fz * 0.72)
		rig.add_child(cheek)

	# หนวด
	for sx in [-1.0, 1.0]:
		var mus := _ball(r * 0.30, FUR_WHITE)
		mus.scale = Vector3(1.25, 0.72, 0.72)
		mus.position = Vector3(sx * r * 0.22, -r * 0.36, fz * 0.88)
		rig.add_child(mus)

	# เคราเป็นพุ่มกลม ๆ ใต้คาง
	var beard_parts := [
		[Vector3(0.0, -0.72, 0.60), 0.44],
		[Vector3(-0.52, -0.52, 0.48), 0.34],
		[Vector3(0.52, -0.52, 0.48), 0.34],
		[Vector3(-0.28, -1.02, 0.46), 0.32],
		[Vector3(0.28, -1.02, 0.46), 0.32],
		[Vector3(0.0, -1.24, 0.38), 0.30],
	]
	for p in beard_parts:
		var b := _ball(r * float(p[1]), FUR_WHITE)
		b.position = (p[0] as Vector3) * r
		rig.add_child(b)


## สร้างจุดยึดบนกระดูก คืน Node3D ที่ใช้หน่วยเป็นเมตร
func _slot(skel: Skeleton3D, bone_suffix: String) -> Node3D:
	var bone_name := _find_bone(skel, bone_suffix)
	if bone_name.is_empty():
		return null
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = bone_name
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * _unit    # แปลงเมตร -> หน่วยของโมเดล
	att.add_child(holder)
	return holder


func _find_bone(skel: Skeleton3D, suffix: String) -> String:
	var needle := suffix.to_lower()
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower().ends_with(needle):
			return skel.get_bone_name(i)
	return ""


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


# --------------------------------------------------------------- camera
func _build_camera() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "CamPivot"
	_cam_pivot.position = Vector3(0.0, STAGE_TOP + TARGET_HEIGHT * 0.55, 0.0)
	add_child(_cam_pivot)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.0, 0.25, 3.9)
	cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	cam.fov = 55.0
	cam.current = true
	_cam_pivot.add_child(cam)


# ------------------------------------------------------- sky / light
func _build_sky_and_light() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.07, 0.12, 0.32)      # ฟ้ายามค่ำ
	sky_mat.sky_horizon_color = Color(0.56, 0.64, 0.84)
	sky_mat.ground_horizon_color = Color(0.62, 0.70, 0.86)
	sky_mat.ground_bottom_color = Color(0.85, 0.89, 0.96)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "MoonLight"
	moon.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	moon.light_energy = 0.9
	moon.light_color = Color(0.86, 0.90, 1.0)
	moon.shadow_enabled = true
	add_child(moon)

	# ไฟอุ่น ๆ ส่องซานต้าจากด้านหน้า
	var warm := OmniLight3D.new()
	warm.name = "WarmLight"
	warm.position = Vector3(1.6, 2.2, 2.0)
	warm.light_color = Color(1.0, 0.82, 0.58)
	warm.light_energy = 2.2
	warm.omni_range = 9.0
	add_child(warm)


# ------------------------------------------------------------ snowfall
func _build_snowfall() -> void:
	var flake := SphereMesh.new()
	flake.radius = 0.5
	flake.height = 1.0
	flake.radial_segments = 4
	flake.rings = 2
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.material = fm

	var snow := CPUParticles3D.new()
	snow.name = "Snow"
	snow.mesh = flake
	snow.amount = 350
	snow.lifetime = 11.0
	snow.preprocess = 6.0
	snow.position = Vector3(0.0, 8.0, 0.0)
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(11.0, 0.5, 11.0)
	snow.direction = Vector3(0.25, -1.0, 0.1)
	snow.spread = 12.0
	snow.gravity = Vector3(0.0, -0.45, 0.0)
	snow.initial_velocity_min = 0.25
	snow.initial_velocity_max = 0.7
	snow.scale_amount_min = 0.035
	snow.scale_amount_max = 0.075
	add_child(snow)


# -------------------------------------------------------------- scenery
func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261225

	# พื้นหิมะ แปดเหลี่ยม low-poly
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 9.5
	disc.bottom_radius = 8.4
	disc.height = 1.4
	disc.radial_segments = 8
	ground.mesh = disc
	ground.name = "SnowGround"
	ground.position.y = -0.7
	ground.material_override = _mat(SNOW)
	add_child(ground)

	# เวทีน้ำแข็งกลางฉาก
	var stage := MeshInstance3D.new()
	var sd := CylinderMesh.new()
	sd.top_radius = 2.1
	sd.bottom_radius = 2.25
	sd.height = 0.16
	sd.radial_segments = 24
	stage.mesh = sd
	stage.name = "IceStage"
	stage.position.y = STAGE_TOP - 0.08
	stage.material_override = _mat(Color(0.80, 0.88, 0.97))
	add_child(stage)

	# ต้นคริสต์มาสล้อมรอบ
	var tree_count := 10
	for i in tree_count:
		var ang := TAU * float(i) / float(tree_count) + rng.randf_range(-0.16, 0.16)
		var r := rng.randf_range(4.8, 7.3)
		var t := _add_xmas_tree(Vector3(cos(ang) * r, 0.0, sin(ang) * r), rng.randf_range(0.85, 1.4), rng)
		t.name = "ChristmasTree%d" % (i + 1)

	# กองหิมะเล็ก ๆ
	for i in 14:
		var a2 := rng.randf_range(0.0, TAU)
		var r2 := rng.randf_range(2.8, 7.6)
		var m := _add_snow_mound(Vector3(cos(a2) * r2, 0.0, sin(a2) * r2), rng)
		m.name = "SnowMound%d" % (i + 1)

	# กล่องของขวัญรอบเวที
	for i in 7:
		var a3 := rng.randf_range(0.0, TAU)
		var r3 := rng.randf_range(2.5, 3.6)
		var g := _add_gift(Vector3(cos(a3) * r3, 0.0, sin(a3) * r3), rng)
		g.name = "GiftBox%d" % (i + 1)

	# ตุ๊กตาหิมะ 2 ตัว
	_add_snowman(Vector3(-3.1, 0.0, 1.9)).name = "Snowman1"
	_add_snowman(Vector3(3.4, 0.0, -1.2)).name = "Snowman2"


func _add_xmas_tree(pos: Vector3, s: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * s
	root.rotation.y = rng.randf_range(0.0, TAU)
	add_child(root)

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.13
	tm.bottom_radius = 0.2
	tm.height = 1.0
	tm.radial_segments = 6
	trunk.mesh = tm
	trunk.position.y = 0.5
	trunk.name = "Trunk"
	trunk.material_override = _mat(Color(0.34, 0.23, 0.16))
	root.add_child(trunk)

	# ใบ 3 ชั้น + หิมะเกาะบนยอดแต่ละชั้น
	for i in 3:
		var w := 1.0 - float(i) * 0.24
		var leaf := _cone(w, 0.95, PINE_DARK.lightened(float(i) * 0.10))
		leaf.position.y = 1.2 + float(i) * 0.52
		leaf.name = "Branch%d" % (i + 1)
		root.add_child(leaf)
		var cap := _cone(w * 0.62, 0.30, SNOW)
		cap.position.y = 1.55 + float(i) * 0.52
		cap.name = "SnowCap%d" % (i + 1)
		root.add_child(cap)

	# ลูกบอลประดับ
	for i in 5:
		var ang := rng.randf_range(0.0, TAU)
		var hgt := rng.randf_range(1.15, 2.1)
		var rad := (2.35 - hgt) * 0.42
		var ball := _ball(0.085, ORNAMENTS[rng.randi() % ORNAMENTS.size()])
		ball.position = Vector3(cos(ang) * rad, hgt, sin(ang) * rad)
		ball.name = "Ornament%d" % (i + 1)
		root.add_child(ball)

	# ดาวบนยอด
	var star := _ball(0.15, GOLD)
	star.position.y = 2.75
	star.name = "TopStar"
	var sm := StandardMaterial3D.new()
	sm.albedo_color = GOLD
	sm.emission_enabled = true
	sm.emission = GOLD
	sm.emission_energy_multiplier = 1.8
	star.material_override = sm
	root.add_child(star)
	return root


func _add_snow_mound(pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = rng.randf_range(0.28, 0.55)
	s.height = s.radius * 1.3
	s.radial_segments = 7
	s.rings = 4
	m.mesh = s
	m.position = pos + Vector3(0.0, s.height * 0.22, 0.0)
	m.material_override = _mat(SNOW.darkened(rng.randf() * 0.06))
	add_child(m)
	return m


func _add_gift(pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
	var s := rng.randf_range(0.3, 0.48)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s * 0.82, s)
	box.mesh = bm
	box.position = pos + Vector3(0.0, s * 0.41, 0.0)
	box.rotation.y = rng.randf_range(0.0, TAU)
	box.material_override = _mat(GIFT_COLORS[rng.randi() % GIFT_COLORS.size()])
	add_child(box)

	for axis in 2:
		var rib := MeshInstance3D.new()
		var rm := BoxMesh.new()
		if axis == 0:
			rm.size = Vector3(s * 0.14, s * 0.85, s * 1.03)
		else:
			rm.size = Vector3(s * 1.03, s * 0.85, s * 0.14)
		rib.mesh = rm
		rib.name = "Ribbon%d" % (axis + 1)
		rib.material_override = _mat(GOLD)
		box.add_child(rib)
	return box


func _add_snowman(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var sizes := [0.42, 0.30, 0.21]
	var y := 0.0
	for r in sizes:
		var b := _ball(r, SNOW)
		y += r * 0.82
		b.position.y = y
		b.name = "SnowBall"
		root.add_child(b)
		y += r * 0.42

	# ตา + จมูกแครอท
	var head_y := y - 0.1
	for x in [-0.075, 0.075]:
		var eye := _ball(0.028, Color(0.10, 0.09, 0.10))
		eye.position = Vector3(x, head_y, 0.175)
		eye.name = "Eye"
		root.add_child(eye)
	var nose := _cone(0.035, 0.18, Color(0.93, 0.52, 0.16))
	nose.position = Vector3(0.0, head_y - 0.03, 0.22)
	nose.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	nose.name = "CarrotNose"
	root.add_child(nose)

	# หมวกแดง
	var hat := _cone(0.15, 0.26, SUIT_RED)
	hat.name = "Hat"
	hat.position.y = head_y + 0.28
	root.add_child(hat)
	return root


# ------------------------------------------------------- mesh helpers
func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _ball(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	mi.mesh = s
	mi.material_override = _mat(c)
	return mi


func _cone(bottom_r: float, h: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = bottom_r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _mat(c)
	return mi


func _torus(inner: float, outer: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 12
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = _mat(c)
	return mi


# -------------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	var title := Label.new()
	title.position = Vector2(30.0, 18.0)
	title.name = "TitleLabel"
	title.text = "MERRY CHRISTMAS"
	_style_label(title, 26)
	title.add_theme_color_override("font_color", GOLD)
	layer.add_child(title)

	_label = Label.new()
	_label.name = "AnimLabel"
	_label.position = Vector2(30.0, 54.0)
	_style_label(_label, 38)
	layer.add_child(_label)

	var help := Label.new()
	help.anchor_left = 0.0
	help.anchor_right = 1.0
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -66.0
	help.offset_bottom = -22.0
	help.name = "HelpLabel"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.text = "[ < ]  [ > ]  change pose          [ Space ]  auto-play on / off"
	_style_label(help, 20)
	layer.add_child(help)


func _style_label(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 9)


# ---------------------------------------------------------------- play
func _play_index(new_index: int) -> void:
	_index = wrapi(new_index, 0, _anim_names.size())
	_anim_player.play(_anim_names[_index], 0.25)
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var mode := "auto" if _auto else "paused"
	_label.text = "%s\n%d / %d   (%s)" % [
		_anim_names[_index], _index + 1, _anim_names.size(), mode
	]


# ------------------------------------------------------------- helpers
## หาไฟล์ท่าทางโดยเดาชื่อหลายแบบ — Mixamo ตั้งชื่อไม่เหมือนกันแล้วแต่ตัวละคร
func _resolve(key: String, explicit: String) -> String:
	if not explicit.is_empty() and ResourceLoader.exists(explicit):
		return explicit

	var words := [key]
	match key:
		"Walk": words = ["Walking", "Walk"]
		"Run": words = ["Running", "Run"]
		"Jump": words = ["Jump", "Jumping"]
		"Idle": words = ["Idle", "Breathing Idle"]

	var prefixes := ["", "character@", "Character@", "X Bot@", "Ch@", "Ch36@"]
	var exts := [".fbx", ".glb", ".gltf"]
	for w in words:
		for p in prefixes:
			for e in exts:
				var path: String = "res://%s%s%s" % [p, w, e]
				if ResourceLoader.exists(path):
					return path

	# หาแบบสแกนโฟลเดอร์ เผื่อชื่อแปลกกว่าที่เดาไว้ (ใช้ได้ตอนรันในเอดิเตอร์)
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			var low := f.to_lower().trim_suffix(".remap")
			if low.ends_with(".fbx") or low.ends_with(".glb") or low.ends_with(".gltf"):
				for w in words:
					if low.contains(String(w).to_lower()):
						dir.list_dir_end()
						return "res://" + f.trim_suffix(".remap")
			f = dir.get_next()
		dir.list_dir_end()

	push_warning("หาไฟล์ท่า " + key + " ไม่เจอ")
	return ""


func _safe_load(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

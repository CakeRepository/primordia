class_name Planet3D
extends Node3D
## 3D view of the World simulation. The sim stays 2D (x, y on the ground plane); this node maps
## it onto a heightfield, sim (x, y) -> (x * S, height, y * S), and draws terrain, water, food,
## predators and every creature except the player (who gets a detailed CreatureModel).

const S := 0.1 # metres per sim unit
const RELIEF := 40.0 # metres of height per unit of elevation away from sea level

var world: World
var terrain := MeshInstance3D.new()
var bodies: MultiMesh # smooth creatures
var spiky: MultiMesh # creatures with spikes
var legs: MultiMesh
var food_mm: MultiMesh
var pred_mm: MultiMesh


func setup(w: World) -> void:
	world = w
	_build_environment()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true # terrain colours are authored in sRGB
	mat.roughness = 0.95
	terrain.material_override = mat
	add_child(terrain)
	_build_water()
	var cap := World.MAX_POP + 100
	bodies = _multimesh(sphere_mesh(1.0), cap)
	spiky = _multimesh(_spiky_sphere(), cap)
	legs = _multimesh(cylinder_mesh(0.5, 0.5, 1.0), cap * 6)
	food_mm = _multimesh(box_mesh(0.28), 1600)
	pred_mm = _multimesh(cylinder_mesh(0.0, 0.55, 1.8), 16)
	build_terrain()
	world.terrain_changed.connect(build_terrain)


func ground_y(p: Vector2) -> float:
	return (world.elev_at(p) - World.SEA) * RELIEF


## 3D position for something whose centre should sit `lift` metres above the ground,
## or floating at the surface when the ground there is under water.
func rest_point(p: Vector2, lift: float) -> Vector3:
	var y := ground_y(p)
	return Vector3(p.x * S, y + lift if y > 0.0 else 0.0, p.y * S)


static func body_color(g: Dictionary) -> Color:
	# Camouflaged bodies are duller rather than transparent, so they still sort correctly.
	return Color.from_hsv(g["hue"] / 360.0, 0.75 * (1.0 - g["camo"] * 0.6), 0.9 - g["diet"] * 0.25 - g["camo"] * 0.2)


## A leg from the underside of a body (centre `at`, radius `rad`) out and down toward angle a
## (sim heading space), `length` metres long. Starting below the centre keeps the leg's
## darker cross-section off the visible flank of the body.
static func leg_transform(at: Vector3, rad: float, a: float, length: float) -> Transform3D:
	var out := Vector3(cos(a), 0.0, sin(a))
	var dir := (out * 0.75 + Vector3.DOWN * 0.66).normalized()
	var hip := at + out * rad * 0.35 + Vector3.DOWN * rad * 0.55
	var thick := maxf(0.05, rad * 0.22)
	var b := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(thick, length, thick))
	return Transform3D(b, hip + dir * length * 0.5)


# ---------------------------------------------------------------- terrain

func build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in World.GH:
		for i in World.GW:
			var k := j * World.GW + i
			st.set_color(world.terrain_color(k))
			st.add_vertex(Vector3((i + 0.5) * World.CS * S, (world.elev[k] - World.SEA) * RELIEF, (j + 0.5) * World.CS * S))
	for j in World.GH - 1:
		for i in World.GW - 1:
			var k := j * World.GW + i
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + World.GW)
			st.add_index(k + 1)
			st.add_index(k + World.GW + 1)
			st.add_index(k + World.GW)
	st.generate_normals()
	terrain.mesh = st.commit()


func _build_water() -> void:
	var size := Vector2(World.WW, World.WH) * S
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size * 4.0 # runs out to the horizon
	water.mesh = plane
	water.position = Vector3(size.x, 0.0, size.y) / 2.0
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.36, 0.5, 0.7)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.12
	water.material_override = wm
	add_child(water)
	var floor_mi := MeshInstance3D.new() # dark ocean floor beyond the map edge
	floor_mi.mesh = plane
	floor_mi.position = water.position + Vector3.DOWN * RELIEF * 0.3
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.12, 0.16)
	floor_mi.material_override = fm
	add_child(floor_mi)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.4, 0.68)
	sky_mat.sky_horizon_color = Color(0.66, 0.76, 0.84)
	sky_mat.ground_horizon_color = Color(0.66, 0.76, 0.84)
	sky_mat.ground_bottom_color = Color(0.08, 0.14, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.76, 0.84)
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


# ---------------------------------------------------------------- life

## Redraw food, predators and every creature except `skip` (the player, drawn separately).
func update_life(skip: World.Creature) -> void:
	var nb := 0
	var ns := 0
	var nl := 0
	for c in world.creatures:
		if c == skip or c.dead:
			continue
		var g := c.g
		var rad := c.r * S
		var at := rest_point(c.pos, rad)
		var head := c.vel.angle()
		var col := body_color(g)
		var xf := Transform3D(Basis(Vector3.UP, -head).scaled(Vector3(rad, rad, rad)), at)
		if g["spikes"] > 0.3:
			if ns < spiky.instance_count:
				spiky.set_instance_transform(ns, xf)
				spiky.set_instance_color(ns, col)
				ns += 1
		elif nb < bodies.instance_count:
			bodies.set_instance_transform(nb, xf)
			bodies.set_instance_color(nb, col)
			nb += 1
		var leg_col := col.darkened(0.3)
		for l: Vector2 in g["limbs"]:
			if nl >= legs.instance_count:
				break
			legs.set_instance_transform(nl, leg_transform(at, rad, head + l.x, rad * (1.0 + l.y * 1.4)))
			legs.set_instance_color(nl, leg_col)
			nl += 1
	bodies.visible_instance_count = nb
	spiky.visible_instance_count = ns
	legs.visible_instance_count = nl

	var nf := 0
	for f in world.foods:
		if nf >= food_mm.instance_count:
			break
		food_mm.set_instance_transform(nf, Transform3D(Basis.IDENTITY, rest_point(f.pos, 0.14)))
		food_mm.set_instance_color(nf, Color("9be8ff") if f.aq else Color("a6f5b8"))
		nf += 1
	food_mm.visible_instance_count = nf

	var np := 0
	for p in world.preds:
		if np >= pred_mm.instance_count:
			break
		var dir := Vector3(p.vel.x, 0.0, p.vel.y)
		dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.RIGHT
		pred_mm.set_instance_transform(np, Transform3D(Basis(Quaternion(Vector3.UP, dir)), rest_point(p.pos, 0.6)))
		pred_mm.set_instance_color(np, Color("7a3a44") if p.stun > 0 else Color("ff5d73"))
		np += 1
	pred_mm.visible_instance_count = np


# ---------------------------------------------------------------- meshes

func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true # must be set before instance_count
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true # picks up the per-instance colour
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.7
	mi.material_override = mat
	add_child(mi)
	return mm


static func sphere_mesh(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


static func cylinder_mesh(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


static func box_mesh(s: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(s, s, s)
	return m


## Unit sphere with ten cone spikes, for creatures whose spikes trait is high.
static func _spiky_sphere() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(sphere_mesh(1.0), 0, Transform3D.IDENTITY)
	var cone := cylinder_mesh(0.0, 0.22, 0.6)
	for i in 10:
		# Fibonacci points over the upper part of the sphere
		var y := 1.0 - (i + 0.5) / 10.0 * 1.3
		var a := i * 2.39996
		var dir := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y)).normalized()
		st.append_from(cone, 0, Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * 1.15))
	return st.commit()

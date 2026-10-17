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

var _water: MeshInstance3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun_color := Color(1.0, 0.96, 0.9) # resting colours, tinted by the climate each frame
var _horizon := Color(0.66, 0.76, 0.84)
var _terrain_arrays: Array = [] # mesh arrays kept so the climate can recolour without a rebuild
var _vert_cell := PackedInt32Array()
var _built_version := -1
var _meteor_fx: Array = [] # [fireball, warning column] per incoming meteor
var _flashes: Array = [] # [MeshInstance3D, seconds since impact]
var _time := 0.0


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


## Per-frame planet state: sea level, climate tint and meteors.
func update_planet(delta: float) -> void:
	_time += delta
	_water.position.y = water_y()
	var heat := clampf((world.temp - world.climate_base) / 0.28, -1.0, 1.0)
	var cold_tint := Color(0.75, 0.86, 1.0)
	var hot_tint := Color(1.0, 0.8, 0.55)
	_sun.light_color = _sun_color.lerp(cold_tint, maxf(0.0, -heat) * 0.4).lerp(hot_tint, maxf(0.0, heat) * 0.4)
	var horizon := _horizon.lerp(cold_tint, maxf(0.0, -heat) * 0.3).lerp(hot_tint, maxf(0.0, heat) * 0.3)
	_sky_mat.sky_horizon_color = horizon
	_sky_mat.ground_horizon_color = horizon
	_env.fog_light_color = horizon
	_update_meteors(delta)


## Height of the sea surface, which rises and falls with the climate.
func water_y() -> float:
	return (world.sea_level - World.SEA) * RELIEF


func ground_y(p: Vector2) -> float:
	return (world.elev_at(p) - World.SEA) * RELIEF


## 3D position for something whose centre should sit `lift` metres above the ground,
## or floating at the surface when the ground there is under water.
func rest_point(p: Vector2, lift: float) -> Vector3:
	var y := ground_y(p)
	var w := water_y()
	return Vector3(p.x * S, y + lift if y > w else w, p.y * S)


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

## Called whenever the world repaints: a full rebuild for new ground, otherwise only the
## vertex colours change (climate, sea level, craters).
func build_terrain() -> void:
	if world.terrain_version == _built_version:
		_recolor_terrain()
		return
	_built_version = world.terrain_version
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
	var mesh := st.commit()
	terrain.mesh = mesh
	_terrain_arrays = mesh.surface_get_arrays(0)
	# Map each vertex back to its cell from its position, whatever order SurfaceTool kept.
	var verts: PackedVector3Array = _terrain_arrays[Mesh.ARRAY_VERTEX]
	_vert_cell.resize(verts.size())
	for v in verts.size():
		var i := clampi(int(verts[v].x / (World.CS * S)), 0, World.GW - 1)
		var j := clampi(int(verts[v].z / (World.CS * S)), 0, World.GH - 1)
		_vert_cell[v] = j * World.GW + i


func _recolor_terrain() -> void:
	var colors := PackedColorArray()
	colors.resize(_vert_cell.size())
	for v in _vert_cell.size():
		colors[v] = world.terrain_color(_vert_cell[v])
	_terrain_arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _terrain_arrays)
	terrain.mesh = mesh


func _build_water() -> void:
	var size := Vector2(World.WW, World.WH) * S
	var water := MeshInstance3D.new()
	_water = water
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
	_sky_mat = sky_mat
	sky_mat.sky_top_color = Color(0.2, 0.4, 0.68)
	sky_mat.sky_horizon_color = Color(0.66, 0.76, 0.84)
	sky_mat.ground_horizon_color = Color(0.66, 0.76, 0.84)
	sky_mat.ground_bottom_color = Color(0.08, 0.14, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	_env = env
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
	_sun = sun
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


# ---------------------------------------------------------------- meteors

## A falling fireball and a red column marking where it will land, per incoming meteor.
func _update_meteors(delta: float) -> void:
	while _meteor_fx.size() < world.incoming.size():
		var ball := MeshInstance3D.new()
		ball.mesh = sphere_mesh(2.2)
		ball.material_override = _glow(Color(1.0, 0.62, 0.25), 1.0)
		add_child(ball)
		var column := MeshInstance3D.new()
		column.mesh = cylinder_mesh(World.METEOR_R * S, World.METEOR_R * S, 90.0)
		column.material_override = _glow(Color(1.0, 0.12, 0.08), 0.25)
		add_child(column)
		_meteor_fx.append([ball, column])
	for i in _meteor_fx.size():
		var fx: Array = _meteor_fx[i]
		var on := i < world.incoming.size()
		fx[0].visible = on
		fx[1].visible = on
		if not on:
			continue
		var p: Vector2 = world.incoming[i][0]
		var left: float = world.incoming[i][1]
		var ground := rest_point(p, 0.0)
		# each meteor comes in at a slant from its own direction (derived from where it lands)
		var a := fposmod(p.x * 0.37 + p.y * 0.11, TAU)
		var h := left * 0.55
		fx[0].position = ground + Vector3.UP * h + Vector3(cos(a), 0.0, sin(a)) * h * 0.8
		fx[1].position = ground + Vector3.UP * 44.0
		fx[1].material_override.albedo_color.a = 0.22 + 0.1 * sin(_time * 8.0)
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Array = _flashes[i]
		f[1] += delta
		var t: float = f[1] / 1.4
		if t >= 1.0:
			f[0].queue_free()
			_flashes.remove_at(i)
			continue
		f[0].scale = Vector3.ONE * (1.0 + t * World.METEOR_R * S * 1.1)
		f[0].material_override.albedo_color.a = 0.6 * (1.0 - t) * (1.0 - t)


## The blast when a meteor lands at p.
func flash(p: Vector2) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = sphere_mesh(1.0)
	mi.material_override = _glow(Color(1.0, 0.75, 0.45), 0.6)
	mi.position = rest_point(p, 0.0)
	add_child(mi)
	_flashes.append([mi, 0.0])


static func _glow(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true # warnings and fireballs must read at any distance
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


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

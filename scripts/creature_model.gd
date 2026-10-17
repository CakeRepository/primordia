class_name CreatureModel
extends Node3D
## The player's body, built from its genome: torso, eyes (bigger with better senses), legs,
## spikes, jaws for carnivores and a tail fin for swimmers. Local forward is -Z.

var rad := 0.6 # body radius in metres
var stand := 0.6 # height of the body centre above the ground
var _legs: Array[Node3D] = []
var _torso: Node3D
var _phase := 0.0


func build(g: Dictionary, radius: float) -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_legs.clear()
	rad = radius
	var col := Planet3D.body_color(g)
	var skin := _mat(col)
	var dark := _mat(col.darkened(0.35))
	_torso = Node3D.new()
	add_child(_torso)
	var body := _part(_torso, Planet3D.sphere_mesh(radius), skin)
	body.scale = Vector3(0.95, 0.85, 1.15)

	var eye_r: float = radius * (0.13 + g["sense"] * 0.17)
	for side in [-1.0, 1.0]:
		var eye := _part(_torso, Planet3D.sphere_mesh(eye_r), _mat(Color(0.95, 0.95, 0.9)))
		eye.position = Vector3(side * radius * 0.4, radius * 0.38, -radius * 0.88)
		var pupil := _part(_torso, Planet3D.sphere_mesh(eye_r * 0.55), _mat(Color(0.05, 0.05, 0.08)))
		pupil.position = eye.position + Vector3(0.0, 0.0, -eye_r * 0.6)

	var reach := 0.0
	for l: Vector2 in g["limbs"]:
		# limb angle is relative to the heading: 0 = forward (-Z), +90 degrees = right (+X)
		var out := Vector3(sin(l.x), 0.0, -cos(l.x))
		var dir := (out * 0.75 + Vector3.DOWN * 0.66).normalized()
		var length := radius * (1.0 + l.y * 1.4)
		var pivot := Node3D.new()
		add_child(pivot)
		var leg := _part(pivot, Planet3D.cylinder_mesh(0.5, 0.5, 1.0), dark)
		var thick := maxf(0.05, radius * 0.22)
		var hip := out * radius * 0.35 + Vector3.DOWN * radius * 0.55
		leg.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(thick, length, thick)), hip + dir * length * 0.5)
		_legs.append(pivot)
		reach = maxf(reach, radius * 0.55 - dir.y * length)
	stand = maxf(radius * 0.9, reach)

	var cone := Planet3D.cylinder_mesh(0.0, radius * 0.16, radius * 0.5)
	var n := roundi(g["spikes"] * 10.0)
	for i in n:
		var y := 0.9 - (i + 0.5) / maxf(n, 1.0) * 1.0
		var a := i * 2.39996
		var dir := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
		var spike := _part(_torso, cone, dark)
		spike.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * radius * 1.1)

	if g["diet"] > 0.5:
		var jaw := _part(_torso, BoxMesh.new(), _mat(Color(0.12, 0.05, 0.05)))
		jaw.scale = Vector3(radius * 0.7, radius * 0.18, radius * 0.4)
		jaw.position = Vector3(0.0, -radius * 0.15, -radius * 1.05)
	if g["aqua"] > 0.5:
		var fin := _part(_torso, Planet3D.sphere_mesh(radius * 0.5), dark)
		fin.scale = Vector3(0.15, 0.9, 1.0)
		fin.position = Vector3(0.0, 0.0, radius * 1.25)

	# A glowing ring at the feet marks you out among kin that look just like you.
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 1.5
	ring.outer_radius = radius * 1.7
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.95, 0.6, 0.8)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_part(self, ring, glow).position = Vector3(0.0, -stand + 0.05, 0.0)


## Face the direction of travel and swing the legs with speed. vel is in sim units per tick.
func animate(vel: Vector2, dt: float) -> void:
	var v := vel.length()
	if v > 0.05:
		# sim heading h maps to (cos h, 0, sin h); a node with rotation.y = t faces (-sin t, 0, -cos t)
		var h := vel.angle()
		rotation.y = lerp_angle(rotation.y, atan2(-cos(h), -sin(h)), clampf(dt * 10.0, 0.0, 1.0))
	_phase += dt * v * 9.0
	var swing := clampf(v, 0.0, 1.0) * 0.45
	for i in _legs.size():
		_legs[i].rotation.y = sin(_phase + i * PI) * swing
	if _torso != null:
		_torso.position.y = absf(sin(_phase)) * rad * 0.08 * clampf(v, 0.0, 1.0)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


static func _part(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi

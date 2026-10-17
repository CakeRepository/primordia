class_name CreatureModel
extends Node3D
## The player's body, built from its genome: torso, eyes (bigger with better senses), legs,
## spikes, jaws for carnivores and a tail fin for swimmers. Local forward is -Z.

var rad := 0.6 # body radius in metres
var stand := 0.6 # height of the body centre above the ground
var floating := false
var _body: MeshInstance3D
var _shape := Vector3.ONE
var _pulse := 1.0 # body pulses per second: fast metabolisms throb, slow ones barely breathe
var _legs: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _torso: Node3D
var _phase := 0.0


## shape is the world's body proportions (width, height, length); marker draws the ring that
## picks the player out in a crowd.
func build(g: Dictionary, radius: float, shape := Vector3.ONE, marker := true) -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_legs.clear()
	_tail.clear()
	rad = radius
	floating = Genome.floats(g)
	var col := Planet3D.body_color(g)
	var skin := _mat(col)
	var dark := _mat(col.darkened(0.35))
	_torso = Node3D.new()
	add_child(_torso)
	if g["temp"] > 0.7: # heat-lovers glow warm
		skin.emission_enabled = true
		skin.emission = Color(1.0, 0.38, 0.05)
		skin.emission_energy_multiplier = 0.6 + (g["temp"] - 0.7) * 3.0
	var body := _part(_torso, Planet3D.sphere_mesh(radius), skin)
	body.scale = shape
	_body = body
	_shape = shape
	_pulse = 0.5 + g["metab"] * 3.0
	if g["temp"] < 0.3: # cold-lovers grow frost crystals
		var crystal := Planet3D.cylinder_mesh(0.0, radius * 0.09, radius * 0.3)
		var frost := _mat(Color(0.88, 0.95, 1.0))
		for i in 7:
			var a := i * 2.39996
			var dir := Vector3(cos(a) * 0.6, 0.75, sin(a) * 0.6).normalized()
			var c := _part(_torso, crystal, frost)
			c.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * radius * 0.95)

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
	stand = radius * 1.5 if floating else maxf(radius * 0.9, reach)

	if g["speed"] > 0.65: # a flagellum: a whip of segments behind the body
		var seg := Planet3D.sphere_mesh(radius * 0.13)
		var parent: Node3D = _torso
		for i in 5:
			var link := Node3D.new()
			link.position = Vector3(0.0, 0.0, radius * (1.05 if i == 0 else 0.32))
			parent.add_child(link)
			_part(link, seg, dark)
			_tail.append(link)
			parent = link

	var cone := Planet3D.cylinder_mesh(0.0, radius * 0.16, radius * 0.5)
	var n := roundi(g["spikes"] * 10.0)
	for i in n:
		var y := 0.9 - (i + 0.5) / maxf(n, 1.0) * 1.0
		var a := i * 2.39996
		var dir := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
		var spike := _part(_torso, cone, dark)
		spike.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * radius * 1.1)

	if g["diet"] > 0.5: # a maw with teeth
		var mouth := _part(_torso, Planet3D.sphere_mesh(radius * 0.34), _mat(Color(0.14, 0.03, 0.05)))
		mouth.scale = Vector3(1.3, 0.6, 0.5)
		mouth.position = Vector3(0.0, -radius * 0.12, -radius * 0.93)
		var tooth := Planet3D.cylinder_mesh(0.0, radius * 0.06, radius * 0.17)
		var ivory := _mat(Color(0.96, 0.93, 0.84))
		for i in 4:
			var t := _part(_torso, tooth, ivory)
			t.position = Vector3((i - 1.5) * radius * 0.13, -radius * 0.03, -radius * 1.06)
			t.rotation_degrees.x = 180.0 # pointing down from the upper lip
	if g["aqua"] > 0.5:
		var fin := _part(_torso, Planet3D.sphere_mesh(radius * 0.5), dark)
		fin.scale = Vector3(0.15, 0.9, 1.0)
		fin.position = Vector3(0.0, 0.0, radius * 1.25)

	if not marker:
		return
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
		if floating: # drift up and down whether moving or not
			_torso.position.y = sin(Time.get_ticks_msec() * 0.002) * rad * 0.18
		else:
			_torso.position.y = absf(sin(_phase)) * rad * 0.08 * clampf(v, 0.0, 1.0)
	if _body != null:
		_body.scale = _shape * (1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.001 * TAU * _pulse))
	var t := Time.get_ticks_msec() * 0.012
	for i in _tail.size():
		_tail[i].rotation.y = sin(t - i * 0.9) * 0.35


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

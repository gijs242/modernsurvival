class_name Dog
extends Soldier
## Attack dog: procedural low-poly quadruped with a gallop cycle. Shares the Soldier interface
## (setup / animate / die / muzzle_flash) so Enemy and the corpse handling treat it like any other body.

var body_n: Node3D
var head_n: Node3D
var tail: Node3D
var legs4: Array = []


func setup(p_style: String, _p_gun: String) -> void:
	style = p_style
	gun_id = "none"
	knife = true
	var fur := Mat.pbr("fabric", Color(0.2, 0.15, 0.1), 0.95, 0.0, 6.0)
	var dark := Mat.pbr("fabric", Color(0.07, 0.06, 0.05), 0.95, 0.0, 6.0)
	var harness := Mat.solid(Color(0.12, 0.12, 0.1), 0.8)
	body_n = Node3D.new()
	body_n.position.y = 0.55
	add_child(body_n)
	_ell(body_n, fur, Vector3(0.28, 0.3, 0.78), Vector3(0, 0, 0.02))                 # torso
	_ell(body_n, fur, Vector3(0.3, 0.33, 0.36), Vector3(0, 0.03, -0.22))             # chest
	_rb(body_n, harness, Vector3(0.3, 0.12, 0.3), Vector3(0, 0.08, -0.12), 0.04)
	head_n = Node3D.new()
	head_n.position = Vector3(0, 0.2, -0.45)
	body_n.add_child(head_n)
	_ell(head_n, fur, Vector3(0.18, 0.2, 0.22), Vector3.ZERO)
	_ell(head_n, dark, Vector3(0.1, 0.1, 0.2), Vector3(0, -0.04, -0.16))            # muzzle
	for x in [-0.06, 0.06]:
		_ell(head_n, dark, Vector3(0.05, 0.12, 0.04), Vector3(x, 0.13, 0.03), Vector3(-0.3, 0, 0))   # ears
	tail = Node3D.new()
	tail.position = Vector3(0, 0.06, 0.4)
	body_n.add_child(tail)
	_part(tail, Shapes.capsule(0.03, 0.32), fur, Vector3(0, 0, 0.14), Vector3(PI / 2 - 0.5, 0, 0))
	for z in [-0.26, 0.28]:
		for x in [-0.09, 0.09]:
			var hip := Node3D.new()
			hip.position = Vector3(x, -0.05, z)
			body_n.add_child(hip)
			_part(hip, Shapes.capsule(0.045, 0.3), fur, Vector3(0, -0.14, 0))
			var low := Node3D.new()
			low.position.y = -0.27
			hip.add_child(low)
			_part(low, Shapes.capsule(0.032, 0.27), dark, Vector3(0, -0.12, 0))
			legs4.append({"hip": hip, "low": low, "front": z < 0, "side": x})
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func animate(dt: float, mv: bool, speed: float, state: int, t: float) -> void:
	if dead:
		return
	phase += dt * (speed * 1.9 if mv else 0.0)
	leg_blend = move_toward(leg_blend, 1.0 if mv else 0.0, dt * 6.0)
	for l in legs4:
		var off: float = 0.0 if l.front else PI * 0.6
		off += 0.35 if l.side > 0 else 0.0
		(l.hip as Node3D).rotation.x = sin(phase + off) * 0.75 * leg_blend
		(l.low as Node3D).rotation.x = (max(0.0, sin(phase + off + 1.3)) * 0.9 if l.front else -max(0.0, sin(phase + off + 1.3)) * 0.9) * leg_blend
	body_n.position.y = 0.55 + abs(sin(phase)) * 0.05 * leg_blend
	body_n.rotation.x = sin(phase) * 0.08 * leg_blend
	head_n.rotation.x = -0.35 if state == 2 else sin(t * 2.0) * 0.05
	tail.rotation.y = sin(t * 9.0) * 0.4


func muzzle_flash() -> void:
	pass


func die(dir: Vector3, _explosive: bool) -> void:
	dead = true
	death_t = 0.0
	death_dir = 1.0 if dir.dot(global_transform.basis.x) > 0.0 else -1.0


func _animate_death(dt: float) -> void:
	death_t += dt
	rotation.z = lerp(rotation.z, death_dir * PI / 2, min(1.0, dt * 8.0))
	position.y = lerp(position.y, 0.12, min(1.0, dt * 8.0))
	for l in legs4:
		(l.hip as Node3D).rotation.x = lerp((l.hip as Node3D).rotation.x, 0.3 if l.front else -0.3, dt * 4.0)
	_sink(dt)

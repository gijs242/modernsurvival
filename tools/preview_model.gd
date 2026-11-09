extends SceneTree
## Dev tool: renders a model from the side.  godot --path . -s tools/preview_model.gd -- <res path> <out.png>

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new()
	get_root().add_child(root)
	var m: Node3D = (load(a[0]) as PackedScene).instantiate()
	root.add_child(m)
	for n in m.get_children():
		print(n.name, " ", n.position)
	var cam := Camera3D.new()
	cam.position = Vector3(float(a[2]) if a.size() > 2 else 0.05, 0.05, float(a[3]) if a.size() > 3 else 0.6)
	cam.fov = 40
	root.add_child(cam)
	cam.current = true
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-30, 20, 0)
	root.add_child(l)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.5, 0.55)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	for i in 30:
		await process_frame
	get_root().get_texture().get_image().save_png(a[1])
	quit()

extends Node3D

@export var grass_count := 200
@export var prop_count := 50
@export var scatter_radius := 800.0

var grass_scene: PackedScene
var prop_scenes: Array[PackedScene] = []

func _ready():
	print("GroundDecorator ready!")
	
	# Load grass
	grass_scene = load("res://assets/glb/SR_Prop_Grass.glb")
	
	# Load some variety props
	prop_scenes.append(load("res://assets/glb/SR_Prop_Cone.glb"))
	prop_scenes.append(load("res://assets/glb/SR_Prop_Barrel.glb"))
	prop_scenes.append(load("res://assets/glb/SR_Prop_Flag_01.glb"))
	prop_scenes.append(load("res://assets/glb/SR_Prop_DirtPile_01.glb"))
	
	# Wait a frame for everything to be ready
	await get_tree().process_frame
	
	# Scatter grass
	_scatter_grass()
	
	# Scatter props
	_scatter_props()
	
	# Apply materials
	_apply_materials()
	
	print("GroundDecorator complete!")

func _scatter_grass():
	if not grass_scene:
		return
	
	var grass_parent = Node3D.new()
	grass_parent.name = "GrassPatches"
	add_child(grass_parent)
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(grass_count):
		var angle = rng.randf() * TAU
		var distance = rng.randf() * scatter_radius
		var x = cos(angle) * distance
		var z = sin(angle) * distance
		
		var grass_instance = grass_scene.instantiate()
		grass_instance.name = "Grass" + str(i)
		grass_instance.transform.origin = Vector3(x, 0, z)
		
		# Random rotation
		grass_instance.rotate_y(rng.randf() * TAU)
		
		# Random scale variation
		var scale_val = rng.randf_range(0.8, 1.2)
		grass_instance.scale = Vector3(scale_val, scale_val, scale_val)
		
		grass_parent.add_child(grass_instance)

func _scatter_props():
	if prop_scenes.is_empty():
		return
	
	var props_parent = Node3D.new()
	props_parent.name = "ScatteredProps"
	add_child(props_parent)
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(prop_count):
		var angle = rng.randf() * TAU
		var distance = rng.randf_range(50, scatter_radius)  # Keep some distance from center
		var x = cos(angle) * distance
		var z = sin(angle) * distance
		
		# Pick random prop
		var prop_scene = prop_scenes[rng.randi() % prop_scenes.size()]
		var prop_instance = prop_scene.instantiate()
		prop_instance.name = "Prop" + str(i)
		prop_instance.transform.origin = Vector3(x, 0, z)
		
		# Random rotation
		prop_instance.rotate_y(rng.randf() * TAU)
		
		# Add prop to parent first, then add collision
		props_parent.add_child(prop_instance)
		
		# Add collision to props (cones, barrels, flags) after adding to parent
		_add_prop_collision(prop_instance)

func _apply_materials():
	var material = load("res://assets/synty_generic.tres")
	if not material:
		return
	
	# Apply to all grass
	var grass_parent = get_node_or_null("GrassPatches")
	if grass_parent:
		_apply_material_recursive(grass_parent, material)
	
	# Apply to all props
	var props_parent = get_node_or_null("ScatteredProps")
	if props_parent:
		_apply_material_recursive(props_parent, material)

func _apply_material_recursive(node: Node, material: Material):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var mesh = mesh_instance.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(i, material)
	
	for child in node.get_children():
		_apply_material_recursive(child, material)

func _add_prop_collision(prop_instance: Node):
	# Wait a frame for prop to be fully added to scene
	await get_tree().process_frame
	
	var parent = prop_instance.get_parent()
	if not parent:
		return
	
	# Wrap in StaticBody3D if not already
	var static_body: StaticBody3D
	if parent is StaticBody3D:
		static_body = parent as StaticBody3D
	else:
		static_body = StaticBody3D.new()
		static_body.name = prop_instance.name + "Body"
		static_body.transform = prop_instance.transform
		
		parent.remove_child(prop_instance)
		prop_instance.transform = Transform3D.IDENTITY
		static_body.add_child(prop_instance)
		parent.add_child(static_body)
	
	# Wait for mesh to load, then add collision
	await get_tree().process_frame
	_find_and_add_collision_to_prop(prop_instance, static_body)

func _find_and_add_collision_to_prop(node: Node, static_body: StaticBody3D):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var mesh = mesh_instance.mesh
		if mesh and mesh is ArrayMesh:
			var array_mesh = mesh as ArrayMesh
			var surface_count = array_mesh.get_surface_count()
			if surface_count > 0:
				# Check if collision already exists
				if static_body.get_node_or_null("CollisionShape3D"):
					return  # Already has collision
				
				# Collect vertices from all surfaces
				var all_vertices = PackedVector3Array()
				for surface_idx in range(surface_count):
					var arrays = array_mesh.surface_get_arrays(surface_idx)
					if arrays and arrays.size() > ArrayMesh.ARRAY_VERTEX:
						var vertices = arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array
						if vertices and vertices.size() > 0:
							all_vertices.append_array(vertices)
				
				if all_vertices.size() > 0:
					# Add collision shape
					var collision_shape = CollisionShape3D.new()
					var convex_shape = ConvexPolygonShape3D.new()
					convex_shape.set_points(all_vertices)
					collision_shape.shape = convex_shape
					static_body.add_child(collision_shape)
					return
	
	# Recursively check children
	for child in node.get_children():
		_find_and_add_collision_to_prop(child, static_body)

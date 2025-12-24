extends Node3D

@export var chunk_size: int = 128
@export var view_distance: int = 3  # 3x3 chunks = smaller, more manageable
@export var height_scale: float = 8.0  # Much flatter terrain
@export var noise_frequency: float = 0.015  # Lower frequency = smoother, rolling hills
@export var grass_per_chunk: int = 30  # Reduced for performance
@export var props_per_chunk: int = 5  # Reduced for performance
@export var mesh_resolution: int = 64  # Balanced resolution for performance and smoothness

var noise: FastNoiseLite
var chunks: Dictionary = {}  # key: Vector2i(chunk_x, chunk_z) -> Node3D chunk
var player_car: RigidBody3D
var material: Material  # For terrain
var prop_material: Material  # For props and grass (with texture)
var grass_scene: PackedScene
var prop_scenes: Array[PackedScene] = []

func _ready():
	# Setup noise
	noise = FastNoiseLite.new()
	noise.seed = 123  # Fixed seed = same world always
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED  # Sharper but smoother hills
	noise.fractal_octaves = 4
	
	# Create simple green material for terrain (no texture, just green shades)
	var terrain_mat = StandardMaterial3D.new()
	terrain_mat.albedo_color = Color(0.25, 0.75, 0.25)  # Nice green
	terrain_mat.roughness = 0.9
	terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Render both sides
	material = terrain_mat
	
	# Load texture material for props and grass
	prop_material = load("res://assets/synty_generic.tres")
	if not prop_material:
		prop_material = terrain_mat  # Fallback to green if texture not found
	
	# Load grass and props
	grass_scene = load("res://assets/glb/SR_Prop_Grass.glb")
	prop_scenes.append(load("res://assets/glb/SR_Prop_Cone.glb"))
	prop_scenes.append(load("res://assets/glb/SR_Prop_Barrel.glb"))
	prop_scenes.append(load("res://assets/glb/SR_Prop_Flag_01.glb"))
	prop_scenes.append(load("res://assets/glb/SR_Prop_DirtPile_01.glb"))
	
	# Generate initial chunks around origin (0,0) immediately - BEFORE waiting for car
	# This ensures terrain exists when car spawns
	_generate_initial_chunks()
	
	# Wait for player car
	await get_tree().process_frame
	player_car = get_tree().get_first_node_in_group("player_car")
	
	if player_car:
		# Continue updating chunks
		await get_tree().process_frame
		update_chunks()

func _generate_initial_chunks():
	# Generate chunks around origin (0,0) immediately so player has terrain to land on
	var center = Vector2i(0, 0)
	var chunks_generated = 0
	for x in range(center.x - view_distance, center.x + view_distance + 1):
		for z in range(center.y - view_distance, center.y + view_distance + 1):
			var coord = Vector2i(x, z)
			if not chunks.has(coord):
				generate_chunk(coord)
				chunks_generated += 1
				# Small delay to prevent frame drops
				if chunks_generated % 3 == 0:
					await get_tree().process_frame
	print("Generated ", chunks_generated, " initial chunks around origin")

var last_update_time := 0.0
var update_interval := 0.5  # Only update chunks every 0.5 seconds

func _process(delta):
	last_update_time += delta
	if last_update_time >= update_interval:
		update_chunks()
		last_update_time = 0.0

func update_chunks():
	if not player_car:
		return
	
	var car_pos = player_car.global_position
	var center_chunk = Vector2i(int(car_pos.x / chunk_size), int(car_pos.z / chunk_size))
	
	# Unload far chunks (more aggressive unloading)
	var to_unload = []
	for chunk_coord in chunks:
		var dist = (chunk_coord - center_chunk).length()
		if dist > view_distance:  # Unload immediately when out of range
			to_unload.append(chunk_coord)
	
	for coord in to_unload:
		if chunks.has(coord) and is_instance_valid(chunks[coord]):
			chunks[coord].queue_free()
		chunks.erase(coord)
	
	# Load/generate nearby chunks (limit generation per frame)
	var chunks_to_generate = []
	for x in range(center_chunk.x - view_distance, center_chunk.x + view_distance + 1):
		for z in range(center_chunk.y - view_distance, center_chunk.y + view_distance + 1):
			var coord = Vector2i(x, z)
			if not chunks.has(coord):
				chunks_to_generate.append(coord)
	
	# Only generate 1 chunk per update to spread load
	if chunks_to_generate.size() > 0:
		generate_chunk(chunks_to_generate[0])

func generate_chunk(coord: Vector2i):
	var chunk = Node3D.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	# Position chunk at world coordinates (Y=0, height is in vertices)
	var world_x = coord.x * chunk_size
	var world_z = coord.y * chunk_size
	chunk.position = Vector3(world_x, 0, world_z)
	add_child(chunk)
	chunks[coord] = chunk
	print("Generated chunk at world pos: ", chunk.position, " coord: ", coord)
	
	# Generate mesh with SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate vertices (lower resolution for performance)
	var res = mesh_resolution
	
	for i in range(res + 1):
		for j in range(res + 1):
			var x = i * chunk_size / float(res)
			var z = j * chunk_size / float(res)
			var noise_x = coord.x * chunk_size + x - chunk_size/2.0
			var noise_z = coord.y * chunk_size + z - chunk_size/2.0
			var height = noise.get_noise_2d(noise_x, noise_z) * height_scale
			
			var pos = Vector3(x - chunk_size/2.0, height, z - chunk_size/2.0)
			st.set_uv(Vector2(i / float(res), j / float(res)))
			st.add_vertex(pos)
	
	# Generate indices (triangles)
	for i in range(res):
		for j in range(res):
			var a = i * (res + 1) + j
			var b = a + (res + 1)
			var c = a + 1
			var d = b + 1
			
			# First triangle
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			
			# Second triangle
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	
	# Generate normals
	st.generate_normals()
	
	# Commit mesh
	var mesh = st.commit()
	
	# Create mesh instance
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	
	# Apply simple green material
	if material:
		mesh_inst.set_surface_override_material(0, material)
	else:
		# Fallback - should never happen but just in case
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.75, 0.25)
		mat.roughness = 0.9
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.set_surface_override_material(0, mat)
	
	chunk.add_child(mesh_inst)
	
	# Create collision - use HeightMapShape3D for ultra-smooth terrain collision
	var static_body = StaticBody3D.new()
	static_body.name = "Collision"
	static_body.collision_layer = 1  # Ground layer
	static_body.collision_mask = 0  # Don't collide with other static bodies
	
	# Generate height map data for HeightMapShape3D
	# Reuse res variable from above
	var map_size = res + 1  # 129x129 for res=128
	var heights = []
	heights.resize(map_size * map_size)
	
	for i in range(map_size):
		for j in range(map_size):
			var x_local = i * chunk_size / float(res)
			var z_local = j * chunk_size / float(res)
			var noise_x = coord.x * chunk_size + x_local - chunk_size/2.0
			var noise_z = coord.y * chunk_size + z_local - chunk_size/2.0
			# Normalize noise to 0-1 range, then scale by height_scale
			var height = (noise.get_noise_2d(noise_x, noise_z) + 1.0) / 2.0 * height_scale
			heights[i * map_size + j] = height
	
	# Create HeightMapShape3D
	var height_map_shape = HeightMapShape3D.new()
	height_map_shape.map_width = map_size
	height_map_shape.map_height = map_size
	height_map_shape.map_data = PackedFloat32Array(heights)
	height_map_shape.map_depth = 100.0
	height_map_shape.map_resolution = 1.0
	
	var col_shape = CollisionShape3D.new()
	col_shape.shape = height_map_shape
	# Position collision shape to match mesh
	col_shape.transform.origin = Vector3(-chunk_size/2.0, 0, -chunk_size/2.0)
	static_body.add_child(col_shape)
	chunk.add_child(static_body)
	print("Terrain HeightMap collision created for chunk ", coord)
	
	# Scatter grass and props on this chunk
	_scatter_on_chunk(chunk, coord)

func _scatter_on_chunk(chunk: Node3D, coord: Vector2i):
	if not grass_scene or prop_scenes.is_empty():
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(coord.x) + "_" + str(coord.y))  # Deterministic per chunk
	
	# Scatter grass
	var grass_parent = Node3D.new()
	grass_parent.name = "Grass"
	chunk.add_child(grass_parent)
	
	for i in range(grass_per_chunk):
		var x = rng.randf_range(-chunk_size/2.0, chunk_size/2.0)
		var z = rng.randf_range(-chunk_size/2.0, chunk_size/2.0)
		var world_x = coord.x * chunk_size + x
		var world_z = coord.y * chunk_size + z
		
		# Get height at this position
		var height = noise.get_noise_2d(world_x, world_z) * height_scale
		
		var grass_instance = grass_scene.instantiate()
		grass_instance.name = "Grass" + str(i)
		grass_instance.transform.origin = Vector3(x, height, z)
		grass_instance.rotate_y(rng.randf() * TAU)
		var scale_val = rng.randf_range(0.8, 1.2)
		grass_instance.scale = Vector3(scale_val, scale_val, scale_val)
		grass_parent.add_child(grass_instance)
		
		# Apply texture material to grass
		if prop_material:
			_apply_material_recursive(grass_instance, prop_material)
	
	# Scatter props
	var props_parent = Node3D.new()
	props_parent.name = "Props"
	chunk.add_child(props_parent)
	
	for i in range(props_per_chunk):
		var x = rng.randf_range(-chunk_size/2.0, chunk_size/2.0)
		var z = rng.randf_range(-chunk_size/2.0, chunk_size/2.0)
		var world_x = coord.x * chunk_size + x
		var world_z = coord.y * chunk_size + z
		
		# Get height at this position
		var height = noise.get_noise_2d(world_x, world_z) * height_scale
		
		var prop_scene = prop_scenes[rng.randi() % prop_scenes.size()]
		var prop_instance = prop_scene.instantiate()
		prop_instance.name = "Prop" + str(i)
		prop_instance.transform.origin = Vector3(x, height, z)
		prop_instance.rotate_y(rng.randf() * TAU)
		props_parent.add_child(prop_instance)
		
		# Apply texture material to props
		if prop_material:
			_apply_material_recursive(prop_instance, prop_material)
		# Add collision to props (cones, barrels, flags)
		_add_prop_collision(prop_instance)

func _apply_material_recursive(node: Node, mat: Material):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var mesh = mesh_instance.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(i, mat)
	
	for child in node.get_children():
		_apply_material_recursive(child, mat)

func _add_prop_collision(prop_instance: Node):
	# Wait a frame for prop to be fully added
	await get_tree().process_frame
	
	# Check if prop is still valid
	if not is_instance_valid(prop_instance):
		return
	
	var parent = prop_instance.get_parent()
	if not parent or not is_instance_valid(parent):
		return
	
	# Wrap in StaticBody3D
	var static_body = StaticBody3D.new()
	static_body.name = prop_instance.name + "Body"
	static_body.transform = prop_instance.transform
	
	parent.remove_child(prop_instance)
	prop_instance.transform = Transform3D.IDENTITY
	static_body.add_child(prop_instance)
	parent.add_child(static_body)
	
	# Wait for mesh, then add collision
	await get_tree().process_frame
	_find_and_add_collision_to_prop(prop_instance, static_body)

func get_height_at(world_x: float, world_z: float) -> float:
	# Get terrain height at world coordinates using noise
	return noise.get_noise_2d(world_x, world_z) * height_scale

func _find_and_add_collision_to_prop(node: Node, static_body: StaticBody3D):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var mesh = mesh_instance.mesh
		if mesh and mesh is ArrayMesh:
			var array_mesh = mesh as ArrayMesh
			var surface_count = array_mesh.get_surface_count()
			if surface_count > 0:
				if static_body.get_node_or_null("CollisionShape3D"):
					return
				
				var all_vertices = PackedVector3Array()
				for surface_idx in range(surface_count):
					var arrays = array_mesh.surface_get_arrays(surface_idx)
					if arrays and arrays.size() > ArrayMesh.ARRAY_VERTEX:
						var vertices = arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array
						if vertices and vertices.size() > 0:
							all_vertices.append_array(vertices)
				
				if all_vertices.size() > 0:
					var collision_shape = CollisionShape3D.new()
					var convex_shape = ConvexPolygonShape3D.new()
					convex_shape.set_points(all_vertices)
					collision_shape.shape = convex_shape
					static_body.add_child(collision_shape)
					return
	
	for child in node.get_children():
		_find_and_add_collision_to_prop(child, static_body)

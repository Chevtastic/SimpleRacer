extends Node3D

var is_paused := false

func _ready():
	print("Main scene ready!")
	
	# CRITICAL: Ensure game is NOT paused
	get_tree().paused = false
	
	# Setup pause menu
	var pause_menu = get_node_or_null("UI/PauseMenu")
	if pause_menu:
		pause_menu.visible = false
	
	# Wait for TerrainManager to generate initial chunks
	var terrain_manager = get_node_or_null("TerrainManager")
	if terrain_manager:
		# Give terrain time to generate initial chunks at origin
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		print("Terrain should be ready")
	
	# Get player car
	var player_car = get_node_or_null("PlayerCar")
	if not player_car:
		print("ERROR: PlayerCar not found!")
		return
	
	print("PlayerCar found!")
	
	# Ensure PlayerCar is in the group for speedometer
	player_car.add_to_group("player_car")
	
	# Add temporary box collision first
	var collision_shape = player_car.get_node_or_null("CollisionShape3D")
	if collision_shape:
		if not collision_shape.shape:
			var box_shape = BoxShape3D.new()
			box_shape.size = Vector3(2, 1, 3)
			collision_shape.shape = box_shape
			print("Added box collision to player car")
	
	# Load selected vehicle from GameSettings
	var vehicle_path = GameSettings.selected_vehicle_path
	print("Selected vehicle: ", vehicle_path)
	
	if vehicle_path.is_empty() or not ResourceLoader.exists(vehicle_path):
		vehicle_path = "res://assets/glb/SR_Veh_Kart_Orange.glb"
		print("Using default vehicle")
	
	# Load vehicle mesh
	var vehicle_scene = load(vehicle_path)
	if vehicle_scene:
		var car_mesh = vehicle_scene.instantiate()
		car_mesh.name = "CarMesh"
		
		# Rotate car 180 degrees on Y axis to fix backwards orientation
		car_mesh.rotate_y(PI)
		
		player_car.add_child(car_mesh)
		print("Vehicle mesh loaded: ", vehicle_path.get_file())
		
		# Adjust camera height based on vehicle type
		await get_tree().process_frame
		_adjust_camera_for_vehicle(vehicle_path, player_car)
		
		# Apply material
		var material = load("res://assets/synty_generic.tres")
		if material:
			_apply_material(car_mesh, material)
	else:
		print("ERROR: Could not load vehicle!")
	
	# Wait for terrain to generate, then place car on ground
	# Give terrain manager time to generate initial chunks and collision
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frames for terrain chunks and collision to fully generate
	
	# Raycast to find terrain height - try multiple times with longer wait
	for attempt in range(10):
		await get_tree().process_frame
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(Vector3(0, 100, 0), Vector3(0, -200, 0))
		query.collision_mask = 1  # Ground layer
		var result = space_state.intersect_ray(query)
		
		if result:
			player_car.transform.origin = Vector3(0, result.position.y + 2, 0)
			player_car.linear_velocity = Vector3.ZERO
			player_car.angular_velocity = Vector3.ZERO
			print("Car placed on terrain at height: ", result.position.y, " (attempt ", attempt + 1, ")")
			break
		elif attempt == 9:
			# Fallback if no terrain found after all attempts
			# Use noise to get approximate height at origin
			# Reuse terrain_manager variable from earlier
			if terrain_manager and terrain_manager.has_method("get_height_at"):
				var height = terrain_manager.get_height_at(0, 0)
				player_car.transform.origin = Vector3(0, height + 2, 0)
				print("Car placed using noise height: ", height)
			else:
				player_car.transform.origin = Vector3(0, 5, 0)
				print("No terrain found, using fallback height")
	
	# Ensure car physics are active
	if player_car is RigidBody3D:
		# CRITICAL: Unfreeze the car
		player_car.freeze = false
		player_car.gravity_scale = 1.0
		player_car.mass = 1.0
		# Make sure physics processing is enabled
		player_car.set_physics_process(true)
		player_car.set_process(true)
		print("Car physics enabled - freeze=", player_car.freeze, " gravity=", player_car.gravity_scale)
	
	# Ensure game is not paused
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Verify car is ready
	print("Car freeze status: ", player_car.freeze)
	print("Car physics processing: ", player_car.is_physics_processing())
	print("Game paused: ", get_tree().paused)
	print("Setup complete!")

func _adjust_camera_for_vehicle(vehicle_path: String, player_car: Node):
	var spring_arm = player_car.get_node_or_null("SpringArm3D")
	if not spring_arm:
		return
	
	var vehicle_name = vehicle_path.get_file().to_lower()
	var camera_height = 2.5  # Default height
	var spring_length = 15.0  # Default length
	
	# Adjust based on vehicle type
	if "monster" in vehicle_name or "truck" in vehicle_name:
		camera_height = 4.5  # Higher for tall vehicles
		spring_length = 18.0
	elif "f1" in vehicle_name or "sports" in vehicle_name or "super" in vehicle_name:
		camera_height = 3.0  # Medium height
		spring_length = 16.0
	elif "kart" in vehicle_name:
		camera_height = 2.0  # Lower for karts
		spring_length = 14.0
	else:
		camera_height = 2.5  # Default
		spring_length = 15.0
	
	# Update SpringArm3D
	spring_arm.transform.origin.y = camera_height
	spring_arm.spring_length = spring_length
	
	# Reset camera rotation to default view
	if spring_arm.has_method("reset_rotation"):
		spring_arm.reset_rotation()
	
	print("Camera adjusted: height=", camera_height, " length=", spring_length)

func _apply_material(node: Node, material: Material):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			for i in range(mesh_instance.mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(i, material)
	for child in node.get_children():
		_apply_material(child, material)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle_pause_menu()

func toggle_pause_menu():
	is_paused = !is_paused
	var pause_menu = get_node_or_null("UI/PauseMenu")
	if pause_menu:
		pause_menu.visible = is_paused
		get_tree().paused = is_paused
		
		# Reset mouse mode when pausing/unpausing
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

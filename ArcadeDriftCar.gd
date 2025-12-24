extends RigidBody3D

@export var engine_power := 100.0  # Increased for better hill climbing
@export var boost_power := 200.0  # Increased boost
@export var turn_speed := 4.0
@export var drift_trigger := 0.9
@export var handbrake_drift := 0.95
@export var max_speed := 120.0
@export var friction := 0.97
@export var boost_duration := 0.5

# Wheel suspension settings
@export var wheel_suspension: float = 2000.0  # Reduced spring strength to prevent bouncing
@export var wheel_damper: float = 1200.0  # Increased damping to prevent bouncing
@export var wheel_rest_length: float = 1.5

var is_drifting := false
var current_power := engine_power
var drift_smoke: GPUParticles3D
var current_speed := 0.0
signal speed_changed(new_speed: float)

var wheel_rays: Array[RayCast3D] = []

func _ready():
	drift_smoke = get_node_or_null("DriftSmoke")
	# Better physics settings for smooth driving
	gravity_scale = 1.0
	mass = 1.0
	freeze = false  # Ensure not frozen
	set_physics_process(true)  # Ensure physics processing
	set_process_input(true)  # Ensure input processing
	
	# Setup wheel suspension rays
	_setup_wheel_suspension()
	
	# Physics material for smooth contact
	var phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 1.2
	phys_mat.bounce = 0.0
	physics_material_override = phys_mat
	
	# Damping to reduce bouncing
	linear_damp = 2.0
	angular_damp = 3.0
	
	print("ArcadeDriftCar ready - freeze=", freeze)

func _setup_wheel_suspension():
	# Create 4 wheel raycasts: Front Left, Front Right, Rear Left, Rear Right
	var wheel_positions = [
		Vector3(-0.8, -0.5, 1.2),   # FL
		Vector3(0.8, -0.5, 1.2),    # FR
		Vector3(-0.8, -0.5, -1.2),  # RL
		Vector3(0.8, -0.5, -1.2)    # RR
	]
	var wheel_names = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
	
	for i in range(4):
		var ray = RayCast3D.new()
		ray.name = wheel_names[i]
		ray.position = wheel_positions[i]
		ray.target_position = Vector3(0, -2.0, 0)
		ray.enabled = true
		ray.collide_with_areas = false
		ray.collision_mask = 1  # Ground layer
		add_child(ray)
		wheel_rays.append(ray)

func _physics_process(delta):
	# Ensure we're not frozen
	if freeze:
		freeze = false
		print("WARNING: Car was frozen, unfreezing now!")
	
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	
	var throttle = Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
	var steer_input = Input.get_action_strength("ui_left") - Input.get_action_strength("ui_right")
	var boost = Input.is_action_pressed("boost")  # Changed to is_action_pressed for hold
	var handbrake = Input.is_action_pressed("handbrake")
	
	# Debug first frame
	if Engine.get_process_frames() == 1:
		print("Input test - throttle: ", throttle, " steer: ", steer_input)
	
	# Boost - works while holding spacebar
	if boost:
		current_power = boost_power
	else:
		current_power = engine_power
	
	# Get current speed
	var velocity_flat = Vector3(linear_velocity.x, 0, linear_velocity.z)
	var speed = velocity_flat.length()
	current_speed = speed
	speed_changed.emit(speed)
	var right_vel = velocity_flat.dot(right)
	
	# Drifting detection
	if speed > 8.0 and abs(right_vel) > speed * drift_trigger or handbrake:
		if not is_drifting:
			is_drifting = true
			if drift_smoke:
				drift_smoke.start_drift()
		if handbrake:
			apply_central_force(forward * throttle * engine_power * handbrake_drift)
	else:
		if is_drifting:
			is_drifting = false
			if drift_smoke:
				drift_smoke.stop_drift()
	
	# Improved steering - speed-dependent and smoother
	var speed_factor = min(speed / max_speed, 1.0)
	var turn_strength = turn_speed * (0.5 + speed_factor * 0.5)  # Better turning at speed
	
	# Apply steering torque instead of direct angular velocity for smoother control
	var turn_torque = steer_input * turn_strength * (1.0 + speed_factor)
	if is_drifting:
		turn_torque *= 1.5
	angular_velocity.y = lerp(angular_velocity.y, turn_torque, delta * 8.0)
	
	# Lock X and Z rotation (prevent car from flipping)
	angular_velocity.x = lerp(angular_velocity.x, 0.0, delta * 10.0)
	angular_velocity.z = lerp(angular_velocity.z, 0.0, delta * 10.0)
	
	# Engine force - limit max speed
	if speed < max_speed or throttle < 0:
		apply_central_force(forward * throttle * current_power)
	
	# Apply friction/drag
	linear_velocity.x *= friction
	linear_velocity.z *= friction
	
	# WHEEL SUSPENSION SYSTEM - smooth terrain following (replaces old gravity handling)
	var ground_normal = Vector3.UP
	var wheel_hit_count = 0
	var average_wheel_hit_y = 0.0
	
	for wheel_ray in wheel_rays:
		if wheel_ray.is_colliding():
			var hit_point = wheel_ray.get_collision_point()
			var hit_normal = wheel_ray.get_collision_normal()
			
			# Calculate compression (how much spring is compressed)
			var ray_world_pos = wheel_ray.global_position
			var distance_to_ground = ray_world_pos.distance_to(hit_point)
			var compression = wheel_rest_length - distance_to_ground
			
			if compression > 0:  # Spring is compressed
				# Suspension force: spring pushes up, damper resists velocity
				var spring_force = wheel_suspension * compression
				# Clamp compression to prevent excessive forces
				spring_force = clamp(spring_force, 0.0, 5000.0)
				var damper_force = wheel_damper * abs(linear_velocity.y) * sign(linear_velocity.y)
				var suspension_force = spring_force - damper_force
				
				# Clamp total suspension force to prevent launching
				suspension_force = clamp(suspension_force, -1000.0, 3000.0)
				
				# Apply force at wheel position (relative to car center)
				apply_force(Vector3(0, suspension_force, 0), wheel_ray.position)
				
				# Accumulate ground normal and height
				ground_normal = ground_normal.lerp(hit_normal, 0.2)
				average_wheel_hit_y += hit_point.y
				wheel_hit_count += 1
	
	# Anti-float: Smoothly adjust car height to match terrain (less aggressive)
	if wheel_hit_count > 0:
		average_wheel_hit_y /= wheel_hit_count
		var target_y = average_wheel_hit_y + 0.5  # 0.5 units above ground
		# Only adjust if we're significantly off (prevent constant micro-adjustments)
		if abs(global_position.y - target_y) > 0.2:
			global_position.y = lerp(global_position.y, target_y, 0.05)  # Slower, gentler adjustment
		
		# Tilt car to match ground normal (smoothly)
		var current_up = global_transform.basis.y
		var target_up = ground_normal.normalized()
		var new_up = current_up.lerp(target_up, 0.1).normalized()
		
		# Create new basis aligned with ground (reuse existing forward variable)
		var car_forward = -global_transform.basis.z.normalized()
		var car_right = car_forward.cross(new_up).normalized()
		var new_forward_dir = new_up.cross(car_right).normalized()
		
		# Smoothly rotate towards ground using quaternion slerp
		var new_basis = Basis(car_right, new_up, -new_forward_dir)
		var current_quat = Quaternion(global_transform.basis)
		var target_quat = Quaternion(new_basis)
		var lerped_quat = current_quat.slerp(target_quat, 0.1)
		global_transform.basis = Basis(lerped_quat)

# Removed _integrate_forces - was causing issues with steering and stability

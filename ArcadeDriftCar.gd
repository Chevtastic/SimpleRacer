extends RigidBody3D

@export var engine_power := 150.0
@export var boost_power := 250.0
@export var turn_speed := 3.0
@export var air_turn_speed := 1.5
@export var drift_trigger := 0.9
@export var max_speed := 120.0
@export var friction := 0.96

# Ground detection
@export var ground_check_distance := 1.0
@export var hover_height := 0.8
@export var hover_force := 500.0

var is_drifting := false
var current_power := engine_power
var drift_smoke: GPUParticles3D
var current_speed := 0.0
var is_grounded := false
signal speed_changed(new_speed: float)

# Single downward raycast for ground detection
var ground_ray: RayCast3D

func _ready():
	drift_smoke = get_node_or_null("DriftSmoke")
	
	# Physics setup - CRITICAL SETTINGS
	gravity_scale = 0.5  # Reduce gravity effect
	mass = 2.0  # Heavier = more stable
	freeze = false
	
	# NO BOUNCE material
	var phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 2.0
	phys_mat.bounce = 0.0
	physics_material_override = phys_mat
	
	# HEAVY damping to kill oscillations
	linear_damp = 3.0  # Increased
	angular_damp = 5.0  # Increased
	
	# Lock rotation on X and Z axes to PREVENT FLIPPING
	lock_rotation = false  # We'll handle this manually
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	
	# Setup single ground raycast
	ground_ray = RayCast3D.new()
	ground_ray.name = "GroundRay"
	ground_ray.target_position = Vector3(0, -ground_check_distance - 0.5, 0)
	ground_ray.enabled = true
	ground_ray.collide_with_areas = false
	ground_ray.collision_mask = 1
	add_child(ground_ray)
	
	print("ArcadeDriftCar initialized - ANTI-BOUNCE MODE")

func _physics_process(delta):
	if freeze:
		freeze = false
	
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var up = global_transform.basis.y
	
	var throttle = Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
	var steer_input = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var boost = Input.is_action_pressed("boost")
	var handbrake = Input.is_action_pressed("handbrake")
	
	# Boost
	current_power = boost_power if boost else engine_power
	
	# Speed calculation
	var velocity_flat = Vector3(linear_velocity.x, 0, linear_velocity.z)
	var speed = velocity_flat.length()
	current_speed = speed
	speed_changed.emit(speed)
	
	# Ground detection
	is_grounded = ground_ray.is_colliding()
	
	# ANTI-FLIP: Aggressively lock X and Z rotation to keep car upright
	var current_rotation = global_transform.basis.get_euler()
	var target_rotation_x = 0.0
	var target_rotation_z = 0.0
	
	# If car is tilted, force it back upright
	if abs(current_rotation.x) > 0.1 or abs(current_rotation.z) > 0.1:
		angular_velocity.x = lerp(angular_velocity.x, 0.0, delta * 20.0)
		angular_velocity.z = lerp(angular_velocity.z, 0.0, delta * 20.0)
		
		# Directly correct rotation if too extreme
		if abs(current_rotation.x) > 0.3 or abs(current_rotation.z) > 0.3:
			var corrected_basis = Basis()
			corrected_basis = corrected_basis.rotated(Vector3.UP, current_rotation.y)
			global_transform.basis = global_transform.basis.slerp(corrected_basis, delta * 5.0)
	
	if is_grounded:
		# === GROUND MODE ===
		var hit_point = ground_ray.get_collision_point()
		var distance_to_ground = global_position.y - hit_point.y
		
		# Simple hover force - pushes car up if too low, down if too high
		var height_error = hover_height - distance_to_ground
		
		# CRITICAL: Only apply upward force, let gravity handle downward
		if height_error > 0.05:  # Too low
			var upward_force = hover_force * height_error
			# Dampen based on vertical velocity to prevent oscillation
			upward_force -= linear_velocity.y * 200.0
			upward_force = clamp(upward_force, 0.0, 1000.0)
			apply_central_force(Vector3.UP * upward_force)
		elif distance_to_ground > hover_height + 0.3:  # Too high (falling)
			# Extra downward force to stick to ground
			apply_central_force(Vector3.DOWN * 200.0)
		
		# Kill vertical velocity if close to target height (CRITICAL for stopping bounce)
		if abs(height_error) < 0.1 and abs(linear_velocity.y) < 2.0:
			linear_velocity.y = lerp(linear_velocity.y, 0.0, delta * 10.0)
		
		# Steering
		var speed_factor = clamp(speed / max_speed, 0.3, 1.0)
		var turn_amount = steer_input * turn_speed * speed_factor
		
		if is_drifting:
			turn_amount *= 1.4
		
		# Apply steering
		angular_velocity.y = lerp(angular_velocity.y, turn_amount, delta * 8.0)
		
		# Engine force
		if speed < max_speed or throttle < 0:
			apply_central_force(forward * throttle * current_power)
		
		# Ground friction
		linear_velocity.x *= friction
		linear_velocity.z *= friction
		
		# Drift detection
		var right_vel = velocity_flat.dot(right)
		if (speed > 10.0 and abs(right_vel) > speed * drift_trigger) or handbrake:
			if not is_drifting:
				is_drifting = true
				if drift_smoke:
					drift_smoke.start_drift()
		else:
			if is_drifting:
				is_drifting = false
				if drift_smoke:
					drift_smoke.stop_drift()
		
	else:
		# === AIR MODE ===
		if is_drifting:
			is_drifting = false
			if drift_smoke:
				drift_smoke.stop_drift()
		
		# Air steering (yaw)
		var air_turn = steer_input * air_turn_speed
		apply_torque(up * air_turn * 80.0)
		
		# Pitch control
		if throttle != 0:
			apply_torque(right * throttle * 50.0)
		
		# Air brake - press handbrake to level out
		if handbrake:
			angular_velocity.x = lerp(angular_velocity.x, 0.0, delta * 8.0)
			angular_velocity.z = lerp(angular_velocity.z, 0.0, delta * 8.0)
			# Try to level out
			var corrected_basis = Basis()
			corrected_basis = corrected_basis.rotated(Vector3.UP, current_rotation.y)
			global_transform.basis = global_transform.basis.slerp(corrected_basis, delta * 3.0)
		
		# Air drag
		linear_velocity.x *= 0.995
		linear_velocity.z *= 0.995
	
	# Emergency flip recovery - if upside down for more than 1 second, auto-flip
	if up.dot(Vector3.UP) < -0.5:  # Upside down
		# Force car back upright
		var upright_basis = Basis()
		upright_basis = upright_basis.rotated(Vector3.UP, current_rotation.y)
		global_transform.basis = global_transform.basis.slerp(upright_basis, delta * 2.0)
		# Stop all rotation
		angular_velocity = Vector3.ZERO

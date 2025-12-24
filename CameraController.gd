extends SpringArm3D

@export var mouse_sensitivity := 0.003
@export var return_speed := 3.0  # How fast camera returns to default
@export var min_vertical_angle := -80.0  # Degrees - full up look
@export var max_vertical_angle := 80.0   # Degrees - full down look

var horizontal_rotation := 0.0  # Rotation around Y axis (horizontal)
var vertical_rotation := 20.0    # Rotation around X axis (vertical, in degrees)
var is_dragging := false

# Default/target rotations
var default_horizontal := 0.0
var default_vertical := 20.0

var camera_node: Camera3D

func reset_rotation():
	horizontal_rotation = default_horizontal
	vertical_rotation = default_vertical
	_update_rotation()

func _ready():
	# Get camera node
	camera_node = get_node_or_null("Camera3D")
	
	# Set initial rotation to match original camera view
	# Original camera was looking down at about 20 degrees
	horizontal_rotation = 0.0
	vertical_rotation = 20.0
	default_horizontal = 0.0
	default_vertical = 20.0
	_update_rotation()
	
	# Ensure input processing is enabled
	set_process_input(true)
	set_process(true)
	print("CameraController ready - input enabled")

func _process(delta):
	# Smoothly return to default position when not dragging
	if not is_dragging:
		# Lerp back to default rotation
		# Handle horizontal rotation wrapping for smooth return
		var h_diff = default_horizontal - horizontal_rotation
		if abs(h_diff) > PI:
			if h_diff > 0:
				horizontal_rotation += TAU
			else:
				horizontal_rotation -= TAU
		
		horizontal_rotation = lerp(horizontal_rotation, default_horizontal, delta * return_speed)
		vertical_rotation = lerp(vertical_rotation, default_vertical, delta * return_speed)
		_update_rotation()

func _input(event):
	# Release mouse on ESC
	if event.is_action_pressed("ui_cancel"):
		is_dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				is_dragging = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				# Stop dragging
				is_dragging = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	elif event is InputEventMouseMotion and is_dragging:
		# Rotate camera based on mouse movement
		horizontal_rotation -= event.relative.x * mouse_sensitivity
		vertical_rotation -= event.relative.y * mouse_sensitivity
		
		# Clamp vertical rotation
		vertical_rotation = clamp(vertical_rotation, min_vertical_angle, max_vertical_angle)
		
		_update_rotation()

func _update_rotation():
	# Apply horizontal rotation (Y axis) to SpringArm - rotates around the car
	rotation.y = horizontal_rotation
	
	# Apply vertical rotation (X axis) to Camera - looks up/down
	# This rotates the camera relative to the SpringArm
	if camera_node:
		camera_node.rotation.x = deg_to_rad(vertical_rotation)
		camera_node.rotation.z = 0.0  # Keep camera upright
	
	# Reset SpringArm X and Z rotation to keep it upright
	rotation.x = 0.0
	rotation.z = 0.0

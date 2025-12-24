extends Panel

@onready var speed_label: Label = $VBoxContainer/SpeedLabel

func _ready():
	# Wait a frame for everything to be ready
	await get_tree().process_frame
	
	# Connect to player car speed signal
	var player_car = get_tree().get_first_node_in_group("player_car")
	if not player_car:
		# Try to find it by path
		player_car = get_node_or_null("/root/World/PlayerCar")
	
	if player_car and player_car.has_signal("speed_changed"):
		player_car.speed_changed.connect(_on_speed_changed)
		print("Speedometer connected to player car")

func _on_speed_changed(speed: float):
	if speed_label:
		speed_label.text = str(int(speed))


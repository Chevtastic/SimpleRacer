extends Control

var vehicle_categories = {
	"Kart": ["SR_Veh_Kart_Orange.glb", "SR_Veh_Kart_Red.glb", "SR_Veh_Kart_Blue.glb", "SR_Veh_Kart_Green.glb"],
	"F1 Car": ["SR_Veh_F1Car_Orange.glb", "SR_Veh_F1Car_Red.glb", "SR_Veh_F1Car_Blue.glb", "SR_Veh_F1Car_Yellow.glb"],
	"Muscle Car": ["SR_Veh_MuscleCar_Orange.glb", "SR_Veh_MuscleCar_Red.glb", "SR_Veh_MuscleCar_Blue.glb", "SR_Veh_MuscleCar_Black.glb"],
	"Monster Truck": ["SR_Veh_MonsterTruck_Orange.glb", "SR_Veh_MonsterTruck_Red.glb", "SR_Veh_MonsterTruck_Blue.glb", "SR_Veh_MonsterTruck_Yellow.glb"]
}

var selected_vehicle: String = "res://assets/glb/SR_Veh_Kart_Orange.glb"

func _ready():
	print("Vehicle Selector ready!")
	var vehicle_grid = $VBoxContainer/ScrollContainer/GridContainer
	var start_button = $VBoxContainer/StartButton
	
	if not vehicle_grid or not start_button:
		print("ERROR: UI elements not found!")
		return
	
	# Populate grid
	for category in vehicle_categories:
		var category_label = Label.new()
		category_label.text = category
		category_label.add_theme_font_size_override("font_size", 20)
		vehicle_grid.add_child(category_label)
		
		for vehicle in vehicle_categories[category]:
			var button = Button.new()
			button.text = vehicle.replace("SR_Veh_", "").replace(".glb", "").replace("_", " ")
			button.custom_minimum_size = Vector2(180, 40)
			var vehicle_path = "res://assets/glb/" + vehicle
			button.pressed.connect(_on_vehicle_selected.bind(vehicle_path, button))
			vehicle_grid.add_child(button)
	
	start_button.pressed.connect(_on_start_pressed)
	print("Vehicle selector initialized with ", vehicle_categories.size(), " categories")

func _on_vehicle_selected(vehicle_path: String, button: Button):
	selected_vehicle = vehicle_path
	print("Selected: ", vehicle_path)
	
	# Visual feedback - highlight selected
	var vehicle_grid = $VBoxContainer/ScrollContainer/GridContainer
	for child in vehicle_grid.get_children():
		if child is Button:
			child.modulate = Color.WHITE
	button.modulate = Color(0.5, 1.0, 0.5)

func _on_start_pressed():
	print("Starting game with: ", selected_vehicle)
	GameSettings.selected_vehicle_path = selected_vehicle
	get_tree().change_scene_to_file("res://main.tscn")

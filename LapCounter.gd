extends Area3D

var lap_count := 0

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body.name == "PlayerCar":
		lap_count += 1
		var ui_label = get_node_or_null("../UI/LapLabel")
		if ui_label:
			ui_label.text = "Laps: " + str(lap_count)


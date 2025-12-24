extends Node

var lap_count := 0

func _ready():
	var lap_counter = get_node_or_null("../LapCounter")
	if lap_counter:
		lap_counter.lap_completed.connect(_on_lap_completed)
	
	var ui_label = get_node_or_null("../UI/LapLabel")
	if ui_label:
		ui_label.text = "Laps: " + str(lap_count)

func _on_lap_completed():
	lap_count += 1
	var ui_label = get_node_or_null("../UI/LapLabel")
	if ui_label:
		ui_label.text = "Laps: " + str(lap_count)


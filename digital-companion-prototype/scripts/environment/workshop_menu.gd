extends Control

const REGIONS := ["green_shade", "shellfish_beach", "toy_maze", "mechatropolis", "nephelis_abyss"]

func _ready() -> void:
	var playable := Button.new()
	playable.text = "Play regional battle fields"
	playable.custom_minimum_size.y = 44
	playable.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/environment_workshop/battle_fields.tscn"))
	$Margin/VBox/Scenes.add_child(playable)
	for region: String in REGIONS:
		for layout: String in ["home", "battle"]:
			var button := Button.new()
			button.text = "%s · %s" % [region.replace("_", " ").capitalize(), layout.capitalize()]
			button.custom_minimum_size.y = 38
			var path := "res://scenes/environment_workshop/%s_%s.tscn" % [region, layout]
			button.pressed.connect(func() -> void: get_tree().change_scene_to_file(path))
			$Margin/VBox/Scenes.add_child(button)

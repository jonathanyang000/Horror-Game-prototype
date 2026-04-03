extends Node3D

@onready var target=$NavigationRegion3D/Player


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	get_tree().call_group("enemies", "target_location", target.global_transform.origin)

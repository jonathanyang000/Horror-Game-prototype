extends CharacterBody3D

@onready var nav_agent = $NavigationAgent3D
var SPEED = 4
func _physicsprocess(_delta):
	var current_location = global_transform.origin
	var next_location = nav_agent.get_next_location()
	var _new_velocity =  (next_location-current_location).normalized()* SPEED
	velocity = _new_velocity.move_toward(_new_velocity,0.25)
	move_and_slide()

func update_target_location(target_location):
	nav_agent.set_target_location(target_location)

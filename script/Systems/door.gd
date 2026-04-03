extends CSGBox3D

var player_nearby = false

func _ready():
	# Add an Area3D to detect the player
	var area = Area3D.new()
	add_child(area)
	
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(3, 4, 2)  # Larger detection zone
	collision.shape = shape
	area.add_child(collision)
	
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "Player":
		print("you are now leaving")
		print("Exiting building...")
		# Wait a moment then quit
		await get_tree().create_timer(2.0).timeout
		get_tree().reload_current_scene()

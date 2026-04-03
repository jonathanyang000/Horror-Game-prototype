extends CSGBox3D

var player_nearby = false
var is_repairing = false
var repair_progress = 0.0
const REPAIR_TIME = 3.0  # 3 seconds to complete
var is_repaired = false 

func _ready():
	# Add an Area3D to detect the player
	var area = Area3D.new()
	add_child(area)
	
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(2, 2, 2)  # Detection range
	collision.shape = shape
	area.add_child(collision)
	
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.name == "Player":
		player_nearby = true
		print("Press E to repair")

func _on_body_exited(body):
	if body.name == "Player":
		player_nearby = false
		is_repairing = false 
		print("Left terminal")

func _process(delta):
# Only allow interaction if not already repaired
	if player_nearby and !is_repaired and Input.is_action_pressed("interact_button"):
		is_repairing = true
		repair_progress += delta
		print("Repairing... ", int(repair_progress / REPAIR_TIME * 100), "%")
		
		if repair_progress >= REPAIR_TIME:
			print("REPAIR COMPLETE!")
			is_repaired = true  # Lock it
			is_repairing = false
			
			# Turn off the glow to show it's complete
			$OmniLight3D.visible = false
			
	elif is_repairing and !is_repaired:
		# If player lets go of E before completion
		is_repairing = false
		repair_progress = 0.0
		print("Repair cancelled")
	elif player_nearby and is_repaired and Input.is_action_just_pressed("interact_button"):
		print("Repair already completed")

extends CharacterBody3D

# Movement settings
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

# Blink settings
const BLINK_DISTANCE = 1.5  # How far to teleport
const BLINK_COOLDOWN = 1.5  # Seconds between blinks
var blink_timer = 0.0

# Get the gravity from the project settings
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera = $Camera3D
@onready var flashlight = $Camera3D/SpotLight3D

func _ready():
	# Capture the mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	# Mouse look
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

func _physics_process(delta):
	# Update blink cooldown
	if blink_timer > 0:
		blink_timer -= delta
	
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Get input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply movement
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	
	# Blink mechanic - blink in direction of movement keys
	if Input.is_action_just_pressed("ui_accept") and blink_timer <= 0:  # Space key
		if input_dir.length() > 0:  # Only blink if a direction key is pressed
			_perform_blink(direction)
		else:
			print("Press a movement key (WASD) to blink in that direction!")
	
	move_and_slide()
	
	# Press ESC to free mouse
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	if Input.is_action_just_pressed("toggle_flashlight"):  # F key by default
		flashlight.visible = !flashlight.visible

func _perform_blink(blink_direction: Vector3):
	# Calculate target position
	var target_position = global_position + (blink_direction * BLINK_DISTANCE)
	
	# Check if path is clear using raycast
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.5, 0),  # Start slightly above ground
		target_position + Vector3(0, 0.5, 0)
	)
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		# Path is clear, blink to full distance
		global_position = target_position
	else:
		# Hit something, blink to just before the wall
		var hit_point = result.position
		var safe_distance = global_position.distance_to(hit_point) - 0.5  # 0.5m buffer
		if safe_distance > 0.5:  # Only blink if there's reasonable space
			global_position = global_position + (blink_direction * safe_distance)
	
	# Start cooldown
	blink_timer = BLINK_COOLDOWN
	
	# Optional: Add visual/audio feedback here
	print("Blink! Cooldown: %.1fs" % BLINK_COOLDOWN)

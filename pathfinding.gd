extends CharacterBody3D

# =============================================================================
# TWEAKABLE VARIABLES
# =============================================================================

@export var movement_speed: float = 5.0
@export var detection_range: float = 100.0
@export var gravity: float = 20.0  # ADD THIS
@export var debug_print: bool = true

# =============================================================================
# SETUP
# =============================================================================

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
var player: Node3D = null

func _ready() -> void:
	# Find player
	player = get_tree().get_first_node_in_group("player")
	if not player:
		push_error("No player found in 'player' group!")
		return
	
	# Setup navigation agent
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.5
	
	# Wait for navigation to be ready
	call_deferred("_setup_navigation")

func _setup_navigation() -> void:
	await get_tree().physics_frame
	if player:
		navigation_agent.target_position = player.global_position
		if debug_print:
			print("[Entity] Navigation ready, chasing player")

# =============================================================================
# CHASE PLAYER
# =============================================================================

func _physics_process(delta: float) -> void:
	if not player:
		return
	
	# Apply gravity FIRST
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Check if navigation map is ready
	if NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0:
		if debug_print:
			print("[Entity] Waiting for navigation map...")
		move_and_slide()
		return
	
	# Check if player is in range
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player > detection_range:
		if debug_print:
			print("[Entity] Player too far: ", distance_to_player)
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	
	# Update target to player's current position
	navigation_agent.target_position = player.global_position
	
	# Check if finished (reached player)
	if navigation_agent.is_navigation_finished():
		if debug_print:
			print("[Entity] Navigation finished (reached target)")
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	
	# Get next position on path
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	var direction: Vector3 = global_position.direction_to(next_path_position)
	
	# ONLY use horizontal movement (ignore Y)
	direction.y = 0
	direction = direction.normalized()
	
	var new_velocity: Vector3 = direction * movement_speed
	
	if debug_print:
		print("[Entity] Moving with velocity: ", new_velocity)
	
	# Rotate toward movement direction
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
	
	# Apply velocity (with avoidance if enabled)
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	# Only apply horizontal velocity
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	# Keep gravity's Y velocity
	move_and_slide()

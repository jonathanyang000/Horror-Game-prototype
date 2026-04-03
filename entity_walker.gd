extends EntityBase
class_name EntityWalker

# =============================================================================
# ALL CHANGEABLE VARIABLES - Adjust in Inspector
# =============================================================================

@export_group("Vision Settings")
@export_range(0.0, 1.0, 0.05) var vision_fov_dot: float = 0.5  ## Field of view (0.5 = ~120°, 0.7 = ~90°, 1.0 = narrow)

@export_subgroup("Line of Sight")
@export_flags_3d_physics var los_collision_mask: int = 1  ## Which layers to check for blocking LOS
@export var los_eye_height: float = 0.5  ## Height of stalker's "eyes"
@export var los_target_height: float = 0.3  ## Height to aim at on player
@export var los_check_interval: float = 0.2  ## How often to raycast (seconds)

@export_group("Movement Settings")
@export var wander_speed: float = 2.0  ## Speed while wandering
@export var chase_speed: float = 4.0  ## Speed while chasing
@export var detection_distance: float = 30.0  ## How far can see player

@export_group("Chase Behavior")
@export var lose_sight_delay: float = 3.0  ## Seconds before giving up chase after losing LOS
@export var chase_persistence: float = 1.5  ## Multiplier for detection range during chase

@export_group("Navigation")
@export var use_pathfinding: bool = false  ## Use NavigationAgent3D for pathfinding

@export_group("Audio")
@export var chase_sound: AudioStream = null  ## Sound when starting chase
@export var wander_sound: AudioStream = null  ## Sound while wandering

# =============================================================================
# INTERNAL VARIABLES - Don't modify
# =============================================================================

var _nav_agent: NavigationAgent3D = null
var _los_timer: float = 0.0
var _has_los: bool = false

# =============================================================================
# SETUP
# =============================================================================

func _entity_ready() -> void:
	# Configure base class values
	can_attack = false
	can_wander = true
	can_chase = true
	
	movement_wander_speed = wander_speed
	movement_chase_speed = chase_speed
	detection_range = detection_distance
	detection_lose_sight_time = lose_sight_delay
	
	# Start wandering
	current_state = State.WANDER
	pick_new_wander_direction()
	
	# Setup navigation if available
	if use_pathfinding and has_node("NavigationAgent3D"):
		_nav_agent = $NavigationAgent3D
		_nav_agent.path_desired_distance = 0.5
		_nav_agent.target_desired_distance = 0.5
		_nav_agent.max_speed = chase_speed
	
	# Setup kill trigger
	if has_node("Area3D"):
		$Area3D.body_entered.connect(_on_body_entered_kill_zone)
	
	# Audio on state change
	state_changed.connect(_on_state_changed_audio)

# =============================================================================
# DETECTION
# =============================================================================

func _check_player_visibility(delta: float) -> void:
	if not player:
		return
	
	var dist: float = distance_to_player()
	
	# Update line of sight check periodically (optimization)
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = los_check_interval
		_has_los = _check_line_of_sight()
	
	# CHASE STATE: More persistent, harder to lose
	if current_state == State.CHASE:
		var extended_range = detection_range * chase_persistence
		
		if dist <= extended_range:
			if _has_los:
				# Can see player - keep chasing
				time_since_last_seen = 0.0
				has_spotted_player = true
			else:
				# Can't see but still in range - start losing track
				_lose_player(delta)
		else:
			# Too far - lose track
			_lose_player(delta)
		return
	
	# WANDER/IDLE STATE: Normal detection
	if dist > detection_range:
		return
	
	# Check FOV and LOS
	if is_player_in_front(vision_fov_dot) and _has_los:
		_spot_player()

func _check_line_of_sight() -> bool:
	if not player:
		return false
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, los_eye_height, 0)
	var to: Vector3 = player.global_position + Vector3(0, los_target_height, 0)
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = los_collision_mask
	
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result.is_empty():
		return true
	
	var collider = result.get("collider")
	return collider == player or (collider != null and collider.get_parent() == player)

func _spot_player() -> void:
	if not has_spotted_player:
		player_spotted.emit(self)
		if debug_print_state_changes:
			print("[%s] Spotted player!" % name)
	
	has_spotted_player = true
	time_since_last_seen = 0.0
	
	if current_state == State.WANDER or current_state == State.IDLE:
		change_state(State.CHASE)

func _lose_player(delta: float) -> void:
	time_since_last_seen += delta
	
	if time_since_last_seen > detection_lose_sight_time:
		if has_spotted_player and current_state == State.CHASE:
			has_spotted_player = false
			player_lost.emit(self)
			
			if debug_print_state_changes:
				print("[%s] Lost player, returning to wander" % name)
			
			change_state(State.WANDER)

# =============================================================================
# CHASE WITH PATHFINDING
# =============================================================================

func _state_chase(delta: float) -> void:
	if not player:
		velocity.x = lerp(velocity.x, 0.0, delta * 8.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 8.0)
		return
	
	# Try navigation pathfinding
	if use_pathfinding and _nav_agent:
		_nav_agent.target_position = player.global_position
		
		var next_pos = _nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		
		velocity.x = direction.x * movement_chase_speed
		velocity.z = direction.z * movement_chase_speed
		
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * movement_rotation_speed * 1.5)
	else:
		# Fallback: Direct chase
		super._state_chase(delta)

# =============================================================================
# KILL ON CONTACT
# =============================================================================

func _on_body_entered_kill_zone(body: Node) -> void:
	if body.is_in_group("player"):
		if debug_print_state_changes:
			print("[%s] Caught player!" % name)
		kill_player()

# =============================================================================
# AUDIO
# =============================================================================

func _on_state_changed_audio(old_state: State, new_state: State) -> void:
	if new_state == State.CHASE and old_state != State.CHASE:
		if chase_sound:
			_play_audio(chase_sound)
	
	if new_state == State.WANDER and old_state != State.WANDER:
		if wander_sound:
			_play_audio(wander_sound)

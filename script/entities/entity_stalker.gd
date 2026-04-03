extends EntityBase
class_name EntityStalker

@export_group("Stalker Vision", "vision_")
@export_range(0.0, 1.0, 0.05) var vision_normal_fov_dot: float = 0.55
@export_range(0.0, 1.0, 0.05) var vision_flashlight_fov_dot: float = 0.15
@export_range(0.0, 200.0, 1.0) var vision_flashlight_range: float = 45.0

@export_subgroup("Line of Sight")
@export_flags_3d_physics var los_collision_mask: int = 1
@export var los_eye_height: float = 0.55
@export var los_player_height: float = 0.45
@export var los_recheck_rate: float = 0.08

@export_group("Stalker Audio")
@export var stalker_breathing_sound: AudioStream
@export var stalker_chase_sound: AudioStream

@export_group("Investigation", "investigate_")
@export var investigate_time: float = 6.0
@export var investigate_reach_distance: float = 1.0
@export var investigate_speed_mult: float = 0.8

@export var investigate_accel: float = 5.0
@export var investigate_turn_speed: float = 8.0
@export var investigate_slow_radius: float = 3.0
@export var investigate_stop_radius: float = 1.5

@export_subgroup("Search Behavior")
@export var search_turn_speed: float = 1.6
@export var search_pick_interval: float = 1.2
@export var search_pause_after_pick: float = 0.3

@export_group("Navigation")
@export var use_navigation: bool = false

@export_group("Player Refs")
@export var flashlight_path: NodePath = NodePath("Camera3D/SpotLight3D")

var _flashlight: SpotLight3D
var _los_timer: float = 0.0
var _cached_has_los: bool = false

var _search_pick_timer: float = 0.0
var _search_pause_timer: float = 0.0
var _search_target_yaw: float = 0.0

var nav_agent: NavigationAgent3D = null

func _entity_ready() -> void:
	can_attack = false
	can_wander = true
	can_chase = true

	movement_wander_speed = 2
	movement_chase_speed = 4
	detection_range = 60.0
	detection_lose_sight_time = 5  # Increased from 2 to 5 seconds

	current_state = State.WANDER
	pick_new_wander_direction()

	if has_node("Area3D"):
		$Area3D.body_entered.connect(_on_kill_trigger)

	state_changed.connect(_on_state_changed_audio)
	
	# Setup navigation if available
	if use_navigation and has_node("NavigationAgent3D"):
		nav_agent = $NavigationAgent3D
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.max_speed = movement_chase_speed
		
		# Wait for navigation to be ready
		call_deferred("_setup_nav_agent")

func _setup_nav_agent() -> void:
	if nav_agent:
		await get_tree().physics_frame
		nav_agent.max_speed = movement_chase_speed

func _cache_player_refs() -> void:
	if player and not is_instance_valid(_flashlight):
		_flashlight = player.get_node_or_null(flashlight_path) as SpotLight3D

func _check_player_visibility(delta: float) -> void:
	if not player:
		return

	_cache_player_refs()
	var dist: float = distance_to_player()

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = los_recheck_rate
		_cached_has_los = _has_line_of_sight()

	# DURING CHASE: Be more persistent, don't lose track easily
	if current_state == State.CHASE:
		# Keep chasing if player is in extended range
		if dist <= detection_range * 1.5:  # 1.5x range during chase
			if _cached_has_los:
				# Can see player - reset lose sight timer
				time_since_last_seen = 0.0
				last_known_player_position = player.global_position
			else:
				# Can't see but still close - only lose track after delay
				_lose_track(delta)
		else:
			# Player is very far - lose track
			_lose_track(delta)
		return

	# NORMAL DETECTION (wander/investigate states)
	var flashlight_is_on: bool = is_instance_valid(_flashlight) and _flashlight.visible
	if flashlight_is_on and dist <= vision_flashlight_range:
		if is_player_in_front(vision_flashlight_fov_dot) and _cached_has_los:
			_spot_player()
			return

	if dist > detection_range:
		_lose_track(delta)
		return

	if is_player_in_front(vision_normal_fov_dot) and _cached_has_los:
		_spot_player()
	else:
		_lose_track(delta)

func _has_line_of_sight() -> bool:
	if not player:
		return false

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0.0, los_eye_height, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, los_player_height, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = los_collision_mask

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var col := hit.get("collider") as Object
	return col == player or (col != null and (col as Node).get_parent() == player)

func _spot_player() -> void:
	if not has_spotted_player:
		player_spotted.emit(self)

	has_spotted_player = true
	time_since_last_seen = 0.0
	last_known_player_position = player.global_position

	if current_state == State.WANDER or current_state == State.INVESTIGATE:
		change_state(State.CHASE)

func _lose_track(delta: float) -> void:
	time_since_last_seen += delta

	if time_since_last_seen > detection_lose_sight_time:
		if has_spotted_player and current_state == State.CHASE:
			has_spotted_player = false
			player_lost.emit(self)

			investigation_timer = _get_investigation_time()
			change_state(State.INVESTIGATE)

func _state_chase(delta: float) -> void:
	if not player:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		return

	last_known_player_position = player.global_position
	
	# Use navigation if available AND navigation map is ready
	if use_navigation and nav_agent and nav_agent.is_inside_tree():
		# Check if navigation is actually ready
		if not nav_agent.is_navigation_finished() or nav_agent.distance_to_target() > 0.5:
			nav_agent.target_position = player.global_position
			
			# Safety check: only use nav if we have a valid path
			var next_pos = nav_agent.get_next_path_position()
			if next_pos != global_position:  # Valid path exists
				var direction = (next_pos - global_position).normalized()
				
				velocity.x = direction.x * movement_chase_speed
				velocity.z = direction.z * movement_chase_speed
				
				var target_rotation = atan2(direction.x, direction.z)
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * (movement_rotation_speed * 1.5))
				return
		
		# If we reach here, navigation failed - fall through to direct chase
	
	# Fallback: Direct chase (no navigation)
	super._state_chase(delta)

func _get_investigation_time() -> float:
	# Initialize search behavior when investigation starts
	_search_pick_timer = 0.01  # Start searching almost immediately
	_search_pause_timer = 0.0
	_search_target_yaw = rotation.y
	return investigate_time

func _get_investigation_reach_distance() -> float:
	return investigate_reach_distance

func _move_to_investigation_location(delta: float) -> void:
	var to_target: Vector3 = last_known_player_position - global_position
	to_target.y = 0.0

	var dist: float = to_target.length()
	if dist <= investigate_stop_radius:
		velocity.x = lerp(velocity.x, 0.0, delta * investigate_accel)
		velocity.z = lerp(velocity.z, 0.0, delta * investigate_accel)
		return

	var safe_dist: float = max(dist, 0.0001)
	var dir: Vector3 = to_target / safe_dist

	var base_speed: float = movement_chase_speed * investigate_speed_mult
	var slow_div: float = max(investigate_slow_radius, 0.001)
	var t: float = clamp(dist / slow_div, 0.0, 1.0)
	var desired_speed: float = lerp(base_speed * 0.6, base_speed, t)

	var desired_vx: float = dir.x * desired_speed
	var desired_vz: float = dir.z * desired_speed

	velocity.x = lerp(velocity.x, desired_vx, delta * investigate_accel)
	velocity.z = lerp(velocity.z, desired_vz, delta * investigate_accel)

	var target_yaw: float = atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * investigate_turn_speed)

func _investigate_at_location(delta: float) -> void:
	velocity.x = lerp(velocity.x, 0.0, delta * investigate_accel)
	velocity.z = lerp(velocity.z, 0.0, delta * investigate_accel)

	# Handle pause after picking new direction
	if _search_pause_timer > 0.0:
		_search_pause_timer -= delta
		return

	# Count down to pick new search direction
	_search_pick_timer -= delta
	if _search_pick_timer <= 0.0:
		_search_pick_timer = search_pick_interval
		_search_pause_timer = search_pause_after_pick
		_search_target_yaw = rotation.y + randf_range(-PI * 0.9, PI * 0.9)

	# Smoothly rotate toward target direction
	rotation.y = lerp_angle(rotation.y, _search_target_yaw, delta * search_turn_speed)

func _on_kill_trigger(body: Node) -> void:
	if body.is_in_group("player"):
		kill_player()

func _on_state_changed_audio(old_state: State, new_state: State) -> void:
	if new_state == State.CHASE and old_state != State.CHASE:
		if stalker_chase_sound:
			_play_audio(stalker_chase_sound)

	if new_state == State.INVESTIGATE and old_state != State.INVESTIGATE:
		if stalker_breathing_sound:
			_play_audio(stalker_breathing_sound)

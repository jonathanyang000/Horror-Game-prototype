extends CharacterBody3D
class_name EntityBase

## Base class for all enemy entities in the game.
## Provides: state machine, movement system, player detection framework, helper utilities.
## All @export variables can be configured per-instance in the Inspector.

# =============================================================================
# SIGNALS
# =============================================================================

signal player_spotted(entity: EntityBase)
signal player_lost(entity: EntityBase)
signal killed_player(entity: EntityBase)
signal state_changed(old_state: State, new_state: State)

# =============================================================================
# STATE MACHINE
# =============================================================================

enum State {
	IDLE,        ## Standing still, no active behavior
	WANDER,      ## Moving randomly, patrolling
	CHASE,       ## Actively pursuing the player
	ATTACKING    ## Performing attack (animation, cooldown, etc.)
}

var current_state: State = State.IDLE

# =============================================================================
# EXPORTED PROPERTIES - Configure in Inspector
# =============================================================================

@export_group("Capabilities", "can_")
@export var can_attack: bool = true ## Can this entity attack the player?
@export var can_wander: bool = true ## Can this entity wander around?
@export var can_chase: bool = true ## Can this entity chase the player?

@export_group("Movement", "movement_")
@export_range(0.0, 10.0, 0.1, "or_greater") var movement_wander_speed: float = 2.0 ## Speed while wandering (m/s)
@export_range(0.0, 20.0, 0.1, "or_greater") var movement_chase_speed: float = 4.0 ## Speed while chasing player (m/s)
@export var movement_wander_interval: Vector2 = Vector2(2.0, 5.0) ## Min/max seconds between random direction changes
@export_range(0.0, 10.0, 0.1) var movement_rotation_speed: float = 3.0 ## How fast entity rotates (multiplier)

@export_group("Detection", "detection_")
@export_range(0.0, 100.0, 1.0) var detection_range: float = 30.0 ## Maximum distance to detect player (meters)
@export_range(0.0, 20.0, 0.1) var detection_lose_sight_time: float = 3.0 ## Seconds without sight before losing track of player

@export_group("Combat", "combat_")
@export_range(0.0, 10.0, 0.1) var combat_damage: float = 1.0 ## Damage dealt per attack
@export_range(0.0, 10.0, 0.1) var combat_attack_range: float = 2.0 ## Distance needed to attack player
@export_range(0.0, 10.0, 0.1) var combat_cooldown: float = 1.5 ## Seconds between attacks

@export_group("Audio", "audio_")
@export var audio_footstep_sound: AudioStream = null ## Sound played while moving (optional)
@export var audio_spotted_sound: AudioStream = null ## Sound played when spotting player (optional)
@export var audio_attack_sound: AudioStream = null ## Sound played when attacking (optional)

@export_group("Debug", "debug_")
@export var debug_show_detection_range: bool = false ## Show detection radius in editor
@export var debug_show_attack_range: bool = false ## Show attack range in editor
@export var debug_print_state_changes: bool = false ## Print to console when state changes

# =============================================================================
# RUNTIME VARIABLES - Managed by code, not exported
# =============================================================================

var wander_direction: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var player: CharacterBody3D = null
var has_spotted_player: bool = false
var time_since_last_seen: float = 0.0
var attack_timer: float = 0.0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Find player in scene
	player = get_tree().get_first_node_in_group("player")
	if !player:
		push_warning("EntityBase '%s': No player found in 'player' group!" % name)
	
	# Call child class setup
	_entity_ready()

func _physics_process(delta: float) -> void:
	# Update detection
	_check_player_visibility(delta)
	
	# Update attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Run state machine
	match current_state:
		State.IDLE:
			_state_idle(delta)
		State.WANDER:
			_state_wander(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACKING:
			_state_attacking(delta)
	
	# Apply movement
	move_and_slide()

# =============================================================================
# VIRTUAL FUNCTIONS - Override in child classes
# =============================================================================

## Called after _ready(). Configure entity-specific properties here.
## Example: Set speeds, connect signals, spawn visual effects
func _entity_ready() -> void:
	pass

## Check if entity can detect player. Update has_spotted_player here.
## Examples: vision cone, sound detection, proximity, omniscient
func _check_player_visibility(_delta: float) -> void:
	pass

## Called every frame in IDLE state. Default: stand still.
func _state_idle(_delta: float) -> void:
	velocity = Vector3.ZERO

## Called every frame in WANDER state. Default: random wandering with smooth rotation.
func _state_wander(delta: float) -> void:
	# Move in current direction
	velocity.x = wander_direction.x * movement_wander_speed
	velocity.z = wander_direction.z * movement_wander_speed
	
	# Smooth rotation toward movement direction
	if wander_direction.length() > 0.1:
		var target_rotation = atan2(wander_direction.x, wander_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * movement_rotation_speed)
	
	# Periodically pick new direction
	wander_timer -= delta
	if wander_timer <= 0:
		pick_new_wander_direction()

## Called every frame in CHASE state. Default: move toward player with smooth rotation.
func _state_chase(delta: float) -> void:
	if !player:
		velocity.x = 0
		velocity.z = 0
		return
	
	# Move toward player
	var direction = direction_to_player()
	velocity.x = direction.x * movement_chase_speed
	velocity.z = direction.z * movement_chase_speed
	
	# Smooth rotation toward player
	var target_rotation = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * (movement_rotation_speed * 1.5))

## Called every frame in ATTACKING state. Default: stand still.
## Override this to add attack animations, damage dealing, etc.
func _state_attacking(_delta: float) -> void:
	velocity = Vector3.ZERO

## Called when exiting a state. Override for cleanup (stop sounds, reset timers, etc.)
func _on_state_exited(_old_state: State) -> void:
	pass

## Called when entering a state. Override for initialization (play sounds, start timers, etc.)
func _on_state_entered(_new_state: State) -> void:
	pass

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

## Change to a new state with validation and enter/exit hooks.
func change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	
	# Validate capability
	if new_state == State.ATTACKING and !can_attack:
		push_warning("Entity '%s' cannot attack (can_attack = false)" % name)
		return
	
	if new_state == State.WANDER and !can_wander:
		push_warning("Entity '%s' cannot wander (can_wander = false)" % name)
		return
	
	if new_state == State.CHASE and !can_chase:
		push_warning("Entity '%s' cannot chase (can_chase = false)" % name)
		return
	
	# Execute state change
	var old_state = current_state
	_on_state_exited(old_state)
	current_state = new_state
	_on_state_entered(new_state)
	
	# Debug output
	if debug_print_state_changes:
		print("[%s] State: %s → %s" % [name, _state_to_string(old_state), _state_to_string(new_state)])
	
	state_changed.emit(old_state, new_state)

# =============================================================================
# MOVEMENT HELPERS
# =============================================================================

## Pick a new random direction to wander toward.
func pick_new_wander_direction() -> void:
	var angle = randf() * TAU
	wander_direction = Vector3(cos(angle), 0, sin(angle))
	wander_timer = randf_range(movement_wander_interval.x, movement_wander_interval.y)

## Smoothly rotate entity toward a target position.
func rotate_toward(target_pos: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	var direction = (target_pos - global_position).normalized()
	var target_rotation = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * movement_rotation_speed * speed_multiplier)

# =============================================================================
# PLAYER TRACKING HELPERS
# =============================================================================

## Get distance to player. Returns INF if no player exists.
func distance_to_player() -> float:
	if !player:
		return INF
	return global_position.distance_to(player.global_position)

## Get normalized direction vector to player. Returns ZERO if no player.
func direction_to_player() -> Vector3:
	if !player:
		return Vector3.ZERO
	return (player.global_position - global_position).normalized()

## Check if player is in front of entity based on FOV.
## fov_dot: 1.0 = directly ahead, 0.0 = 90° to either side, -1.0 = behind
## Example: fov_dot = 0.5 gives ~120° field of view
func is_player_in_front(fov_dot: float = 0.5) -> bool:
	if !player:
		return false
	
	var to_player = direction_to_player()
	var forward = -transform.basis.z
	return forward.dot(to_player) >= fov_dot

## Check if player is within attack range.
func is_player_in_attack_range() -> bool:
	return distance_to_player() <= combat_attack_range

# =============================================================================
# COMBAT HELPERS
# =============================================================================

## Check if attack is ready (cooldown finished).
func can_attack_now() -> bool:
	return can_attack and attack_timer <= 0.0

## Start attack cooldown. Call this when beginning an attack.
func start_attack_cooldown() -> void:
	attack_timer = combat_cooldown

## Deal damage to player. Override this for custom damage logic.
func damage_player(damage: float = -1.0) -> void:
	var actual_damage = damage if damage > 0 else combat_damage
	# TODO: Implement damage system when player health exists
	print("[%s] Dealt %.1f damage to player" % [name, actual_damage])

## Kill the player. Emits signal and restarts scene.
func kill_player() -> void:
	killed_player.emit(self)
	print("=== %s KILLED YOU ===" % name.to_upper())
	
	# Play death sound if available
	if audio_attack_sound:
		_play_audio(audio_attack_sound)
	
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()

# =============================================================================
# AUDIO HELPERS
# =============================================================================

## Play an audio stream. Creates a temporary AudioStreamPlayer3D.
func _play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	if !stream:
		return
	
	var player_node = AudioStreamPlayer3D.new()
	add_child(player_node)
	player_node.stream = stream
	player_node.volume_db = volume_db
	player_node.play()
	
	# Auto-cleanup when finished
	await player_node.finished
	player_node.queue_free()

# =============================================================================
# DEBUGGING HELPERS
# =============================================================================

## Get current state as string for debugging.
func get_state_name() -> String:
	return _state_to_string(current_state)

func _state_to_string(state: State) -> String:
	match state:
		State.IDLE: return "IDLE"
		State.WANDER: return "WANDER"
		State.CHASE: return "CHASE"
		State.ATTACKING: return "ATTACKING"
		_: return "UNKNOWN"

## Print debug info about entity state.
func debug_print() -> void:
	print("[%s] State: %s | Distance: %.1fm | Spotted: %s | Attack Ready: %s" % [
		name,
		get_state_name(),
		distance_to_player(),
		has_spotted_player,
		can_attack_now()
	])

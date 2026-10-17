extends CharacterBody3D
class_name PlayerController

const WEAPON_REST_ROTATION_DEGREES := 12.0
const WEAPON_SWING_ROTATION_DEGREES := -55.0
const DAMAGE_OVERLAY_COLOR := Color(0.9, 0.04, 0.02, 0.24)

@export_category("Movement")
@export_range(0.1, 20.0, 0.1) var move_speed: float = 6.0
@export_range(0.1, 60.0, 0.1) var acceleration: float = 24.0
@export_range(0.1, 60.0, 0.1) var deceleration: float = 30.0
@export_range(0.1, 20.0, 0.1) var jump_velocity: float = 5.5
@export_range(1.0, 3.0, 0.05) var run_speed_multiplier: float = 1.65
@export_range(0.1, 0.6, 0.01) var run_double_tap_window: float = 0.3

@export_category("Combat")
@export_range(1, 1000, 1) var basic_attack_damage: int = 25
@export_range(0.1, 2.0, 0.05) var basic_attack_cooldown: float = 0.55
@export_range(0.01, 0.5, 0.01) var basic_attack_hit_delay: float = 0.09
@export_range(0.05, 0.5, 0.01) var basic_attack_swing_duration: float = 0.18
@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 2.0

@export_category("Camera")
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.003
@export_range(-89.0, 0.0, 1.0) var minimum_pitch_degrees: float = -55.0
@export_range(0.0, 89.0, 1.0) var maximum_pitch_degrees: float = 65.0
@export_range(30.0, 240.0, 1.0) var keyboard_look_speed_degrees: float = 100.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var health: HealthComponent = $Health
@onready var world_model: Node3D = $WorldModel
@onready var attack_direction: Node3D = $AttackDirection
@onready var weapon_pivot: Node3D = $CameraPivot/Camera3D/WeaponPivot
@onready var melee_hitbox: Area3D = $AttackDirection/MeleeHitbox
@onready var melee_collision_shape: CollisionShape3D = $AttackDirection/MeleeHitbox/CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var damage_overlay: ColorRect = $HUD/DamageOverlay
@onready var health_label: Label = $HUD/HealthPanel/HealthContent/HealthLabel
@onready var health_bar: ProgressBar = $HUD/HealthPanel/HealthContent/HealthBar
@onready var respawn_label: Label = $HUD/HealthPanel/HealthContent/RespawnLabel

var _camera_pitch: float = 0.0
var _last_forward_press_msec: int = -1
var _is_running: bool = false
var _can_attack: bool = true
var _attack_tween: Tween
var _spawn_position: Vector3
var _is_defeated: bool = false
var _damage_feedback_tween: Tween


func _ready() -> void:
	_spawn_position = global_position
	_camera_pitch = camera.rotation.x
	world_model.visible = false
	_sync_facing_to_camera()
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_on_health_changed(health.current_health, health.maximum_health)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_update_keyboard_look(delta)
	_sync_facing_to_camera()

	if _is_defeated:
		velocity = Vector3.ZERO
		return

	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var movement_direction := _get_camera_relative_direction(input_vector)
	var current_move_speed := move_speed * run_speed_multiplier if _is_running else move_speed

	if movement_direction != Vector3.ZERO:
		velocity.x = move_toward(
			velocity.x,
			movement_direction.x * current_move_speed,
			acceleration * delta
		)
		velocity.z = move_toward(
			velocity.z,
			movement_direction.z * current_move_speed,
			acceleration * delta
		)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity += get_gravity() * delta

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		_handle_run_input(event)

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_mouse_capture()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.is_action_pressed("basic_attack"):
				_try_basic_attack()
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_camera_pitch = clampf(
			_camera_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(minimum_pitch_degrees),
			deg_to_rad(maximum_pitch_degrees)
		)
		camera.rotation.x = _camera_pitch
		_sync_facing_to_camera()


func _handle_run_input(event: InputEventKey) -> void:
	if event.is_action_pressed("move_forward"):
		var current_press_msec := Time.get_ticks_msec()
		var double_tap_window_msec := int(run_double_tap_window * 1000.0)

		if (
			_last_forward_press_msec >= 0
			and current_press_msec - _last_forward_press_msec <= double_tap_window_msec
		):
			_is_running = true

		_last_forward_press_msec = current_press_msec
	elif event.is_action_released("move_forward"):
		_is_running = false


func _try_basic_attack() -> void:
	if not _can_attack or _is_defeated:
		return

	_can_attack = false
	_play_basic_attack_animation()

	await get_tree().create_timer(basic_attack_hit_delay).timeout
	if _is_defeated:
		_can_attack = true
		return
	_deal_basic_attack_damage()

	var remaining_cooldown := maxf(basic_attack_cooldown - basic_attack_hit_delay, 0.0)
	if remaining_cooldown > 0.0:
		await get_tree().create_timer(remaining_cooldown).timeout

	_can_attack = true


func _deal_basic_attack_damage() -> void:
	var damaged_health_components: Array[HealthComponent] = []
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = melee_collision_shape.shape
	shape_query.transform = melee_collision_shape.global_transform
	shape_query.collision_mask = melee_hitbox.collision_mask
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false

	var collision_results := get_world_3d().direct_space_state.intersect_shape(shape_query, 16)

	for result in collision_results:
		var body := result.get("collider") as Node
		if body == null:
			continue

		var health := body.get_node_or_null("Health") as HealthComponent
		if health == null or health in damaged_health_components:
			continue

		health.take_damage(basic_attack_damage)
		damaged_health_components.append(health)


func _play_basic_attack_animation() -> void:
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()

	weapon_pivot.rotation.z = deg_to_rad(WEAPON_REST_ROTATION_DEGREES)
	_attack_tween = create_tween()
	_attack_tween.tween_property(
		weapon_pivot,
		"rotation:z",
		deg_to_rad(WEAPON_SWING_ROTATION_DEGREES),
		basic_attack_swing_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(
		weapon_pivot,
		"rotation:z",
		deg_to_rad(WEAPON_REST_ROTATION_DEGREES),
		0.12
	)


func _on_health_changed(current_health: int, maximum_health: int) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	health_label.text = "HEALTH  %d / %d" % [current_health, maximum_health]


func _on_damaged(_amount: int) -> void:
	if _damage_feedback_tween != null and _damage_feedback_tween.is_valid():
		_damage_feedback_tween.kill()

	damage_overlay.visible = true
	damage_overlay.color = DAMAGE_OVERLAY_COLOR
	_damage_feedback_tween = create_tween()
	_damage_feedback_tween.tween_property(
		damage_overlay,
		"color",
		Color(DAMAGE_OVERLAY_COLOR, 0.0),
		0.3
	)
	_damage_feedback_tween.tween_callback(func() -> void: damage_overlay.visible = false)


func _on_died() -> void:
	if _is_defeated:
		return

	_is_defeated = true
	_is_running = false
	_can_attack = false
	velocity = Vector3.ZERO
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	weapon_pivot.rotation.z = deg_to_rad(WEAPON_REST_ROTATION_DEGREES)
	collision_shape.set_deferred("disabled", true)
	weapon_pivot.visible = false
	respawn_label.visible = true

	await get_tree().create_timer(respawn_delay).timeout

	global_position = _spawn_position
	health.reset_health()
	weapon_pivot.visible = true
	respawn_label.visible = false
	collision_shape.set_deferred("disabled", false)
	_is_defeated = false
	_can_attack = true


func _get_camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector == Vector2.ZERO:
		return Vector3.ZERO

	var direction := camera_pivot.global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
	direction.y = 0.0
	return direction.normalized()


func _update_keyboard_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var yaw_input := (
		float(Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_LEFT))
	)
	var pitch_input := (
		float(Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_UP))
	)
	var look_speed := deg_to_rad(keyboard_look_speed_degrees)
	camera_pivot.rotate_y(-yaw_input * look_speed * delta)
	_camera_pitch = clampf(
		_camera_pitch - pitch_input * look_speed * delta,
		deg_to_rad(minimum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)
	camera.rotation.x = _camera_pitch


func _sync_facing_to_camera() -> void:
	attack_direction.rotation.y = camera_pivot.rotation.y
	world_model.rotation.y = camera_pivot.rotation.y


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


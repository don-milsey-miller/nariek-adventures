extends CharacterBody3D
class_name PlayerController

@export_category("Movement")
@export_range(0.1, 20.0, 0.1) var move_speed: float = 6.0
@export_range(0.1, 60.0, 0.1) var acceleration: float = 24.0
@export_range(0.1, 60.0, 0.1) var deceleration: float = 30.0
@export_range(0.1, 20.0, 0.1) var turn_speed: float = 12.0
@export_range(0.1, 20.0, 0.1) var jump_velocity: float = 5.5
@export_range(1.0, 3.0, 0.05) var run_speed_multiplier: float = 1.65
@export_range(0.1, 0.6, 0.01) var run_double_tap_window: float = 0.3

@export_category("Combat")
@export_range(1, 1000, 1) var basic_attack_damage: int = 25
@export_range(0.1, 2.0, 0.05) var basic_attack_cooldown: float = 0.55
@export_range(0.01, 0.5, 0.01) var basic_attack_hit_delay: float = 0.09
@export_range(0.05, 0.5, 0.01) var basic_attack_swing_duration: float = 0.18

@export_category("Camera")
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.003
@export_range(-89.0, 0.0, 1.0) var minimum_pitch_degrees: float = -55.0
@export_range(0.0, 89.0, 1.0) var maximum_pitch_degrees: float = 65.0
@export_range(1.0, 5.0, 0.1) var minimum_zoom: float = 2.5
@export_range(5.0, 12.0, 0.1) var maximum_zoom: float = 8.0
@export_range(0.1, 2.0, 0.1) var zoom_step: float = 0.6

@onready var visuals: Node3D = $Visuals
@onready var weapon_pivot: Node3D = $Visuals/WeaponPivot
@onready var melee_hitbox: Area3D = $Visuals/MeleeHitbox
@onready var melee_collision_shape: CollisionShape3D = $Visuals/MeleeHitbox/CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D

var _camera_pitch: float = 0.0
var _last_forward_press_msec: int = -1
var _is_running: bool = false
var _can_attack: bool = true
var _attack_tween: Tween


func _ready() -> void:
	_camera_pitch = spring_arm.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
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
		_rotate_visuals_toward(movement_direction, delta)
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
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_set_camera_zoom(spring_arm.spring_length - zoom_step)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_set_camera_zoom(spring_arm.spring_length + zoom_step)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_camera_pitch = clampf(
			_camera_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(minimum_pitch_degrees),
			deg_to_rad(maximum_pitch_degrees)
		)
		spring_arm.rotation.x = _camera_pitch


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
	if not _can_attack:
		return

	_can_attack = false
	_play_basic_attack_animation()

	await get_tree().create_timer(basic_attack_hit_delay).timeout
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

	weapon_pivot.rotation.y = deg_to_rad(-65.0)
	_attack_tween = create_tween()
	_attack_tween.tween_property(
		weapon_pivot,
		"rotation:y",
		deg_to_rad(65.0),
		basic_attack_swing_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(weapon_pivot, "rotation:y", deg_to_rad(-65.0), 0.12)


func _get_camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector == Vector2.ZERO:
		return Vector3.ZERO

	var direction := camera_pivot.global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
	direction.y = 0.0
	return direction.normalized()


func _rotate_visuals_toward(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, turn_speed * delta)


func _set_camera_zoom(new_length: float) -> void:
	spring_arm.spring_length = clampf(new_length, minimum_zoom, maximum_zoom)


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


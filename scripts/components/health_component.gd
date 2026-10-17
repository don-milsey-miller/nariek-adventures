extends Node
class_name HealthComponent

signal health_changed(current_health: int, maximum_health: int)
signal damaged(amount: int)
signal died

@export_range(1, 100000, 1) var maximum_health: int = 100

var current_health: int = 0
var is_dead: bool:
	get:
		return current_health <= 0


func _ready() -> void:
	current_health = maximum_health


func take_damage(amount: int) -> int:
	if amount <= 0 or is_dead:
		return 0

	var applied_damage := mini(amount, current_health)
	current_health -= applied_damage
	damaged.emit(applied_damage)
	health_changed.emit(current_health, maximum_health)

	if is_dead:
		died.emit()

	return applied_damage


func reset_health() -> void:
	current_health = maximum_health
	health_changed.emit(current_health, maximum_health)


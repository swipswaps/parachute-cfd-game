extends Node
var discovered_errors := {}
var fix_points := 0
var badges := []

func on_error_detected(error_type: String, source: String) -> void:
	if not discovered_errors.has(error_type):
		discovered_errors[error_type] = {
			"first_seen": Time.get_datetime_string_from_system(),
			"count": 1,
			"sources": [source]
		}
		_award_badge("Discoverer", "First detected: " + error_type)
	else:
		discovered_errors[error_type].count += 1
		if source not in discovered_errors[error_type].sources:
			discovered_errors[error_type].sources.append(source)

func on_error_fixed(error_type: String) -> void:
	fix_points += 10
	_award_badge("Healer", "Fixed: " + error_type)

func _award_badge(name: String, description: String) -> void:
	badges.append({"name": name, "description": description, "time": Time.get_datetime_string_from_system()})
	var error_bus = Engine.get_singleton("ErrorBus")
	if error_bus and error_bus.has_signal("badge_earned"):
		error_bus.badge_earned.emit(name, description)

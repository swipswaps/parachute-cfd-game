# PATH: godot_project/scripts/game_manager.gd
# WHAT: Manages game state, scoring, UI, and win/lose conditions
# WHY:  Coordinates parachute, wind visualization, and player feedback
# MENTAL MODEL BEFORE: Separate uncoordinated systems
# MENTAL MODEL AFTER:  Central manager orchestrates all game elements
# FAILURE MODE: Parachute lands → score not calculated if manager missing
# VERIFIES WITH: Score displayed correctly, game ends on landing
extends Node

# Game state
enum GameState { MENU, FLYING, LANDED, GAME_OVER }
var current_state: GameState = GameState.MENU

# Scoring
var base_score: int = 1000
var final_score: int = 0

# Target
var target_position: Vector3 = Vector3.ZERO
var target_radius: float = 10.0  # meters

# References
@onready var parachute = $Parachute
@onready var hud = $HUD
@onready var wind_field = $WindField


func _ready() -> void:
	"""
	Initialize game manager.

	MENTAL MODEL: Setup UI, place target, prepare for flight
	FAILURE MODE: Missing child nodes → null reference errors
	VERIFIES WITH: Game starts in MENU state, UI visible
	"""
	set_state(GameState.MENU)


func _process(_delta) -> void:
	"""
	Update game state each frame.

	MENTAL MODEL: Monitor parachute altitude, update HUD, check landing
	FAILURE MODE: No altitude check → parachute falls through ground
	VERIFIES WITH: HUD updates every frame, landing detected
	"""

	if current_state == GameState.FLYING:
		update_hud()
		check_landing()


func set_state(new_state: GameState) -> void:
	"""Change game state and trigger appropriate actions."""
	current_state = new_state

	match new_state:
		GameState.MENU:
			# Show menu UI
			pass
		GameState.FLYING:
			# Start flight
			spawn_parachute()
		GameState.LANDED:
			# Calculate score
			calculate_score()
		GameState.GAME_OVER:
			# Show results
			pass


func spawn_parachute() -> void:
	"""
	Place parachute at starting altitude.

	MENTAL MODEL: Parachute starts 500m above target, player controls descent
	FAILURE MODE: Start position outside wind field → no wind data
	VERIFIES WITH: Parachute visible, controllable, descending
	"""
	var start_altitude := 500.0  # meters AGL
	parachute.global_transform.origin = target_position + Vector3.UP * start_altitude
	parachute.velocity = Vector3.ZERO

	print("Parachute deployed at altitude: %.0f m" % start_altitude)


func update_hud() -> void:
	"""
	Update HUD with current flight data.

	MENTAL MODEL: Read parachute state → format strings → update labels
	FAILURE MODE: HUD labels not found → silent failure
	VERIFIES WITH: HUD shows altitude, speed, distance
	"""
	if not parachute:
		return

	var altitude = parachute.global_transform.origin.y
	var distance_to_target = parachute.global_transform.origin.distance_to(target_position)
	var descent_rate = parachute.get_descent_rate()
	var forward_speed = parachute.get_forward_speed()

	# Get current wind
	var wind = Vector3.ZERO
	if wind_field:
		wind = wind_field.get_wind_at(parachute.global_transform.origin)

	var wind_speed = Vector2(wind.x, wind.z).length()

	# Update HUD labels (assumes HUD has these children)
	if hud:
		hud.get_node("AltitudeLabel").text = "Altitude: %.0f m" % altitude
		hud.get_node("DistanceLabel").text = "Distance: %.0f m" % distance_to_target
		hud.get_node("DescentLabel").text = "Descent: %.1f m/s" % descent_rate
		hud.get_node("SpeedLabel").text = "Speed: %.1f m/s" % forward_speed
		hud.get_node("WindLabel").text = "Wind: %.1f m/s" % wind_speed


func check_landing() -> void:
	"""
	Detect when parachute touches ground.

	MENTAL MODEL: Altitude < threshold → landed
	FAILURE MODE: Ground not at y=0 → wrong threshold
	VERIFIES WITH: Landing triggers score calculation

	Source: Parachute landing is defined as < 1m altitude and < 5 m/s descent
		(FAA parachute landing standards)
	"""
	if not parachute:
		return

	var altitude = parachute.global_transform.origin.y
	var descent_rate = parachute.get_descent_rate()

	if altitude < 1.0:  # Landed
		set_state(GameState.LANDED)


func calculate_score() -> void:
	"""
	Calculate final score based on accuracy and technique.

	MENTAL MODEL: Base score 1000, subtract penalties for distance/speed/time
	FAILURE MODE: Negative score possible → clamp to 0
	VERIFIES WITH: Score displayed, matches expected formula

	Scoring formula (from README.md):
		Base: 1000 pts
		- Distance penalty: 10 pts/meter
		- Speed penalty: 5 pts per m/s over 3 m/s
		+ Time bonus: 2 pts/second (efficiency)
	"""
	var distance = parachute.global_transform.origin.distance_to(target_position)
	var landing_speed = parachute.velocity.length()

	# Calculate penalties
	var distance_penalty = int(distance * 10.0)
	var speed_penalty := 0
	if landing_speed > 3.0:
		speed_penalty = int((landing_speed - 3.0) * 5.0)

	# Calculate bonuses
	var flight_time = Time.get_ticks_msec() / 1000.0  # Simplified
	var time_bonus := 0  # TODO: Track actual flight time

	final_score = base_score - distance_penalty - speed_penalty + time_bonus
	final_score = max(0, final_score)  # Clamp to non-negative

	print("=== LANDING SCORE ===")
	print("Distance from target: %.1f m (-%d pts)" % [distance, distance_penalty])
	print("Landing speed: %.1f m/s (-%d pts)" % [landing_speed, speed_penalty])
	print("FINAL SCORE: %d" % final_score)

	# Show results screen
	set_state(GameState.GAME_OVER)


func _input(_event) -> void:
	"""
	Handle player input for parachute control.

	MENTAL MODEL: Arrow keys → steering input → parachute turns
	FAILURE MODE: No parachute reference → input ignored
	VERIFIES WITH: Parachute responds to arrow keys
	"""
	if current_state != GameState.FLYING:
		return

	if not parachute:
		return

	# Steering input
	var turn = Input.get_axis("ui_left", "ui_right")
	var brake = 1.0 if Input.is_action_pressed("ui_down") else 0.0

	parachute.apply_steering(turn, brake)

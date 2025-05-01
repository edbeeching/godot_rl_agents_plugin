extends ISensor2D
class_name PositionSensor2D

@export var objects_to_observe: Array[Node2D]

## Whether to include relative x position in obs
@export var include_x := true
## Whether to include relative y position in obs
@export var include_y := true

## Max distance, values in obs will be normalized,
## 0 will represent the closest distance possible, and 1 the farthest.
## Do not use a much larger value than needed, as it would make the obs
## very small after normalization.
@export_range(0.01, 20_000) var max_distance := 1.0

@export var use_separate_direction: bool = false

@export var debug_lines: bool = true
@export var debug_color: Color = Color.GREEN

@onready var line: Line2D


func _ready() -> void:
	if debug_lines:
		line = Line2D.new()
		add_child(line)
		line.width = 1
		line.default_color = debug_color

func get_observation():
	var observations: Array[float]

	if debug_lines:
		line.clear_points()

	for obj in objects_to_observe:
		var relative_position := Vector2.ZERO

		## If object has been removed, keep the zeroed position
		if is_instance_valid(obj): relative_position = to_local(obj.global_position)

		if debug_lines:
			line.add_point(Vector2.ZERO)
			line.add_point(relative_position)

		var direction := Vector2.ZERO 
		var distance := 0.0
		if use_separate_direction:
			direction = relative_position.normalized()
			distance = min(relative_position.length() / max_distance, 1.0)
			if include_x:
				observations.append(direction.x)
			if include_y:
				observations.append(direction.y)
			observations.append(distance)
		else:
			relative_position = relative_position.limit_length(max_distance) / max_distance
			if include_x:
				observations.append(relative_position.x)
			if include_y:
				observations.append(relative_position.y)

	return observations

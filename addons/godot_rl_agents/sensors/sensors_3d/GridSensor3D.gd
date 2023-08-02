@tool
extends ISensor3D
class_name GridSensor3D

@export_flags_3d_physics var detection_mask := 0:
	get: return detection_mask
	set(value):
		detection_mask = value
		_update()

@export var collide_with_areas := false:
	get: return collide_with_areas
	set(value):
		collide_with_areas = value
		_update()

@export var collide_with_bodies := true:
	get: return collide_with_bodies
	set(value):
		collide_with_bodies = value
		_update()

@export_range(0.1, 2, 0.1) var cell_width := 1.0:
	get: return cell_width
	set(value):
		cell_width = value
		_update()

@export_range(0.1, 2, 0.1) var cell_height := 1.0:
	get: return cell_height
	set(value):
		cell_height = value
		_update()	

@export_range(1, 21, 2, "or_greater") var grid_size := 3:
	get: return grid_size
	set(value):
		grid_size = value
		_update()

var obs_buffer = null

func _update():
	if Engine.is_editor_hint():
		_spawn_nodes()	


func _ready() -> void:
	_spawn_nodes()

func _get_n_bits():
	var total_bits = 0
	var collision_mapping = {} # defines which layer is mapped to which cell obs index
	for i in 32:
		var bit_mask = 2**i
		if (detection_mask & bit_mask) > 0:
			collision_mapping[i] = total_bits
			total_bits += 1
		
		#prints(i, bit_mask, detection_mask, int((detection_mask & bit_mask) > 0), total_bits)
		
	return collision_mapping

func _spawn_nodes():
	for cell in get_children():
		cell.name = "_%s" % cell.name # Otherwise naming below will fail
		cell.queue_free()
	
	var collision_mapping = _get_n_bits()
	prints("collision_mapping", collision_mapping, len(collision_mapping))
	# allocate memory for the observations
	
	
	var box_shape := BoxShape3D.new()
	box_shape.set_size(Vector3(cell_width, cell_height, cell_width))
	var cell_step = -(grid_size/2)*cell_width
	var shift := Vector3(cell_step, 0, cell_step)
	for i in grid_size:
		for j in grid_size:
			var cell : = Area3D.new()
			cell.position = Vector3(i*cell_width, 0.0, j*cell_width) + shift
			cell.name = "GridCell %s %s" %[i, j]
			cell.collision_layer = 0
			cell.collision_mask = detection_mask
			cell.monitorable = false
			cell.input_ray_pickable = false
			add_child(cell)
			cell.set_owner(get_tree().edited_scene_root)
		
			var col_shape : = CollisionShape3D.new()
			col_shape.shape = box_shape
			col_shape.name = "ColShape %s %s" %[i, j]
			cell.add_child(col_shape)
			col_shape.set_owner(get_tree().edited_scene_root)
		


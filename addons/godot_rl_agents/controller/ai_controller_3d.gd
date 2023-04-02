extends AIController
class_name AIController3D

# ------------------ Godot RL Agents Logic ------------------------------------#
var _player: Spatial

func init(player: Spatial):
	_player = player

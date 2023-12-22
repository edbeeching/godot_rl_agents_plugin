extends Node3D
class_name RGBCameraSensor3D
var camera_pixels = null

@onready var camera_texture := $Control/TextureRect/CameraTexture as Sprite2D
@onready var sub_viewport := $SubViewport as SubViewport


func get_camera_pixel_encoding():
	return camera_texture.get_texture().get_image().get_data().hex_encode()


func get_camera_shape() -> Array:
	assert(
		sub_viewport.size.x >= 36 and sub_viewport.size.y >= 36,
		"SubViewport size must be 36x36 or larger."
	)
	if sub_viewport.transparent_bg:
		return [4, sub_viewport.size.y, sub_viewport.size.x]
	else:
		return [3, sub_viewport.size.y, sub_viewport.size.x]

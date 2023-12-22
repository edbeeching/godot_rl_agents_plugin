extends Node3D
class_name RGBCameraSensor3D
var camera_pixels = null

@onready var camera_texture := $Control/TextureRect/CameraTexture as Sprite2D

func get_camera_pixel_encoding():
	return camera_texture.get_texture().get_image().get_data().hex_encode()

func get_camera_shape()-> Array:
	assert($SubViewport.size.x >= 36 and $SubViewport.size.y >= 36, "SubViewport size must be 36x36 or larger.")
	if $SubViewport.transparent_bg:
		return [4, $SubViewport.size.y, $SubViewport.size.x]
	else:
		return [3, $SubViewport.size.y, $SubViewport.size.x]

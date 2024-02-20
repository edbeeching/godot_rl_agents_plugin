extends Node3D
class_name RGBCameraSensor3D
var camera_pixels = null

@onready var camera_texture := $Control/CameraTexture as Sprite2D
@onready var processed_texture := $Control/ProcessedTexture as Sprite2D
@onready var sub_viewport := $SubViewport as SubViewport
@onready var displayed_image: ImageTexture

@export var render_image_resolution := Vector2(36, 36)
## Display size does not affect rendered or sent image resolution.
## Scale is relative to either render image or downscale image resolution
## depending on which mode is set.
@export var displayed_image_scale_factor := Vector2(8, 8)

@export_group("Downscale image options")
## Enable to downscale the rendered image before sending the obs.
@export var downscale_image: bool = false
## If downscale_image is true, will display the downscaled image instead of rendered image.
@export var display_downscaled_image: bool = true
## This is the resolution of the image that will be sent after downscaling
@export var resized_image_resolution := Vector2(36, 36)


func _ready():
	sub_viewport.size = render_image_resolution
	camera_texture.scale = displayed_image_scale_factor

	if downscale_image and display_downscaled_image:
		camera_texture.visible = false
		processed_texture.scale = displayed_image_scale_factor
	else:
		processed_texture.visible = false


func get_camera_pixel_encoding():
	var image := camera_texture.get_texture().get_image() as Image

	if downscale_image:
		image.resize(
			resized_image_resolution.x, resized_image_resolution.y, Image.INTERPOLATE_NEAREST
		)
		if display_downscaled_image:
			if not processed_texture.texture:
				displayed_image = ImageTexture.create_from_image(image)
				processed_texture.texture = displayed_image
			else:
				displayed_image.update(image)

	return image.get_data().hex_encode()


func get_camera_shape() -> Array:
	var size = resized_image_resolution if downscale_image else render_image_resolution

	assert(
		size.x >= 36 and size.y >= 36,
		"Camera sensor sent image resolution must be 36x36 or larger."
	)
	if sub_viewport.transparent_bg:
		return [4, size.y, size.x]
	else:
		return [3, size.y, size.x]

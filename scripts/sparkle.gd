extends RefCounted
## The little glint over everything on the ground that can be picked up:
## dropped items (scenes/item_pickup.tscn) and the branches, stones and
## mushrooms in forage.gd. It's purely for show, so the server never sends
## anything about it: each peer animates its own, all in the shader (see
## shaders/sparkle.gdshader).

const SHADER := preload("res://shaders/sparkle.gdshader")

## How high above where the item lies, in meters, the glints center.
const HEIGHT := 0.15

static var _mesh: QuadMesh


## The one mesh every sparkle draws, with its material.
static func mesh() -> Mesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		var material := ShaderMaterial.new()
		material.shader = SHADER
		_mesh.material = material
		# The shader moves the glint around the item and turns it to the
		# camera, so leave room for that when culling.
		_mesh.custom_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	return _mesh

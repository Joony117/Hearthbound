extends RefCounted
## Bounds the town tests share (ig-6m2.8.2, ig-wgj.6). Not a test_ file, so GUT never runs it.


## The Pick box in the building's own frame: the Shape's size, through the Shape's transform.
static func pick_box(building: Node3D) -> AABB:
	var shape: CollisionShape3D = building.get_node("Pick/Shape") as CollisionShape3D
	var size: Vector3 = (shape.shape as BoxShape3D).size
	return shape.transform * AABB(-size / 2.0, size)


## The bounds of a shown model (the Model, or a Tier child) in the building's frame: every mesh under
## it, through its chain of transforms. A glTF root is not a mesh, so it has no AABB of its own.
static func bounds_under(building: Node3D, shown: Node3D) -> AABB:
	var bounds := AABB()
	var first: bool = true
	for node: Node in shown.find_children("*", "GeometryInstance3D", true, false):
		var mesh: GeometryInstance3D = node as GeometryInstance3D
		var moved: AABB = _relative_to(mesh, building) * mesh.get_aabb()
		bounds = moved if first else bounds.merge(moved)
		first = false
	return bounds


static func footprint(bounds: AABB) -> Rect2:
	return Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)


static func _relative_to(node: Node3D, building: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var step: Node3D = node
	while step != building:
		chain = step.transform * chain
		step = step.get_parent() as Node3D
	return chain

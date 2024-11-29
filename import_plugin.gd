@tool
extends EditorImportPlugin

enum PRESETS { DEFAULT }

const IMPORT_SETTINGS: ProcgenImportSettings = preload("res://addons/gd-procgen-arcana-addon/ProcGen_DefaultImportSettings.tres")


func _get_importer_name() -> String:
	return "procgen_arcana"

func _get_visible_name() -> String:
	return "Procgen Arcana"

func _get_recognized_extensions() -> PackedStringArray:
	return ["json"]

func _get_save_extension() -> String:
	return "json"

func _get_resource_type() -> String:
	return ''

func _get_priority() -> float:
	return 0.1

func _get_import_order() -> int:
	return ImportOrder.IMPORT_ORDER_SCENE

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	match preset_index:
		PRESETS.DEFAULT:
			return []
		_:
			return []

func _get_preset_count():
	return PRESETS.size()

func _get_preset_name(preset_index):
	match preset_index:
		PRESETS.DEFAULT:
			return "Default"
		_:
			return "Unknown"

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var root: Node3D = Node3D.new()
	root.name = "Map"

	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_file))

	# Make sure we have a valid Procgen Arcana JSON file
	if json == null:
		push_error("Unable to parse %s, not valid JSON." % source_file)
		return ERR_FILE_CANT_READ
	elif not json.has('type') or json.type != 'FeatureCollection' or not json.has('features'):
		push_error("Unable to find feature list for file %s - not a Procgen Arcana JSON file?" % source_file)
		return ERR_FILE_CANT_READ

	for row in json.features:
		if has_method("_import_" + row.id):
			call("_import_" + row.id, root, row)

	var scene = PackedScene.new()
	var pack_result = scene.pack(root)

	if pack_result != Error.OK:
		root.free()
		return pack_result

	var copy_result: Error = DirAccess.copy_absolute(
		source_file,
		"%s.%s" % [save_path, _get_save_extension()]
	)
	if copy_result != OK:
		return copy_result

	var save_result: Error = ResourceSaver.save(scene, source_file.replace(".json", ".tscn"))
	return save_result



func _import_earth(scene_root: Node3D, data: Variant) -> void:
	var min_xy: Vector2 = Vector2.INF
	var max_xy: Vector2 = -Vector2.INF

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = IMPORT_SETTINGS.COL_EARTH

	var verts: PackedVector2Array
	for point in data.coordinates[0]:
		verts.push_back(Vector2(point[0], point[1]))

	var csg: CSGPolygon3D = CSGPolygon3D.new()
	csg.polygon = verts
	csg.name = "%s" % data.id
	scene_root.add_child(csg)
	csg.set_owner(scene_root)
	csg.rotation_degrees.x = -90
	csg.material = mat
	csg.depth = 0.02


func _import_buildings(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var house_scene : PackedScene = IMPORT_SETTINGS.house_mesh

	var num: int = 0
	for building in data.coordinates:
		# Get building boundaries
		var coord_data: Dictionary = get_coord_data(building[0])

		# Make the building
		var m:Node3D = house_scene.instantiate()
		#m.name = "building_%s" % num
		m.name = "building_%s" % num
		m.scale = Vector3(coord_data.width, 1, coord_data.depth)
		m.position = coord_data.center
		m.rotation.y = coord_data['rotation']

		parent.add_child(m)
		m.set_owner(scene_root)

		num += 1


func _import_fields(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.424, 0.38, 0.365)

	var num: int = 0
	for coord in data.coordinates:
		var verts: PackedVector2Array
		for point in coord[0]:
			verts.push_back(Vector2(point[0], point[1]))

		var csg: CSGPolygon3D = CSGPolygon3D.new()
		csg.polygon = verts
		csg.name = "%s_%s" % [data.id, num]
		parent.add_child(csg)
		csg.set_owner(scene_root)
		csg.rotation_degrees.x = -90
		csg.position.y += 0.01
		csg.material = mat
		csg.depth = 0.02

		num += 1


func _import_palisade(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.424, 0.38, 0.365)

	var num: int = 0
	for coord in data.coordinates:
		var verts: PackedVector2Array
		for point in coord:
			verts.push_back(Vector2(point[0], point[1]))

		# Create a path
		var path: Path3D = Path3D.new()
		path.name = "%s_%s" % [data.id, num]
		parent.add_child(path)
		path.set_owner(scene_root)
		path.curve = Curve3D.new()
		for point in coord:
			path.curve.add_point(Vector3(point[0], 0, -point[1]))

		# Add a CSGPolygon3D that follows the path
		var csg: CSGPolygon3D = CSGPolygon3D.new()
		csg.name = "%s_mesh_%s" % [data.id, num]
		path.add_child(csg)
		csg.set_owner(scene_root)
		csg.mode = CSGPolygon3D.MODE_PATH
		csg.path_node = NodePath("..")
		csg.material = mat
		csg.polygon = PackedVector2Array([
			Vector2(-.5, -.01),
			Vector2(-.5, 2),
			Vector2(.5, 2),
			Vector2(.5, -.01),
		])

		num += 1


func _import_planks(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.722, 0.616, 0.541)

	var num: int = 0
	for geo in data.geometries:
		# Create a path
		var path: Path3D = Path3D.new()
		path.name = "plank_%s" % num
		parent.add_child(path)
		path.set_owner(scene_root)
		path.curve = Curve3D.new()
		for coord in geo.coordinates:
			path.curve.add_point(Vector3(coord[0], 0, -coord[1]))

		# Add a CSGPolygon3D that follows the path
		var csg: CSGPolygon3D = CSGPolygon3D.new()
		csg.name = "plank_mesh_%s" % num
		path.add_child(csg)
		csg.set_owner(scene_root)
		csg.mode = CSGPolygon3D.MODE_PATH
		csg.path_node = NodePath("..")
		csg.material = mat
		csg.polygon = PackedVector2Array([
			Vector2(-geo.width/2, -.01),
			Vector2(-geo.width/2, .5),
			Vector2(geo.width/2, .5),
			Vector2(geo.width/2, -.01),
		])


func _import_roads(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = IMPORT_SETTINGS.COL_ROAD

	var num: int = 0
	for geo in data.geometries:
		# Create a path
		var path: Path3D = Path3D.new()
		path.name = "road_%s" % num
		parent.add_child(path)
		path.set_owner(scene_root)
		path.curve = Curve3D.new()
		for coord in geo.coordinates:
			path.curve.add_point(Vector3(coord[0], 0, -coord[1]))

		# Add a CSGPolygon3D that follows the path
		var csg: CSGPolygon3D = CSGPolygon3D.new()
		csg.name = "road_mesh_%s" % num
		path.add_child(csg)
		csg.set_owner(scene_root)
		csg.mode = CSGPolygon3D.MODE_PATH
		csg.path_node = NodePath("..")
		csg.material = mat
		csg.polygon = PackedVector2Array([
			Vector2(-geo.width/2, -.01),
			Vector2(-geo.width/2, .02),
			Vector2(geo.width/2, .02),
			Vector2(geo.width/2, -.01),
		])

		num += 1

func _import_squares(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = IMPORT_SETTINGS.COL_ROAD

	var num: int = 0
	for coord in data.coordinates:
		var verts: PackedVector2Array
		for point in coord[0]:
			verts.push_back(Vector2(point[0], point[1]))

		var csg: CSGPolygon3D = CSGPolygon3D.new()
		csg.polygon = verts
		csg.name = "%s_%s" % [data.id, num]
		parent.add_child(csg)
		csg.set_owner(scene_root)
		csg.rotation_degrees.x = -90
		csg.position.y += 0.01
		csg.material = mat
		csg.depth = 0.02

		num += 1



func _import_trees(scene_root: Node3D, data: Variant) -> void:
	var parent: Node3D = Node3D.new()
	parent.name = data.id
	scene_root.add_child(parent)
	parent.set_owner(scene_root)

	var tree_scene : PackedScene = IMPORT_SETTINGS.tree_mesh
	
	var num: int = 0
	for coord in data.coordinates:
		# Make the building
		var m:Node3D = tree_scene.instantiate()
		#m.name = "building_%s" % num
		m.name = "tree_%s" % num
		m.position = Vector3(coord[0], 0, -coord[1])
		parent.add_child(m)
		m.set_owner(scene_root)

		num += 1

func _import_water(scene_root: Node3D, data: Variant) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = IMPORT_SETTINGS.COL_WATER

	var verts: PackedVector2Array
	for point in data.coordinates[0][0]:
		verts.push_back(Vector2(point[0], point[1]))

	var csg: CSGPolygon3D = CSGPolygon3D.new()
	csg.polygon = verts
	csg.name = "%s" % data.id
	scene_root.add_child(csg)
	csg.set_owner(scene_root)
	csg.rotation_degrees.x = -90
	csg.position.y += 0.01
	csg.material = mat
	csg.depth = 0.02

	# When there are 2 water sets, the first is an island cutout and second is
	# an earth-sized rect.
	# We need to change the cutout (water[0]) to be earth coloured, and change
	# the earth node to be water coloured.
	# Both nodes then need to be lowered by 0.01 so we're not overlapping fields,
	# roads etc
	if data.coordinates.size() > 1:
		csg.material.albedo_color = IMPORT_SETTINGS.COL_EARTH
		csg.position.y -= 0.01
		var earth: CSGPolygon3D = scene_root.get_node("earth")
		earth.material.albedo_color = IMPORT_SETTINGS.COL_WATER
		earth.position.y -= 0.01


func get_coord_data(coords: Variant) -> Dictionary:
	var dict: Dictionary = {}

	# Convert coords to vectors
	var points: Array[Vector3]
	points.resize(4)
	points[0] = Vector3(coords[0][0], 0, -coords[0][1])
	points[1] = Vector3(coords[1][0], 0, -coords[1][1])
	points[2] = Vector3(coords[2][0], 0, -coords[2][1])
	points[3] = Vector3(coords[3][0], 0, -coords[3][1])

	dict['width'] = points[1].distance_to(points[0])
	dict['depth'] = points[3].distance_to(points[1])
	dict['center'] = (points[1] + points[3]) / 2.0
	#dict['rotation'] = points[2].angle_to(points[1])
	dict['rotation'] = Vector2(coords[0][0], coords[0][1]).angle_to_point(Vector2(coords[1][0], coords[1][1]))

	return dict

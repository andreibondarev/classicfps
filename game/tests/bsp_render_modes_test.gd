extends SceneTree

const BspMapScript := preload("res://scripts/bsp_map.gd")
const ASSAULT_MAP := "res://generated/cs_assault/map.json"
const INFERNO_MAP := "res://generated/de_inferno/map.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BSP RENDER MODE TEST: " + message)


func _first_material(map: BspMap, model_index: int) -> Material:
	var root_node := map.model_root(model_index)
	if not is_instance_valid(root_node):
		return null
	for child: Node in root_node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			if is_instance_valid(mesh) and mesh.get_surface_count() > 0:
				return mesh.surface_get_material(0)
	return null


## Opaque brush submodels now share the world's lightmapped ShaderMaterial
## (GoldSrc lightmaps doors/rotating brushes exactly like worldspawn); a
## plain-opaque submodel is therefore either that shader or an opaque
## StandardMaterial fallback on maps without a baked atlas.
func _is_opaque(material: Material) -> bool:
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return (
			is_instance_valid(shader)
			and shader.code == BspMapScript.LIGHTMAP_SHADER_SOURCE
		)
	if material is StandardMaterial3D:
		return (
			(material as StandardMaterial3D).transparency
			== BaseMaterial3D.TRANSPARENCY_DISABLED
		)
	return false


func _run() -> void:
	var assault := BspMapScript.new()
	root.add_child(assault)
	_check(assault.load_map(ASSAULT_MAP), "stock Assault loads")
	var translucent := _first_material(assault, 56) as StandardMaterial3D
	_check(
		is_instance_valid(translucent)
		and translucent.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		and absf(translucent.albedo_color.a - 50.0 / 255.0) <= 0.0001,
		"render mode 2 glass uses authored renderamt 50 alpha blending",
	)
	var ordinary := _first_material(assault, 11)
	_check(
		is_instance_valid(ordinary) and _is_opaque(ordinary),
		"ordinary rotating entrance remains opaque",
	)
	assault.queue_free()
	await process_frame
	if FileAccess.file_exists(INFERNO_MAP):
		var inferno := BspMapScript.new()
		root.add_child(inferno)
		_check(inferno.load_map(INFERNO_MAP), "stock Inferno loads")
		# *148 is a lamp-post clip func_wall: rendermode 2 with no renderamt.
		_check(
			_first_material(inferno, 148) == null,
			"render mode 2 without renderamt draws nothing (GoldSrc zero default)",
		)
		_check(
			inferno._model_collision_faces.has(148),
			"invisible render-mode func_wall keeps its collision",
		)
		_check(
			_first_material(inferno, 120) != null,
			"lamp-post lantern inside the clip wall still renders",
		)
		inferno.queue_free()
		await process_frame
	if failures.is_empty():
		print("BSP_RENDER_MODES_TEST_PASS")
		await process_frame
		quit(0)
	else:
		print("BSP_RENDER_MODES_TEST_FAIL (%d)" % failures.size())
		quit(1)

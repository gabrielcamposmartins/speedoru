extends Node
## Cena inicial: abre a tela de carregamento e carrega o menu principal (garagem) por trás dela.

@export_file("*.tscn") var first_scene := "res://scenes/menu/main_menu.tscn"


func _ready() -> void:
	# Servidor dedicado (godot --headless --path . -- --server): sem menu, só o GameServer
	var net := get_node_or_null("/root/Net")
	if net and net.is_server:
		var server := GameServer.new()
		server.name = "GameServer"
		get_tree().change_scene_to_node.call_deferred(server)
		return
	var loading := get_node_or_null("/root/Loading") as LoadingScreen
	if loading:
		loading.change_scene.call_deferred(first_scene)
	else:
		get_tree().change_scene_to_file.call_deferred(first_scene)

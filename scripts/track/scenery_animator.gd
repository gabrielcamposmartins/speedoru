class_name SceneryAnimator
extends SceneryAnimatorCore
## Anima os objetos do cenário: rotores das turbinas, balões flutuando, dirigíveis em órbita e
## nuvens levadas pelo vento (voltam do outro lado ao sair da área).
## Roda no código nativo (SceneryAnimatorCore, native/src/scenery.rs): add_rotor, add_balloon,
## add_blimp, add_flock, add_blimp_pass, remove_blimp, add_clouds e cloud_wind são de lá.

## Terreno (opcional): dirigíveis e pássaros mantêm altura mínima sobre o relevo.
var terrain: TrackTerrain:
	set(value):
		terrain = value
		_core_set_terrain(value)

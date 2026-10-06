class_name TrackSurface
extends RefCounted
## Tipos de piso. Cada StaticBody3D da pista guarda o tipo no metadado "surface"; o modelo de
## pneu do F1Car lê o corpo em contato com cada roda (sem metadado = asfalto).

enum Type { ASPHALT, KERB, GRASS, GRAVEL, BARRIER }

const NAMES := ["asfalto", "zebra", "grama", "cascalho", "barreira"]
## Multiplicador do coeficiente de atrito do pneu.
const GRIP := [1.0, 0.9, 0.55, 0.5, 0.6]
## Resistência ao rolamento extra (fração da carga na roda): o cascalho segura o carro.
const DRAG := [0.0, 0.004, 0.06, 0.45, 0.0]
## Vibração vertical (m/s² aprox.) — zebras e cascalho chacoalham o carro.
const RUMBLE := [0.0, 2.5, 0.6, 3.5, 0.0]


static func of_body(body: Object) -> int:
	if body != null and body.has_meta("surface"):
		return int(body.get_meta("surface"))
	return Type.ASPHALT


static func make_body(node_name: String, type: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.set_meta("surface", type)
	return body

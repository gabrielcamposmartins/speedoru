class_name NetSnapshot
extends RefCounted
## Instantâneo binário de todos os carros da corrida (servidor → clientes, 30 por segundo).
##
## Cabeçalho: tempo do servidor (f64) e número de carros (u8). Por carro (68 bytes): índice,
## posição, rotação, velocidade, giro, marcha, pedais, direção, bandeiras (DRS, boost, limitador,
## parado, escondido, TC, ABS, automático), bateria, desgaste dos 4 pneus, composto, dano
## (asa dianteira/traseira, arrasto, motor), rodas quebradas, uso dos pneus, balanço de freio e
## quanto cada roda está abaixo da fixação (suspensão, em mm).

const F_DRS := 1
const F_BOOST := 2
const F_LIMITER := 4
const F_HOLD := 8
const F_HIDDEN := 16
const F_TC := 32
const F_ABS := 64
const F_AUTO := 128


static func encode(time: float, entries: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_double(time)
	b.put_u8(entries.size())
	for e: RaceEntry in entries:
		var car := e.car
		var xf := car.global_transform
		var q := xf.basis.get_rotation_quaternion()
		var v := car.linear_velocity
		b.put_u8(e.index)
		b.put_float(xf.origin.x)
		b.put_float(xf.origin.y)
		b.put_float(xf.origin.z)
		b.put_float(q.x)
		b.put_float(q.y)
		b.put_float(q.z)
		b.put_float(q.w)
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
		b.put_u16(clampi(roundi(car.rpm), 0, 65535))
		b.put_8(clampi(car.gear, -1, 9))
		b.put_u8(_u8(car.throttle_input if car.gear != -1 else maxf(car.throttle_input, car.reverse_input)))
		b.put_u8(_u8(car.brake_input))
		b.put_8(clampi(roundi(car.steering / 0.5 * 127.0), -127, 127))
		var flags := 0
		if car.drs_open:
			flags |= F_DRS
		if car.boost_active:
			flags |= F_BOOST
		if car.limiter_on:
			flags |= F_LIMITER
		if car.hold:
			flags |= F_HOLD
		if not car.visible:
			flags |= F_HIDDEN
		if car.traction_control:
			flags |= F_TC
		if car.abs_active:
			flags |= F_ABS
		if car.automatic:
			flags |= F_AUTO
		b.put_u8(flags)
		b.put_u8(_u8(car.battery))
		for k in 4:
			b.put_u8(_u8(car.tire_wear[k]))
		b.put_u8(car.config.tyre_compound if car.config else 1)
		b.put_u8(_u8(car.damage_front_downforce))
		b.put_u8(_u8(car.damage_rear_downforce))
		b.put_u8(_u8(car.damage_drag))
		b.put_u8(_u8(car.damage_power))
		var broken := 0
		for k in mini(car.wheel_broken.size(), 4):
			if car.wheel_broken[k]:
				broken |= 1 << k
		b.put_u8(broken)
		for k in 4:
			b.put_u8(_u8(car.tire_usage[k] * 0.5))
		b.put_u8(_u8(car.brake_bias_front))
		var wheels := car.get_wheels()
		for k in 4:
			var drop := 0.04
			if k < wheels.size() and k < car._mounts.size():
				drop = car._mounts[k].y - wheels[k].position.y
			b.put_u8(clampi(roundi(drop * 1000.0), 0, 255))
	return b.data_array


## {"t": tempo, "cars": {índice: {pos, rot, vel, rpm, gear, ...}}}
static func decode(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	var n := b.get_u8()
	var cars := {}
	for i in n:
		var c := {}
		var idx := b.get_u8()
		c["pos"] = Vector3(b.get_float(), b.get_float(), b.get_float())
		c["rot"] = Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float()).normalized()
		c["vel"] = Vector3(b.get_float(), b.get_float(), b.get_float())
		c["rpm"] = float(b.get_u16())
		c["gear"] = b.get_8()
		c["throttle"] = b.get_u8() / 255.0
		c["brake"] = b.get_u8() / 255.0
		c["steer"] = b.get_8() / 127.0 * 0.5
		c["flags"] = b.get_u8()
		c["battery"] = b.get_u8() / 255.0
		c["wear"] = PackedFloat32Array([b.get_u8() / 255.0, b.get_u8() / 255.0, b.get_u8() / 255.0, b.get_u8() / 255.0])
		c["compound"] = b.get_u8()
		c["damage"] = PackedFloat32Array([b.get_u8() / 255.0, b.get_u8() / 255.0, b.get_u8() / 255.0, b.get_u8() / 255.0])
		c["broken"] = b.get_u8()
		c["usage"] = PackedFloat32Array([b.get_u8() / 127.5, b.get_u8() / 127.5, b.get_u8() / 127.5, b.get_u8() / 127.5])
		c["bias"] = b.get_u8() / 255.0
		c["drop"] = PackedFloat32Array([b.get_u8() / 1000.0, b.get_u8() / 1000.0, b.get_u8() / 1000.0, b.get_u8() / 1000.0])
		cars[idx] = c
	return {"t": t, "cars": cars}


static func _u8(x: float) -> int:
	return clampi(roundi(x * 255.0), 0, 255)

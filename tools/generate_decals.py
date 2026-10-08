"""
Gera os decalques padrão do carro (SVG brancos; a cor é escolhida no jogo).

Uso (a partir da raiz do projeto):
    python tools/generate_decals.py

Saída: assets/decals/<id>.svg. Os desenhos são só formas (sem texto/fontes) para o
rasterizador de SVG do Godot (ThorVG) e ficam brancos com fundo transparente: no jogo o
decalque é projetado no carro (Decal) e tingido com a cor escolhida.
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "decals")


def svg(w, h, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n%s\n</svg>\n'
            % (w, h, w, h, body))


def poly(points, extra=""):
    pts = " ".join("%.1f,%.1f" % p for p in points)
    return '<polygon points="%s" fill="#ffffff"%s/>' % (pts, extra)


def star(cx, cy, r_out, r_in, n=5, rot=-90.0):
    pts = []
    for k in range(n * 2):
        r = r_out if k % 2 == 0 else r_in
        a = math.radians(rot + k * 180.0 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def decals():
    out = {}
    out["estrela"] = svg(512, 512, poly(star(256, 270, 240, 100)))
    out["raio"] = svg(512, 512, poly([(300, 10), (90, 290), (230, 290), (170, 502), (420, 200), (270, 200), (360, 10)]))
    # Chamas: três línguas de fogo saindo da esquerda
    flames = []
    for k, (y, length, thick) in enumerate([(120, 900, 70), (200, 1000, 90), (285, 820, 70)]):
        x0 = 20
        d = ("M %d %d C %d %d, %d %d, %d %d C %d %d, %d %d, %d %d Z"
             % (x0, y - thick, x0 + length * 0.35, y - thick * 1.6, x0 + length * 0.7, y - thick * 0.2, x0 + length, y - thick * 0.9,
                x0 + length * 0.75, y + thick * 0.4, x0 + length * 0.4, y + thick * 1.3, x0, y + thick))
        flames.append('<path d="%s" fill="#ffffff"/>' % d)
    out["chamas"] = svg(1024, 400, "\n".join(flames))
    # Bandeira quadriculada (4 x 9)
    sq = []
    s = 56
    for r in range(4):
        for c in range(9):
            if (r + c) % 2 == 0:
                sq.append('<rect x="%d" y="%d" width="%d" height="%d" fill="#ffffff"/>' % (c * s, r * s, s, s))
    sq.append('<rect x="0" y="0" width="%d" height="%d" fill="none" stroke="#ffffff" stroke-width="6"/>' % (9 * s, 4 * s))
    out["xadrez"] = svg(9 * s, 4 * s, "\n".join(sq))
    # Sakura: cinco pétalas com o entalhe na ponta
    petals = []
    for k in range(5):
        a = k * 72.0
        petals.append('<g transform="rotate(%.1f 256 256)"><path d="M 256 250 C 170 200, 170 70, 230 40 L 256 80 L 282 40 '
                      'C 342 70, 342 200, 256 250 Z" fill="#ffffff"/></g>' % a)
    petals.append('<circle cx="256" cy="256" r="26" fill="#ffffff"/>')
    out["sakura"] = svg(512, 512, "\n".join(petals))
    out["coracao"] = svg(512, 512, '<path d="M 256 470 C 120 360, 20 270, 40 160 C 60 50, 200 40, 256 140 C 312 40, 452 50, 472 160 '
                                   'C 492 270, 392 360, 256 470 Z" fill="#ffffff"/>')
    # Asas: emblema com escudo redondo no meio e quatro penas de cada lado, as de cima mais longas
    wing = []
    for side in (-1, 1):
        for k in range(4):
            y0 = 140 + k * 42
            x0 = 512 + side * 70
            x1 = 512 + side * (470 - k * 85)
            y1 = 70 + k * 60
            wing.append(poly([(x0, y0 - 18), (x1, y1 - 14), (x1 + side * 26, y1 + 6), (x1, y1 + 18), (x0, y0 + 18)]))
    wing.append('<circle cx="512" cy="190" r="95" fill="#ffffff"/>')
    out["asas"] = svg(1024, 340, "\n".join(wing))
    # Listras de velocidade (paralelogramos inclinados)
    stripes = [poly([(60 + k * 30, 40 + k * 110), (1000 - k * 120, 40 + k * 110), (960 - k * 120, 110 + k * 110),
                     (20 + k * 30, 110 + k * 110)]) for k in range(3)]
    out["listras"] = svg(1024, 380, "\n".join(stripes))
    # Garras: três rasgos curvos, grossos no meio e finos nas pontas
    claws = []
    for k in range(3):
        x = 110 + k * 135
        claws.append('<path d="M %d 20 C %d 160, %d 330, %d 495 C %d 330, %d 170, %d 20 Z" fill="#ffffff"/>'
                     % (x, x + 95, x + 55, x - 20, x + 5, x + 25, x + 30))
    out["garras"] = svg(512, 512, "\n".join(claws))
    # Disco de número (anel + círculo)
    out["alvo"] = svg(512, 512, '<circle cx="256" cy="256" r="236" fill="none" stroke="#ffffff" stroke-width="34"/>\n'
                                '<circle cx="256" cy="256" r="150" fill="#ffffff"/>')
    # Onda: faixa senoidal
    top = []
    bottom = []
    for k in range(41):
        x = k * 1024.0 / 40
        y = 150 + 90 * math.sin(k / 40.0 * math.tau * 1.5)
        top.append((x, y - 45))
        bottom.append((x, y + 45))
    out["onda"] = svg(1024, 300, poly(top + bottom[::-1]))
    # "S" grosso com pontas arredondadas (logo da equipe)
    out["logo_s"] = svg(512, 512, '<path d="M 390 120 C 320 40, 130 50, 140 160 C 150 260, 370 240, 375 345 C 380 460, 180 475, 115 395" '
                                  'fill="none" stroke="#ffffff" stroke-width="78" stroke-linecap="round"/>')
    # Estrela cadente: estrela + rastro
    trail = poly([(60, 330), (330, 210), (360, 260), (90, 360)]) + poly([(100, 420), (320, 300), (340, 340), (120, 445)])
    out["cometa"] = svg(640, 512, trail + "\n" + poly(star(470, 200, 150, 62)))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, text in decals().items():
        with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("  ", name)


if __name__ == "__main__":
    main()

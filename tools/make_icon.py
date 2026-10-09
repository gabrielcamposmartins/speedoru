"""
Ícone do Speedoru: uma roda de F1 estilo anime (pneu preto com brilho toon e a faixa amarela do
composto, aro escuro com raios ciano, a pinça de freio vermelha aparecendo e a porca central).

Uso (raiz do projeto):  python tools/make_icon.py
Gera assets/ui/speedoru_icon.png (1024 px, janela do jogo) e assets/ui/speedoru_icon.ico (16 a
256 px: o .exe, o instalador e os atalhos).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")
S = 2048  # desenha grande e reduz (borda suave)
C = S / 2

TYRE = (24, 24, 31, 255)
TYRE_LIGHT = (70, 72, 88, 255)
TYRE_EDGE = (10, 10, 14, 255)
STRIPE = (255, 210, 63, 255)
RIM = (36, 39, 50, 255)
DISC = (18, 19, 24, 255)
SPOKE = (56, 242, 255, 255)
SPOKE_DARK = (18, 150, 190, 255)
LIP = (56, 242, 255, 255)
CALIPER = (232, 37, 70, 255)
HUB = (205, 214, 228, 255)
NUT = (60, 64, 76, 255)
GLOW = (56, 242, 255)


def circle(d, r, fill, cx=C, cy=C):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def ring(d, r0, r1, fill, a0=0, a1=360, steps=240):
    """Anel entre r0 e r1, de a0 a a1 graus (0 = direita, sentido horário na tela)."""
    pts = []
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append((C + math.cos(a) * r1, C + math.sin(a) * r1))
    for k in range(steps, -1, -1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append((C + math.cos(a) * r0, C + math.sin(a) * r0))
    d.polygon(pts, fill=fill)


def wedge(d, a_mid, r0, r1, w0, w1, fill):
    """Raio em cunha: largura w0 no cubo e w1 no aro (em graus)."""
    pts = []
    for r, w in ((r0, -w0), (r1, -w1), (r1, w1), (r0, w0)):
        a = math.radians(a_mid + w / 2)
        pts.append((C + math.cos(a) * r, C + math.sin(a) * r))
    d.polygon(pts, fill=fill)


def main():
    R = S * 0.46
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Brilho neon em volta (a cor da marca)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    ring(gd, R * 0.97, R * 1.04, (*GLOW, 170))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.018))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    # Pneu: contorno escuro, borracha e o brilho toon (meia-lua em cima à esquerda)
    circle(d, R, TYRE_EDGE)
    circle(d, R * 0.975, TYRE)
    ring(d, R * 0.80, R * 0.93, TYRE_LIGHT, 195, 285)
    ring(d, R * 0.83, R * 0.90, (98, 100, 120, 255), 215, 265)
    # Faixa amarela do composto, com duas falhas
    ring(d, R * 0.70, R * 0.745, STRIPE, 20, 160)
    ring(d, R * 0.70, R * 0.745, STRIPE, 200, 340)
    # Aro: fundo escuro (disco de freio) e a pinça vermelha atrás dos raios
    circle(d, R * 0.64, TYRE_EDGE)
    circle(d, R * 0.62, DISC)
    ring(d, R * 0.40, R * 0.56, CALIPER, -70, -25)
    # Raios: cinco pares em cunha, ciano, com o lado escuro (dá volume)
    for k in range(5):
        a = -90 + k * 72
        for off in (-9, 9):
            wedge(d, a + off, R * 0.17, R * 0.60, 7, 11, SPOKE_DARK)
            wedge(d, a + off - 1.5, R * 0.17, R * 0.60, 5, 8, SPOKE)
    # Lábio do aro (ciano) por cima das pontas dos raios
    ring(d, R * 0.585, R * 0.64, LIP)
    ring(d, R * 0.585, R * 0.60, SPOKE_DARK)
    # Cubo: prata com a porca sextavada e um brilho
    circle(d, R * 0.20, TYRE_EDGE)
    circle(d, R * 0.18, HUB)
    hexagon = [(C + math.cos(math.radians(30 + 60 * k)) * R * 0.10, C + math.sin(math.radians(30 + 60 * k)) * R * 0.10)
               for k in range(6)]
    d.polygon(hexagon, fill=NUT)
    circle(d, R * 0.035, (235, 240, 248, 255), cx=C - R * 0.08, cy=C - R * 0.08)
    big = img.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    big.save(os.path.join(OUT, "speedoru_icon.png"))
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    big.save(os.path.join(OUT, "speedoru_icon.ico"), sizes=sizes)
    print("ícone gerado em", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()

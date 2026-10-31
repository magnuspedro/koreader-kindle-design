#!/usr/bin/env python3
"""Generate the gesture diagrams used in the README (docs/gestures/*.svg).

Run from the repository root:  python3 tools/gen_gestures.py
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "gestures")
FONT = "font-family='Helvetica, Arial, sans-serif'"
INK = "#111"
SOFT = "#888"


def svg(w, h, body):
    return (f"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' viewBox='0 0 {w} {h}'>"
            "<defs><marker id='a' viewBox='0 0 10 10' refX='6' refY='5' markerWidth='5' markerHeight='5' "
            f"orient='auto-start-reverse'><path d='M0,0 L10,5 L0,10 z' fill='{INK}'/></marker></defs>"
            f"<rect width='{w}' height='{h}' fill='white'/>{body}</svg>")


def text(x, y, s, size=13, anchor="middle", weight="normal", color=INK):
    return (f"<text x='{x}' y='{y}' {FONT} font-size='{size}' text-anchor='{anchor}' "
            f"font-weight='{weight}' fill='{color}'>{s}</text>")


# ---------------------------------------------------------------- tap zones
def zones():
    W, H = 760, 640
    fx, fy, fw, fh = 30, 20, 340, 600          # device frame
    sx, sy, sw, sh = fx + 22, fy + 22, fw - 44, fh - 70  # screen
    b = [f"<rect x='{fx}' y='{fy}' width='{fw}' height='{fh}' rx='26' fill='#222'/>",
         f"<rect x='{sx}' y='{sy}' width='{sw}' height='{sh}' fill='white'/>",
         text(fx + fw / 2, fy + fh - 16, "kindle", 14, color="#999")]

    def zone(x, y, w, h, n, fill):
        X, Y, Wd, Hd = sx + x * sw, sy + y * sh, w * sw, h * sh
        b.append(f"<rect x='{X:.1f}' y='{Y:.1f}' width='{Wd:.1f}' height='{Hd:.1f}' fill='{fill}' "
                 f"stroke='{SOFT}' stroke-dasharray='4 3'/>")
        cx, cy = X + Wd / 2, Y + Hd / 2
        b.append(f"<circle cx='{cx:.1f}' cy='{cy:.1f}' r='13' fill='{INK}'/>")
        b.append(text(cx, cy + 5, n, 14, weight="bold", color="white"))

    zone(0, 1 / 8, 1 / 4, 6 / 8, "6", "#f4f4f4")      # back
    zone(1 / 4, 1 / 8, 3 / 4, 6 / 8, "7", "#fbfbfb")  # forward
    zone(1 / 8, 0, 6 / 8, 1 / 8, "1", "#e2e2e2")      # toolbar
    zone(0, 0, 1 / 8, 1 / 8, "3", "#cfcfcf")          # page flipping
    zone(7 / 8, 0, 1 / 8, 1 / 8, "2", "#cfcfcf")      # bookmark
    zone(1 / 8, 7 / 8, 7 / 8, 1 / 8, "5", "#e2e2e2")  # Aa
    zone(0, 7 / 8, 1 / 8, 1 / 8, "4", "#cfcfcf")      # light

    legend = [
        ("1", "Toque: barra de ferramentas", "Segurar a barra do topo: painel Aa"),
        ("2", "Marcar / desmarcar página", ""),
        ("3", "Modo folhear (liga/desliga)", ""),
        ("4", "Luz: liga/desliga", ""),
        ("5", "Painel Aa", ""),
        ("6", "Página anterior", "2 toques: volta 10 páginas"),
        ("7", "Próxima página", "2 toques: avança 10 páginas"),
    ]
    lx, ly = 400, 60
    b.append(text(lx, ly - 20, "Toques na página", 20, "start", "bold"))
    for n, a, c in legend:
        b.append(f"<circle cx='{lx + 13}' cy='{ly + 14}' r='13' fill='{INK}'/>")
        b.append(text(lx + 13, ly + 19, n, 14, weight="bold", color="white"))
        b.append(text(lx + 36, ly + 14 + (0 if c else 5), a, 15, "start"))
        if c:
            b.append(text(lx + 36, ly + 32, c, 13, "start", color="#555"))
        ly += 68 if c else 54
    return svg(W, H, "".join(b))


# ---------------------------------------------------------------- gestures
DIRS = {"n": (0, -1), "s": (0, 1), "e": (1, 0), "w": (-1, 0),
        "ne": (0.75, -0.75), "nw": (-0.75, -0.75), "se": (0.75, 0.75), "sw": (-0.75, 0.75)}
MW, MH = 84, 112   # mini screen


def arrow(points, width=4):
    d = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    return (f"<polyline points='{d}' fill='none' stroke='{INK}' stroke-width='{width}' "
            "stroke-linejoin='round' stroke-linecap='round' marker-end='url(#a)'/>")


def dot(x, y):
    return f"<circle cx='{x:.1f}' cy='{y:.1f}' r='5' fill='{INK}'/>"


def path_from(dirs, step=34, jog=16):
    pts = [(0.0, 0.0)]
    prev = None
    for d in dirs:
        dx, dy = DIRS[d]
        if prev and (dx, dy) == (-prev[0], -prev[1]):
            # U-turn: shift the return stroke sideways so both strokes stay visible
            jx, jy = (0, jog) if dy == 0 else (jog, 0)
            pts.append((pts[-1][0] + jx, pts[-1][1] + jy))
        pts.append((pts[-1][0] + dx * step, pts[-1][1] + dy * step))
        prev = (dx, dy)
    if len(pts) > 2 and abs(pts[-1][0] - pts[0][0]) < 1 and abs(pts[-1][1] - pts[0][1]) < 1:
        # closed loop: stop short so the start dot stays visible
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        pts[-1] = (x0 + (x1 - x0) * 0.65, y0 + (y1 - y0) * 0.65)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    ox = MW / 2 - (min(xs) + max(xs)) / 2
    oy = MH / 2 - (min(ys) + max(ys)) / 2
    return [(x + ox, y + oy) for x, y in pts]


def drawing(kind, arg):
    """Return SVG elements inside the mini screen (origin 0,0)."""
    if kind == "multi":
        pts = path_from(arg, step=34 if len(arg) <= 2 else 26)
        return dot(*pts[0]) + arrow(pts)
    if kind == "swipe":
        pts = path_from([arg], step=50)
        return dot(*pts[0]) + arrow(pts)
    if kind == "two":
        dx, dy = DIRS[arg]
        out = ""
        for k in (-1, 1):
            ox, oy = (-dy * 10 * k, dx * 10 * k)
            p0 = (MW / 2 - dx * 22 + ox, MH / 2 - dy * 22 + oy)
            p1 = (MW / 2 + dx * 22 + ox, MH / 2 + dy * 22 + oy)
            out += dot(*p0) + arrow([p0, p1])
        return out
    if kind == "pinch":
        c = (MW / 2, MH / 2)
        out = ""
        for sgn in (-1, 1):
            far = (c[0] + sgn * 28, c[1] + sgn * 34)
            near = (c[0] + sgn * 8, c[1] + sgn * 10)
            out += (dot(*far) + arrow([far, near])) if arg == "in" else (dot(*near) + arrow([near, far]))
        return out
    if kind == "edge":
        dy = -1 if arg == "up" else 1
        p0, p1 = (9, MH / 2 - dy * 30), (9, MH / 2 + dy * 30)
        return dot(*p0) + arrow([p0, p1])
    if kind == "top_down":
        return (f"<rect x='0' y='0' width='{MW}' height='14' fill='#e2e2e2'/>"
                + dot(MW / 2, 6) + arrow([(MW / 2, 6), (MW / 2, 50)]))
    if kind == "bottom_up":
        return (f"<rect x='0' y='{MH - 14}' width='{MW}' height='14' fill='#e2e2e2'/>"
                + dot(MW / 2, MH - 6) + arrow([(MW / 2, MH - 6), (MW / 2, MH - 50)]))
    if kind == "diag":
        return dot(30, 70) + arrow([(30, 70), (54, 46)])
    raise ValueError(kind)


SECTIONS = [
    ("Um dedo", [
        ("swipe", "w", "Próxima página"),
        ("swipe", "e", "Página anterior"),
        ("top_down", None, "Barra de ferramentas"),
        ("bottom_up", None, "Painel Aa"),
        ("edge", "up", "Mais luz"),
        ("edge", "down", "Menos luz"),
        ("diag", None, "Atualizar tela"),
    ]),
    ("Dois dedos", [
        ("two", "e", "Índice"),
        ("two", "w", "Marcadores"),
        ("two", "n", "Mais luz"),
        ("two", "s", "Menos luz"),
        ("pinch", "in", "Fonte menor"),
        ("pinch", "out", "Fonte maior"),
    ]),
    ("Desenhos com um dedo", [
        ("multi", ["n", "e"], "Índice"),
        ("multi", ["n", "w"], "Marcadores"),
        ("multi", ["e", "n"], "Histórico"),
        ("multi", ["e", "s"], "Ir para página"),
        ("multi", ["e", "w"], "Último marcador"),
        ("multi", ["e", "w", "e"], "Favoritos"),
        ("multi", ["w", "e"], "Posição anterior"),
        ("multi", ["w", "e", "w"], "Livro anterior"),
        ("multi", ["w", "n"], "Status do livro"),
        ("multi", ["w", "s"], "Voltar"),
        ("multi", ["s", "n"], "Folhear"),
        ("multi", ["n", "s", "n"], "Capítulo anterior"),
        ("multi", ["s", "n", "s"], "Próximo capítulo"),
        ("multi", ["s", "w"], "Ajuste de luz"),
        ("multi", ["se", "ne"], "Seguir link"),
        ("multi", ["e", "s", "w", "n"], "Atualizar tela"),
        ("multi", ["nw", "sw", "nw"], "Wi-Fi liga/desliga"),
        ("multi", ["se", "ne", "nw"], "Ligar Wi-Fi"),
        ("multi", ["se", "sw", "nw"], "Desligar Wi-Fi"),
    ]),
]


def gestures():
    cols, cw, ch = 7, 120, 160
    W = cols * cw + 20
    body, y = [], 10
    for title, items in SECTIONS:
        body.append(text(14, y + 26, title, 20, "start", "bold"))
        y += 40
        for i, (kind, arg, label) in enumerate(items):
            c, r = i % cols, i // cols
            x0 = 10 + c * cw + (cw - MW) / 2
            y0 = y + r * ch
            body.append(f"<g transform='translate({x0:.1f},{y0:.1f})'>"
                        f"<rect x='-1' y='-1' width='{MW + 2}' height='{MH + 2}' rx='6' fill='white' stroke='{SOFT}'/>"
                        f"{drawing(kind, arg)}</g>")
            body.append(text(x0 + MW / 2, y0 + MH + 24, label, 13))
        y += math.ceil(len(items) / cols) * ch + 10
    return svg(W, y + 10, "".join(body))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, data in (("zonas.svg", zones()), ("gestos.svg", gestures())):
        with open(os.path.join(OUT, name), "w") as f:
            f.write(data)
        print("wrote", os.path.join(OUT, name))

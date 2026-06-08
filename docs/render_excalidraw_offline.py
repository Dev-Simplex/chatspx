"""Renderiza .excalidraw em PNG offline (sem browser/CDN).

Não tem estilo artístico do Excalidraw, mas mostra o layout exato.

Uso:
    python3 render_excalidraw_offline.py <arquivo.excalidraw>
"""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PADDING = 60
SCALE = 1.5  # 1.5x pra ficar nítido

def load_font(size):
    # Tenta fontes do Windows / fallback
    for name in ["arial.ttf", "Arial.ttf", "C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/segoeui.ttf"]:
        try:
            return ImageFont.truetype(name, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()

def compute_bbox(elements):
    xs = []; ys = []
    for el in elements:
        if el.get("isDeleted"): continue
        x = el.get("x", 0); y = el.get("y", 0)
        w = abs(el.get("width", 0)); h = abs(el.get("height", 0))
        if el.get("type") in ("arrow", "line") and "points" in el:
            for px, py in el["points"]:
                xs.append(x+px); ys.append(y+py)
        else:
            xs.extend([x, x+w]); ys.extend([y, y+h])
    if not xs: return (0, 0, 800, 600)
    return (min(xs), min(ys), max(xs), max(ys))

def draw_arrowhead(draw, x1, y1, x2, y2, color, size=10):
    import math
    angle = math.atan2(y2-y1, x2-x1)
    p1 = (x2 - size*math.cos(angle - math.pi/6), y2 - size*math.sin(angle - math.pi/6))
    p2 = (x2 - size*math.cos(angle + math.pi/6), y2 - size*math.sin(angle + math.pi/6))
    draw.polygon([(x2,y2), p1, p2], fill=color)

def render(input_path, output_path=None):
    data = json.loads(Path(input_path).read_text(encoding="utf-8"))
    elements = [e for e in data["elements"] if not e.get("isDeleted")]
    min_x, min_y, max_x, max_y = compute_bbox(elements)

    width = int((max_x - min_x + PADDING*2) * SCALE)
    height = int((max_y - min_y + PADDING*2) * SCALE)

    img = Image.new("RGB", (width, height), data.get("appState", {}).get("viewBackgroundColor", "#ffffff"))
    draw = ImageDraw.Draw(img)

    offset_x = -min_x + PADDING
    offset_y = -min_y + PADDING

    def tx(v): return int((v + offset_x) * SCALE)
    def ty(v): return int((v + offset_y) * SCALE)

    # Render por tipo, mas primeiro shapes, depois textos, depois arrows (camadas)
    shapes = [e for e in elements if e.get("type") in ("rectangle", "ellipse", "diamond")]
    arrows = [e for e in elements if e.get("type") in ("arrow", "line")]
    texts = [e for e in elements if e.get("type") == "text"]

    for el in shapes:
        t = el["type"]
        x = tx(el.get("x", 0)); y = ty(el.get("y", 0))
        w = int(el.get("width", 0) * SCALE); h = int(el.get("height", 0) * SCALE)
        stroke = el.get("strokeColor", "#000000")
        fill = el.get("backgroundColor", "transparent")
        if fill == "transparent": fill = None
        sw = max(1, int(el.get("strokeWidth", 2) * SCALE * 0.7))
        is_dashed = el.get("strokeStyle") == "dashed"

        if t == "rectangle":
            # corner radius
            r = 8 if el.get("roundness") else 0
            if r:
                draw.rounded_rectangle([x, y, x+w, y+h], radius=int(r*SCALE), fill=fill, outline=stroke, width=sw)
            else:
                draw.rectangle([x, y, x+w, y+h], fill=fill, outline=stroke, width=sw)
        elif t == "ellipse":
            draw.ellipse([x, y, x+w, y+h], fill=fill, outline=stroke, width=sw)
        elif t == "diamond":
            cx = x + w//2; cy = y + h//2
            pts = [(cx, y), (x+w, cy), (cx, y+h), (x, cy)]
            draw.polygon(pts, fill=fill, outline=stroke)
            # diamond outline polygon ignora width, então desenho linhas
            for i in range(4):
                draw.line([pts[i], pts[(i+1)%4]], fill=stroke, width=sw)

    # Arrows e linhas
    for el in arrows:
        x = el.get("x", 0); y = el.get("y", 0)
        points = el.get("points", [[0,0],[10,0]])
        stroke = el.get("strokeColor", "#000000")
        sw = max(1, int(el.get("strokeWidth", 2) * SCALE * 0.7))
        # Converte pontos pra coordenadas absolutas + scale
        coords = [(tx(x+px), ty(y+py)) for px, py in points]
        # Desenha segmentos
        for i in range(len(coords)-1):
            draw.line([coords[i], coords[i+1]], fill=stroke, width=sw)
        # Arrowhead no último ponto
        if el.get("endArrowhead") == "arrow" and len(coords) >= 2:
            draw_arrowhead(draw, *coords[-2], *coords[-1], stroke, size=int(10*SCALE))

    # Textos
    for el in texts:
        x = tx(el.get("x", 0)); y = ty(el.get("y", 0))
        text = el.get("text", "")
        color = el.get("strokeColor", "#000000")
        font_size = int(el.get("fontSize", 16) * SCALE)
        font = load_font(font_size)
        align = el.get("textAlign", "left")
        w = int(el.get("width", 0) * SCALE)
        h = int(el.get("height", 0) * SCALE)

        # Multi-line
        lines = text.split("\n")
        line_h = int(font_size * el.get("lineHeight", 1.25))

        # Calcula y inicial pra vertical align
        total_h = line_h * len(lines)
        if el.get("verticalAlign") == "middle":
            start_y = y + (h - total_h) // 2
        elif el.get("verticalAlign") == "bottom":
            start_y = y + h - total_h
        else:
            start_y = y

        for i, line in enumerate(lines):
            line_y = start_y + i * line_h
            if align == "center":
                bbox = draw.textbbox((0, 0), line, font=font)
                line_w = bbox[2] - bbox[0]
                line_x = x + (w - line_w) // 2
            elif align == "right":
                bbox = draw.textbbox((0, 0), line, font=font)
                line_x = x + w - (bbox[2] - bbox[0])
            else:
                line_x = x
            draw.text((line_x, line_y), line, fill=color, font=font)

    if output_path is None:
        output_path = Path(input_path).with_suffix(".png")
    img.save(output_path)
    return output_path

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python render_excalidraw_offline.py <arquivo.excalidraw>")
        sys.exit(1)
    out = render(sys.argv[1])
    print(f"Renderizado: {out}")

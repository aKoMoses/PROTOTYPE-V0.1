"""Presentation of the four actual authored models and native garage captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'captures' / 'four-active'
DEST.mkdir(parents=True, exist_ok=True)
font = lambda size: ImageFont.truetype(str(ROOT / 'art/ui/fonts/RussoOne-Regular.ttf'), size)
canvas = Image.new('RGB', (1600, 2360), '#171e22')
draw = ImageDraw.Draw(canvas)
draw.text((40, 25), 'PROTOTYPE 0 / QUATRE NOUVEAUX MODULES', font=font(31), fill='#ede6d5')
draw.text((42, 73), 'Modeles Blender et montage dans le vrai garage Godot', font=font(18), fill='#a7b5bc')
draw.line((40, 109, 1560, 109), fill='#b58a48', width=2)
for index, (identifier, title, description) in enumerate([
    ('pelto_smash', 'PELTO SMASH', 'Patins de frappe, verins et collecteur hydraulique'),
    ('counter', 'COUNTER', 'Trois plaques de garde et condensateur de riposte'),
    ('permutation', 'PERMUTATION', 'Deux bobines de phase et pont de permutation'),
    ('eclipse', 'ECLIPSE', 'Iris a huit pales et croissant de ceramique'),
]):
    x, y = 40 + (index % 2)*790, 127 + (index // 2)*1120
    render = Image.open(ROOT / 'art/modules/previews' / (identifier + '.png')).convert('RGB')
    canvas.paste(render.resize((600, 600), Image.Resampling.LANCZOS), (x+65, y))
    draw.text((x, y+613), title, font=font(26), fill='#ede6d5')
    draw.text((x, y+651), description, font=font(16), fill='#a7b5bc')
    capture = Image.open(DEST / (identifier + '-garage-detail.png')).convert('RGB')
    canvas.paste(capture.resize((730, 411), Image.Resampling.LANCZOS), (x, y+685))
canvas.save(DEST / 'quatre-modules.png')
print(DEST / 'quatre-modules.png')

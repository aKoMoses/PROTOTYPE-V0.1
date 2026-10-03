"""A contact sheet of the actual Blender models and native garage renders."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'captures' / 'fulguro-static'
DEST.mkdir(parents=True, exist_ok=True)
font = lambda size: ImageFont.truetype(str(ROOT / 'art/ui/fonts/RussoOne-Regular.ttf'), size)
canvas = Image.new('RGB', (1600, 1320), '#171e22')
draw = ImageDraw.Draw(canvas)
draw.text((40, 25), 'PROTOTYPE 0 / DEUX NOUVEAUX MODULES', font=font(32), fill='#ede6d5')
draw.text((42, 73), 'Modeles Blender et montage dans le vrai garage Godot', font=font(18), fill='#a7b5bc')
draw.line((40, 109, 1560, 109), fill='#b58a48', width=2)
for index, (identifier, title, description) in enumerate([
    ('fulguro_punch', 'FULGURO PUNCH', 'Pistons, couronne d\'impact et dissipateurs cuivre'),
    ('static_shield', 'STATIC SHIELD', 'Emetteur de stase, trois secteurs et iris cyan'),
]):
    x = 40 + index * 790
    render = Image.open(ROOT / 'art/modules/previews' / (identifier + '.png')).convert('RGB')
    canvas.paste(render.resize((730, 730), Image.Resampling.LANCZOS), (x, 127))
    draw.text((x, 862), title, font=font(27), fill='#ede6d5')
    draw.text((x, 904), description, font=font(16), fill='#a7b5bc')
    capture = Image.open(DEST / (identifier + '-garage-detail.png')).convert('RGB')
    canvas.paste(capture.resize((730, 365), Image.Resampling.LANCZOS), (x, 940))
canvas.save(DEST / 'deux-modules.png')
print(DEST / 'deux-modules.png')

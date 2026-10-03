"""Presentation of the six actual passive models and native garage captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'captures' / 'passives'
DEST.mkdir(parents=True, exist_ok=True)
font = lambda size: ImageFont.truetype(str(ROOT / 'art/ui/fonts/RussoOne-Regular.ttf'), size)
canvas = Image.new('RGB', (1600, 3480), '#171e22')
draw = ImageDraw.Draw(canvas)
draw.text((40, 25), 'PROTOTYPE 0 / LES SIX PASSIFS', font=font(31), fill='#ede6d5')
draw.text((42, 73), 'Modeles Blender et montage dans le vrai garage Godot', font=font(18), fill='#a7b5bc')
draw.line((40, 109, 1560, 109), fill='#b58a48', width=2)
for index, (identifier, title, description) in enumerate([
    ('baroud', 'BAROUD D’HONNEUR', 'Reserve de secours et coupe-circuit protege'),
    ('omnivamp', 'OMNIVAMP', 'Reservoirs de recuperation et circuit de retour'),
    ('tracker', 'TRAQUEUR', 'Deux optiques, iris et dissipateur en cuivre'),
    ('alternator', 'ALTERNATEUR', 'Commutateur et contacts a deux canaux'),
    ('inertia', 'INERTIE', 'Cardans inclines, volant et amortisseurs'),
    ('auxiliary_reactor', 'REACTEUR AUXILIAIRE', 'Modele existant, verifie avec les cinq nouveaux'),
]):
    x, y = 40 + (index % 2)*790, 127 + (index // 2)*1120
    render = Image.open(ROOT / 'art/modules/previews' / (identifier + '.png')).convert('RGB')
    canvas.paste(render.resize((600, 600), Image.Resampling.LANCZOS), (x+65, y))
    draw.text((x, y+613), title, font=font(26), fill='#ede6d5')
    draw.text((x, y+651), description, font=font(16), fill='#a7b5bc')
    capture = Image.open(DEST / (identifier + '-garage-detail.png')).convert('RGB')
    canvas.paste(capture.resize((730, 411), Image.Resampling.LANCZOS), (x, y+685))
canvas.save(DEST / 'six-passifs.png')
print(DEST / 'six-passifs.png')

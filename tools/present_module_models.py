"""Compose an inspectable contact sheet from the authored Blender renders."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'art' / 'modules' / 'previews'
OUTPUT = ROOT / 'captures' / 'module-quality'
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT / '.gdignore').write_text('')
FONT = ROOT / 'art' / 'ui' / 'fonts' / 'RussoOne-Regular.ttf'
canvas = Image.new('RGB', (1740, 1320), '#171e22')
draw = ImageDraw.Draw(canvas)
font = lambda size: ImageFont.truetype(str(FONT), size)
draw.text((50, 34), 'PROTOTYPE 0  /  MODULES', font=font(38), fill='#ece5d3')
draw.text((51, 87), 'Cinq modeles 3D - apercus des sources Blender', font=font(18), fill='#a5afb2')
draw.line((50, 127, 1690, 127), fill='#a67838', width=2)
models = [
    ('pyro_boots', 'PYRO BOOTS', 'Turbine, tuyere creuse et protection thermique'),
    ('bio_injector', 'BIO INJECTOR', 'Cartouches bridees, graduations et conduites'),
    ('rocket_basket', 'PANIER ROQUETTES', 'Six tubes ouverts et cassette blindee'),
    ('magnetic_field', 'CHAMP MAGNETIQUE', 'Bobines de cuivre et isolateur ceramique'),
    ('auxiliary_reactor', 'REACTEUR AUXILIAIRE', 'Cuve cyan, radiateurs et grille de protection'),
]
for index, (identifier, title, subtitle) in enumerate(models):
    row, col = divmod(index, 3)
    x = 50 + col * 565 + (282 if row == 1 else 0)
    y = 153 + row * 567
    picture = Image.open(SOURCE / (identifier + '.png')).convert('RGB').resize((500, 500), Image.Resampling.LANCZOS)
    canvas.paste(picture, (x+15, y))
    draw.text((x, y+512), title, font=font(23), fill='#ece5d3')
    draw.text((x, y+546), subtitle, font=font(12), fill='#a5afb2')
canvas.save(OUTPUT / 'cinq-modules.png')
print(str(OUTPUT / 'cinq-modules.png'))

"""Prepare the single proposal with the same verified natural-grain workflow."""
from pathlib import Path
root=Path(__file__).resolve().parent
p=root/"prepare.py"
s=p.read_text(encoding="utf-8").replace('"module_count":2','"module_count":1').replace('"candidate_count":8','"candidate_count":1').replace('READY 8 new effects, 4 previews','READY 1 new effect, 2 listening reels')
p.write_text(s,encoding="utf-8")
p=root/"generate.py"
s=p.read_text(encoding="utf-8").replace('Projector: compression and outward pressure. Permutation: charged shadow and spatial exchange. No notification tones or shared ramps.','Eclipse arrival: one explosive rematerialization with physical weight and scattering particles. No teleport chime or notification tone.')
p.write_text(s,encoding="utf-8")
from prepare import main
main()

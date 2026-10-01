"""Reuse the verified natural-grain workflow with accurate pair metadata."""
from pathlib import Path
root=Path(__file__).resolve().parent
for name in ["prepare.py","verify.py"]:
 p=root/name
 s=p.read_text(encoding="utf-8").replace('"candidate_count":9','"candidate_count":8').replace('9 new effects','8 new effects').replace('9 sources/candidates','8 sources/candidates')
 p.write_text(s,encoding="utf-8")
p=root/"generate.py"
s=p.read_text(encoding="utf-8").replace('"Complete physical gestures, distinct causal roles; no universal envelope or notification beep."','"Projector: compression and outward pressure. Permutation: charged shadow and spatial exchange. No notification tones or shared ramps."')
p.write_text(s,encoding="utf-8")
p=root/"index.html"
s=p.read_text(encoding="utf-8").replace("Roquettes & Counter","Projector & Permutation").replace("Panier roquettes & Counter","Projector & Permutation").replace("neuf sources régénérées","huit nouvelles sources").replace("Le premier lot reste archivé et rejeté. Projector, Permutation et Éclipse attendront la validation de cette paire.","Panier roquettes et Counter ont été validés. Cette paire attend ton écoute ; Éclipse viendra ensuite.")
p.write_text(s,encoding="utf-8")

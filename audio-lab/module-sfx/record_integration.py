"""Record both approved pairs and verify installed copies without rewriting audio."""
import json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent.parent
installed=[]
modules=[]
for name in ["rocket-counter-v2","projector-permutation-v2"]:
 pair=ROOT/"revisions"/name
 m=json.loads((pair/"manifest.json").read_text(encoding="utf-8"))
 for cue in m["cues"]:
  path=PROJECT/"art/audio/game-sfx"/(cue["id"]+".wav")
  assert hashlib.sha256(path.read_bytes()).hexdigest()==cue["sha256"]
  cue["decision"]="accepted by user"
  installed.append({"id":cue["id"],"file":str(path.relative_to(PROJECT)),"sha256":cue["sha256"]})
 modules.extend(m["modules"])
 m["selection"]="accepted by user"
 m["integrated_in_game"]=True
 m["review_boundary"]="User accepted the pair. Gameplay wiring and cleanup verified headlessly; live listening and two-computer network test not performed."
 (pair/"manifest.json").write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding="utf-8")
 (pair/"selection.json").write_text(json.dumps({"selection":"all cues accepted by user","generator":"Stable Audio","integrated_in_game":True},ensure_ascii=False,indent=2),encoding="utf-8")
 p=pair/"index.html"
 s=p.read_text(encoding="utf-8").replace("Propositions à écouter — pas encore validées ni intégrées","Validés — intégrés localement au jeu").replace("Projector, Permutation et Éclipse attendront la validation de cette paire.","Les quatre premiers modules sont intégrés ; Éclipse reste à préparer.").replace("Projector et Permutation sont la prochaine paire à écouter ; Éclipse viendra ensuite.","Projector et Permutation sont également intégrés ; Éclipse reste à préparer.").replace("Panier roquettes et Counter ont été validés. Cette paire attend ton écoute ; Éclipse viendra ensuite.","Les quatre premiers modules ont été validés et intégrés. Éclipse reste à préparer.")
 p.write_text(s,encoding="utf-8")
report={"status":"integrated locally","generator":"Stable Audio 3 Small-SFX","accepted_modules":modules,"files":installed,"checks":["MODULE SFX TEST: PASS","COUNTER TEST: PASS (53 checks)","TEST ROCKET BASKET: PASS","PROJECTOR TEST: PASS","PERMUTATION TEST: PASS","PROJECTOR PERMUTATION SFX TEST: PASS","NETWORK COMBAT TEST: PASS"],"remaining_review":["Eclipse deferred"],"limits":"Headless runtime checks; no live listening or separate-PC network acceptance."}
(ROOT/"integration.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(f"INSTALLED {len(installed)} approved Stable Audio cues, SHA256 identical")

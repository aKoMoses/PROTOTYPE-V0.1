"""Package real GPU screenshots and measured UI geometry for the iPhone audit."""
from __future__ import annotations

import argparse
import base64
from io import BytesIO
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "captures" / "forge-iphone"
TEMPLATE = OUTPUT / "preview-template.html"
APPLE = "https://developer.apple.com/design/human-interface-guidelines/designing-for-games/"
VIEWS = {"garage": "Atelier", "weapon": "Armes", "passive": "Passifs", "offensive": "Offensifs", "defensive": "Défensifs", "mobility": "Mobilité"}


def package(report: dict, quality: int) -> dict:
    profiles = []
    for profile in report["profiles"]:
        frames = []
        for frame in profile["frames"]:
            with Image.open(OUTPUT / frame["file"]) as source:
                assert source.size == (profile["width"], profile["height"])
                buffer = BytesIO()
                # Format conversion only; retain the exact native screenshot size.
                source.convert("RGB").save(buffer, format="WEBP", quality=quality, method=6)
            row = next((b for b in frame["buttons"] if b["label"] in ("BLASTER", "BAROUD D’HONNEUR", "BAROUD D'HONNEUR", "PANIER ROQUETTES")), None)
            frames.append({
                "view": frame["view"], "title": VIEWS[frame["view"]],
                "src": "data:image/webp;base64," + base64.b64encode(buffer.getvalue()).decode("ascii"),
                "font": frame["nav_font_pt"] if frame["view"] == "garage" else frame["description_font_pt"],
                "nav_height": frame["nav_button_rect"][3], "save_height": frame["save_button_rect"][3],
                "row_height": row["rect"][3] if row else None,
                "targets": [{"label": b["label"], "rect": b["rect"]} for b in frame["buttons"] if b["under_44pt"]],
            })
        profiles.append({**{k: profile[k] for k in ("id", "title", "width", "height", "safe_side", "safe_bottom")}, "frames": frames})
    return {"profiles": profiles, "checks": report["checks"], "preview_quality": quality}


def write_report(report: dict) -> None:
    lines = [
        "# Garage — audit des formats iPhone sur PC", "",
        "La scène réelle a été rendue avec Godot 4.7.2, Vulkan Mobile sur GTX 1660 SUPER, dans trois fenêtres paysage représentatives. Aucun script de jeu n'a été modifié pour cet audit.", "",
        "Chaque pixel de la fenêtre représente ici une unité logique assimilée à un point iOS. Les tailles obtenues sont des estimations de mise en page pour un affichage plein écran standard, sans Zoom de l'écran. La densité Retina, les dimensions physiques du téléphone, le rendu iOS et les performances ne sont pas simulés.", "",
        "## Résultat", "",
        "Le décor tient dans les trois formats, les cinq postes restent visibles et les touches précises ouvrent leurs catalogues. L'interface conserve ses proportions PC et devient trop petite pour un usage confortable au doigt.", "",
        "| Format logique | Descriptions | Navigation, hauteur | Sauver et jouer, hauteur | Titres des choix |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for p in report["profiles"]:
        frame = p["frames"][1]
        lines.append(f"| {p['title']} {p['width']}×{p['height']} | {frame['description_font_pt']:.1f} pt | {frame['nav_button_rect'][3]:.1f} pt | {frame['save_button_rect'][3]:.1f} pt | {frame['row_title_font_pt']:.1f} pt |")
    lines.extend([
        "", f"[Apple recommande pour les jeux iOS](<{APPLE}>) des textes d'au moins 11 points et des boutons touchables d'au moins 44×44 points. Ce sont les repères utilisés ici, pas une mesure du confort réel d'une personne.", "",
        "Les lignes du catalogue mesurent environ 33–38 points de haut. La sélection des passifs et de la mobilité est assez grande dans la vue 3D ; les rangements arrière d'armes, offensifs et défensifs demandent davantage de précision, surtout en petit format.", "",
        "Le volume de sélection du robot occupe environ 76–87 points de haut dans la vue d'ensemble, soit 20 % de l'écran. Cette mesure inclut la boîte du modèle ; ses détails et ses plaques sont encore plus petits. Les vues rapprochées de catalogue sont plus lisibles que la vue générale.", "",
        "## Bords et geste d'accueil", "",
        "Le format compact est testé sans réserve de bord. Les deux formats larges utilisent une hypothèse prudente de 59 points de chaque côté et 21 points en bas, pour matérialiser les bords à encoche et la zone du geste d'accueil. Ce ne sont pas des valeurs mesurées sur un modèle d'iPhone.", "",
        "Les marges latérales actuelles protègent les commandes dans cette hypothèse. Les cinq commandes du pied de page empiètent en revanche sur la bande inférieure de 21 points. Le garage n'utilise pas actuellement la zone sûre de l'appareil ; seul le HUD de combat le fait.", "",
        "## Contrôles et captures", "",
        f"{report['checks']} contrôles exécutés, {len(report['failures'])} échec : dimensions réelles des fenêtres et images, visibilité des cinq postes, touches directes sur leurs volumes 3D, sélection d'une ligne par le couple touche/souris émulée sur Windows, préservation du build.", "",
        "Les événements souris émulés des boutons sont injectés explicitement : Window.push_input ne produit pas automatiquement les événements complémentaires du système tactile. Le glissement de la fiche est seulement enregistré, sans validation de la gestuelle iOS.", "",
        "Dix-huit PNG natifs sont conservés dans `captures/forge-iphone/`, pour l'atelier et les cinq catalogues à chaque format. L'aperçu interactif contient des copies WebP compressées ; les PNG et `audit.json` restent les preuves originales.", "",
        "```powershell",
        r"& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --audio-driver Dummy --script tools/capture_forge_iphone.gd",
        "python tools/present_forge_iphone.py", "```", "",
        "## Passe recommandée", "",
        "1. Donner aux boutons une hauteur tactile indépendante de la mise à l'échelle PC et réserver la zone du geste d'accueil.",
        "2. Agrandir les textes ; simplifier la fiche latérale sur petit écran, avec les détails longs accessibles séparément.",
        "3. Rapprocher modérément le cadrage général et élargir les volumes de sélection des petits postes arrière.", "",
        "Ces corrections sont proposées à partir de cet audit ; elles ne sont pas appliquées au jeu. La fluidité, les temps de chargement et le comportement réel d'iOS nécessitent une version iPhone.",
    ])
    (ROOT / "docs" / "forge-iphone-audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inline-output", type=Path)
    args = parser.parse_args()
    report = json.loads((OUTPUT / "audit.json").read_text(encoding="utf-8"))
    assert not report["failures"], report["failures"]
    template = TEMPLATE.read_text(encoding="utf-8")
    assert "__AUDIT_DATA__" in template
    for quality in (88, 82, 76, 70, 64):
        data = package(report, quality)
        document = template.replace("__AUDIT_DATA__", json.dumps(data, ensure_ascii=False, separators=(",", ":")))
        if len(document.encode("utf-8")) < 990_000:
            break
    else:
        raise RuntimeError("Preview exceeds the 1 MB inline limit")
    assert "<!doctype" not in document.lower() and "<html" not in document.lower()
    destination = OUTPUT / "garage-iphone.html"
    destination.write_text(document, encoding="utf-8")
    if args.inline_output:
        args.inline_output.parent.mkdir(parents=True, exist_ok=True)
        args.inline_output.write_text(document, encoding="utf-8")
    write_report(report)
    print(f"IPHONE PREVIEW: {len(report['profiles'])} formats, 18 real views, {len(document.encode('utf-8'))} bytes, WebP quality {quality}")
    print(destination)


if __name__ == "__main__":
    main()

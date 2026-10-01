extends RefCounted

const MAX_RANK := 3
const PATHS := {
	"shotgun": ["breaker", "sweeper"], "blaster": ["rail", "arc"],
	"javelin": ["harpoon", "beacon"],
	"static_shield": ["carapace", "counter"], "magnetic_field": ["rampart", "capacitor"],
	"pyro_boots": ["trail", "thruster"], "bio_injector": ["overdrive", "metabolism"],
	"baroud": ["revenge", "escape"], "omnivamp": ["reserve", "harvest"],
}
const DEFINITIONS := {
	"breaker": {"name": "Briseur", "ultimate": "Bélier", "color": "#ffae63", "stages": ["Ajoute un projectile central lourd. Les impacts proches ralentissent.", "Le projectile central déstabilise les ennemis légers.", "La salve ouvre un passage avec une onde frontale traversante."]},
	"sweeper": {"name": "Balayeur", "ultimate": "Éventail", "color": "#ffd966", "stages": ["Deux plombs latéraux élargissent la salve.", "Dix plombs couvrent un cône plus large.", "Douze plombs balaient une grande portion de la horde."]},
	"rail": {"name": "Perforateur", "ultimate": "Lance plasma", "color": "#65eaff", "stages": ["Les tirs chargés traversent une seconde cible alignée.", "Les tirs chargés traversent jusqu'à trois ennemis.", "Un rayon chargé large traverse jusqu'à six ennemis."]},
	"arc": {"name": "Conducteur", "ultimate": "Arc électrique", "color": "#ba9cff", "stages": ["Charge une cible. Les tirs suivants rebondissent vers un voisin.", "La cible chargée transmet le tir à deux voisins.", "Les tirs transmis forment une chaîne de trois rebonds."]},
	"harpoon": {"name": "Harpon", "ultimate": "Ancrage", "color": "#ffe394", "stages": ["Cloue brièvement les ennemis légers. Le rappel blesse sur son passage.", "Le harpon contrôle plus longtemps et son câble s'élargit.", "Le rappel traverse un large couloir et ralentit les ennemis lourds."]},
	"beacon": {"name": "Balise de fuite", "ultimate": "Relais", "color": "#78fff1", "stages": ["Plante une balise au sol. Réappuie sur A pour la rejoindre.", "La balise peut être placée plus loin et reste plus longtemps.", "L'arrivée à la balise repousse les ennemis proches."]},
	"carapace": {"name": "Carapace", "ultimate": "Armure segmentée", "color": "#81cdfa", "stages": ["Le bouclier absorbe davantage d'impacts sans bloquer tes actions.", "Des plaques supplémentaires augmentent sa réserve de protection.", "La rupture du bouclier repousse les ennemis autour de toi."]},
	"counter": {"name": "Riposte", "ultimate": "Contre-décharge", "color": "#d9adff", "stages": ["Une courte protection transforme les impacts bloqués en riposte.", "Une fenêtre plus longue stocke davantage d'énergie.", "La riposte libère une forte décharge dans la direction visée."]},
	"rampart": {"name": "Rempart", "ultimate": "Passage magnétique", "color": "#57e8d5", "stages": ["Les ennemis qui traversent le mur sont ralentis.", "Le mur s'élargit et retient davantage les poursuivants.", "Deux piliers protègent un large passage et freinent les ennemis."]},
	"capacitor": {"name": "Condensateur", "ultimate": "Batterie magnétique", "color": "#ffde72", "stages": ["Le mur stocke les tirs absorbés. Réappuie sur E pour le décharger.", "La réserve d'énergie augmente et la décharge porte plus loin.", "Le mur libère une forte décharge frontale à ton signal."]},
	"trail": {"name": "Sillage", "ultimate": "Barrière de feu", "color": "#ff803e", "stages": ["Le dash laisse une traînée brûlante persistante.", "La traînée brûle plus longtemps et couvre davantage de terrain.", "Une large barrière de feu punit les ennemis qui te suivent."]},
	"thruster": {"name": "Propulseur", "ultimate": "Double réacteur", "color": "#8ce8ff", "stages": ["Une charge supplémentaire permet trois dashs séparés.", "Les réacteurs prolongent légèrement chaque dash.", "Le départ du dash repousse les ennemis qui t'encerclent."]},
	"overdrive": {"name": "Surcharge", "ultimate": "Survoltage", "color": "#ff766f", "stages": ["Accélère encore les tirs et la recharge pendant l'injection.", "Les éliminations prolongent l'effet, avec une limite.", "Une fenêtre d'agression renforcée peut durer jusqu'à huit secondes."]},
	"metabolism": {"name": "Métabolisme", "ultimate": "Circulation vitale", "color": "#8affae", "stages": ["Pendant l'injection, bouger régénère ta vie.", "La régénération mobile augmente. Un coup la suspend brièvement.", "Une injection plus longue permet de récupérer en restant mobile."]},
	"revenge": {"name": "Contre-attaque", "ultimate": "Renaissance", "color": "#ff6e87", "stages": ["Après un coup fatal, inflige assez de dégâts pour revenir à la vie.", "Le sursis dure plus longtemps et le retour rend davantage de vie.", "Le réacteur survit au coup fatal et récompense ta contre-attaque."]},
	"escape": {"name": "Repli vital", "ultimate": "Réacteur de secours", "color": "#89dfff", "stages": ["Après un coup fatal, accélère et évite les coups pour survivre.", "Une courte protection facilite le départ du repli.", "Réussir le repli restaure une réserve de vie plus importante."]},
	"reserve": {"name": "Réserve", "ultimate": "Protection vitale", "color": "#6cfff1", "stages": ["Les soins excédentaires d'Omnivamp créent une protection temporaire.", "La réserve protectrice augmente et se dissipe moins vite.", "Les segments vitaux conservent une plus grande réserve de protection."]},
	"harvest": {"name": "Récolte", "ultimate": "Moisson vitale", "color": "#b2ff80", "stages": ["Les ennemis que tu blesses laissent un fragment de soin à leur mort.", "Les fragments soignent davantage et sont attirés à courte portée.", "Les fragments vitaux te rejoignent depuis une plus grande distance."]},
}

static func state(build: Dictionary, category: String) -> Dictionary:
	return build.get("aspects", {}).get(category, {"path": "", "rank": 0})

static func label(build: Dictionary, category: String) -> String:
	var aspect := state(build, category)
	var id := str(aspect.get("path", ""))
	var rank := int(aspect.get("rank", 0))
	if not DEFINITIONS.has(id) or rank <= 0:
		return ""
	return "%s · %s" % [DEFINITIONS[id].ultimate if rank == MAX_RANK else DEFINITIONS[id].name, "ULTIME" if rank == MAX_RANK else "%d/3" % rank]

static func choices(build: Dictionary, category: String, item_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var aspect := state(build, category)
	var rank := int(aspect.get("rank", 0))
	if rank >= MAX_RANK or not PATHS.has(item_id):
		return result
	var paths: Array = PATHS[item_id] if rank == 0 else [str(aspect.path)]
	for id in paths:
		var entry: Dictionary = DEFINITIONS[id]
		result.append({"category": category, "kind": "evolution", "id": item_id, "path": id, "rank": rank + 1, "title": entry.ultimate if rank + 1 == MAX_RANK else entry.name, "description": entry.stages[rank]})
	return result

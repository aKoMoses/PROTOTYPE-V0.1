extends RefCounted

## Distinct tactical compositions; total enemy count and elite milestones stay stable.
const WAVES := [
	["chaser", "shooter", "chaser"],
	["shooter", "charger", "shooter"],
	["charger", "shooter", "chaser", "chaser"],
	["shooter", "charger", "shooter", "chaser"],
	["chaser", "charger", "chaser", "shooter", "charger", "shooter"],
	["shooter", "shooter", "chaser", "charger", "shooter", "chaser"],
	["charger", "chaser", "charger", "shooter", "chaser", "shooter", "chaser"],
	["shooter", "charger", "shooter", "chaser", "charger", "shooter", "chaser"],
	["chaser", "charger", "shooter", "chaser", "shooter", "charger", "chaser", "shooter"],
	["charger", "charger", "chaser", "shooter", "charger", "shooter", "chaser", "shooter"],
	["shooter", "chaser", "charger", "shooter", "chaser", "shooter", "charger", "chaser", "charger", "shooter"],
	["chaser", "shooter", "charger", "shooter", "chaser", "charger", "shooter", "chaser", "charger", "boss"],
]
const BRIEFS := [
	"POURSUITE · Bouge et garde le tireur en vue.",
	"TIRS CROISÉS · Coupe une ligne de tir avec un couvert.",
	"DOUBLE CHARGE · Esquive, puis frappe pendant la récupération.",
	"ÉTAU · Le chargeur te déloge ; les tireurs couvrent la sortie.",
	"ENCERCLEMENT · Garde un chemin de fuite pour les renforts.",
	"ÉVENTAIL · Écarte-toi de l’axe de tir de l’élite.",
	"PERCÉE · Attire les chargeurs avant de changer de direction.",
	"PRESSION CROISÉE · Élimine un tireur pour ouvrir une sortie.",
	"BOUCLIER FRONTAL · Contourne l’élite pour la toucher.",
	"CHARGES EN CHAÎNE · Garde ta mobilité pour la seconde attaque.",
	"DERNIER ASSAUT · Choisis une cible et garde de l’espace.",
	"BOSS · Profite de ses récupérations ; reste attentif aux renforts.",
]

static func roles(wave: int) -> Array[String]:
	var result: Array[String] = []
	if wave >= 1 and wave <= WAVES.size():
		result.assign(WAVES[wave - 1])
	return result

static func brief(wave: int) -> String:
	return str(BRIEFS[clampi(wave - 1, 0, BRIEFS.size() - 1)])

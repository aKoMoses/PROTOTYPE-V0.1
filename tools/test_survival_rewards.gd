extends SceneTree

const PROGRESSION := preload("res://scripts/survival_progression.gd")
const SYNERGIES := preload("res://scripts/survival_synergies.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	await process_frame
	var first := PROGRESSION.new()
	check(first.reward_choices(1).is_empty(), "aucune récompense avant le choix de l'arme")
	check(first.choose_weapon("blaster"), "Blaster de départ")
	var orders: Dictionary = {}
	for run in range(30):
		var progression := PROGRESSION.new()
		progression.choose_weapon("blaster" if run % 2 == 0 else "shotgun")
		var offer: Array[Dictionary] = progression.reward_choices(1)
		check(offer.size() == 3, "trois cartes après la première vague")
		check(offer == progression.reward_choices(1), "tirage conservé jusqu'au choix")
		check(offer.any(func(card: Dictionary) -> bool: return card.kind == "item"), "nouvel équipement disponible au départ")
		check(offer.any(func(card: Dictionary) -> bool: return card.kind in ["power", "tempo", "evolution"]), "amélioration de l'arme disponible au départ")
		var signature := ",".join(offer.map(func(card: Dictionary) -> String: return str(card.id) + ":" + str(card.kind)))
		orders[signature] = true
		check(not progression.apply_reward(1, {"category": "weapon", "kind": "synergy", "id": "thermal"}), "carte non proposée refusée")
		check(progression.apply_reward(1, offer[0]), "carte proposée acceptée")
		check(progression.reward_choices(2).size() == 3, "trois cartes à la vague suivante")
		if offer[0].kind == "power":
			check(not progression.reward_choices(2).any(func(card: Dictionary) -> bool: return card.kind == "power" and card.category == offer[0].category), "même puissance non proposée deux fois de suite")
	check(orders.size() > 1, "tirages et ordre variables entre parties")

	var paired := PROGRESSION.new()
	paired.choose_weapon("blaster")
	paired.equipment.mobility = "pyro_boots"
	check(SYNERGIES.available_for(paired.build()).has("thermal"), "synergie disponible quand les deux éléments sont équipés")
	check(SYNERGIES.active_for(paired.build()).is_empty(), "synergie encore inactive avant son choix")
	var synergy_offer := paired.reward_choices(2)
	var thermal: Dictionary = {}
	for card in synergy_offer:
		if card.kind == "synergy" and card.id == "thermal":
			thermal = card
	check(not thermal.is_empty(), "synergie présente parmi les trois cartes")
	if not thermal.is_empty():
		check(paired.apply_reward(2, thermal), "carte de synergie acceptée")
		check(SYNERGIES.active_for(paired.build()).has("thermal"), "effet activé après le choix")
		check(not SYNERGIES.available_for(paired.build()).has("thermal"), "synergie acquise retirée du tirage")
		check(not paired.reward_choices(3).any(func(card: Dictionary) -> bool: return card.kind == "synergy" and card.id == "thermal"), "synergie non reproposée")
	for failure in failures:
		push_error(failure)
	print("SURVIVAL REWARDS TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

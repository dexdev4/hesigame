extends Node
## The deals a beaten boss offers (Deals), apart from the game:
##   godot --headless --path . tools/deal_test.tscn
## Checks which deals a run can be offered (never one that takes the last life, nor one that pays for a life it has no room
## for or no money for), what each does to lives, the run's money, its score and its car, that the coin toss comes out as
## it should for every roll, that the three cards are two upgrades and a deal (or three upgrades when there is no deal to
## offer), that the deal cards' text says what the deal does, and that a deal never collides with an upgrade's id. Then
## plays thousands of random runs' worth of deals against a stand-in for the run, and checks that lives never leave 1..6.
## (A scene, because Data is an autoload.) Exits with a non-zero code if a check fails.

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _ready() -> void:
	seed(11)
	_rules()
	_outcomes()
	_cards()
	_text()
	_plays()
	print("== %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _rules() -> void:
	_check(Deals.MAX_LIVES == Data.MAX_LIVES, "the deals know the most lives a run can have (%d, the game says %d)" % [Deals.MAX_LIVES, Data.MAX_LIVES])
	for id in ["blood", "thrill", "gamble"]:
		_check(not Deals.offered(id, 1, 99999), "%s is never offered with one life left" % id)
		_check(Deals.offered(id, 2, 0), "%s is offered with two lives, even with no money" % id)
	_check(not Deals.offered("insure", 3, 1499), "life insurance is not offered with $1,499")
	_check(Deals.offered("insure", 3, 1500), "life insurance is offered with $1,500")
	_check(not Deals.offered("insure", Deals.MAX_LIVES, 99999), "life insurance is not offered to a run with all its lives")
	_check(Deals.offered("hotrod", 1, 0), "the race tune is offered whatever the run has")
	_check(not Deals.offered("nonsense", 3, 3000), "an unknown deal is never offered")
	var ids := {}
	for d in Deals.LIST:
		_check(not ids.has(d.id), "deal id %s is used once" % d.id)
		ids[d.id] = true
		_check(d.get("deal", false) == true, "%s is marked as a deal (the pick screen colours it)" % d.id)
		_check(String(d.name) != "" and String(d.tag) != "" and String(d.desc) != "", "%s has a name, a tag and a description" % d.id)
	for b in Data.BOONS:
		_check(not ids.has(b.id), "the upgrade %s does not share its id with a deal" % b.id)
	_check(Deals.available(1, 0).size() == 1 and Deals.available(1, 0)[0].id == "hotrod", "with one life and no money only the race tune can be offered")
	_check(Deals.available(3, 2000).size() == Deals.LIST.size(), "with three lives and $2,000 every deal can be offered")


func _outcomes() -> void:
	var o := Deals.outcome("blood")
	_check(o.lives == -1 and o.cash == 1000 and is_equal_approx(o.score, 1.0) and o.mods.is_empty(), "blood money: -1 life, +$1,000, nothing else")
	o = Deals.outcome("thrill")
	_check(o.lives == -1 and o.cash == 0 and is_equal_approx(o.score, 1.3), "thrill seeker: -1 life, score x1.3")
	o = Deals.outcome("insure")
	_check(o.lives == 1 and o.cash == -1500, "life insurance: +1 life for $1,500")
	o = Deals.outcome("hotrod")
	_check(o.lives == 0 and o.cash == 0 and is_equal_approx(o.mods.top, 1.10) and is_equal_approx(o.mods.accel, 1.12) and is_equal_approx(o.mods.handling, 0.85), "race tune: top x1.10, accel x1.12, grip x0.85")
	for r in [0.0, 0.25, 0.49, 0.4999]:
		o = Deals.outcome("gamble", r)
		_check(o.cash == 2500 and o.lives == 0 and not o.bad, "the coin toss at %.4f is heads: +$2,500" % r)
	for r in [0.5, 0.51, 0.75, 0.9999]:
		o = Deals.outcome("gamble", r)
		_check(o.cash == 0 and o.lives == -1 and o.bad, "the coin toss at %.4f is tails: -1 life" % r)
	var heads := 0
	for i in 10000:
		if Deals.outcome("gamble", randf()).cash > 0:
			heads += 1
	_check(absf(float(heads) / 10000.0 - 0.5) < 0.02, "a fair coin: %d heads in 10,000 tosses" % heads)
	for d in Deals.LIST:
		_check(String(Deals.outcome(d.id, 0.7).text) != "", "%s has a line for the notification" % d.id)
	_check(Deals.outcome("nonsense").text == "" and Deals.outcome("nonsense").lives == 0, "an unknown deal does nothing")


func _cards() -> void:
	var ups: Array = [{"id": "a"}, {"id": "b"}, {"id": "c"}, {"id": "d"}]
	var deals: Array = [{"id": "x", "deal": true}, {"id": "y", "deal": true}, {"id": "z", "deal": true}]
	var c := Deals.cards(ups, deals, 0.0)
	_check(c.size() == 3 and c[0].id == "a" and c[1].id == "b" and c[2].id == "x", "two upgrades, as the shuffle left them, and a deal (r = 0)")
	c = Deals.cards(ups, deals, 0.5)
	_check(c[2].id == "y", "the deal follows the roll (r = 0.5)")
	c = Deals.cards(ups, deals, 0.9999)
	_check(c[2].id == "z", "the deal follows the roll (r = 0.9999)")
	c = Deals.cards(ups, deals, 1.0)
	_check(c.size() == 3 and c[2].id == "z", "a roll of exactly 1 stays inside the list")
	c = Deals.cards(ups, [], 0.3)
	_check(c.size() == 3 and c[0].id == "a" and c[1].id == "b" and c[2].id == "c", "with no deal to offer the three cards are upgrades, as they were")
	c = Deals.cards([{"id": "a"}], deals, 0.3)
	_check(c.size() == 1 and c[0].id == "a", "one upgrade left and the deal is not forced in")
	c = Deals.cards([{"id": "a"}, {"id": "b"}], deals, 0.3)
	_check(c.size() == 3 and c[0].id == "a" and c[1].id == "b" and c[2].get("deal", false), "two upgrades left and a deal makes three cards")


func _text() -> void:
	_check(Deals.preview("blood", 3, 1240) == "LIVES 3 → 2 · RUN $1,240 → $2,240", "blood money's card: %s" % Deals.preview("blood", 3, 1240))
	_check(Deals.preview("insure", 2, 3200) == "LIVES 2 → 3 · RUN $3,200 → $1,700", "life insurance's card: %s" % Deals.preview("insure", 2, 3200))
	_check(Deals.preview("insure", 5, 1500) == "LIVES 5 → 6 · RUN $1,500 → $0", "life insurance's card at the money it needs: %s" % Deals.preview("insure", 5, 1500))
	_check(Deals.preview("thrill", 4, 0) == "LIVES 4 → 3 · SCORE × 1.3", "thrill seeker's card: %s" % Deals.preview("thrill", 4, 0))
	_check(Deals.preview("gamble", 3, 500) == "LIVES 3 · HEADS RUN $500 → $3,000 · TAILS LIVES 2", "high roller's card: %s" % Deals.preview("gamble", 3, 500))
	_check(Deals.preview("hotrod", 3, 0).contains("GRIP"), "the race tune's card says what it costs: %s" % Deals.preview("hotrod", 3, 0))
	_check(Deals.preview("nonsense", 3, 0) == "", "an unknown deal has no card text")
	for d in Deals.LIST:
		_check(Deals.preview(d.id, 3, 2000) != "", "%s has a line on its card" % d.id)
		_check(String(d.desc).length() <= 90, "%s's description fits a card (%d characters)" % [d.id, String(d.desc).length()])


## A stand-in for what the game does with a deal (Game._take_deal), played over and over from random states.
func _plays() -> void:
	var bad_lives := 0
	var bad_cash := 0
	var taken := {}
	for i in 20000:
		var lives := randi_range(1, Deals.MAX_LIVES)
		var cash := randi_range(0, 4000)
		var avail := Deals.available(lives, cash)
		if avail.is_empty():
			bad_lives += 1
			continue
		var d: Dictionary = Deals.cards([{"id": "a"}, {"id": "b"}, {"id": "c"}], avail, randf())[2]
		taken[d.id] = int(taken.get(d.id, 0)) + 1
		var o := Deals.outcome(d.id, randf())
		var l2: int = lives + int(o.lives)
		var c2: int = cash + int(o.cash)
		if l2 < 1 or l2 > Deals.MAX_LIVES:
			bad_lives += 1
		if c2 < 0:
			bad_cash += 1
	_check(bad_lives == 0, "no deal ever leaves a run with fewer than 1 or more than %d lives (%d of 20,000 did)" % [Deals.MAX_LIVES, bad_lives])
	_check(bad_cash == 0, "no deal ever takes more money than the run has (%d of 20,000 did)" % bad_cash)
	for d in Deals.LIST:
		_check(int(taken.get(d.id, 0)) > 500, "every deal comes up now and then: %s %d times in 20,000" % [d.id, int(taken.get(d.id, 0))])

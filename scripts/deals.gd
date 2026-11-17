class_name Deals
extends RefCounted
## The trade-offs a beaten boss can offer besides its upgrades: something is given up for something else, or it is left to
## a coin. Kept apart from the game (no nodes, no scene) so the rules can be tested on their own: tools/deal_test.gd.
##
## The pick screen shows three cards. Two are upgrades (Data.BOONS, as before) and, when the run can take one, the third is
## a deal. The money of a deal goes into the run's earnings (Game.Run.cash_bonus), so it is there at once to pay for fuel
## at the next stop and is banked with the rest when the run ends.

const MAX_LIVES := 6          # (Data.MAX_LIVES: this file stands alone)
const BLOOD_CASH := 1000      # a life for this much
const THRILL_SCORE := 1.3     # a life for this much more score for the rest of the run
const INSURE_COST := 1500     # this much of the run's earnings for a life
const GAMBLE_CASH := 2500     # a coin toss: this much...
const GAMBLE_CHANCE := 0.5    # ...or a life, and this is the chance of the money
const HOTROD := {"top": 1.10, "accel": 1.12, "handling": 0.85}  # power for grip

const LIST := [
	{"id": "blood", "name": "Blood money", "tag": "DEAL · LIFE FOR CASH", "deal": true,
		"desc": "Give up 1 life, get $1,000 now, added to this run's earnings (it can pay for fuel)."},
	{"id": "thrill", "name": "Thrill seeker", "tag": "DEAL · LIFE FOR SCORE", "deal": true,
		"desc": "Give up 1 life. Every point you score for the rest of the run is worth 30% more."},
	{"id": "insure", "name": "Life insurance", "tag": "DEAL · CASH FOR LIFE", "deal": true,
		"desc": "Pay $1,500 of this run's earnings for 1 extra life."},
	{"id": "gamble", "name": "High roller", "tag": "DEAL · COIN TOSS", "deal": true,
		"desc": "Toss a coin: heads you get $2,500 now, tails you lose 1 life (never your last)."},
	{"id": "hotrod", "name": "Race tune", "tag": "DEAL · GRIP FOR POWER", "deal": true,
		"desc": "+10% top speed and +12% acceleration for this run, but 15% less grip."},
]


static func by_id(id: String) -> Dictionary:
	for d in LIST:
		if d.id == id:
			return d
	return {}


static func is_deal(id: String) -> bool:
	return not by_id(id).is_empty()


## Can this deal be offered to a run with `lives` lives, `run_cash` dollars earned and not yet spent on fuel? A deal never
## takes the last life, and one that pays for a life needs the money and the room.
static func offered(id: String, lives: int, run_cash: int) -> bool:
	match id:
		"blood", "thrill", "gamble":
			return lives >= 2
		"insure":
			return lives < MAX_LIVES and run_cash >= INSURE_COST
		"hotrod":
			return true
	return false


## What taking the deal does: how many lives it gives (negative: takes), how many dollars go into the run's earnings
## (negative: come out of them), what every point is multiplied by from now on and what the car's stats are multiplied by
## (the keys of Game.Run.mods). `roll` is a number from 0 up to 1, for a deal that is left to chance. "text" is the line
## for the notification, "bad" whether it went badly.
static func outcome(id: String, roll := 0.0) -> Dictionary:
	var o := {"lives": 0, "cash": 0, "score": 1.0, "mods": {}, "text": "", "bad": false}
	match id:
		"blood":
			o.lives = -1
			o.cash = BLOOD_CASH
			o.text = "Blood money · -1 life, +$%s" % Fmt.num(BLOOD_CASH)
		"thrill":
			o.lives = -1
			o.score = THRILL_SCORE
			o.text = "Thrill seeker · -1 life, +30% score"
		"insure":
			o.lives = 1
			o.cash = -INSURE_COST
			o.text = "Life insurance · -$%s, +1 life" % Fmt.num(INSURE_COST)
		"gamble":
			if roll < GAMBLE_CHANCE:
				o.cash = GAMBLE_CASH
				o.text = "High roller · heads! +$%s" % Fmt.num(GAMBLE_CASH)
			else:
				o.lives = -1
				o.bad = true
				o.text = "High roller · tails. -1 life"
		"hotrod":
			o.mods = HOTROD.duplicate()
			o.text = "Race tune · more power, less grip"
	return o


## The line under a deal's card: what the run has now and what it has after (lives and the run's earnings).
static func preview(id: String, lives: int, run_cash: int) -> String:
	match id:
		"blood":
			return "LIVES %d → %d · RUN $%s → $%s" % [lives, lives - 1, Fmt.num(run_cash), Fmt.num(run_cash + BLOOD_CASH)]
		"thrill":
			return "LIVES %d → %d · SCORE × 1.3" % [lives, lives - 1]
		"insure":
			return "LIVES %d → %d · RUN $%s → $%s" % [lives, mini(MAX_LIVES, lives + 1), Fmt.num(run_cash), Fmt.num(run_cash - INSURE_COST)]
		"gamble":
			return "LIVES %d · HEADS RUN $%s → $%s · TAILS LIVES %d" % [lives, Fmt.num(run_cash), Fmt.num(run_cash + GAMBLE_CASH), lives - 1]
		"hotrod":
			return "TOP +10% · ACCEL +12% · GRIP −15%"
	return ""


## The deals this run can be offered.
static func available(lives: int, run_cash: int) -> Array:
	var out: Array = []
	for d in LIST:
		if offered(d.id, lives, run_cash):
			out.append(d)
	return out


## The three cards after a boss: `upgrades` is the shuffled list of what the run can take, the first two are kept, and the
## third is one of `deals` (chosen by `r`, a number from 0 up to 1) if there is any; without a deal it is the third upgrade.
static func cards(upgrades: Array, deals: Array, r: float) -> Array:
	var out: Array = upgrades.slice(0, 3)
	if not deals.is_empty() and out.size() >= 2:
		out = upgrades.slice(0, 2)
		out.append(deals[mini(deals.size() - 1, int(r * deals.size()))])
	return out


class_name Fmt
## Number formatting helpers.


## 12345 -> "12,345"
static func num(n: float) -> String:
	var v := roundi(n)
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func km(m: float, digits := 1) -> String:
	return ("%." + str(digits) + "f km") % (m / 1000.0)

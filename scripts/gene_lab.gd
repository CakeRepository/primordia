class_name GeneLab
extends RefCounted
## Gene lab text shared by the 2D and 3D HUDs: the DNA strip around the cursor and trait bars.

const COLORS := {"A": "6df2c2", "T": "ff8f5a", "G": "6ab7ff", "C": "f2d36d"}


## BBCode for a RichTextLabel: header, up to `span` bases centred on the cursor, the decoded
## traits, and a status line.
static func render(dna: String, cursor: int, span: int, header: String, status: String) -> String:
	var lo := clampi(cursor - span / 2, 0, maxi(0, dna.length() - span))
	var hi := mini(dna.length(), lo + span)
	var s := header + "\n"
	for i in range(lo, hi):
		var ch := dna[i]
		if i == cursor:
			s += "[bgcolor=#ffffff][color=#000000]%s[/color][/bgcolor]" % ch
		else:
			s += "[color=#%s]%s[/color]" % [COLORS[ch], ch]
	s += "\n"
	var g := Genome.decode(dna)
	# Two traits per row, in a table so the bars line up despite the proportional font.
	s += "[table=4]"
	for k in Genome.KEYS:
		var n := roundi(g[k] * 20.0)
		s += "[cell]%s   [/cell][cell]%s%s      [/cell]" % [Genome.LABELS[k], "█".repeat(n), "░".repeat(20 - n)]
	s += "[/table]\n"
	var hab := "lives in water" if g["aqua"] > 0.65 else ("amphibious" if g["aqua"] > 0.35 else "lives on land")
	s += "%d genes, %d limbs, %s\n[color=#7fa39d]%s[/color]" % [g["genes"], g["limbs"].size(), hab, status]
	return s

extends RefCounted
## Elevation and banking for each circuit. The source centrelines are 2D, so
## heights here are hand-built approximations of each track's well-known
## profile, anchored on its corners (positions are fractions of the lap from
## the start line). Banking is in degrees over a lap-fraction range.
## Circuits without a profile get gentle generated undulation of `amp` metres.

const PROFILES := {
	"spa": {
		# La Source on a hill, plunge to Eau Rouge, climb Raidillon and the
		# Kemmel straight to Les Combes (highest), long fall to Stavelot
		# (lowest), back up through Blanchimont to the Bus Stop. ~100 m range.
		"elev": [[0.0, 80], [0.058, 86], [0.10, 70], [0.148, 50], [0.17, 74], [0.19, 88],
				[0.34, 100], [0.39, 94], [0.43, 84], [0.49, 70], [0.56, 52], [0.62, 38],
				[0.66, 30], [0.71, 18], [0.745, 12], [0.80, 22], [0.86, 40], [0.92, 60],
				[0.965, 72]],
	},
	"suzuka": {
		# Down to Turn 1, up the Esses to Dunlop, down through Degner and under
		# the bridge, round the hairpin, up to Spoon, back over the bridge, down
		# through 130R to the chicane and up to the line.
		"elev": [[0.0, 20], [0.12, 10], [0.16, 12], [0.20, 18], [0.25, 26], [0.30, 33],
				[0.34, 40], [0.40, 30], [0.44, 20], [0.50, 16], [0.56, 22], [0.62, 30],
				[0.68, 34], [0.75, 30], [0.80, 28], [0.87, 18], [0.93, 10], [0.97, 14]],
	},
	"spielberg": {
		# Uphill to Turn 1, steeply up to the Turn 3 hairpin (top of the hill),
		# then down through the back of the circuit. ~65 m.
		"elev": [[0.0, 5], [0.104, 20], [0.20, 40], [0.323, 65], [0.42, 50], [0.512, 38],
				[0.60, 25], [0.68, 12], [0.74, 6], [0.85, 4], [0.924, 2]],
	},
	"austin": {
		# The famous steep climb to Turn 1, then down through the esses to the
		# back straight and the stadium section.
		"elev": [[0.0, 2], [0.06, 12], [0.121, 36], [0.17, 28], [0.25, 18], [0.33, 12],
				[0.40, 8], [0.47, 3], [0.60, 4], [0.687, 5], [0.76, 8], [0.85, 6],
				[0.92, 3], [0.974, 1]],
	},
	"saopaulo": {
		# Downhill into the Senna S, down to Descida do Lago, up to Pinheirinho,
		# dip through Mergulho and Junção, then the long climb to the line.
		"elev": [[0.0, 40], [0.05, 34], [0.09, 26], [0.17, 18], [0.25, 12], [0.33, 6],
				[0.37, 8], [0.47, 14], [0.54, 20], [0.57, 24], [0.62, 22], [0.70, 12],
				[0.76, 8], [0.85, 24], [0.94, 36]],
	},
	"zandvoort": {
		# Dunes: over the Hunserug crest, down Scheivlak; banked Hugenholtz and
		# Arie Luyendyk corners.
		"elev": [[0.0, 5], [0.086, 5], [0.172, 6], [0.22, 14], [0.274, 10], [0.33, 6],
				[0.41, 8], [0.49, 12], [0.60, 7], [0.70, 10], [0.80, 6], [0.907, 4]],
		"bank": [[0.152, 0.192, 19.0], [0.875, 0.94, 17.0]],
	},
	"budapest": {
		"elev": [[0.0, 25], [0.146, 12], [0.264, 4], [0.307, 8], [0.406, 22], [0.464, 15],
				[0.55, 18], [0.62, 24], [0.70, 30], [0.81, 26], [0.87, 22], [0.92, 20]],
	},
	"catalunya": {
		# Climb through Turns 2-4, down to Turn 5, up to the blind Campsa crest,
		# down the back straight to La Caixa, then up through the last sector.
		"elev": [[0.0, 10], [0.18, 8], [0.204, 10], [0.27, 18], [0.365, 22], [0.462, 12],
				[0.52, 16], [0.568, 28], [0.66, 18], [0.753, 6], [0.80, 12], [0.864, 18],
				[0.93, 15]],
	},
	"nuerburgring": {
		"elev": [[0.0, 40], [0.079, 38], [0.17, 30], [0.29, 5], [0.43, 20], [0.54, 35],
				[0.65, 45], [0.75, 42], [0.84, 38], [0.89, 40]],
	},
	"sepang": {"amp": 9.0},
	"silverstone": {"amp": 5.0},
	"sakhir": {"amp": 7.0},
	"mexicocity": {"amp": 4.0},
	"shanghai": {"amp": 3.5},
	"monza": {"amp": 3.5},
	"melbourne": {"amp": 2.0},
	"montreal": {"amp": 1.5},
	"yasmarina": {"amp": 2.0},
	"hockenheim": {"amp": 3.0},
	"sochi": {"amp": 1.5},
}


static func get_profile(id: String) -> Dictionary:
	return PROFILES.get(id, {"amp": 3.0})

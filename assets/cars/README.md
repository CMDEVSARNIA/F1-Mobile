# Custom car model

**Default car:** the built-in low-poly F1 car in `scripts/lowpoly_car.gd`, modelled in
code (lofted cross-sections, flat-shaded, ~1.5k triangles) with team liveries, a working
DRS flap and compound-coloured tyre stripes.

**Voxel car:** `voxel/voxel_car.obj` is the
[F1 Style Race Car Voxel](https://join217.itch.io/open-wheel-race-car) by join217, converted
with `tools/split_voxel_obj.py`. To use it, copy both files here as `car.obj` / `car.mtl`
and change the `mtllib` line to `car.mtl`. Custom models don't get DRS or tyre stripes.

Save a model here as **`car.glb`** (also accepted: `car.gltf`, `car.fbx`, `car.obj`)
and every car on the grid uses it instead of the built-in low-poly car.

The game fits it automatically (`scripts/car_model.gd`):

- the longest side is laid along the track and scaled to F1 length (5.6 m)
- the model is centred and put on the ground
- materials or meshes named like `body`, `paint`, `livery`, `chassis` or `main`
  get each team's colour

The one thing it can't guess is front vs back. If the cars drive backwards, set
`CUSTOM_YAW_DEG := 180.0` in `scripts/car_model.gd`.

Keep it **under ~30k triangles**, with textures at 1024 px or smaller, because there
are ten on screen on a phone. Wheels won't spin or steer on a custom model.

## Free open-wheel models on itch.io

| Model | Licence | Formats | Notes |
| --- | --- | --- | --- |
| [Iconic Open Wheelers – Low Poly](https://som-natalino.itch.io/low) by som_natalino | CC0 | GLB, FBX, OBJ | Best fit. The single **f2002** car is a free download (2.2 MB); the full pack of 50s to 00s cars is $1+. |
| [F1 Style Race Car Voxel](https://join217.itch.io/open-wheel-race-car) by join217 | Free, commercial OK | OBJ | Blocky voxel look. |
| [Formula 1 + low-poly tag](https://itch.io/game-assets/tag-formula1/tag-low-poly) | varies | varies | Check the licence on each page. |
| [Formula Racing Asset Pack](https://ewinsky.itch.io/fmp-racing-game) by Neo Ewinsky | not stated | — | Still in development, licence unclear. Ask before using. |

On itch.io, a free file is under **Download** (for "name your own price", click
"No thanks, just take me to the downloads"). If the zip contains a `.glb` plus a
textures folder, copy both here and keep the folder name the same.

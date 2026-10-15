# Custom car model

Drop a glTF binary here named **`car.glb`** and every car on the grid uses it
instead of the built-in low-poly car (`scripts/car_model.gd`).

Rules the game assumes:

- The car **faces -Z** (Godot's forward). If it drives sideways or backwards, change
  `CUSTOM_YAW_DEG` in `scripts/car_model.gd` (try 90, -90 or 180).
- Origin on the ground, roughly between the axles; real-world scale is about
  5.5 m long and 2 m wide. Fix size with `CUSTOM_SCALE`, position with `CUSTOM_OFFSET`.
- Keep it **under ~30k triangles** and textures at 1024 px or below. Ten of these on
  screen on a phone add up fast.

Where to look: Sketchfab (filter "Downloadable", search "F1 car" / "formula car"
/ "open wheel"), Poly Pizza, or CGTrader free models. Download as **glTF/GLB**.
Check the licence on each one. For a personal, never-distributed build most
CC-BY / CC-BY-NC models are fine, but don't publish an APK containing them
without honouring the licence.

Note: a custom model gets no team colour (it keeps its own textures), and wheels
won't spin/steer unless you wire them up in `car_model.gd`.

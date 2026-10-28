shader_type sky;
// Cloud panorama plus a sun disc that always sits where the scene's sun is.

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float sun_size = 0.9994;
uniform float exposure = 1.0;

void sky() {
	// Base level only: mip selection jumps at the wrap seam and draws a line.
	vec3 col = textureLod(panorama, SKY_COORDS, 0.0).rgb * exposure;
	if (LIGHT0_ENABLED) {
		float d = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		float disc = smoothstep(sun_size, sun_size + 0.0003, d);
		// Bright disc, tight halo and a broad warm glow around the sun.
		col += LIGHT0_COLOR * (disc * 6.0 + pow(d, 400.0) * 0.8 + pow(d, 16.0) * 0.12);
	}
	COLOR = col;
}

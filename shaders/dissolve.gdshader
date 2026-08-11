shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Death shader with several modes. One shader rather than six keeps every death
// style sharing the same texture handling and edge-lighting maths — only the
// mask that decides "what has gone yet" changes.
//
// MODE 0  NOISE    burn away against a noise field
// MODE 1  RISE     wipe upward from the feet
// MODE 2  FALL     wipe downward from the head
// MODE 3  FADE     no clipping, just alpha
// MODE 4  SHARDS   coarse noise, so it breaks into chunks rather than grains

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D noise_tex;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 edge_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float edge_width : hint_range(0.001, 0.5) = 0.09;
uniform float edge_energy : hint_range(0.0, 20.0) = 5.0;
uniform float rough : hint_range(0.0, 1.0) = 0.8;
uniform float noise_scale : hint_range(0.5, 24.0) = 3.0;
uniform int mode : hint_range(0, 4) = 0;
// Object-space vertical bounds, so a wipe travels the body rather than the world.
uniform float y_min = -1.0;
uniform float y_max = 2.2;

varying float v_local_y;

void vertex() {
	v_local_y = VERTEX.y;
}

void fragment() {
	float n = texture(noise_tex, UV * noise_scale).r;
	float h = clamp((v_local_y - y_min) / max(y_max - y_min, 0.001), 0.0, 1.0);

	// mask = how "present" this fragment still is. Below `dissolve` it is gone.
	float mask = n;
	if (mode == 1) {
		mask = mix(h, n, 0.25);          // rise: mostly height, a little noise
	} else if (mode == 2) {
		mask = mix(1.0 - h, n, 0.25);    // fall
	} else if (mode == 4) {
		mask = step(0.5, n) * 0.6 + n * 0.4;  // chunky
	}

	if (mode != 3 && mask < dissolve) {
		discard;
	}

	vec4 c = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	METALLIC = 0.0;

	if (mode == 3) {
		// Vapour: no clip, the whole body thins out and glows as it goes.
		ALPHA = clamp(1.0 - dissolve, 0.0, 1.0);
		EMISSION = edge_color * dissolve * edge_energy * 0.5;
	} else {
		float edge = 1.0 - smoothstep(dissolve, dissolve + edge_width, mask);
		EMISSION = edge_color * edge * edge_energy;
	}
}

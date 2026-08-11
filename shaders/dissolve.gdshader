shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Death dissolve. Clips the mesh against a noise field and lights the cut edge,
// so a body burns away instead of sinking through the floor.
//
// It keeps the creature's own albedo texture, so a dissolving Pumpkinhulk still
// looks like a Pumpkinhulk right up until it is gone.

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D noise_tex;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 edge_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float edge_width : hint_range(0.001, 0.4) = 0.09;
uniform float edge_energy : hint_range(0.0, 12.0) = 5.0;
uniform float rough : hint_range(0.0, 1.0) = 0.8;
uniform float noise_scale : hint_range(0.5, 12.0) = 3.0;

void fragment() {
	float n = texture(noise_tex, UV * noise_scale).r;

	// Everything below the threshold is already gone.
	if (n < dissolve) {
		discard;
	}

	vec4 c = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	METALLIC = 0.0;

	// Bright only in the narrow band about to vanish — that band is what reads
	// as burning rather than fading.
	float edge = 1.0 - smoothstep(dissolve, dissolve + edge_width, n);
	EMISSION = edge_color * edge * edge_energy;
}

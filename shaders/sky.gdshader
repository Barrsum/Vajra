shader_type sky;

// Stylised sky: procedural sun, moon with real phases, three layers of drifting
// cloud, and stars. Everything keys off the scene's DirectionalLight3D nodes —
// the first is the sun, the second the moon — so rotating the sun rotates the
// whole time of day and every colour follows.
//
// Adapted from https://godotshaders.com/shader/stylized-sky-shader-with-clouds/
//
// Changes from the source, all noted where they happen:
//   · dropped render_mode use_quarter_res_pass — the shader never reads
//     QUARTER_RES_COLOR, so it was rendering the sky an extra time for nothing
//   · pow(x, 2) -> pow(x, 2.0), which Godot's parser requires
//   · renamed the local `hash` that shadowed the function of the same name

group_uniforms sky;
uniform vec3 day_top_color : source_color = vec3(0.1, 0.6, 1.0);
uniform vec3 day_bottom_color : source_color = vec3(0.4, 0.8, 1.0);
uniform vec3 sunset_top_color : source_color = vec3(0.7, 0.75, 1.0);
uniform vec3 sunset_bottom_color : source_color = vec3(1.0, 0.5, 0.7);
uniform vec3 night_top_color : source_color = vec3(0.02, 0.0, 0.04);
uniform vec3 night_bottom_color : source_color = vec3(0.1, 0.0, 0.2);

group_uniforms horizon;
uniform vec3 horizon_color : source_color = vec3(0.0, 0.7, 0.8);
uniform float horizon_blur : hint_range(0.0, 1.0, 0.01) = 0.05;

group_uniforms sun;  // First DirectionalLight3D will be the sun
uniform vec3 sun_color : source_color = vec3(10.0, 8.0, 1.0);
uniform vec3 sun_sunset_color : source_color = vec3(10.0, 0.0, 0.0);
uniform float sun_size : hint_range(0.01, 1.0) = 0.2;
uniform float sun_blur : hint_range(0.01, 20.0) = 10.0;

group_uniforms moon;  // Second DirectionalLight3D will be the moon
uniform vec3 moon_color : source_color = vec3(1.0, 0.95, 0.7);
uniform float moon_size : hint_range(0.01, 1.0) = 0.06;
uniform float moon_blur : hint_range(0.01, 10.0) = 0.1;

group_uniforms clouds;
uniform vec3 clouds_edge_color : source_color = vec3(0.8, 0.8, 0.98);
uniform vec3 clouds_top_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 clouds_middle_color : source_color = vec3(0.92, 0.92, 0.98);
uniform vec3 clouds_bottom_color : source_color = vec3(0.83, 0.83, 0.94);
uniform float clouds_speed : hint_range(0.0, 20.0, 0.01) = 2.0;
uniform float clouds_direction : hint_range(-0.5, 0.5, 0.01) = 0.2;
uniform float clouds_scale : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float clouds_cutoff : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float clouds_fuzziness : hint_range(0.0, 2.0, 0.01) = 0.5;
// More weight is simply a darker colour, useful for rain/storm.
uniform float clouds_weight : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float clouds_blur : hint_range(0.0, 1.0, 0.01) = 0.25;

group_uniforms stars;
// Stars should be on a black background.
uniform sampler2D stars_texture : filter_linear_mipmap, hint_default_black;
uniform float stars_speed : hint_range(0.0, 20.0, 0.01) = 1.0;

group_uniforms settings;
uniform float overwritten_time = 0.0;

// --- cloud noise ------------------------------------------------------------
//
// FastNoiseLite's fractal ping-pong, ported to GLSL. This is here rather than
// as a NoiseTexture2D because a tiling texture on a sky dome repeats visibly.
// Source: https://github.com/Auburn/FastNoiseLite

const int PRIME_X = 501125321;
const int PRIME_Y = 1136930381;

float lerpf(float a, float b, float t) {
	return a + t * (b - a);
}

float cubic_lerp(float a, float b, float c, float d, float t) {
	float p = d - c - (a - b);
	return t * t * t * p + t * t * (a - b - p) + t * (c - a) + b;
}

float ping_pong(float t) {
	t -= trunc(t * 0.5) * 2.0;
	return t < 1.0 ? t : 2.0 - t;
}

int hash(int seed, int x_primed, int y_primed) {
	return (seed ^ x_primed ^ y_primed) * 0x27d4eb2d;
}

float val_coord(int seed, int x_primed, int y_primed) {
	// Named h, not hash: a local shadowing the function above is a redefinition
	// error in Godot even though it compiles as GLSL.
	int h = hash(seed, x_primed, y_primed);
	h *= h;
	h ^= h << 19;
	return float(h) * (1.0 / 2147483648.0);
}

float single_value_cubic(int seed, float x, float y) {
	int x1 = int(floor(x));
	int y1 = int(floor(y));

	float xs = x - float(x1);
	float ys = y - float(y1);

	x1 *= PRIME_X;
	y1 *= PRIME_Y;
	int x0 = x1 - PRIME_X;
	int y0 = y1 - PRIME_Y;
	int x2 = x1 + PRIME_X;
	int y2 = y1 + PRIME_Y;
	int x3 = x1 + (PRIME_X << 1);
	int y3 = y1 + (PRIME_Y << 1);

	return cubic_lerp(
		cubic_lerp(val_coord(seed, x0, y0), val_coord(seed, x1, y0), val_coord(seed, x2, y0), val_coord(seed, x3, y0), xs),
		cubic_lerp(val_coord(seed, x0, y1), val_coord(seed, x1, y1), val_coord(seed, x2, y1), val_coord(seed, x3, y1), xs),
		cubic_lerp(val_coord(seed, x0, y2), val_coord(seed, x1, y2), val_coord(seed, x2, y2), val_coord(seed, x3, y2), xs),
		cubic_lerp(val_coord(seed, x0, y3), val_coord(seed, x1, y3), val_coord(seed, x2, y3), val_coord(seed, x3, y3), xs),
		ys) * (1.0 / (1.5 * 1.5));
}

// Same meaning as the fields in Godot's own noise settings.
const float FRACTAL_BOUNDING = 1.0 / 1.75;
const int OCTAVES = 5;
const float PING_PONG_STRENGTH = 2.0;
const float WEIGHTED_STRENGTH = 0.0;
const float GAIN = 0.5;
const float LACUNARITY = 2.0;

float gen_fractal_ping_pong(vec2 pos, int seed, float frequency) {
	float x = pos.x * frequency;
	float y = pos.y * frequency;
	float sum = 0.0;
	float amp = FRACTAL_BOUNDING;
	int s = seed;
	for (int i = 0; i < OCTAVES; i++) {
		float n = ping_pong((single_value_cubic(s, x, y) + 1.0) * PING_PONG_STRENGTH);
		s++;
		sum += (n - 0.5) * 2.0 * amp;
		amp *= lerpf(1.0, n, WEIGHTED_STRENGTH);
		x *= LACUNARITY;
		y *= LACUNARITY;
		amp *= GAIN;
	}
	return sum * 0.5 + 0.5;
}

// Gives the moon a real terminator instead of a flat disc.
// Source: https://kelvinvanhoorn.com/2022/03/17/skybox-tutorial-part-1/
float sphere_intersect(vec3 view_dir, vec3 sphere_pos, float radius) {
	float b = dot(-sphere_pos, view_dir);
	float c = dot(-sphere_pos, -sphere_pos) - pow(radius, 2.0);
	float h = pow(b, 2.0) - c;
	return h < 0.0 ? -1.0 : -b - sqrt(h);
}


void sky() {
	float time = overwritten_time != 0.0 ? overwritten_time : TIME;

	// --- sky ---------------------------------------------------------------
	float _eyedir_y = abs(sin(EYEDIR.y * PI * 0.5));

	// The day colour is the base; sunset and night are mixed over it.
	vec3 _sky_color = mix(day_bottom_color, day_top_color, _eyedir_y);
	_sky_color = mix(_sky_color, vec3(0.0), clamp((0.7 - clouds_cutoff) * clouds_weight, 0.0, 1.0));

	float _sunset_amount = clamp(0.5 - abs(LIGHT0_DIRECTION.y), 0.0, 0.5) * 2.0;
	// Redder around the west; on the opposite side you barely see it.
	float _sunset_distance = clamp(1.0 - pow(distance(EYEDIR, LIGHT0_DIRECTION), 2.0), 0.0, 1.0);
	vec3 _sky_sunset_color = mix(sunset_bottom_color, sunset_top_color, _eyedir_y + 0.5);
	_sky_sunset_color = mix(_sky_sunset_color, sunset_bottom_color, _sunset_amount * _sunset_distance);
	_sky_color = mix(_sky_color, _sky_sunset_color, _sunset_amount);

	float _night_amount = clamp(-LIGHT0_DIRECTION.y + 0.7, 0.0, 1.0);
	vec3 _sky_night_color = mix(night_bottom_color, night_top_color, _eyedir_y);
	_sky_color = mix(_sky_color, _sky_night_color, _night_amount);

	COLOR = _sky_color;

	// --- horizon -----------------------------------------------------------
	float _horizon_amount = 0.0;
	if (EYEDIR.y < 0.0) {
		_horizon_amount = clamp(abs(EYEDIR.y) / horizon_blur, 0.0, 1.0);
		// Mixed toward the night sky so the horizon darkens with it.
		vec3 _horizon_color = mix(horizon_color, _sky_color, _night_amount * 0.9);
		// Heavy cloud darkens it too.
		_horizon_color = mix(_horizon_color, vec3(0.0), (1.0 - clouds_cutoff) * clouds_weight * 0.7);
		COLOR = mix(COLOR, _horizon_color, _horizon_amount);
	}

	// --- moon --------------------------------------------------------------
	float _moon_amount = 0.0;
	if (LIGHT1_ENABLED) {
		// Bigger near the horizon.
		float _moon_size = moon_size + cos(LIGHT1_DIRECTION.y * PI) * moon_size * 0.25;
		float _moon_distance = distance(EYEDIR, LIGHT1_DIRECTION) / _moon_size;
		_moon_amount = clamp((1.0 - _moon_distance) / moon_blur, 0.0, 1.0);
		if (_moon_amount > 0.0) {
			// Phase: lit according to where the sun actually is.
			float _moon_intersect = sphere_intersect(EYEDIR, LIGHT1_DIRECTION, _moon_size);
			vec3 _moon_normal = normalize(LIGHT1_DIRECTION - EYEDIR * _moon_intersect);
			float _moon_n_dot_l = pow(clamp(dot(_moon_normal, -LIGHT0_DIRECTION), 0.05, 1.0), 2.0);
			_moon_amount *= 1.0 - _horizon_amount;
			COLOR = mix(COLOR, moon_color, _moon_n_dot_l * _moon_amount);
		}
	}

	// --- sun ---------------------------------------------------------------
	float _sun_distance = 0.0;
	if (LIGHT0_ENABLED) {
		_sun_distance = distance(EYEDIR, LIGHT0_DIRECTION);
		float _sun_size = sun_size + cos(LIGHT0_DIRECTION.y * PI) * sun_size * 0.25;
		float _sun_amount = clamp((1.0 - _sun_distance / _sun_size) / sun_blur, 0.0, 1.0);
		if (_sun_amount > 0.0) {
			float _sunset_mix = 1.0;
			if (LIGHT0_DIRECTION.y > 0.0) {
				_sunset_mix = clamp(cos(LIGHT0_DIRECTION.y * PI), 0.0, 1.0);
			}
			vec3 _sun_color = mix(sun_color, sun_sunset_color, _sunset_mix);
			// Behind the moon, then behind the horizon.
			_sun_amount = clamp(_sun_amount * (1.0 - _moon_amount), 0.0, 1.0);
			_sun_amount *= 1.0 - _horizon_amount;
			// Level the HDR glow so the disc does not bloom over everything.
			if (_sun_color.r > 1.0 || _sun_color.g > 1.0 || _sun_color.b > 1.0) {
				_sun_color *= _sun_amount;
			}
			COLOR = mix(COLOR, _sun_color, _sun_amount);
		}
	}

	// --- stars -------------------------------------------------------------
	vec2 _sky_uv = EYEDIR.xz / sqrt(max(EYEDIR.y, 0.001));
	if (EYEDIR.y > -0.01 && LIGHT0_DIRECTION.y < 0.0) {
		float _stars_cos = cos(stars_speed * time * 0.005);
		float _stars_sin = sin(stars_speed * time * 0.005);
		vec2 _stars_uv = vec2(
			_sky_uv.x * _stars_cos - _sky_uv.y * _stars_sin,
			_sky_uv.x * _stars_sin + _sky_uv.y * _stars_cos
		);
		vec3 _stars_color = texture(stars_texture, _stars_uv).rgb * -LIGHT0_DIRECTION.y;
		_stars_color *= 1.0 - _moon_amount;
		COLOR += _stars_color;
	}

	// --- clouds ------------------------------------------------------------
	if (EYEDIR.y > 0.0) {
		float _clouds_speed = time * clouds_speed * 0.01;
		float _sin_x = sin(clouds_direction * PI * 2.0);
		float _cos_y = cos(clouds_direction * PI * 2.0);
		// Three layers, lightest on top. Each drifts at a slightly different
		// speed and angle, which reads as clouds changing shape rather than
		// three sheets sliding past each other.
		vec2 _move = vec2(_sin_x, _cos_y) * _clouds_speed;
		float _noise_top = gen_fractal_ping_pong((_sky_uv + _move) * clouds_scale, 0, 0.5);
		_move = vec2(_sin_x * 0.97, _cos_y * 1.07) * _clouds_speed * 0.89;
		float _noise_middle = gen_fractal_ping_pong((_sky_uv + _move) * clouds_scale, 1, 0.75);
		_move = vec2(_sin_x * 1.01, _cos_y * 0.89) * _clouds_speed * 0.79;
		float _noise_bottom = gen_fractal_ping_pong((_sky_uv + _move) * clouds_scale, 2, 1.0);

		// Feeding each layer a little of the one below gives depth.
		_noise_bottom = smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzziness, _noise_bottom);
		_noise_middle = smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzziness, _noise_middle + _noise_bottom * 0.2) * 1.1;
		_noise_top = smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzziness, _noise_top + _noise_middle * 0.4) * 1.2;
		float _clouds_amount = clamp(_noise_top + _noise_middle + _noise_bottom, 0.0, 1.0);
		_clouds_amount *= clamp(abs(EYEDIR.y) / clouds_blur, 0.0, 1.0);

		vec3 _clouds_color = mix(vec3(0.0), clouds_top_color, _noise_top);
		_clouds_color = mix(_clouds_color, clouds_middle_color, _noise_middle);
		_clouds_color = mix(_clouds_color, clouds_bottom_color, _noise_bottom);
		// Edge colour softens the silhouette. Turn off for sharper edges.
		_clouds_color = mix(clouds_edge_color, _clouds_color, _noise_top);
		// Sun bleeding through.
		_clouds_color = mix(_clouds_color, clamp(sun_color, 0.0, 1.0), pow(1.0 - clamp(_sun_distance, 0.0, 1.0), 5.0));
		_clouds_color = mix(_clouds_color, sunset_bottom_color, _sunset_amount * 0.75);
		_clouds_color = mix(_clouds_color, _sky_color, clamp(_night_amount, 0.0, 0.98));
		_clouds_color = mix(_clouds_color, vec3(0.0), clouds_weight * 0.9);
		COLOR = mix(COLOR, _clouds_color, _clouds_amount);
	}
}

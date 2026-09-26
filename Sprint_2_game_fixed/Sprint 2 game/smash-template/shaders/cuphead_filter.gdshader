shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

uniform float grain_amount : hint_range(0.0, 1.0) = 0.12;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.55;
uniform float sepia_amount : hint_range(0.0, 1.0) = 0.2;
uniform float jitter_amount : hint_range(0.0, 0.01) = 0.0015;
uniform float scratch_amount : hint_range(0.0, 1.0) = 0.35;
uniform float posterize_levels : hint_range(2.0, 32.0) = 16.0;
uniform float film_fps : hint_range(2.0, 30.0) = 12.0;

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Step time down to a low frame rate so grain/jitter judder like old
	// film instead of animating smoothly at the game's real frame rate.
	float stepped_time = floor(TIME * film_fps) / film_fps;

	vec2 uv = SCREEN_UV;
	vec2 jitter = (vec2(rand(vec2(stepped_time, 1.0)), rand(vec2(2.0, stepped_time))) - 0.5) * jitter_amount;
	vec4 col = texture(screen_tex, uv + jitter);

	// gentle sepia tint
	vec3 sepia = vec3(
		dot(col.rgb, vec3(0.393, 0.769, 0.189)),
		dot(col.rgb, vec3(0.349, 0.686, 0.168)),
		dot(col.rgb, vec3(0.272, 0.534, 0.131))
	);
	col.rgb = mix(col.rgb, sepia, sepia_amount);

	// light posterization for a flatter, hand-inked cel-shaded feel
	col.rgb = floor(col.rgb * posterize_levels) / posterize_levels;

	// vignette
	vec2 centered = uv - 0.5;
	float vig = 1.0 - dot(centered, centered) * vignette_strength;
	col.rgb *= clamp(vig, 0.0, 1.0);

	// animated grain, stepped to the low film frame rate
	float noise = rand(uv * vec2(1920.0, 1080.0) + stepped_time * 97.0);
	col.rgb += (noise - 0.5) * grain_amount;

	// occasional flickering vertical scratch, like dust/damage on old film
	float scratch_seed = rand(vec2(floor(stepped_time * 4.0), 7.0));
	float scratch_x = rand(vec2(scratch_seed, 3.0));
	float scratch = smoothstep(0.002, 0.0, abs(uv.x - scratch_x));
	scratch *= step(1.0 - scratch_amount * 0.15, scratch_seed);
	col.rgb += scratch * 0.5;

	COLOR = vec4(col.rgb, 1.0);
}

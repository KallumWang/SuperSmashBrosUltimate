shader_type canvas_item;
// Full-screen "old cartoon film" look. It's drawn by the FilterRect in
// autoload/PostFX.tscn on top of everything, and works by re-reading what's
// already been drawn on screen and altering it. Every `uniform` below shows
// up as a slider in the Inspector, and PostFX.set_param() can change them
// from code using these exact names.

// The picture behind this rect (hint_screen_texture = "give me the screen
// as it's been drawn so far"). filter_nearest keeps it crisp, no blurring.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

uniform float grain_amount : hint_range(0.0, 1.0) = 0.12;           // strength of the speckle noise
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.55;     // how dark the corners get
uniform float sepia_amount : hint_range(0.0, 1.0) = 0.2;            // 0 = normal colors, 1 = fully brown-tinted
uniform float jitter_amount : hint_range(0.0, 0.01) = 0.0015;     // how far the whole picture wobbles, as a fraction of screen size
uniform float scratch_amount : hint_range(0.0, 1.0) = 0.35;        // how often the vertical scratch line shows up
uniform float posterize_levels : hint_range(2.0, 32.0) = 16.0;    // shades per color channel - lower = flatter, more cartoony
uniform float film_fps : hint_range(2.0, 30.0) = 12.0;             // how many times per second the grain/jitter change

// Shaders have no random() built in, so this is the classic trick: a sine of
// a dot product, scaled huge, keeping only the decimal part (fract). The
// same input always gives the same output in 0..1, but nearby inputs look
// unrelated - good enough for film grain.
float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Step time down to a low frame rate so grain/jitter judder like old
	// film instead of animating smoothly at the game's real frame rate.
	float stepped_time = floor(TIME * film_fps) / film_fps;

	vec2 uv = SCREEN_UV; // 0..1 position on screen (SCREEN_UV, not UV, since we want the whole screen not this rect's own coordinates)
	// Tiny random x/y shift of where we sample the screen - the "-0.5"
	// centers rand's 0..1 around 0 so it nudges both ways.
	vec2 jitter = (vec2(rand(vec2(stepped_time, 1.0)), rand(vec2(2.0, stepped_time))) - 0.5) * jitter_amount;
	vec4 col = texture(screen_tex, uv + jitter);

	// gentle sepia tint: the three dot() lines are the standard sepia color
	// matrix (each output channel is a weighted mix of the input r,g,b),
	// then mix() blends between the original color and that by sepia_amount
	vec3 sepia = vec3(
		dot(col.rgb, vec3(0.393, 0.769, 0.189)),
		dot(col.rgb, vec3(0.349, 0.686, 0.168)),
		dot(col.rgb, vec3(0.272, 0.534, 0.131))
	);
	col.rgb = mix(col.rgb, sepia, sepia_amount);

	// light posterization for a flatter, hand-inked cel-shaded feel
	col.rgb = floor(col.rgb * posterize_levels) / posterize_levels;

	// vignette: distance from the middle (squared is cheaper than the real
	// distance) -> the farther out, the more it darkens
	vec2 centered = uv - 0.5;
	float vig = 1.0 - dot(centered, centered) * vignette_strength;
	col.rgb *= clamp(vig, 0.0, 1.0);

	// animated grain, stepped to the low film frame rate
	// (uv * 1920x1080 makes the noise change per pixel on a 1080p screen;
	// adding stepped_time * 97.0 makes it a different pattern each film frame)
	float noise = rand(uv * vec2(1920.0, 1080.0) + stepped_time * 97.0);
	col.rgb += (noise - 0.5) * grain_amount;

	// occasional flickering vertical scratch, like dust/damage on old film
	// scratch_seed changes 4 times a second; it picks both WHERE the
	// scratch is (scratch_x) and WHETHER it appears at all (the step() line
	// below only lets it through when the seed is in the top
	// scratch_amount*15% of its range)
	float scratch_seed = rand(vec2(floor(stepped_time * 4.0), 7.0));
	float scratch_x = rand(vec2(scratch_seed, 3.0));
	// smoothstep with the edges "backwards" (0.002 then 0.0) = a thin line
	// that's brightest right at scratch_x and fades out within 0.2% of the screen width
	float scratch = smoothstep(0.002, 0.0, abs(uv.x - scratch_x));
	scratch *= step(1.0 - scratch_amount * 0.15, scratch_seed);
	col.rgb += scratch * 0.5;

	COLOR = vec4(col.rgb, 1.0); // alpha forced to 1 so this rect fully replaces what's behind it
}

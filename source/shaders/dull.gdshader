// Fades a sprite toward gray. Used on clickable structures until the player
// places them in the right order; dullness 0 shows the sprite's true colors.
shader_type canvas_item;

uniform float dullness : hint_range(0.0, 1.0) = 1.0;
// How gray and how dark a fully dulled sprite gets.
uniform float desaturation : hint_range(0.0, 1.0) = 0.85;
uniform float darken : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	// COLOR already holds the texture color times modulate.
	vec4 color = COLOR;
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 dulled = mix(color.rgb, vec3(gray), desaturation) * (1.0 - darken);
	COLOR = vec4(mix(color.rgb, dulled, dullness), color.a);
}

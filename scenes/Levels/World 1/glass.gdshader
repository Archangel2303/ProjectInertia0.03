shader_type spatial;

render_mode blend_mix, cull_back;

uniform sampler2D screen_texture : hint_screen_texture;

uniform float transparency : hint_range(0.0,1.0) = 0.15;
uniform float refraction_strength = 0.02;
uniform vec3 glass_color : source_color = vec3(0.9, 0.95, 1.0);

void fragment() {

    vec2 refraction_uv = SCREEN_UV + NORMAL.xy * refraction_strength;

    vec3 screen_color = texture(screen_texture, refraction_uv).rgb;

    ALBEDO = mix(screen_color, glass_color, 0.2);
    ALPHA = transparency;

    ROUGHNESS = 0.02;
    SPECULAR = 1.0;
}
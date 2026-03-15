shader_type spatial;
render_mode blend_add, cull_front, depth_draw_never, unshaded;

uniform vec4 shell_color : source_color = vec4(0.25, 1.0, 0.65, 1.0);
uniform float shell_alpha : hint_range(0.0, 2.0) = 0.45;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float flicker_speed : hint_range(0.0, 10.0) = 4.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.2;

void fragment() {
    float fres = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), rim_power);
    float flicker = 1.0 + sin(TIME * flicker_speed + UV.y * 20.0) * flicker_amount;
    ALBEDO = vec3(0.0);
    EMISSION = shell_color.rgb * fres * flicker * 2.0;
    ALPHA = shell_alpha * fres * flicker;
}
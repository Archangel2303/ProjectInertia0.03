shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.02, 0.01, 0.06, 1.0);
uniform vec4 grid_color : source_color = vec4(1.0, 0.0, 0.55, 0.12);
uniform vec4 horizon_color : source_color = vec4(0.0, 0.92, 1.0, 0.18);
uniform float grid_spacing : hint_range(20.0, 120.0) = 60.0;
uniform float grid_thickness : hint_range(0.5, 4.0) = 1.2;
uniform float horizon_y : hint_range(0.0, 1.0) = 0.42;
uniform float horizon_glow : hint_range(0.0, 0.2) = 0.06;
uniform float scanline_alpha : hint_range(0.0, 0.15) = 0.04;
uniform float scanline_spacing : hint_range(1.0, 8.0) = 2.0;
uniform float time_scroll_speed : hint_range(0.0, 40.0) = 12.0;

void fragment() {
    vec2 uv = UV;
    vec2 px = uv * (1.0 / TEXTURE_PIXEL_SIZE);
    vec4 col = bg_color;

    // Perspective grid below horizon
    if (uv.y > horizon_y) {
        float depth = (uv.y - horizon_y) / (1.0 - horizon_y);
        depth = max(depth, 0.001);

        // Vertical lines — fixed in screen space then perspective-projected
        float vx = mod(px.x, grid_spacing);
        float v_line = step(vx, grid_thickness) + step(grid_spacing - grid_thickness, vx);
        v_line *= depth;

        // Horizontal lines — scroll toward viewer
        float world_z = 1.0 / depth;
        float scroll = TIME * time_scroll_speed;
        float hz = mod(world_z * grid_spacing + scroll, grid_spacing);
        float h_line = step(hz, grid_thickness * 1.5);

        float grid = max(v_line, h_line);
        col = mix(col, grid_color, grid * grid_color.a * depth);
    }

    // Horizon glow line
    float h_dist = abs(uv.y - horizon_y);
    float glow = exp(-h_dist / max(horizon_glow, 0.001));
    col.rgb += horizon_color.rgb * glow * horizon_color.a;

    // Top gradient — subtle nebula warmth
    if (uv.y < horizon_y) {
        float sky_t = 1.0 - (uv.y / horizon_y);
        col.rgb += vec3(0.12, 0.0, 0.18) * sky_t * 0.5;
    }

    // Scanlines
    float scan = mod(px.y, scanline_spacing * 2.0);
    float scanline = step(scanline_spacing, scan);
    col.rgb *= 1.0 - scanline_alpha * scanline;

    COLOR = col;
}

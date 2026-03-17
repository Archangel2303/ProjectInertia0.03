shader_type spatial;

render_mode unshaded, cull_back;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec3 grid_color : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 bg_color : source_color = vec3(0.01, 0.02, 0.05);
uniform vec3 edge_color : source_color = vec3(0.0, 1.0, 0.6);

uniform float grid_scale = 1.0;
uniform float line_width = 0.002;
uniform float grid_glow = 2.0;
uniform float fade_start_distance = 5.0;
uniform float fade_end_distance = 120.0;
uniform float far_line_width_scale = 0.25;
uniform float far_intensity_scale = 0.2;
uniform float fade_power = 1.4;
uniform float grazing_width_scale = 0.45;
uniform float max_aa_spread = 0.06;
uniform float core_width_ratio = 0.28;
uniform float core_glow = 0.015;
uniform float hollow_strength = 0.35;
uniform float hollow_curve = 1.25;
uniform float core_emission_softness = 1.4;
uniform float core_color_bias = 0.7;
uniform float emission_peak_limit = 2.5;
uniform float core_far_suppression = 0.85;
uniform float hollow_light_kill = 0.9;
uniform float alias_risk_start = 1.2;
uniform float alias_risk_end = 2.8;
uniform float alias_outer_suppression = 0.35;
uniform float alias_core_suppression = 0.55;
uniform float alias_emission_suppression = 0.45;
uniform float min_core_visibility = 0.40;
uniform float min_core_emission = 0.30;
uniform float guaranteed_core_ratio = 0.35;
uniform float core_albedo_add = 0.35;

uniform float edge_glow = 3.0;
uniform float fresnel_power = 4.0;
uniform float chromatic_aberration_strength = 0.0012;
uniform float chromatic_aberration_edge_start = 0.72;
uniform float chromatic_aberration_intensity = 0.12;
uniform float glitch_pulse_strength = 0.12;
uniform float glitch_pulse_rate = 0.35;
uniform float glitch_pulse_density = 0.03;
uniform float glitch_pulse_speed = 1.4;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec4 grid_layers(vec2 world_uv, float width){
    vec2 uv = world_uv * max(grid_scale, 0.001);
    vec2 grid = abs(fract(uv) - 0.5);
    vec2 aa = fwidth(uv);
    float aa_spread = min(max(aa.x, aa.y), max_aa_spread);
    float half_width = clamp(width * 0.5, 0.001, 0.49);
    float d = min(grid.x, grid.y);

    // Outer colored line
    float outer_line = 1.0 - smoothstep(half_width, half_width + aa_spread, d);

    // Thin white hot core centered in each line
    float core_half_width = clamp(half_width * core_width_ratio, 0.0003, half_width);
    float core_line = 1.0 - smoothstep(core_half_width, core_half_width + aa_spread * 0.6, d);

    // Cell-center mask to darken interior spaces for a hollow look
    float hollow_mask = pow(
        smoothstep(half_width + aa_spread, 0.5, d),
        max(hollow_curve, 0.01)
    );

    float risk_metric = aa_spread / max(half_width, 0.0002);
    float alias_risk = smoothstep(alias_risk_start, alias_risk_end, risk_metric);

    outer_line *= 1.0 - alias_risk * clamp(alias_outer_suppression, 0.0, 1.0);
    core_line *= 1.0 - alias_risk * clamp(alias_core_suppression, 0.0, 1.0);
    core_line = max(core_line, outer_line * clamp(guaranteed_core_ratio, 0.0, 1.0));

    return vec4(outer_line, core_line, hollow_mask, alias_risk);
}

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void fragment(){
    float fade_span = max(fade_end_distance - fade_start_distance, 0.001);
    float world_distance = distance(world_pos, CAMERA_POSITION_WORLD);
    float dist_t = clamp((world_distance - fade_start_distance) / fade_span, 0.0, 1.0);
    float distance_fade = pow(1.0 - dist_t, max(fade_power, 0.01));

    float tapered_line_width = line_width * mix(1.0, far_line_width_scale, dist_t);

    // Counteract perspective broadening at grazing angles.
    float facing = clamp(abs(dot(normalize(world_normal), normalize(VIEW))), 0.0, 1.0);
    float angle_width_scale = mix(grazing_width_scale, 1.0, facing);
    tapered_line_width *= angle_width_scale;

    vec4 lx = grid_layers(world_pos.yz, tapered_line_width);
    vec4 ly = grid_layers(world_pos.xz, tapered_line_width);
    vec4 lz = grid_layers(world_pos.xy, tapered_line_width);

    vec3 n = normalize(world_normal);
    vec3 blend = pow(abs(n), vec3(4.0));
    blend /= max(blend.x + blend.y + blend.z, 0.0001);

    float outer_grid = lx.x * blend.x + ly.x * blend.y + lz.x * blend.z;
    float core_grid = lx.y * blend.x + ly.y * blend.y + lz.y * blend.z;
    float hollow_mask = lx.z * blend.x + ly.z * blend.y + lz.z * blend.z;
    float alias_risk = lx.w * blend.x + ly.w * blend.y + lz.w * blend.z;

    float distance_intensity = mix(1.0, far_intensity_scale, dist_t) * distance_fade;
    outer_grid *= distance_intensity;
    core_grid *= distance_intensity;
    hollow_mask *= distance_fade;
    float alias_stability = 1.0 - alias_risk;
    core_grid *= mix(1.0, alias_stability, 0.7);
    core_grid = max(core_grid, outer_grid * clamp(min_core_visibility, 0.0, 1.0));

    // Sparse digital pulse: occasional line flicker keyed to world-space line regions.
    float line_seed = hash21(floor(world_pos.xz * max(grid_scale, 0.001) * 0.5));
    float pulse_tick = floor(TIME * max(glitch_pulse_rate, 0.01));
    float pulse_gate = step(1.0 - clamp(glitch_pulse_density, 0.0, 1.0), hash11(line_seed * 431.73 + pulse_tick));
    float pulse_wave = 0.5 + 0.5 * sin(TIME * max(glitch_pulse_speed, 0.01) * 12.0 + line_seed * 25.1327);
    float glitch_gain = 1.0 + clamp(glitch_pulse_strength, 0.0, 2.0) * pulse_gate * pulse_wave;
    outer_grid *= glitch_gain;
    core_grid *= glitch_gain;

    // Tron-style edge highlight
    float fresnel = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

    float hollow_kill = 1.0 - clamp(hollow_mask * hollow_light_kill, 0.0, 1.0);
    vec3 hollow_bg = bg_color * (1.0 - hollow_strength * hollow_mask) * hollow_kill;
    float line_mask = max(outer_grid, core_grid);
    vec3 line_color = mix(grid_color, core_color, clamp(core_grid, 0.0, 1.0));
    vec3 base_albedo = mix(hollow_bg, line_color, clamp(line_mask, 0.0, 1.0));
    vec3 core_add = core_color * core_grid * clamp(core_albedo_add, 0.0, 2.0);
    ALBEDO = min(base_albedo + core_add, vec3(1.0));

    float core_emission_mask = pow(clamp(core_grid, 0.0, 1.0), max(core_emission_softness, 0.01));
    core_emission_mask *= mix(1.0, 1.0 - clamp(core_far_suppression, 0.0, 1.0), dist_t);
    core_emission_mask *= 1.0 - alias_risk * clamp(alias_emission_suppression, 0.0, 1.0);
    core_emission_mask = max(core_emission_mask, outer_grid * clamp(min_core_emission, 0.0, 1.0));
    vec3 stabilized_core_color = mix(core_color, grid_color, clamp(core_color_bias, 0.0, 1.0));

    vec3 emission_color =
        grid_color * outer_grid * grid_glow +
        stabilized_core_color * core_emission_mask * core_glow +
        edge_color * fresnel * edge_glow * line_mask;

    EMISSION = min(emission_color * hollow_kill, vec3(max(emission_peak_limit, 0.0)));

    // Subtle edge-only chromatic fringe to reinforce the digital-sim look.
    vec2 center_delta = SCREEN_UV - vec2(0.5);
    float edge_radius = length(center_delta * 2.0);
    float edge_mask = smoothstep(chromatic_aberration_edge_start, 1.0, edge_radius);
    vec2 ca_dir = normalize(center_delta + vec2(0.0001, 0.0));
    vec2 ca_offset = ca_dir * (chromatic_aberration_strength * edge_mask);
    vec2 uv_r = clamp(SCREEN_UV + ca_offset, vec2(0.001), vec2(0.999));
    vec2 uv_g = clamp(SCREEN_UV, vec2(0.001), vec2(0.999));
    vec2 uv_b = clamp(SCREEN_UV - ca_offset, vec2(0.001), vec2(0.999));
    vec3 ca_sample = vec3(texture(screen_texture, uv_r).r, texture(screen_texture, uv_g).g, texture(screen_texture, uv_b).b);
    vec3 ca_tint = ca_sample - vec3(dot(ca_sample, vec3(0.3333)));
    float ca_mix = edge_mask * chromatic_aberration_intensity;
    ALBEDO = clamp(ALBEDO + ca_tint * ca_mix * 0.30, vec3(0.0), vec3(1.0));
    EMISSION += ca_tint * ca_mix * 0.20;
}

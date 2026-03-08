in vec4 v_color;
in highp vec2 v_wall_uv;
in highp float v_height_m;
in lowp float v_is_side;
flat in highp float v_ed_flat;

void main() {
    fragColor = v_color;

    // --- Procedural windows on side faces ---
    if (v_is_side > 0.5 && v_height_m >= 3.1) {
        float num_floors = max(1.0, floor(v_height_m / 3.0));
        float floor_v = fract(v_wall_uv.y * num_floors);

        // Floor band margins (60% window fill — visible floor slabs)
        float band_b = 0.18;
        float band_t = 0.78;
        float fw_v = fwidth(floor_v);
        float floor_mask = smoothstep(band_b - fw_v, band_b + fw_v, floor_v)
                         * smoothstep(band_t + fw_v, band_t - fw_v, floor_v);

        // Vertical window columns — tile using flat edge distance anchor
        float window_spacing = 600.0;
        float raw_u = (v_wall_uv.x - v_ed_flat) / window_spacing;
        float cell_u = fract(raw_u);
        float fw_u = fwidth(cell_u);

        float win_l = 0.20;
        float win_r = 0.80;
        float col_mask = smoothstep(win_l - fw_u, win_l + fw_u, cell_u)
                       * smoothstep(win_r + fw_u, win_r - fw_u, cell_u);

        float win_mask = floor_mask * col_mask;

        if (win_mask > 0.01) {
            vec2 grid_id = floor(vec2(raw_u, v_wall_uv.y * num_floors));
            float hash = fract(sin(dot(grid_id, vec2(12.9898, 78.233))) * 43758.5453);

            vec3 window_color = vec3(0.55, 0.78, 0.90) + hash * vec3(-0.04, -0.02, 0.02);

            // Diagonal glare — always on, very subtle
            float local_u = clamp((cell_u - win_l) / (win_r - win_l), 0.0, 1.0);
            float local_v = clamp((floor_v - band_b) / (band_t - band_b), 0.0, 1.0);
            float diag = (local_u + local_v) * 0.7;
            float fw_diag = fwidth(diag);
            float glare = smoothstep(0.3 - fw_diag, 0.5, diag)
                        * smoothstep(0.7 + fw_diag, 0.5, diag);
            glare *= 0.20 + hash * 0.08;
            window_color = mix(window_color, vec3(1.0), glare);

            float luminance = dot(v_color.rgb, vec3(0.299, 0.587, 0.114));
            vec3 lit_window = window_color * max(luminance * 1.2, 0.60);
            fragColor.rgb = mix(fragColor.rgb, lit_window, 0.88 * win_mask);
        }
    }

    // --- Soft edge AO (side faces only) ---
    if (v_is_side > 0.5) {
        float base_ao = smoothstep(0.0, 0.10, v_wall_uv.y);
        fragColor.rgb *= mix(0.86, 1.0, base_ao);

        float top_glow = smoothstep(0.92, 1.0, v_wall_uv.y);
        fragColor.rgb *= mix(1.0, 1.06, top_glow);
    }

    #ifdef OVERDRAW_INSPECTOR
        fragColor = vec4(1.0);
    #endif
}

in vec4 v_color;
in highp vec2 v_wall_uv;
flat in highp float v_height_m;
flat in lowp float v_is_side;
flat in highp float v_ed_flat;
flat in highp float v_face_width;
flat in mediump vec3 v_wall_normal;
flat in highp float v_body_hash;
uniform lowp vec3 u_camera_dir;

void main() {
    fragColor = v_color;

    // --- Per-building body color variation (computed in vertex shader from centroid+height) ---
    float body_hash = v_body_hash;
#define DEBUG_BUILDING_COLORS
#ifdef DEBUG_BUILDING_COLORS
    float h2 = fract(body_hash * 7.31);
    float h3 = fract(body_hash * 13.17);
    vec3 body_color = vec3(
        0.65 + 0.35 * body_hash,
        0.65 + 0.35 * h2,
        0.65 + 0.35 * h3
    );
#else
    vec3 beige_warm = vec3(0.961, 0.929, 0.886); // #F5EDE2
    vec3 beige_cool = vec3(0.910, 0.867, 0.816); // #E8DDD0
    vec3 body_color = mix(beige_warm, beige_cool, body_hash);
#endif
    fragColor.rgb = body_color;
    fragColor.a = v_color.a;

    // --- Procedural windows on side faces ---
    if (v_is_side > 0.5 && v_height_m >= 3.1) {
        float num_floors = max(1.0, floor(v_height_m / 3.0));
        float floor_v = fract(v_wall_uv.y * num_floors);

        // Floor band margins (60% window fill — visible floor slabs)
        float band_b = 0.18;
        float band_t = 0.78;
        float fw_v = fwidth(v_wall_uv.y * num_floors);
        float floor_mask = smoothstep(band_b - fw_v, band_b + fw_v, floor_v)
                         * smoothstep(band_t + fw_v, band_t - fw_v, floor_v);

        // Vertical window columns — keep facade edge padding independent from
        // the repeated column rhythm, clipping the tail window at the right
        // boundary when needed.
        float window_width = 360.0;
        float window_gap = 8.0;
        float window_spacing = window_width + window_gap;
        float outer_pad_l = 60.0;
        float outer_pad_r = 60.0;

        float col_mask = 0.0;
        float raw_u = 0.0;
        float cell_u = 0.0;
        float face_u = clamp(v_wall_uv.x - v_ed_flat, 0.0, max(v_face_width, 0.0));

        if (v_face_width > outer_pad_l + outer_pad_r) {
            float content_max = v_face_width - outer_pad_r;
            float fw_face = fwidth(face_u);
            float within_content = smoothstep(outer_pad_l - fw_face, outer_pad_l + fw_face, face_u)
                                 * smoothstep(content_max + fw_face, content_max - fw_face, face_u);

            raw_u = (face_u - outer_pad_l) / window_spacing;
            cell_u = fract(raw_u);
            float fw_u = fwidth(raw_u);
            float win_r = window_width / window_spacing;
            col_mask = within_content
                     * smoothstep(0.0 - fw_u, 0.0 + fw_u, cell_u)
                     * smoothstep(win_r + fw_u, win_r - fw_u, cell_u);
        }

        float win_mask = floor_mask * col_mask;

        // Grazing-angle detail gate: fade out windows when face is nearly
        // edge-on (UV frequency exceeds Nyquist → aliasing).
        float detail = 1.0 - smoothstep(0.4, 0.8, fwidth(raw_u));
        float floor_detail = 1.0 - smoothstep(0.4, 0.8, fw_v);
        win_mask *= min(detail, floor_detail);

        // Top-of-building parapet — same thickness as inter-floor slab
        float slab_uv = (1.0 - band_t + band_b) / num_floors;
        float fw_top = fwidth(v_wall_uv.y);
        win_mask *= smoothstep(1.0 - slab_uv + fw_top, 1.0 - slab_uv - fw_top, v_wall_uv.y);

        if (win_mask > 0.01) {
            vec2 grid_id = floor(vec2(raw_u, v_wall_uv.y * num_floors));
            float face_seed = v_ed_flat * 0.0073 + v_face_width * 0.0129 + v_height_m * 0.0197;
            float hash = fract(sin(dot(grid_id, vec2(12.9898, 78.233)) + face_seed) * 43758.5453);
            float hash2 = fract(sin(dot(grid_id + 19.37, vec2(39.3468, 11.1351)) + face_seed) * 24634.6345);

            vec3 palette_a = vec3(0.57, 0.82, 0.95);
            vec3 palette_b = vec3(0.70, 0.87, 0.98);
            vec3 palette_c = vec3(0.63, 0.79, 0.94);
            vec3 palette_d = vec3(0.80, 0.92, 0.99);
            vec3 palette_base = mix(
                mix(palette_a, palette_b, step(0.25, hash)),
                mix(palette_c, palette_d, step(0.75, hash)),
                step(0.50, hash)
            );
            vec3 window_color = clamp(palette_base + (hash2 - 0.5) * vec3(0.055, 0.034, 0.038), 0.0, 1.0);

            float local_u = clamp((cell_u * window_spacing) / window_width, 0.0, 1.0);
            float local_v = clamp((floor_v - band_b) / (band_t - band_b), 0.0, 1.0);

            // Keep the diagonal read as a broad reflected wash, mirrored to run
            // from top-right toward bottom-left.
            float streak_axis = (1.0 - local_u) * 0.72 + local_v * 0.92;
            float streak_center = 0.77 + (hash2 - 0.5) * 0.12;
            float streak_width = 0.26;
            float streak_dist = abs(streak_axis - streak_center);
            float fw_streak = fwidth(streak_axis);
            float streak = 1.0 - smoothstep(streak_width - fw_streak, streak_width + 0.22 + fw_streak, streak_dist);
            float streak_gradient = 0.58 * local_v + 0.42 * (1.0 - local_u);
            window_color *= 0.90 + streak_gradient * 0.14;
            window_color = mix(window_color, vec3(0.97, 0.985, 1.0), streak * (0.11 + hash * 0.04));

            float facing = clamp(abs(dot(normalize(v_wall_normal), normalize(u_camera_dir))), 0.0, 1.0);
            float grazing = pow(1.0 - facing, 1.65);
            float specular = min(grazing * (0.32 + hash2 * 0.12), 0.52);
            window_color = mix(window_color, vec3(0.985, 0.995, 1.0), specular);

            float luminance = dot(v_color.rgb, vec3(0.299, 0.587, 0.114));
            vec3 lit_window = window_color * max(luminance * 1.18, 0.70);
            lit_window *= 1.0 + 0.24 * grazing;
            fragColor.rgb = mix(fragColor.rgb, lit_window, 0.84 * win_mask);
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

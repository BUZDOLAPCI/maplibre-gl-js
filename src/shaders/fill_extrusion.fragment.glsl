in vec4 v_color;
in highp vec2 v_wall_uv;
in highp float v_height_m;
in lowp float v_is_side;
flat in highp float v_ed_flat;
flat in highp float v_face_width;
flat in mediump vec3 v_wall_normal;
in highp vec2 v_tile_pos;

uniform lowp vec3 u_camera_dir;

void main() {
    fragColor = v_color;

    // --- Per-building body color variation (shader-based, cross-platform) ---
    float body_hash;
    if (v_is_side > 0.5) {
        // Side walls: per-face variation via edgedistance
        body_hash = fract(sin(v_ed_flat * 0.0073 + v_height_m * 0.0197) * 43758.5453);
    } else {
        // Roof: position-based grid for zebra-striping across merged polygons
        float cell_size = 700.0;
        vec2 cell = floor(v_tile_pos / cell_size);
        body_hash = fract(sin(dot(cell, vec2(12.9898, 78.233)) + v_height_m * 0.0197) * 43758.5453);
    }
    vec3 beige_warm = vec3(0.961, 0.929, 0.886); // #F5EDE2
    vec3 beige_cool = vec3(0.910, 0.867, 0.816); // #E8DDD0
    fragColor.rgb = mix(beige_warm, beige_cool, body_hash);
    fragColor.a = v_color.a;

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
            float fw_u = fwidth(cell_u);
            float win_r = window_width / window_spacing;
            col_mask = within_content
                     * smoothstep(0.0 - fw_u, 0.0 + fw_u, cell_u)
                     * smoothstep(win_r + fw_u, win_r - fw_u, cell_u);
        }

        float win_mask = floor_mask * col_mask;

        // Top-of-building parapet — same thickness as inter-floor slab
        float slab_uv = (1.0 - band_t + band_b) / num_floors;
        float fw_top = fwidth(v_wall_uv.y);
        win_mask *= smoothstep(1.0 - slab_uv + fw_top, 1.0 - slab_uv - fw_top, v_wall_uv.y);

        if (win_mask > 0.01) {
            // DEBUG: flat blue to isolate mask vs color noise
            fragColor.rgb = mix(fragColor.rgb, vec3(0.6, 0.8, 0.95), 0.84 * win_mask);
        }
    }

    // --- Soft edge AO (side faces only) ---
    if (v_is_side > 0.5) {
        float base_ao = smoothstep(0.0, 0.10, v_wall_uv.y);
        fragColor.rgb *= mix(0.86, 1.0, base_ao);

        float top_glow = smoothstep(0.92, 1.0, v_wall_uv.y);
        fragColor.rgb *= mix(1.0, 1.06, top_glow);
    }

    // --- Per-building depth offset to resolve z-fighting on shared walls ---
    // Adjacent row houses share coplanar wall faces; without an offset the GPU
    // alternates between the two buildings' fragments per pixel (noise).
    // A tiny deterministic offset based on body_hash ensures one building
    // consistently wins the depth test on shared walls.
    gl_FragDepth = gl_FragCoord.z - body_hash * 5e-5;

    #ifdef OVERDRAW_INSPECTOR
        fragColor = vec4(1.0);
    #endif
}

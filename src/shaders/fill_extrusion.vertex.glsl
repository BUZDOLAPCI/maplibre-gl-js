uniform vec3 u_lightcolor;
uniform lowp vec3 u_lightpos;
uniform lowp vec3 u_lightpos_globe;
uniform lowp float u_lightintensity;
uniform float u_vertical_gradient;
uniform lowp float u_opacity;
uniform vec2 u_fill_translate;
uniform vec2 u_tile_id;
uniform float u_centroid_scale;
uniform highp float u_is_shadow;
uniform highp float u_meters_to_tile;

in vec2 a_pos;
in vec4 a_normal_ed;
in float a_face_width;
in vec2 a_centroid;


out vec4 v_color;
out highp vec2 v_wall_uv;
flat out highp float v_height_m;
flat out lowp float v_is_side;
flat out highp float v_ed_flat;
flat out highp float v_face_width;
flat out mediump vec3 v_wall_normal;
flat out highp float v_body_hash;
out float v_directional;

#pragma mapbox: define highp float base
#pragma mapbox: define highp float height

#pragma mapbox: define highp vec4 color

void main() {
    #pragma mapbox: initialize highp float base
    #pragma mapbox: initialize highp float height
    #pragma mapbox: initialize highp vec4 color

    vec3 normal = a_normal_ed.xyz;
    float edgedistance = a_normal_ed.w;

    #ifdef TERRAIN3D
        // Raise the "ceiling" of elements by the elevation of the centroid, in meters.
        float height_terrain3d_offset = get_elevation(a_centroid);
        // To avoid having buildings "hang above a slope", create a "basement"
        // by lowering the "floor" of ground-level (and below) elements.
        // This is in addition to the elevation of the centroid, in meters.
        float base_terrain3d_offset = height_terrain3d_offset - (base > 0.0 ? 0.0 : 10.0);
    #else
        float height_terrain3d_offset = 0.0;
        float base_terrain3d_offset = 0.0;
    #endif
    // Sub-terranian "floors and ceilings" are clamped to ground-level.
    // 3D Terrain offsets, if applicable, are applied on the result.
    base = max(0.0, base) + base_terrain3d_offset;
    height = max(0.0, height) + height_terrain3d_offset;

    float t = mod(normal.x, 2.0);
    float elevation = t > 0.0 ? height : base;
    vec2 posInTile = a_pos + u_fill_translate;

    // --- Shadow pass: project geometry onto ground plane ---
    if (u_is_shadow > 0.001) {
        // Skip side faces — only roof projects shadow
        if (normal.y != 0.0) {
            gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
            v_color = vec4(0.0); v_wall_uv = vec2(0.0); v_height_m = 0.0;
            v_is_side = 0.0; v_ed_flat = 0.0; v_face_width = 0.0;
            v_wall_normal = vec3(0.0); v_body_hash = 0.0; v_directional = 0.0;
            return;
        }

        // Light direction and shadow angle
        vec2 light_xy = u_lightpos.xy;
        float light_xy_len = length(light_xy);
        float light_z = max(u_lightpos.z, 0.05);
        vec2 light_dir = light_xy_len > 0.0 ? -light_xy / light_xy_len : vec2(0.0, 0.0);
        float shadow_angle_factor = clamp(light_xy_len / light_z, 0.0, 6.0);

        float shadow_height_m = max(height - base, 0.0);
        float shadow_len_m = shadow_height_m * shadow_angle_factor;
        vec2 shadow_offset_tile = light_dir * shadow_len_m * u_meters_to_tile;

        // Top vertices (t > 0) shift outward; base vertices stay at footprint
        float shadow_mix = t > 0.0 ? 1.0 : 0.0;
        vec2 shadow_xy = posInTile + shadow_offset_tile * shadow_mix;

        gl_Position = u_projection_matrix * vec4(shadow_xy, 0.0, 1.0);

        // Set varyings needed by fragment shader shadow path
        v_is_side = (normal.y != 0.0) ? 1.0 : 0.0;
        v_height_m = shadow_height_m;
        float height_range_s = max(height - base, 0.001);
        v_wall_uv = vec2(edgedistance, (elevation - base) / height_range_s);

        // Not used in shadow path but must be defined
        v_ed_flat = 0.0;
        v_face_width = 0.0;
        v_wall_normal = vec3(0.0);
        v_body_hash = 0.0;
        v_directional = 0.0;
        v_color = vec4(0.0);
        return;
    }

    #ifdef GLOBE
        vec3 spherePos = projectToSphere(posInTile, a_pos);
        gl_Position = interpolateProjectionFor3D(posInTile, spherePos, elevation);
    #else
        gl_Position = u_projection_matrix * vec4(posInTile, elevation, 1.0);
    #endif

    // --- Procedural window data ---
    v_is_side = (normal.y != 0.0) ? 1.0 : 0.0;
    v_height_m = max(0.0, height - base);
    float height_range = max(height - base, 0.001);
    v_wall_uv = vec2(edgedistance, (elevation - base) / height_range);
    v_ed_flat = edgedistance;
    v_face_width = a_face_width;
    v_wall_normal = normal.y != 0.0 ? normalize(vec3(normal.x, normal.y, 0.0)) : vec3(0.0);
    vec2 world_centroid = u_tile_id + (a_centroid / 8192.0) * u_centroid_scale;
    // Hash world_centroid directly — no grid snapping needed.
    // world_centroid is bit-exact across zoom levels (all ops are power-of-2
    // divisions), so the chaotic sin() hash produces stable colors per building.
    // Two-round hash with large-magnitude constants for decorrelation.
    float h = fract(sin(dot(world_centroid, vec2(127.1, 311.7))) * 43758.5453);
    h = fract(sin(h * 78.233 + dot(world_centroid, vec2(269.5, 183.3))) * 24634.6345);
    v_body_hash = fract(h + height * 0.0197);

    // Relative luminance (how dark/bright is the surface color?)
    float colorvalue = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;

    v_color = vec4(0.0, 0.0, 0.0, 1.0);

    // Add slight ambient lighting so no extrusions are totally black
    vec4 ambientlight = vec4(0.03, 0.03, 0.03, 1.0);
    color += ambientlight;

    // Calculate cos(theta), where theta is the angle between surface normal and diffuse light ray
    vec3 normalForLighting = normal / 16384.0;
    float directional = clamp(dot(normalForLighting, u_lightpos), 0.0, 1.0);

    #ifdef GLOBE
        mat3 rotMatrix = globeGetRotationMatrix(spherePos);
        normalForLighting = rotMatrix * normalForLighting;
        // Interpolate dot product result instead of normals and light direction
        directional = mix(directional, clamp(dot(normalForLighting, u_lightpos_globe), 0.0, 1.0), u_projection_transition);
    #endif

    // Adjust directional so that
    // the range of values for highlight/shading is narrower
    // with lower light intensity
    // and with lighter/brighter surface colors
    directional = mix((1.0 - u_lightintensity), max((1.0 - colorvalue + u_lightintensity), 1.0), directional);

    // Add gradient along z axis of side surfaces
    if (normal.y != 0.0) {
        // This avoids another branching statement, but multiplies by a constant of 0.84 if no vertical gradient,
        // and otherwise calculates the gradient based on base + height
        directional *= (
            (1.0 - u_vertical_gradient) +
            (u_vertical_gradient * clamp((t + base) * pow(height / 150.0, 0.5), mix(0.7, 0.98, 1.0 - u_lightintensity), 1.0)));
    }

    // Pass directional factor to fragment shader for procedural body color lighting
    v_directional = directional;

    // Assign final color based on surface + ambient light color, diffuse light directional, and light color
    // with lower bounds adjusted to hue of light
    // so that shading is tinted with the complementary (opposite) color to the light color
    v_color.r += clamp(color.r * directional * u_lightcolor.r, mix(0.0, 0.3, 1.0 - u_lightcolor.r), 1.0);
    v_color.g += clamp(color.g * directional * u_lightcolor.g, mix(0.0, 0.3, 1.0 - u_lightcolor.g), 1.0);
    v_color.b += clamp(color.b * directional * u_lightcolor.b, mix(0.0, 0.3, 1.0 - u_lightcolor.b), 1.0);
    v_color *= u_opacity;
}

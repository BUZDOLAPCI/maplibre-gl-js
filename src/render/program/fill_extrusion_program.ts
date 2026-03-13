import {patternUniformValues} from './pattern';
import {
    Uniform1i,
    Uniform1f,
    Uniform2f,
    Uniform3f
} from '../uniform_binding';

import {mat3, vec3} from 'gl-matrix';
import {extend} from '../../util/util';
import {cameraDirectionFromPitchBearing} from '../../geo/projection/mercator_utils';
import {EXTENT} from '../../data/extent';
import {earthRadius} from '../../geo/lng_lat';

import type {Context} from '../../gl/context';
import type {Painter} from '../painter';
import type {OverscaledTileID} from '../../tile/tile_id';
import type {UniformValues, UniformLocations} from '../uniform_binding';
import type {CrossfadeParameters} from '../../style/evaluation_parameters';
import type {Tile} from '../../tile/tile';

export type FillExtrusionUniformsType = {
    'u_lightpos': Uniform3f;
    'u_lightpos_globe': Uniform3f;
    'u_lightintensity': Uniform1f;
    'u_lightcolor': Uniform3f;
    'u_camera_dir': Uniform3f;
    'u_vertical_gradient': Uniform1f;
    'u_opacity': Uniform1f;
    'u_fill_translate': Uniform2f;
    'u_tile_id': Uniform2f;
    'u_centroid_scale': Uniform1f;
    'u_is_shadow': Uniform1f;
    'u_meters_to_tile': Uniform1f;
};

export type FillExtrusionPatternUniformsType = {
    'u_lightpos': Uniform3f;
    'u_lightpos_globe': Uniform3f;
    'u_lightintensity': Uniform1f;
    'u_lightcolor': Uniform3f;
    'u_camera_dir': Uniform3f;
    'u_height_factor': Uniform1f;
    'u_vertical_gradient': Uniform1f;
    'u_opacity': Uniform1f;
    'u_fill_translate': Uniform2f;
    // pattern uniforms:
    'u_texsize': Uniform2f;
    'u_image': Uniform1i;
    'u_pixel_coord_upper': Uniform2f;
    'u_pixel_coord_lower': Uniform2f;
    'u_scale': Uniform3f;
    'u_fade': Uniform1f;
};

const fillExtrusionUniforms = (context: Context, locations: UniformLocations): FillExtrusionUniformsType => ({
    'u_lightpos': new Uniform3f(context, locations.u_lightpos),
    'u_lightpos_globe': new Uniform3f(context, locations.u_lightpos_globe),
    'u_lightintensity': new Uniform1f(context, locations.u_lightintensity),
    'u_lightcolor': new Uniform3f(context, locations.u_lightcolor),
    'u_camera_dir': new Uniform3f(context, locations.u_camera_dir),
    'u_vertical_gradient': new Uniform1f(context, locations.u_vertical_gradient),
    'u_opacity': new Uniform1f(context, locations.u_opacity),
    'u_fill_translate': new Uniform2f(context, locations.u_fill_translate),
    'u_tile_id': new Uniform2f(context, locations.u_tile_id),
    'u_centroid_scale': new Uniform1f(context, locations.u_centroid_scale),
    'u_is_shadow': new Uniform1f(context, locations.u_is_shadow),
    'u_meters_to_tile': new Uniform1f(context, locations.u_meters_to_tile),
});

const fillExtrusionPatternUniforms = (context: Context, locations: UniformLocations): FillExtrusionPatternUniformsType => ({
    'u_lightpos': new Uniform3f(context, locations.u_lightpos),
    'u_lightpos_globe': new Uniform3f(context, locations.u_lightpos_globe),
    'u_lightintensity': new Uniform1f(context, locations.u_lightintensity),
    'u_lightcolor': new Uniform3f(context, locations.u_lightcolor),
    'u_camera_dir': new Uniform3f(context, locations.u_camera_dir),
    'u_vertical_gradient': new Uniform1f(context, locations.u_vertical_gradient),
    'u_height_factor': new Uniform1f(context, locations.u_height_factor),
    'u_opacity': new Uniform1f(context, locations.u_opacity),
    'u_fill_translate': new Uniform2f(context, locations.u_fill_translate),
    // pattern uniforms
    'u_image': new Uniform1i(context, locations.u_image),
    'u_texsize': new Uniform2f(context, locations.u_texsize),
    'u_pixel_coord_upper': new Uniform2f(context, locations.u_pixel_coord_upper),
    'u_pixel_coord_lower': new Uniform2f(context, locations.u_pixel_coord_lower),
    'u_scale': new Uniform3f(context, locations.u_scale),
    'u_fade': new Uniform1f(context, locations.u_fade)
});

function computeMetersToTile(coord: OverscaledTileID): number {
    const numTiles = Math.pow(2, coord.canonical.z);
    const tileY = coord.canonical.y;
    const latRad = Math.atan(Math.sinh(Math.PI * (1 - 2 * (tileY + 0.5) / numTiles)));
    const tileWidthMeters = 2 * Math.PI * earthRadius * Math.cos(latRad) / numTiles;
    return EXTENT / tileWidthMeters;
}

const fillExtrusionUniformValues = (
    painter: Painter,
    shouldUseVerticalGradient: boolean,
    opacity: number,
    translate: [number, number],
    coord: OverscaledTileID,
    shadowOpacity: number = 0,
): UniformValues<FillExtrusionUniformsType> => {
    const light = painter.style.light;
    const _lp = light.properties.get('position');
    const lightPos = [_lp.x, _lp.y, _lp.z] as vec3;
    const lightMat = mat3.create();
    if (light.properties.get('anchor') === 'viewport') {
        mat3.fromRotation(lightMat, painter.transform.bearingInRadians);
    }
    vec3.transformMat3(lightPos, lightPos, lightMat);
    const transformedLightPos = painter.transform.transformLightDirection(lightPos);
    const cameraDirSource = cameraDirectionFromPitchBearing(painter.transform.pitch, painter.transform.bearing);
    const cameraDir = [cameraDirSource.x, cameraDirSource.y, cameraDirSource.z] as vec3;

    const lightColor = light.properties.get('color');

    // Normalize tile coordinates to zoom-independent space so the same building
    // produces the same body_hash regardless of which zoom level's tile contains it.
    // At zoom z, tile (tx, ty) maps to reference coordinate (tx / 2^(z-8), ty / 2^(z-8)).
    // This gives values in [0, 256) — good float32 precision without modular aliasing.
    const zoomFactor = Math.pow(2, coord.canonical.z - 8);
    const metersToTile = shadowOpacity > 0 ? computeMetersToTile(coord) : 0;

    return {
        'u_lightpos': lightPos,
        'u_lightpos_globe': transformedLightPos,
        'u_lightintensity': light.properties.get('intensity'),
        'u_lightcolor': [lightColor.r, lightColor.g, lightColor.b],
        'u_camera_dir': cameraDir,
        'u_vertical_gradient': +shouldUseVerticalGradient,
        'u_opacity': opacity,
        'u_fill_translate': translate,
        'u_tile_id': [coord.canonical.x / zoomFactor, coord.canonical.y / zoomFactor],
        'u_centroid_scale': 1.0 / zoomFactor,
        'u_is_shadow': shadowOpacity,
        'u_meters_to_tile': metersToTile,
    };
};

const fillExtrusionPatternUniformValues = (
    painter: Painter,
    shouldUseVerticalGradient: boolean,
    opacity: number,
    translate: [number, number],
    coord: OverscaledTileID,
    crossfade: CrossfadeParameters,
    tile: Tile
): UniformValues<FillExtrusionPatternUniformsType> => {
    return extend(fillExtrusionUniformValues(painter, shouldUseVerticalGradient, opacity, translate, coord),
        patternUniformValues(crossfade, painter, tile),
        {
            'u_height_factor': -Math.pow(2, coord.overscaledZ) / tile.tileSize / 8
        });
};

export {
    fillExtrusionUniforms,
    fillExtrusionPatternUniforms,
    fillExtrusionUniformValues,
    fillExtrusionPatternUniformValues
};

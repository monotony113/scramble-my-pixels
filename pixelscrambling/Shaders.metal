//
//  Shaders.metal
//  PixelScramblingMetalLibrary
//
//  Created by Tony Wu on 1/19/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

inline uint4 denormalizeColor(float4 c) {
    return uint4(c * 255);
}
inline float4 normalizeColor(uint4 c) {
    return float4(c) / 255.0f;
}

kernel void permutationKernel(texture2d<float, access::read>    srcTexture  [[texture(0)]],
                              texture2d<uint, access::read>     lookupTable [[texture(1)]],
                              texture2d<float, access::write>   dstTexture  [[texture(2)]],
                              uint2                             gid         [[thread_position_in_grid]])
{
    if (gid.x >= srcTexture.get_width() || gid.y >= srcTexture.get_height())
    {
        return;
    }
    
    uint4 transformInstruction = lookupTable.read(gid);
    uint directionAndScale = transformInstruction.z;
    
    float2 distanceScalar = float2(transformInstruction.xy);
    float scale = float(directionAndScale / 4 + 1);
    float2 direction;
    switch (directionAndScale % 4) {
        case 0: direction = float2(1, 1); break;
        case 1: direction = float2(-1, 1); break;
        case 2: direction = float2(1, -1); break;
        case 3: direction = float2(-1, -1); break;
    }
    direction.x = scale * direction.x * distanceScalar.x;
    direction.y = scale * direction.y * distanceScalar.y;

    float4 color = srcTexture.read(uint2(float2(gid) + direction));
    
    dstTexture.write(color, gid);
    
}

kernel void substitutionKernel(texture2d<float, access::read>   srcTexture  [[texture(0)]],
                               texture2d<uint, access::read>    lookupTable [[texture(1)]],
                               texture2d<float, access::write>  dstTexture  [[texture(2)]],
                               uint2                            gid         [[thread_position_in_grid]])
{
    if (gid.x >= srcTexture.get_width() || gid.y >= srcTexture.get_height())
    {
        return;
    }
    
    uint4 operand = lookupTable.read(gid);
    float4 floatColor = srcTexture.read(gid);
    uint4 integerColor = denormalizeColor(floatColor);
    
    dstTexture.write(float4(normalizeColor(integerColor ^ operand).rgb, floatColor.a), gid);
    
}

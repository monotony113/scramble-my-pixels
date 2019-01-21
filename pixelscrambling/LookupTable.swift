//
//  TextureSupport.swift
//  pixelscrambling
//
//  Created by Tony Wu on 1/18/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import Foundation
import CoreImage
import Metal

typealias FlattenedLookupTable = [UInt8]
typealias LookupTableTileElement = [UInt8]
typealias LookupTableTileRow = [LookupTableTileElement]
typealias LookupTableTile = [LookupTableTileRow]

/// Specifies how to produce a lookup table texture i.e. a lookup table interpreted by Metal as an `MTLTexture`, also specifies how the lookup table should be devised.
struct LookupTableTextureSpecification: Hashable {
    let width: Int
    let height: Int
    let originX: Int
    let originY: Int
    let secret: CipherSecret
    let cipherMode: CipherMode
    let clusterSize: Int
    let clusterSizeTable: [Int]
    let blockSize: Int
    let pixelFormat: MTLPixelFormat = .rgba8Uint
    init(_ r: MTLRegion, _ c: RendererConfig, _ p: MTLPixelFormat) {
        secret = c.secret
        cipherMode = c.cipherMode
        width = r.size.width
        height = r.size.height
        originX = r.origin.x
        originY = r.origin.y
        clusterSize = c.clusterSize
        clusterSizeTable = c.clusterTable
        blockSize = c.blockSize
    }
}

class MetalLookupTableFactory {
    var device: MTLDevice!
    var coreImageContext: CIContext!
    var spec: LookupTableTextureSpecification! = nil
    
    func makeTexture() -> MTLTexture? {
        let tableWidth = spec.width
        let tableHeight = spec.height
        let tableOriginX = spec.originX
        let tableOriginY = spec.originY
        let tableRect = CGRect(x: tableOriginX, y: tableOriginY, width: tableWidth, height: tableHeight)
        let tableMTLRegion = MTLRegion(origin: MTLOrigin(x: tableOriginX, y: tableOriginY, z: 0), size: MTLSize(width: tableWidth, height: tableHeight, depth: 1))

        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: spec.pixelFormat, width: tableWidth, height: tableHeight, mipmapped: false)
        textureDesc.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDesc) else { return nil }
        
        var tableCanvas = CIImage.empty()
        
        let regions = tessellateRect(rect: tableRect, spec.blockSize, spec.clusterSizeTable, spec.clusterSizeTable.count - 1)
        
        let tiles = regions.compactMap { (regionSpec: TessellationRegionSpecification) -> CIImage? in
            guard let table = makeLookupTableTile(with: spec.secret, for: spec.cipherMode,
                                                  width: regionSpec.dataWidth, height: regionSpec.dataHeight,
                                                  clusterSize: regionSpec.clusterSize) else { return nil }
            let tableTileData = Array(table.joined().joined())
            return CIImage(bitmapData: Data(tableTileData),
                           bytesPerRow: regionSpec.boxWidth * 4,
                           size: CGSize(width: regionSpec.boxWidth, height: regionSpec.boxHeight),
                           format: CIFormat.RGBA8, colorSpace: nil)
        }
        if tiles.count == 0 { return nil }
        
        let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
        let affineTileFilter = CIFilter(name: "CIAffineTile")!
        for n in 0..<regions.count {
            let region = regions[n].region
            let transform = CGAffineTransform(translationX: region.origin.x, y: region.origin.y)
            
            affineTileFilter.setDefaults()
            affineTileFilter.setValue(tiles[n], forKey: kCIInputImageKey)
            affineTileFilter.setValue(transform, forKey: kCIInputTransformKey)
            let tiledRegion = affineTileFilter.outputImage?.cropped(to: region)
            
            compositeFilter.setDefaults()
            compositeFilter.setValue(tiledRegion, forKey: kCIInputImageKey)
            compositeFilter.setValue(tableCanvas, forKey: kCIInputBackgroundImageKey)
            tableCanvas = compositeFilter.outputImage!
            
        }

        var tableCanvasBitmap = Data.init(count: tableWidth * tableHeight * 4)
        tableCanvasBitmap.withUnsafeMutableBytes { (mutablePointer: UnsafeMutablePointer<UInt8>) in
            
            coreImageContext.render(tableCanvas, toBitmap: mutablePointer, rowBytes: tableWidth * 4, bounds: tableRect, format: CIFormat.RGBA8, colorSpace: nil)
            texture.replace(region: tableMTLRegion, mipmapLevel: 0, withBytes: mutablePointer, bytesPerRow: tableWidth * 4)
            
        }

        return texture
    }
    
    // MARK: Support functions
    private struct TessellationRegionSpecification {
        let boxWidth: Int
        let boxHeight: Int
        let clusterSize: Int
        let region: CGRect
        var dataWidth: Int { return boxWidth / clusterSize }
        var dataHeight: Int { return boxHeight / clusterSize }
        init(w: Int, h: Int, d: Int, r: CGRect) {
            self.boxWidth = w
            self.boxHeight = h
            self.clusterSize = d
            self.region = r
        }
    }
    
    /// Partition a rectangle into multiple regions, each will be populated with lookup table data of a particular dimension
    ///
    /// It is necessary to span the `CipherSecret` across a 2D region on the texture instead of simply filling the texture with bytes linearly in order to destroy not only the colors but also the structure (shapes) in the original image.
    ///
    /// - Parameters:
    ///   - rect: the dimension of the image, which the lookup table should match
    ///   - maxBlockSize: how "blocky" the eventual image will be. Each block contains instructions, obtained from `CipherSecret`, to manipulate the pixels within its region
    ///   - clusterSizeTable: an array of possible values of the # of pixels that should be moved around or substituted together, using the same instruction
    ///   - index: the index of `clusterSizeTable`. Used during recursion to signal return.
    /// - Returns: a specification, which is an array of regions the rectangle is partitioned into, that is passed to `makeTexture()` 
    private func tessellateRect(rect: CGRect, _ maxBlockSize: Int, _ clusterSizeTable: [Int], _ index: Int) -> [TessellationRegionSpecification] {
        let width = Int(rect.width)
        let height = Int(rect.height)
        let base_x = Int(rect.origin.x)
        let base_y = Int(rect.origin.y)
        if index == -1 || width == 0 || height == 0 { return [] }
        let definition = clusterSizeTable[index]
        
        let maxTileDataSize = (maxBlockSize * maxBlockSize) / (definition * definition)
        let maxDataSize = (width / definition) * (height / definition)
        var regionSpecs = [TessellationRegionSpecification]()
        let tallRect = height > width
        
        if definition > width || definition > height {
            regionSpecs.append(contentsOf: tessellateRect(rect: rect, maxBlockSize, clusterSizeTable, index - 1))
            return regionSpecs
        }
        
        var (p, q) = (Int(), Int())
        var (w, h, a, b, dw, dh) = (Int(), Int(), Int(), Int(), Int(), Int())
        if tallRect { p = height; q = width } else { p = width; q = height }
        let d = definition
        if maxTileDataSize > maxDataSize {
            w = p - p % d
            h = q - q % d
        } else if maxBlockSize > q {
            h = q - q % d
            w = maxBlockSize * maxBlockSize / h / d * d
        } else if maxBlockSize <= q {
            w = maxBlockSize
            h = maxBlockSize
        }
        if w > maxBlockSize { w = maxBlockSize }
        if h > maxBlockSize { h = maxBlockSize }
        a = p / w
        b = q / h
        dw = p - w * a
        dh = q - h * b
        if tallRect { (w, h, a, b, dw, dh) = (h, w, b, a, dh, dw) }
        
        let r = CGRect(x: base_x, y: base_y, width: w * a, height: h * b)
        let rectTile = TessellationRegionSpecification(w: w, h: h, d: d, r: r)
        
        regionSpecs.append(rectTile)
        
        regionSpecs.append(contentsOf: tessellateRect(rect: CGRect(x: base_x, y: base_y + height - dh, width: width, height: dh), maxBlockSize, clusterSizeTable, index))
        regionSpecs.append(contentsOf: tessellateRect(rect: CGRect(x: base_x + width - dw, y: base_y, width: dw, height: height - dh), maxBlockSize, clusterSizeTable, index))
        
        return regionSpecs
    }
    
    /// Produce either an S-box, a P-box, or a reversed P-box.
    ///
    /// - Parameters:
    ///   - cipherMode: type of the box
    ///   - width: width
    ///   - height: height
    ///   - clusterSize: the width of the region the pixels in which will share the same instruction, for example pixels in a 4x4 region will move together in a P-box with a clusterSize of 4
    /// - Returns: a 3D array of `UInt8` values, each 4 of them describes the instruction to manipulate 1 pixel and will be stored as 1 pixel in a lookup table, which will be interpreted as an image.
    private func makeLookupTableTile(with secret: CipherSecret, for cipherMode: CipherMode, width: Int, height: Int, clusterSize: Int) -> LookupTableTile? {
        let dataSize = width * height
        let scaledWidth = width * clusterSize
        let scaledHeight = height * clusterSize
        if dataSize > secret.sequenceLength { return nil }
        if 4 * (clusterSize - 1) > UInt8.max { return nil }
        var box = LookupTableTile(repeating: LookupTableTileRow(repeating: LookupTableTileElement(repeating: 0, count: 4), count: width), count: height)
        
        let trimmedSequence: [UInt16]
        switch cipherMode {
        case .substitution:
            trimmedSequence = Array(secret.substitutionSequence[0..<dataSize])
        case .permutation:
            trimmedSequence = secret.permutationSequence.filter() { b in (b < dataSize) }
        case .unpermutation:
            trimmedSequence = secret.permutationSequence.filter() { b in b < dataSize }.enumerated().sorted() { e1, e2 in
                return pseudoStableSort2DAscending(e1.element, e1.offset, e2.element, e2.offset)
                }.map() { b in UInt16(b.offset) }
        }
        
        var n: Int = 0
        for i in 0..<height {
            for j in 0..<width {
                switch cipherMode {
                case .substitution:
                    for k in 0...3 {
                        box[i][j][k] = UInt8(normalizeInteger(Int(trimmedSequence[n]), d: 0...255, r: 0...255))
                        n += 1
                        if n == trimmedSequence.count { n = 0 }
                    }
                case .permutation, .unpermutation:
                    let dx = Int(trimmedSequence[n]) % width - n % width
                    let dy = Int(trimmedSequence[n]) / width - n / width
                    var direction = UInt8()
                    switch (dx.signum(), dy.signum()) {
                    case (0...1, 0...1):
                        direction = 0
                    case (-1, 0...1):
                        direction = 1
                    case (0...1, -1):
                        direction = 2
                    case (-1, -1):
                        direction = 3
                    default:
                        break
                    }
                    box[i][j][0] = UInt8(abs(dx))
                    box[i][j][1] = UInt8(abs(dy))
                    box[i][j][2] = direction
                    box[i][j][3] = 255
                    n += 1
                }
            }
        }
        
        if clusterSize == 1 {
            return box
        } else {
            var scaledBox = LookupTableTile(repeating: LookupTableTileRow(repeating: LookupTableTileElement(repeating: 0, count: 4), count: scaledWidth), count: scaledHeight)
            for i in 0..<scaledHeight {
                for j in 0..<scaledWidth {
                    switch cipherMode {
                    case .substitution:
                        scaledBox[i][j] = box[i / clusterSize][j / clusterSize]
                    case .permutation, .unpermutation:
                        let unscaled = box[i / clusterSize][j / clusterSize]
                        scaledBox[i][j][0] = unscaled[0]
                        scaledBox[i][j][1] = unscaled[1]
                        scaledBox[i][j][2] = unscaled[2] + UInt8(4 * (clusterSize - 1))
                        scaledBox[i][j][3] = 255
                    }
                }
            }
            return scaledBox
        }
    }

}


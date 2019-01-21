//
//  LiveImageRenderingView.swift
//  pixelscrambling
//
//  Created by Tony Wu on 1/16/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import AppKit
import Metal

typealias RendererConfig = ImageRenderer.RendererConfig
typealias RendererEvent = ImageRenderer.RendererEvent
typealias RendererTask = ImageRenderer.RendererTask
typealias RendererPass = ImageRenderer.RendererPass

class ImageRenderer: NSObject {
    
    /// An `enum` used to define a series possible tasks the renderer can do. This allows serialized ciphering/deciphering operations. UI support for such serialization (some kind of job queue that a user can add tasks to) has not been implemented.
    ///
    /// - setup: sets up Metal, including `MTLDevice`, `MTLCommandQueue`, Metal library, functions, and pipelines, as well as auxillary classes such as `CIContext`
    /// - texture: loads the image into GPU as a texture
    /// - compute: The Magic. manipulates the image (now as an `MTLTexture`) using kernel functions
    /// - blit: syncs the computed texture back to CPU memory
    /// - commit: commit the command queue
    /// - flush: partially resets the renderer, removing transcient, intermediate data such as image bitmap data and cipher key to free up resource and prevent spilling into the next operation, but retains lookup table textures for future use
    /// - reset: resets renderer properties
    enum RendererTask {
        case setup
        case texture
        case compute(CipherMode)
        case blit
        case commit
        case flush
        case reset
    }
    class RendererPass: Operation {
        let renderer: ImageRenderer!
        let op: RendererTask
        
        override func main() {
            switch op {
            case .setup:
                name = "setup"
                if !isCancelled && !renderer.metalEnvironment { renderer.setupMetalEnvironment() }
            case .texture:
                name = "texture"
                if !isCancelled { renderer.loadTexture() }
            case .compute(let mode):
                name = "compute"
                renderer.config.cipherMode = mode
                if !isCancelled { renderer.makeLookupTable() }
                if !isCancelled { renderer.compute() }
            case .blit:
                name = "blit"
                if !isCancelled { renderer.blitTexture() }
            case .commit:
                name = "commit"
                if !isCancelled { renderer.commitCommandBuffers() }
            case .flush:
                name = "flush"
                renderer.resetRenderer(fully: false)
            case .reset:
                name = "reset"
                renderer.resetRenderer(fully: true)
            }
        }
        
        init(r: ImageRenderer, o: RendererTask) {
            renderer = r
            op = o
            super.init()
            switch o {
            case .setup: name = "setup"
            case .texture: name = "texture"
            case .compute(_): name = "compute"
            case .blit: name = "blit"
            case .commit: name = "commit"
            case .flush: name = "flush"
            case .reset: name = "reset"
            }
        }
    }
    private var rendererPassCount: Int = 0
    
    enum RendererEvent: String {
        case updateProgress = "updateProgress"
        case updateCompletion = "updateCompletion"
        case rendererShouldTerminate = "rendererShouldTerminate"
        case renderSuccessful = "renderSuccessful"
    }
    /// Talk to view controller through notifications.
    ///
    /// Notification is used in all communication scenarios, including notifying the view controller that the renderer should be stopped because in encountered an error and unfinished `Operation`s be cancelled.
    ///
    /// - Parameters:
    ///   - event: a `RendererEvent`
    ///   - userInfo: the `userInfo` attached to the `Notification`, usually strings to show in the UI
    private func postNotification(_ event: RendererEvent, userInfo: [String: Any]) {
        notificationCenter.post(name: Notification.Name(event.rawValue), object: self, userInfo: userInfo)
    }
    private func makeUserInfo(_ event: RendererEvent, _ attachment: Any) -> [String: Any] {
        return [event.rawValue: attachment]
    }
    private func updateInfoAfterBufferCompleted(_ buffer: MTLCommandBuffer) {
        postNotification(.updateCompletion, userInfo: makeUserInfo(.updateCompletion, NSLocalizedString(buffer.label!, comment: "") ))
    }
    
    struct TextureConfig {
        var width: Int
        var height: Int
        var bitsPerComponent: Int
        var floatingPoint: Bool
        var colorSpace: CGColorSpace
        var bytesPerRow: Int { return width * 4 * bitsPerComponent / 8 }
        var totalBytes: Int { return bytesPerRow * height }
        var pixelFormat: MTLPixelFormat? {
            switch bitsPerComponent {
            case 8: return .rgba8Unorm
            case 16: return floatingPoint ? .rgba16Float : .rgba16Unorm
            case 32: return .rgba32Float
            default: return nil
            }
        }
        var ciFormat: CIFormat! {
            switch bitsPerComponent {
            case 8: return .RGBA8
            case 16: return floatingPoint ? .RGBAh : .RGBA16
            case 32: return .RGBAf
            default: return nil
            }
        }
        var cgBitmapInfo: UInt32 {
            return floatingPoint ? CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.floatComponents.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        }
        var rect: CGRect { return CGRect(x: 0, y: 0, width: width, height: height) }
        var mtlRegion: MTLRegion { return MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1)) }
    }
    
    var notificationCenter: NotificationCenter!
    
    var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var commandBuffers: [MTLCommandBuffer] = []
    
    var imageContext: CIContext!
    
    private var metalLib: MTLLibrary!
    private var pixelPermutationKernel: MTLFunction!
    private var pixelSubstitutionKernel: MTLFunction!
    private var computePipelineStatePixelPermutation: MTLComputePipelineState!
    private var computePipelineStatePixelSubstitution: MTLComputePipelineState!
    
    private var textureDescriptor: MTLTextureDescriptor!
    var textureConfig: TextureConfig! {
        if inputImage == nil { return nil }
        return ImageRenderer.TextureConfig.init(width: inputImage.width,
                                                height: inputImage.height,
                                                bitsPerComponent: inputImage.bitsPerComponent,
                                                floatingPoint: ((inputImage.bitmapInfo.rawValue & CGBitmapInfo.floatInfoMask.rawValue) >> 8) == 1,
                                                colorSpace: inputImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    private var lookupTableConfig: TextureConfig! {
        var config = textureConfig
        config?.bitsPerComponent = 8
        config?.floatingPoint = false
        return config
    }
    
    var srcImageTexture: MTLTexture!
    private var lookupTableTexture: MTLTexture!
    private var dstImageTexture: MTLTexture!
    private var swapImageTexture: MTLTexture!
    var outImageTexture: MTLTexture!
    
    private var srcImageBitmapData: Data!
    private var outImageBitmapData: Data!
    
    var inputImage: CGImage!
    var outputImage: CGImage!
    var outputContainer: ImageContainer!
    var outputCacheURL: URL {
        if outputContainer == .tiff {
            return cacheDirectoryURL.appendingPathComponent("output.tiff", isDirectory: false)
        } else {
            return cacheDirectoryURL.appendingPathComponent("output.png", isDirectory: false)
        }
    }

    private let lookupTableFactory = MetalLookupTableFactory()
    private var lookupTableSpecs: [LookupTableTextureSpecification] = []
    private var lookupTableTextureCache: [LookupTableTextureSpecification: MTLTexture] = [:]
    
    struct RendererConfig: Hashable {
        var secret: CipherSecret
        var cipherMode: CipherMode!
        var clusterSize: Int
        var clusterTable: [Int]
        var blockSize: Int
        init(k: CipherSecret, d: Int, r: Int) {
            secret = k
            clusterSize = d
            blockSize = r
            clusterTable = factorize(blockSize, ge: (blockSize - 1) / 256 + 1, le: clusterSize)
        }
    }
    var config: RendererConfig! = nil
    
    var metalEnvironment = false
    func setupMetalEnvironment() {
        postNotification(.updateProgress, userInfo: makeUserInfo(.updateProgress, NSLocalizedString("Setting up GPU...", comment: "")))
        
        guard let lib = device.makeDefaultLibrary() else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to load Metal library.", comment: "")))
            return
        }
        metalLib = lib
        guard let pKernel = metalLib.makeFunction(name: "permutationKernel") else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate,  NSLocalizedString("Failed to load Metal functions.", comment: "")))
            return
        }
        guard let sKernel = metalLib.makeFunction(name: "substitutionKernel") else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to load Metal functions.", comment: "")))
            return
        }
        pixelPermutationKernel = pKernel
        pixelSubstitutionKernel = sKernel
        guard let queue = device.makeCommandQueue() else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to make GPU command queue.", comment: "")))
            return
        }
        commandQueue = queue
        
        do {
            computePipelineStatePixelPermutation = try device.makeComputePipelineState(function: pixelPermutationKernel)
            computePipelineStatePixelSubstitution = try device.makeComputePipelineState(function: pixelSubstitutionKernel)
        } catch {
            let err = error as NSError
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to create compute pipelines, error code ", comment: "") + "\(err.code): \(err.localizedDescription); \(err.userInfo)"))
        }

        lookupTableFactory.device = device
        
        lookupTableFactory.coreImageContext = CIContext(mtlDevice: device, options: [
            CIContextOption.cacheIntermediates: false,
            CIContextOption.workingColorSpace: NSNull(),
            CIContextOption.outputPremultiplied: false,
            ])
        
        imageContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .outputPremultiplied: false])
        
        metalEnvironment = true
    }
    
    func loadTexture() {
        postNotification(.updateProgress, userInfo: makeUserInfo(.updateProgress, NSLocalizedString("Loading image into GPU texture...", comment: "")))
        
        guard let pixelFormat = textureConfig?.pixelFormat else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Cannot determine pixel format of image.", comment: "")))
            return
        }
        
        textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: textureConfig.width, height: textureConfig.height, mipmapped: false)
        textureDescriptor.storageMode = .private
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        dstImageTexture = device.makeTexture(descriptor: textureDescriptor)
        swapImageTexture = device.makeTexture(descriptor: textureDescriptor)

        textureDescriptor.usage = .shaderRead
        textureDescriptor.storageMode = .managed
        outImageTexture = device.makeTexture(descriptor: textureDescriptor)
        
        if srcImageTexture == nil {
            srcImageTexture = device.makeTexture(descriptor: textureDescriptor)
            
            srcImageBitmapData = Data.init(count: textureConfig.totalBytes)
            let copiedBitmapToTexture = srcImageBitmapData.withUnsafeMutableBytes { (mutablePointer: UnsafeMutablePointer<UInt8>) -> Bool in
                
                guard let context = CGContext(data: mutablePointer,
                                              width: textureConfig.width,
                                              height: textureConfig.height,
                                              bitsPerComponent: textureConfig.bitsPerComponent,
                                              bytesPerRow: textureConfig.bytesPerRow,
                                              space: textureConfig.colorSpace,
                                              bitmapInfo: textureConfig.cgBitmapInfo)
                    else { return false }
                context.draw(inputImage, in: textureConfig.rect)
                srcImageTexture.replace(region: textureConfig.mtlRegion, mipmapLevel: 0, withBytes: mutablePointer, bytesPerRow: textureConfig.bytesPerRow)
                
                return true
            }
            if !copiedBitmapToTexture {
                postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to load image into GPU.", comment: "")))
                return
            }

        }
        
    }
    
    func makeLookupTable() {
        postNotification(.updateProgress, userInfo: [RendererEvent.updateProgress.rawValue: NSLocalizedString("Generating lookup table...", comment: "")])
        
        guard let pixelFormat = lookupTableConfig.pixelFormat else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Cannot determine pixel format of lookup table.", comment: "")))
            return
        }
        
        let lookupTableSpec = LookupTableTextureSpecification(lookupTableConfig.mtlRegion, config, pixelFormat)
        
        if let texture = lookupTableTextureCache[lookupTableSpec] {
            lookupTableTexture = texture
        } else {
            lookupTableFactory.spec = lookupTableSpec
            guard let texture = lookupTableFactory.makeTexture() else {
                postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to produce lookup table.", comment: "")))
                return
            }
            
            lookupTableTexture = texture
            lookupTableTextureCache[lookupTableSpec] = texture
        }
    }
    
    func compute() {
        postNotification(.updateProgress, userInfo: [RendererEvent.updateProgress.rawValue: NSLocalizedString("Computing new bitmap...", comment: "")])
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to schedule GPU computation.", comment: "")))
            return
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to schedule GPU computation.", comment: "")))
            return
        }
        
        let computePipeline: MTLComputePipelineState!
        switch config.cipherMode! {
        case .permutation, .unpermutation:
            computePipeline = computePipelineStatePixelPermutation
        case .substitution:
            computePipeline = computePipelineStatePixelSubstitution
        }
        computeEncoder.setComputePipelineState(computePipeline)
        
        if rendererPassCount == 0 {
            computeEncoder.setTexture(srcImageTexture, index: 0)
            computeEncoder.setTexture(dstImageTexture, index: 2)
        } else if rendererPassCount % 2 == 1 {
            computeEncoder.setTexture(dstImageTexture, index: 0)
            computeEncoder.setTexture(swapImageTexture, index: 2)
        } else {
            computeEncoder.setTexture(swapImageTexture, index: 0)
            computeEncoder.setTexture(dstImageTexture, index: 2)
        }
        computeEncoder.setTexture(lookupTableTexture, index: 1)
        rendererPassCount += 1
        
        let w = computePipeline.threadExecutionWidth
        let h = computePipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadGroup = MTLSize(width: w, height: h, depth: 1)
        computeEncoder.dispatchThreadgroups(textureConfig.mtlRegion.size, threadsPerThreadgroup: threadsPerThreadGroup)
        
        computeEncoder.endEncoding()
        commandBuffer.label = "compute"
        commandBuffer.addCompletedHandler(updateInfoAfterBufferCompleted(_:))
        commandBuffer.enqueue()
        commandBuffers.append(commandBuffer)

    }
    
    func blitTexture() {
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to start GPU computation.", comment: "")))
            return
        }
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to start GPU computation.", comment: "")))
            return
        }
        
        switch rendererPassCount % 2 {
        case 0: blitEncoder.copy(from: swapImageTexture, sourceSlice: 0, sourceLevel: 0,
                                 sourceOrigin: textureConfig.mtlRegion.origin, sourceSize: textureConfig.mtlRegion.size,
                                 to: outImageTexture, destinationSlice: 0, destinationLevel: 0,
                                 destinationOrigin: textureConfig.mtlRegion.origin)
        case 1: blitEncoder.copy(from: dstImageTexture, sourceSlice: 0, sourceLevel: 0,
                                 sourceOrigin: textureConfig.mtlRegion.origin, sourceSize: textureConfig.mtlRegion.size,
                                 to: outImageTexture, destinationSlice: 0, destinationLevel: 0,
                                 destinationOrigin: textureConfig.mtlRegion.origin)
        default: break
        }
        
        blitEncoder.synchronize(texture: outImageTexture, slice: 0, level: 0)
        
        blitEncoder.endEncoding()
        commandBuffer.label = "blit"
        commandBuffer.addCompletedHandler(updateInfoAfterBufferCompleted(_:))
        commandBuffer.addCompletedHandler(getBytesFromTextureAndExport(_:))
        commandBuffer.enqueue()
        commandBuffers.append(commandBuffer)

    }
    
    func commitCommandBuffers() {
        commandBuffers.forEach { buffer in buffer.commit() }
    }
    
    func getBytesFromTextureAndExport(_ buffer: MTLCommandBuffer) {
        
        outImageBitmapData = Data.init(count: textureConfig.totalBytes)
        let gotBitmap = outImageBitmapData.withUnsafeMutableBytes { (mutablePointer: UnsafeMutablePointer<UInt8>) -> Bool in
            
            outImageTexture.getBytes(mutablePointer, bytesPerRow: textureConfig.bytesPerRow, from: textureConfig.mtlRegion, mipmapLevel: 0)
            guard let context = CGContext(data: mutablePointer,
                                          width: textureConfig.width,
                                          height: textureConfig.height,
                                          bitsPerComponent: textureConfig.bitsPerComponent,
                                          bytesPerRow: textureConfig.bytesPerRow,
                                          space: textureConfig.colorSpace,
                                          bitmapInfo: textureConfig.cgBitmapInfo)
                else { return false }
            guard let image = context.makeImage() else { return false }
            
            outputImage = image
            return true
            
        }
        
        if !gotBitmap {
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to read image bitmap from memory.", comment: "")))
            return
        }

        do {
            try NSBitmapImageRep(cgImage: outputImage).representation(using: outputContainer, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])?.write(to: outputCacheURL)
        } catch {
            let err = error as NSError
            postNotification(.rendererShouldTerminate, userInfo: makeUserInfo(.rendererShouldTerminate, NSLocalizedString("Failed to write image to cache directory, error code ", comment: "") + "\(err.code): \(err.userInfo)"))
            return
        }
        
        postNotification(.renderSuccessful, userInfo: makeUserInfo(.renderSuccessful, NSLocalizedString("Done.", comment: "")))

    }
    
    func resetRenderer(fully: Bool) {
        rendererPassCount = 0
        commandBuffers = []
        
        outImageBitmapData = nil
        
        config = nil
        
        inputImage = nil
        outputImage = nil

        srcImageTexture = nil
        dstImageTexture = nil
        lookupTableTexture = nil
        swapImageTexture = nil
        outImageTexture = nil
        
        if fully {
            textureDescriptor = nil
            srcImageBitmapData = nil
            
            lookupTableSpecs = []
            lookupTableTextureCache = [:]
        }
        
    }
    
}


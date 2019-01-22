//
//  ViewController.swift
//  pixelflipping
//
//  Created by Tony Wu on 1/5/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import AppKit

let kBottomBarHeightExpanded = CGFloat(108.0)
let kBottomBarHeightShrunken = CGFloat(32.0)
let kGrayscaleFilter = CIFilter(name: "CIColorControls", parameters: ["inputSaturation": 0.0])!
typealias ImageContainer = NSBitmapImageRep.FileType

class MainViewController: NSViewController {

    @IBOutlet weak var controlPanel: NSBox!
    @IBOutlet weak var advancedModeButton: NSButton!
    @IBOutlet weak var scrambleButton: NSButton!
    @IBOutlet weak var imageCanvasBox: NSBox!
    
    @IBOutlet weak var passwordField: NSTextField!
    @IBOutlet weak var passwordFileControl: NSPathControl!
    @IBOutlet weak var passwordOrFileSwitch: NSButton!
    
    @IBOutlet weak var optionColorProcessing: NSPopUpButton!
    @IBOutlet weak var optionBlockSize: NSSlider!
    @IBOutlet weak var optionBlockSizeMinStepper: NSStepper!
    @IBOutlet weak var optionBlockSizeMaxStepper: NSStepper!
    @IBOutlet weak var optionClusterSize: NSSlider!
    @IBOutlet weak var optionValueBlockSizeInfo: NSTextField!
    @IBOutlet weak var optionValueBlockSizeMinInfo: NSTextField!
    @IBOutlet weak var optionValueBlockSizeMaxInfo: NSTextField!
    @IBOutlet weak var optionValueClusterSizeInfo: NSTextField!

    private var possibleClusterSizes: [Int] = [1]
    private var blockSize: Int = 1
    private var clusterSize: Int = 1
    private var advancedMode: Bool = false
    
    private var rendererPassQueue: [RendererTask] = []
    
    private var mtlDevice: MTLDevice!
    private var imageRenderer = ImageRenderer()
    private var rendererNotificationCenter = NotificationCenter()
    
    private var optionsEnabled: Bool {
        return srcImageCanvas?.inputImage != nil
    }
    private var scrambleButtonEnabled: Bool {
        return ((srcImageCanvas?.inputImage != nil)) && ((!passwordField.isHidden && passwordField.stringValue != "") || (!passwordFileControl.isHidden && passwordFileControl.url != nil && !passwordFileControl.url!.hasDirectoryPath))
    }
    private var scrambleButtonAsCancelbutton: Bool = false
    private func updateControlsAvailability() {
        scrambleButton.isEnabled = scrambleButtonEnabled
        optionColorProcessing.isEnabled = optionsEnabled
        optionBlockSize.isEnabled = optionsEnabled
        optionClusterSize.isEnabled = optionsEnabled
        optionBlockSizeMaxStepper.isEnabled = optionsEnabled
        optionBlockSizeMinStepper.isEnabled = optionsEnabled
    }
    
    private var decipherMode = false {
        didSet {
            scrambleButton.title = decipherMode ? NSLocalizedString("Unscramble", comment: "") : NSLocalizedString("Scramble", comment: "")
            if calculatorMode { srcImageCanvas.header.title = decipherMode ? NSLocalizedString("CIPHERED → ORIGINAL", comment: "") : NSLocalizedString("ORIGINAL → CIPHERED", comment: "") }
        }
    }
    @IBOutlet weak var directionSwitch: NSButton!
    @IBAction func switchMode(_ sender: NSButton) {
        rotateIndicator(toLeft: decipherMode)
        decipherMode = !decipherMode
        if !calculatorMode && self.srcImageCanvas != nil && self.dstImageCanvas != nil {
            userInitiatedWorkQueue.addOperation {
                let swapCanvas = self.dstImageCanvas
                self.dstImageCanvas = self.srcImageCanvas
                self.srcImageCanvas = swapCanvas
                OperationQueue.main.addOperation {
                    self.setTranslucent(self.srcImageCanvas, false)
                    self.setTranslucent(self.dstImageCanvas, true)
                    self.updateControlsAvailability()
                }
            }
        } else {
            leftImageCanvas.header.state = .on
            rightImageCanvas.header.state = .on
        }
    }

    @IBOutlet weak var leftImageCanvas: ImageCanvas!
    @IBOutlet weak var rightImageCanvas: ImageCanvas!
    private var srcImageCanvas: ImageCanvas!
    private var dstImageCanvas: ImageCanvas!
    private var targetCanvas: ImageCanvas { return calculatorMode ? srcImageCanvas : dstImageCanvas }
    
    @IBOutlet var leftCanvasTrailingConstraintToDivide: NSLayoutConstraint!
    @IBOutlet var leftCanvasTrailingConstraintToSuper: NSLayoutConstraint!
    @IBOutlet var rightCanvasLeadingConstraintToDivide: NSLayoutConstraint!
    @IBOutlet var rightCanvasLeadingConstraintToSuper: NSLayoutConstraint!
    private var calculatorMode: Bool = false
    @IBAction func calcMode(_ sender: NSButton) {
        calculatorMode = sender.state == .on
        if calculatorMode {
            directionSwitch.isHidden = true
            if srcImageCanvas == rightImageCanvas {
                leftImageCanvas.isHidden = true
                rightImageCanvas.header.title = decipherMode ? NSLocalizedString("CIPHERED → ORIGINAL", comment: "") : NSLocalizedString("ORIGINAL → CIPHERED", comment: "")
                rightImageCanvas.headerCover.isHidden = true
                rightCanvasLeadingConstraintToSuper.priority = NSLayoutConstraint.Priority(rawValue: 750)
                rightCanvasLeadingConstraintToDivide.priority = NSLayoutConstraint.Priority(rawValue: 500)
            } else {
                rightImageCanvas.isHidden = true
                leftImageCanvas.header.title = decipherMode ? NSLocalizedString("CIPHERED → ORIGINAL", comment: "") : NSLocalizedString("ORIGINAL → CIPHERED", comment: "")
                leftImageCanvas.headerCover.isHidden = true
                leftCanvasTrailingConstraintToSuper.priority = NSLayoutConstraint.Priority(rawValue: 750)
                leftCanvasTrailingConstraintToDivide.priority = NSLayoutConstraint.Priority(rawValue: 500)
                srcImageCanvas = leftImageCanvas
                dstImageCanvas = rightImageCanvas
            }
        } else {
            directionSwitch.isHidden = false
            leftImageCanvas.header.title = NSLocalizedString("ORIGINAL", comment: "")
            rightImageCanvas.header.title = NSLocalizedString("CIPHERED", comment: "")
            leftImageCanvas.isHidden = false
            rightImageCanvas.isHidden = false
            leftImageCanvas.headerCover.isHidden = false
            rightImageCanvas.headerCover.isHidden = false
            leftCanvasTrailingConstraintToSuper.priority = NSLayoutConstraint.Priority(rawValue: 500)
            leftCanvasTrailingConstraintToDivide.priority = NSLayoutConstraint.Priority(rawValue: 750)
            rightCanvasLeadingConstraintToSuper.priority = NSLayoutConstraint.Priority(rawValue: 500)
            rightCanvasLeadingConstraintToDivide.priority = NSLayoutConstraint.Priority(rawValue: 750)
        }
    }
    
    private var moreOptionsButtonStateBeforeFullscreen = NSButton.StateValue.on
    private var imageCanvasTempHeightConstraint = NSLayoutConstraint()
    private var bottomBarHeightConstraintShrunken = NSLayoutConstraint()
    @IBOutlet var bottomBarHeightConstraintExpanded: NSLayoutConstraint!
    
    private lazy var userInitiatedWorkQueue: OperationQueue = {
        let providerQueue = OperationQueue()
        providerQueue.qualityOfService = .userInitiated
        return providerQueue
    }()
    private lazy var rendererWorkQueue: OperationQueue = {
        let providerQueue = OperationQueue()
        providerQueue.qualityOfService = .utility
        providerQueue.maxConcurrentOperationCount = 1
        return providerQueue
    }()
    
    private lazy var destinationURL: URL = {
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Drops")
        try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        return destinationURL
    }()
    
    private func referenceToLayoutConstraints() {
        bottomBarHeightConstraintShrunken = controlPanel.heightAnchor.constraint(equalToConstant: kBottomBarHeightShrunken)
    }
    
    // MARK: NSViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        referenceToLayoutConstraints()
        notificationCenterAddObservers()
        optionBlockSizeMinStepper.autorepeat = true
        optionBlockSizeMaxStepper.autorepeat = true

        leftImageCanvas.delegate = self
        rightImageCanvas.delegate = self
        
        leftImageCanvas.registerDraggedItemTypes()
        rightImageCanvas.registerDraggedItemTypes()
        
        optionColorProcessing.removeAllItems()
        optionColorProcessing.addItems(withTitles: ["permute", "2-pass permute", "substitute", "both"])
        
        passwordFileControl.allowedTypes = ["public.content"]
        passwordFileControl.pathStyle = .popUp
        passwordFileControl.url = nil
        passwordFileControl.delegate = self
        
        passwordField.delegate = self
        
        if let device = MTLCreateSystemDefaultDevice() {
            mtlDevice = device
        } else {
            presentError(RuntimeError.deviceNotSupported)
        }
        
        imageRenderer.device = mtlDevice
        imageRenderer.notificationCenter = rendererNotificationCenter
        
    }
    override func viewWillAppear() {
        controlPanel.removeConstraint(bottomBarHeightConstraintExpanded)
        controlPanel.addConstraint(bottomBarHeightConstraintShrunken)
        directionSwitch.wantsLayer = true
        updateControlsAvailability()
    }
    override func viewDidAppear() {
    }
    
}

extension MainViewController: NSWindowDelegate {
    // MARK: NSWindowDelegate
    @IBAction func discloseMoreOptions(_ sender: NSButton) {
        switch sender.state {
        case .on: controlPanel.removeConstraint(bottomBarHeightConstraintShrunken); advancedMode = true
        case .off: controlPanel.removeConstraint(bottomBarHeightConstraintExpanded); advancedMode = false
        default: break
        }
        imageCanvasTempHeightConstraint = imageCanvasBox.heightAnchor.constraint(equalToConstant: imageCanvasBox.bounds.size.height)
        imageCanvasBox.addConstraint(imageCanvasTempHeightConstraint)
        
        NotificationCenter.default.post(name: NSNotification.Name("discloseMoreOptionsResizeWindow"), object: nil, userInfo: ["buttonState": sender.state])
        
        imageCanvasBox.removeConstraint(imageCanvasTempHeightConstraint)
        switch sender.state {
        case .on: controlPanel.addConstraint(bottomBarHeightConstraintExpanded)
        case .off: controlPanel.addConstraint(bottomBarHeightConstraintShrunken)
        default: break
        }
    }

    func showMoreOptionsIfFullscreen(_ n: Notification) {
        switch n.name.rawValue {
        case "NSWindowWillEnterFullScreenNotification":
            moreOptionsButtonStateBeforeFullscreen = advancedModeButton.state
            if advancedModeButton.state == .off {
                advancedModeButton.state = .on
                discloseMoreOptions(advancedModeButton)
            }
            advancedModeButton.isEnabled = false
        case "NSWindowWillExitFullScreenNotification":
            if moreOptionsButtonStateBeforeFullscreen == .off {
                advancedModeButton.state = .off
                discloseMoreOptions(advancedModeButton)
            }
            advancedModeButton.isEnabled = true
        default: break
        }
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        showMoreOptionsIfFullscreen(notification)
        self.view.setNeedsDisplay(self.view.frame)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        showMoreOptionsIfFullscreen(notification)
        self.view.setNeedsDisplay(self.view.frame)
    }

}

extension MainViewController {
    // MARK: Image Canvas
    private func prepareForUpdate(for imageCanvas: ImageCanvas) {
        imageCanvas.isLoading = true
    }
    private func populateImageCanvas(_ canvas: ImageCanvas, displayedImage: NSImage?, inputImage: CGImage?, imageInfo: String?, outputContainer: ImageContainer?, outputCacheURL: URL?, nilMeansReset: Bool) {
        
        canvas.displayedImage = nilMeansReset ? displayedImage : displayedImage ?? canvas.displayedImage
        canvas.inputImage = nilMeansReset ? inputImage : inputImage ?? canvas.inputImage
        
        canvas.imageInfo.textColor = NSColor.controlTextColor
        canvas.imageInfo.tokenStyle = .squared
        canvas.imageInfo.stringValue = nilMeansReset ? (imageInfo ?? "") : (imageInfo ?? canvas.imageInfo.stringValue)
        canvas.imageInfo.needsDisplay = true
        
        canvas.outputCacheURL = nilMeansReset ? outputCacheURL : outputCacheURL ?? canvas.outputCacheURL
        canvas.outputContainer = nilMeansReset ? outputContainer: outputContainer ?? canvas.outputContainer
        
        self.updateAvailableBlockSize()
        self.updateControlsAvailability()
        
    }
    private func placeImage(from url: URL, onto srcImageCanvas: ImageCanvas, _ dstImageCanvas: ImageCanvas) {
        imageRenderer.resetRenderer(fully: true)
        userInitiatedWorkQueue.addOperation {
            if let (imageSource, info, container) = self.prefetchImageInfo(from: url) {
                self.userInitiatedWorkQueue.addOperation {
                    if let cgImage = self.loadCGImage(from: imageSource) {
                        OperationQueue.main.addOperation {
                            self.populateImageCanvas(srcImageCanvas, displayedImage: NSImage(byReferencing: url), inputImage: cgImage, imageInfo: info, outputContainer: container, outputCacheURL: nil, nilMeansReset: true)
                            self.setTranslucent(srcImageCanvas, false)
                            self.setTranslucent(dstImageCanvas, true)
                        }
                    } else {
                        self.rendererNotifyTermination(self.makeUpdateInfoNotification(.rendererShouldTerminate, message: NSLocalizedString("Failed to setup image for processing. Image format may be unsupported.", comment: "")))
                    }
                }
            } else {
                OperationQueue.main.addOperation {
                    self.handleError(RuntimeError.resourceNotReadable)
                }
            }
        }
    }
    private func handleError(_ error: Error) {
        OperationQueue.main.addOperation {
            if let window = self.view.window {
                self.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            } else {
                self.presentError(error)
            }
        }
    }
    
    // MARK: Set up renderer resources
    private func prefetchImageInfo(from url: URL) -> (isrc: CGImageSource, info: String, container: ImageContainer)? {
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let isrcOptions = [kCGImageSourceShouldCache: kCFBooleanFalse, kCGImageSourceShouldAllowFloat: kCFBooleanTrue]
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, isrcOptions as CFDictionary) as? [CFString: Any] else { return nil }
        guard let imageFileProp = CGImageSourceCopyProperties(imageSource, isrcOptions as CFDictionary) as? [CFString: Any]else { return nil }
        
        guard let imageType = CGImageSourceGetType(imageSource) else { return nil }
        
        let imageWidth = imageProperties[kCGImagePropertyPixelWidth]!
        let imageHeight = imageProperties[kCGImagePropertyPixelHeight]!
        let imageSizeFormatted = "\(imageWidth)×\(imageHeight)"
        
        let imageDepth: Int = imageProperties[kCGImagePropertyDepth] as! Int
        var imageFloat: Bool = false
        if let float = imageProperties[kCGImagePropertyIsFloat] as? Bool, float {
            imageFloat = float
        }
        
        let imageTypeFormatted = String((imageType as String).split(separator: ".", omittingEmptySubsequences: true).last ?? "Type ?").uppercased()
        let imageFileSize: Int64 = imageFileProp[kCGImagePropertyFileSize] as! Int64
        let imageFileSizeFormatted: String = imageFileSize > 0 ? ByteCountFormatter.string(fromByteCount: imageFileSize, countStyle: .file) : "File Size ?"

        let imageInfo = "\(imageTypeFormatted)|\(imageSizeFormatted)|\(imageDepth)-bit\(" " + (imageFloat ? "float" : ""))|\(imageFileSizeFormatted)"
        
        let container = (imageType == kUTTypeTIFF || imageType == kUTTypeRawImage || imageFloat) ? ImageContainer.tiff : ImageContainer.png
        return (isrc: imageSource, info: imageInfo, container: container)
            
    }
    private func loadCGImage(from source: CGImageSource) -> CGImage? {
        let isrcOptions = [kCGImageSourceShouldAllowFloat: kCFBooleanTrue]
        return CGImageSourceCreateImageAtIndex(source, 0, isrcOptions as CFDictionary)
    }
    
    private func rotateIndicator(toLeft: Bool) {
        let layerFrame = directionSwitch.layer!.frame
        let layerNewCenter = CGPoint(x: layerFrame.midX, y: layerFrame.midY)
        directionSwitch.layer?.position = layerNewCenter
        directionSwitch.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let rotateAnimation = CABasicAnimation(keyPath: "transform.rotation")
        rotateAnimation.fromValue = toLeft ? CGFloat.pi : 0.0
        rotateAnimation.toValue = toLeft ? 0.0 : CGFloat.pi
        rotateAnimation.duration = CFTimeInterval(0.2)
        rotateAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rotateAnimation.isRemovedOnCompletion = false
        rotateAnimation.fillMode = CAMediaTimingFillMode.forwards
        directionSwitch.layer?.add(rotateAnimation, forKey: "transform.rotation")
    }
    func setTranslucent(_ canvas: ImageCanvas, _ yes: Bool) {
        if yes {
            canvas.contentFilters = [kGrayscaleFilter]
            canvas.alphaValue = 0.5
            canvas.viewIsDimmed = true
        } else {
            canvas.contentFilters = []
            canvas.alphaValue = 1.0
            canvas.viewIsDimmed = false
        }
    }
    
}

extension MainViewController: ImageCanvasDragAndDropDelegate, NSFilePromiseProviderDelegate {
    // MARK: Handle drag and drop
    func draggingEntered(for imageCanvas: ImageCanvas, _ imageCanvasID: Int, sender: NSDraggingInfo) -> NSDragOperation {
        return sender.draggingSourceOperationMask.intersection(.copy)
    }
    func ifDraggingEndedInAnotherCanvas(from imageCanvas: ImageCanvas, _ imageCanvasID: Int, endedAt point: NSPoint) {
        let rect = imageCanvasID == 0 ? rightImageCanvas.frame : leftImageCanvas.frame
        if NSPointInRect(point, self.view.window!.convertToScreen(rect)) {
            let source = imageCanvasID == 0 ? leftImageCanvas! : rightImageCanvas!
            let dest = imageCanvasID == 0 ? rightImageCanvas! : leftImageCanvas!
            let sourceID = decipherMode ? 1 : 0
            guard let image = source.displayedImage else { return }
            guard let cgImage = source.inputImage else { return }
            
            populateImageCanvas(dest, displayedImage: image, inputImage: cgImage, imageInfo: source.imageInfo.stringValue, outputContainer: source.outputContainer, outputCacheURL: source.outputCacheURL, nilMeansReset: true)
            
            if sourceID == imageCanvasID {
                switchMode(directionSwitch)
            } else {
                setTranslucent(source, true)
            }
        }
    }
    func performDragOperation(for imageCanvas: ImageCanvas, _ imageCanvasID: Int, sender: NSDraggingInfo) -> Bool {
        let supportedClasses = [
            NSFilePromiseReceiver.self,
            NSURL.self
        ]
        let searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [kUTTypeImage]
        ]
        
        if !calculatorMode {
            switch imageCanvasID {
            case 0:
                srcImageCanvas = leftImageCanvas
                dstImageCanvas = rightImageCanvas
                if decipherMode { rotateIndicator(toLeft: true); decipherMode = false }
            case 1:
                srcImageCanvas = rightImageCanvas
                dstImageCanvas = leftImageCanvas
                if !decipherMode { rotateIndicator(toLeft: false); decipherMode = true }
            default: break
            }
        }
        
        sender.enumerateDraggingItems(options: [], for: nil, classes: supportedClasses, searchOptions: searchOptions) { (draggedItem, _, _) in
            switch draggedItem.item {
            case let filePromiseReceiver as NSFilePromiseReceiver:
                self.prepareForUpdate(for: imageCanvas)
                filePromiseReceiver.receivePromisedFiles(atDestination: self.destinationURL, options: [:],
                                                         operationQueue: self.userInitiatedWorkQueue) { (fileURL, error) in
                                                            if let error = error {
                                                                self.handleError(error)
                                                            } else {
                                                                OperationQueue.main.addOperation {
                                                                    self.placeImage(from: fileURL, onto: self.srcImageCanvas, self.dstImageCanvas)
                                                                }
                                                            }
                }
            case let fileURL as URL:
                self.prepareForUpdate(for: imageCanvas)
                OperationQueue.main.addOperation {
                    self.placeImage(from: fileURL, onto: self.srcImageCanvas, self.dstImageCanvas)
                }
            default: break
            }
        }
        return true
    }
    func pasteboardWriter(for imageCanvas: ImageCanvas) -> NSPasteboardWriting {
        var provider: NSFilePromiseProvider!
        if imageCanvas.outputCacheURL != nil {
            provider = NSFilePromiseProvider(fileType: kUTTypeFileURL as String, delegate: self)
            provider.userInfo = imageCanvas.outputCacheURL
            return provider
        } else {
            switch imageCanvas.outputContainer! {
            case .tiff:
                provider = NSFilePromiseProvider(fileType: kUTTypeTIFF as String, delegate: self)
            case .png:
                provider = NSFilePromiseProvider(fileType: kUTTypePNG as String, delegate: self)
            default:
                provider = NSFilePromiseProvider(fileType: kUTTypePNG as String, delegate: self)
            }
            provider.userInfo = imageCanvas.displayedImage
            return provider
        }
    }

    // MARK: NSFilePromiseDelegate
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        switch fileType {
        case String(kUTTypeFileURL):
            return (filePromiseProvider.userInfo as! URL).lastPathComponent
        case String(kUTTypeTIFF):
            return "output.tiff"
        case String(kUTTypePNG):
            return "output.png"
        default:
            return "output.png"
        }
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            if filePromiseProvider.fileType == kUTTypeFileURL as String {
                let cacheUrl = filePromiseProvider.userInfo as! URL
                try FileManager.default.copyItem(at: cacheUrl, to: url)
                completionHandler(nil)
                return
            }
            let image = filePromiseProvider.userInfo as! NSImage
            var format: ImageContainer
            switch filePromiseProvider.fileType {
            case String(kUTTypeTIFF):
                format = .tiff
            case String(kUTTypePNG):
                format = .png
            default:
                format = .png
            }
            guard let tiffRep = image.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.lzw, factor: 0) else {
                throw RuntimeError.fileModified
            }
            guard let bitmapImageRef = NSBitmapImageRep(data: tiffRep) else { throw RuntimeError.fileModified }
            guard let data = bitmapImageRef.representation(using: format, properties: [:]) else { throw RuntimeError.fileModified }
            try data.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        return userInitiatedWorkQueue
    }
}

extension MainViewController: NSTextFieldDelegate, NSPathControlDelegate {
    // MARK: NSControlDelegates
    // MARK: Update controls based on input availability
    @IBAction func switchPasswordOrFile(_ sender: NSButton) {
        switch sender.state {
        case .on:
            passwordField.isHidden = true
            passwordFileControl.isHidden = false
        case .off:
            passwordField.isHidden = false
            passwordFileControl.isHidden = true
        default: break
        }
        updateControlsAvailability()
    }
    @IBAction func pathControlAccessed(_ sender: NSPathControl) {
        updateControlsAvailability()
    }
    func controlTextDidChange(_ obj: Notification) {
        updateControlsAvailability()
    }
    
    func pathControl(_ pathControl: NSPathControl, willPopUp menu: NSMenu) {
        menu.item(at: 0)?.title = NSLocalizedString("Choose a file...", comment: "")
    }
    func pathControl(_ pathControl: NSPathControl, willDisplay openPanel: NSOpenPanel) {
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = pathControl.url?.deletingLastPathComponent()
        openPanel.prompt = NSLocalizedString("Open", comment: "")
        openPanel.message = NSLocalizedString("Choose a file to use as the encryption/decryption key for the image", comment: "")
    }
    
    // MARK: Update view, info and options
    private func updateAvailableBlockSize() {
        guard let image = srcImageCanvas.inputImage else { return }
        
        let imageShortEdge = image.width < image.height ? image.width : image.height
        let maxBlockSize = imageShortEdge >= 1024 ? 1024 : imageShortEdge
        let oldValue = optionBlockSize.doubleValue
        let oldMin = optionBlockSizeMinStepper.doubleValue
        let oldMax = optionBlockSizeMaxStepper.doubleValue
        
        optionBlockSizeMinStepper.minValue = Double(16)
        optionBlockSizeMinStepper.maxValue = Double(maxBlockSize)
        optionBlockSizeMaxStepper.minValue = Double(16)
        optionBlockSizeMaxStepper.maxValue = Double(maxBlockSize)
        optionBlockSizeMinStepper.doubleValue = oldMin == -1 ? 64 : optionBlockSizeMinStepper.doubleValue
        optionBlockSizeMaxStepper.doubleValue = oldMax == -1 ? 1024 : optionBlockSizeMaxStepper.doubleValue
        
        updateBlockSizeSliderMin(optionBlockSizeMinStepper)
        updateBlockSizeSliderMax(optionBlockSizeMaxStepper)

        if #available(OSX 10.14, *) {
            optionBlockSize.trackFillColor = NSColor.controlAccentColor
        } else {
            // Fallback on earlier versions
        }
        optionBlockSize.doubleValue = oldValue == -1 ? 256 : optionBlockSize.doubleValue

        updateBlockSizeInfo(optionBlockSize)
    }
    private func updateBlockSizeInfo(_ sender: NSControl) {
        self.updateAvailableClusterSizes(blockSize: Int(sender.doubleValue))
        self.blockSize = sender.integerValue
        self.optionValueBlockSizeInfo.stringValue = "\(self.blockSize)×\(self.blockSize)"
    }
    @IBAction func updateBlockSizeSliderMin(_ sender: NSStepper) {
        optionBlockSize.minValue = sender.doubleValue
        optionValueBlockSizeMinInfo.stringValue = "\(Int(sender.doubleValue))"
        updateBlockSizeInfo(optionBlockSize)
    }
    @IBAction func updateBlockSizeSliderMax(_ sender: NSStepper) {
        optionBlockSize.maxValue = sender.doubleValue
        optionValueBlockSizeMaxInfo.stringValue = "\(Int(sender.doubleValue))"
        updateBlockSizeInfo(optionBlockSize)
    }
    @IBAction func changedBlockSize(_ sender: NSSlider) {
        OperationQueue.main.addOperation {
            self.updateBlockSizeInfo(sender)
        }
    }
    
    
    /// Cluster sizes are calculated by factorizing block size to prevent pixels that fall in to the "remainder" regions i.e. regions that are left over after tiling from falling out of the texture, which was an issue when this is not done.
    ///
    /// **Note:** since the lookup table uses one byte to store the distance a pixel needs to move on the x- or y-axis, when block size goes above 256 (thus the max possible distance > 256), the lowest possible cluster size will be made greater than 1 to make sure bytes in lookup table don't overflow.
    ///
    /// When the specified block size is both > 256 and *a prime number,* factorization will produce only the number itself since 1 has been ruled out. This causes the lookup table generator to fail because it can't cover the "remainder" region once the only possible cluster size runs out. Possible solutions are preventing the rendering from starting, or forcing block size to fall back to 256 when this happens.
    ///
    /// This is left as a bug because it is fun to watch the program fail.
    ///
    /// - Parameter blockSize: The block size.
    private func updateAvailableClusterSizes(blockSize: Int) {
        var newPossibleClusterSizes = factorize(blockSize, ge: (blockSize - 1) / 256 + 1, le: min(64, blockSize - 1))
        if newPossibleClusterSizes.count == 0 { newPossibleClusterSizes = [blockSize] }
        let oldValue = possibleClusterSizes[optionClusterSize.integerValue]
        let closestPossibleNewValue = newPossibleClusterSizes.reduce(2048) { closestValue, newValue in
            return abs(newValue - oldValue) < abs(closestValue - oldValue) ? newValue : closestValue
        }
        let closestIndex = newPossibleClusterSizes.firstIndex(of: closestPossibleNewValue)!
        possibleClusterSizes = newPossibleClusterSizes
        
        optionClusterSize.minValue = 0
        optionClusterSize.maxValue = Double(possibleClusterSizes.count - 1)
        optionClusterSize.allowsTickMarkValuesOnly = true
        optionClusterSize.numberOfTickMarks = possibleClusterSizes.count
        if #available(OSX 10.14, *) {
            optionClusterSize.trackFillColor = NSColor.controlAccentColor
        } else {
            // Fallback on earlier versions
        }
        optionClusterSize.integerValue = closestIndex
        
        updateClusterSizeValueInfo(optionClusterSize)
    }
    private func updateClusterSizeValueInfo(_ sender: NSSlider) {
        self.clusterSize = possibleClusterSizes[sender.integerValue]
        self.optionValueClusterSizeInfo.stringValue = "\(self.clusterSize)×\(self.clusterSize)"
    }
    @IBAction func changedClusterSizeValue(_ sender: NSSlider) {
        OperationQueue.main.addOperation {
            self.updateClusterSizeValueInfo(sender)
        }
    }

}

extension MainViewController {
    
    private func notificationCenterAddObservers() {
        rendererNotificationCenter.addObserver(forName: Notification.Name(RendererEvent.updateProgress.rawValue), object: imageRenderer, queue: OperationQueue.main, using: infoUpdateProgress(_:))
        rendererNotificationCenter.addObserver(forName: Notification.Name(RendererEvent.updateCompletion.rawValue), object: imageRenderer, queue: OperationQueue.main, using: infoUpdateProgress(_:))
        rendererNotificationCenter.addObserver(forName: Notification.Name(RendererEvent.renderSuccessful.rawValue), object: imageRenderer, queue: OperationQueue.main, using: rendererDone(_:))
        rendererNotificationCenter.addObserver(forName: Notification.Name(RendererEvent.rendererShouldTerminate.rawValue), object: imageRenderer, queue: OperationQueue.main, using: rendererNotifyTermination(_:))
    }
    private func makeUpdateInfoNotification(_ event: RendererEvent, message: String) -> Notification {
        return Notification(name: Notification.Name(RendererEvent.updateProgress.rawValue), object: imageRenderer, userInfo: [RendererEvent.updateProgress.rawValue: message])
    }
    
    private func infoUpdateProgress(_ n: Notification) {
        let message = n.userInfo![n.name.rawValue] as! String
        targetCanvas.imageInfo.tokenStyle = .none
        switch n.name.rawValue {
        case "updateProgress": targetCanvas.imageInfo.textColor = NSColor.controlTextColor
        case "updateCompletion": targetCanvas.imageInfo.textColor = NSColor.systemBlue
        case "renderSuccessful": targetCanvas.imageInfo.textColor = NSColor.systemGreen
        default: targetCanvas.imageInfo.textColor = NSColor.controlTextColor
        }
        targetCanvas.imageInfo.stringValue = message
    }
    private func rendererNotifyTermination(_ n: Notification) {
        rendererWorkQueue.cancelAllOperations()
        rendererPassQueue.removeAll()

        let message = n.userInfo![n.name.rawValue] as! String
        targetCanvas.imageInfo.tokenStyle = .none
        
        switch message {
        case NSLocalizedString("Cancelled.", comment: ""): targetCanvas.imageInfo.textColor = NSColor.systemYellow
        default: targetCanvas.imageInfo.textColor = NSColor.systemRed
        }
        
        targetCanvas.imageInfo.stringValue = message
        targetCanvas.isLoading = false
        targetCanvas.imageView.isHidden = false
        
        userInitiatedWorkQueue.addOperation {
            self.rendererWorkQueue.waitUntilAllOperationsAreFinished()
            self.rendererWorkQueue.addOperation(RendererPass(r: self.imageRenderer, o: .flush))
        }
        
        restrictUIDuringRender(false)
    
    }
    private func rendererException(_ n: Notification) {
        let error = n.userInfo![n.name.rawValue] as! Error
        handleError(error)
        userInitiatedWorkQueue.addOperation {
            self.rendererWorkQueue.waitUntilAllOperationsAreFinished()
            self.rendererWorkQueue.addOperation(RendererPass(r: self.imageRenderer, o: .reset))
        }
        OperationQueue.main.addOperation {
            self.srcImageCanvas.reset()
            self.dstImageCanvas.reset()
            self.setTranslucent(self.srcImageCanvas, false)
            self.setTranslucent(self.dstImageCanvas, false)
        }
    }
    private func rendererDone(_ n: Notification) {
        infoUpdateProgress(n)
        
        OperationQueue.main.addOperation {
            if let (_, info, container) = self.prefetchImageInfo(from: self.imageRenderer.outputCacheURL) {
                self.populateImageCanvas(self.targetCanvas,
                                         displayedImage: NSImage(cgImage: self.imageRenderer.outputImage, size: self.imageRenderer.textureConfig.rect.size),
                                         inputImage: self.imageRenderer.outputImage,
                                         imageInfo: info,
                                         outputContainer: container,
                                         outputCacheURL: self.imageRenderer.outputCacheURL,
                                         nilMeansReset: true)
                if !self.calculatorMode { self.srcImageCanvas.outputCacheURL = nil }
            }
            
            self.targetCanvas.isLoading = false
            self.targetCanvas.imageView.isHidden = false

            self.userInitiatedWorkQueue.addOperation {
                self.rendererWorkQueue.waitUntilAllOperationsAreFinished()
                self.rendererWorkQueue.addOperation(RendererPass(r: self.imageRenderer, o: .flush))
            }
            
            self.restrictUIDuringRender(false)
            MTLCaptureManager.shared().stopCapture()
        }

    }
    private func restrictUIDuringRender(_ freeze: Bool) {
        self.scrambleButtonAsCancelbutton = freeze
        self.scrambleButton.title = freeze ? NSLocalizedString("Cancel", comment: "") : self.decipherMode ? NSLocalizedString("Unscramble", comment: "") : NSLocalizedString("Scramble", comment: "")
        self.directionSwitch.isEnabled = !freeze
        if freeze {
            self.leftImageCanvas.unregisterDraggedTypes()
            self.rightImageCanvas.unregisterDraggedTypes()
        } else {
            self.leftImageCanvas.registerDraggedItemTypes()
            self.rightImageCanvas.registerDraggedItemTypes()
        }
    }

    private func makeImageRendererPassQueue() {
        let compute: RendererTask = decipherMode ? .compute(.unpermutation) : .compute(.permutation)
        switch (optionColorProcessing.selectedItem?.title, advancedMode) {
        case (_, false):
            rendererPassQueue = [.setup, .texture, compute, .blit, .commit]
        case ("permute", _):
            rendererPassQueue = [.setup, .texture, compute, .blit, .commit]
        case ("2-pass permute", _):
            rendererPassQueue = [.setup, .texture, compute, compute, .blit, .commit]
        case ("substitute", _):
            rendererPassQueue = [.setup, .texture, .compute(.substitution), .blit, .commit]
        case ("both", _):
            rendererPassQueue = [.setup, .texture, compute, .compute(.substitution), compute, .blit, .commit]
        default:
            rendererPassQueue = [.setup, .texture, compute, .blit, .commit]
        }
    }
    private func commitRenderWorkQueue() {
        rendererWorkQueue.addOperations(rendererPassQueue.map { pass in
            RendererPass(r: self.imageRenderer, o: pass)
        }, waitUntilFinished: false)
    }
    @IBAction func run(_ sender: NSButton) {
        
        if scrambleButtonAsCancelbutton {
            rendererNotifyTermination(makeUpdateInfoNotification(.rendererShouldTerminate, message: NSLocalizedString("Cancelled.", comment: "")))

            restrictUIDuringRender(false)
            return
        }
        
        restrictUIDuringRender(true)
        
        infoUpdateProgress(makeUpdateInfoNotification(.updateProgress, message: NSLocalizedString("Reading config...", comment: "")))

        makeImageRendererPassQueue()
        
        let usePassword: Bool = passwordOrFileSwitch.state == .off
        let passwordString = passwordField.stringValue
        let filePath = passwordFileControl.url?.path
        
        targetCanvas.imageView.isHidden = true
        setTranslucent(targetCanvas, false)
        targetCanvas.isLoading = true
        
        guard let inputImage = srcImageCanvas.inputImage else { return }
        guard let outputContainer = srcImageCanvas.outputContainer else { return }

        imageRenderer.inputImage = inputImage
        imageRenderer.outputContainer = outputContainer

        infoUpdateProgress(makeUpdateInfoNotification(.updateProgress, message: NSLocalizedString("Generating key...", comment: "")))

        userInitiatedWorkQueue.addOperation {
            let config: RendererConfig
            let key: CipherSecret
            
            if usePassword {
                let password = passwordString
                key = CipherSecret(fromString: password, length: 256)
            } else {
                guard let path = filePath else { return }
                guard let k = CipherSecret(fromFilePath: path, length: /*self.blockSize*/256) else { return }
                key = k
            }
            
            if self.advancedMode {
                config = RendererConfig(k: key, d: self.clusterSize, r: self.blockSize)
            } else {
                config = RendererConfig(k: key, d: 1, r: Int(sqrt(Double(key.sequenceLength))))
            }
            
            self.imageRenderer.config = config
            
//            MTLCaptureManager.shared().startCapture(device: self.mtlDevice)
            
            self.commitRenderWorkQueue()
        }

    }
    
}

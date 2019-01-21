//
//  ImageRenderer.swift
//  pixelscrambling
//
//  Created by Tony Wu on 1/15/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//  Copyright © 2018 Apple Inc. See LISCENSE.txt

import AppKit

@objc protocol ImageCanvasDragAndDropDelegate {
    func draggingEntered(for imageCanvas: ImageCanvas, _ imageCanvasID: Int, sender: NSDraggingInfo) -> NSDragOperation
    func performDragOperation(for imageCanvas: ImageCanvas, _ imageCanvasID: Int, sender: NSDraggingInfo) -> Bool
    func pasteboardWriter(for imageCanvas: ImageCanvas) -> NSPasteboardWriting
    func ifDraggingEndedInAnotherCanvas(from imageCanvas: ImageCanvas, _ imageCanvasID: Int, endedAt point: NSPoint)
}

class ImageCanvas: NSView, NSDraggingSource {
    
    @IBOutlet weak var delegate: ImageCanvasDragAndDropDelegate!
    @IBOutlet weak var imageView: NSImageView!
    @IBOutlet weak var imageInfo: NSTokenField!
    @IBOutlet weak var backgroundTip: NSTextField!
    @IBOutlet weak var canvasBorder: NSBox!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var header: NSButton!
    @IBOutlet weak var headerCover: NSTextField!
    var viewIsDimmed: Bool = false
    
    // MARK: Identifier
    @IBInspectable var imageCanvasID: Int = 0
    
    func registerDraggedItemTypes() {
        self.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
        self.registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    
    let dragThreshold: CGFloat = 3.0
    
    // MARK: UI related
    var displayedImage: NSImage? {
        set {
            imageView.image = newValue
            isLoading = false
            backgroundTip.isHidden = (imageView.image != nil)
            needsLayout = true
        }
        get {
            return imageView.image
        }
    }
    var inputImage: CGImage!
    
    var outputContainer: ImageContainer!
    var outputCacheURL: URL!
    var isLoading: Bool = false {
        didSet {
            imageView.isEnabled = !isLoading
            backgroundTip.isHidden = isLoading || (imageView.image != nil)
            progressIndicator.isHidden = !isLoading
            if isLoading {
                progressIndicator.startAnimation(nil)
            } else {
                progressIndicator.stopAnimation(nil)
            }
        }
    }
    
    // MARK: NSView
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    override func awakeFromNib() {
        imageView.unregisterDraggedTypes()
        imageInfo.tokenStyle = .squared
        imageInfo.tokenizingCharacterSet = CharacterSet(charactersIn: "|")
    }
    
    // completely stolen from Apple's MemeGenerator sample
    private func rectForDrawingImage(with imageSize: CGSize, scaling: NSImageScaling) -> CGRect {
        var drawingRect = CGRect(origin: .zero, size: imageSize)
        let containerRect = bounds
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return drawingRect
        }
        
        func scaledSizeToFitFrame() -> CGSize {
            var scaledSize = CGSize.zero
            let horizontalScale = containerRect.width / imageSize.width
            let verticalScale = containerRect.height / imageSize.height
            let minimumScale = min(horizontalScale, verticalScale)
            scaledSize.width = imageSize.width * minimumScale
            scaledSize.height = imageSize.height * minimumScale
            return scaledSize
        }
        
        switch scaling {
        case .scaleProportionallyDown:
            if imageSize.width > containerRect.width || imageSize.height > containerRect.height {
                drawingRect.size = scaledSizeToFitFrame()
            }
        case .scaleAxesIndependently:
            drawingRect.size = containerRect.size
        case .scaleProportionallyUpOrDown:
            if imageSize.width > 0.0 && imageSize.height > 0.0 {
                drawingRect.size = scaledSizeToFitFrame()
            }
        case .scaleNone:
            break
        }
        
        drawingRect.origin.x = containerRect.minX + (containerRect.width - drawingRect.width) * 0.5
        drawingRect.origin.y = containerRect.minY + (containerRect.height - drawingRect.height) * 0.5
        
        return drawingRect
    }
    
    // UnsafeMutablePointer<ObjCBool>
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil) // location recorded as soon as mouseDown
        let eventMask: NSEvent.EventTypeMask = [.leftMouseUp, .leftMouseDragged]
        let timeout = NSEvent.foreverDuration
        window?.trackEvents(matching: eventMask, timeout: timeout, mode: .eventTracking) { (event, stop) in
            guard let event = event else { return }
            if event.type == .leftMouseUp {
                stop.pointee = true // stop tracking the event
            } else {
                let movedLocation = convert(event.locationInWindow, from: nil)
                if abs(movedLocation.x - location.x) > dragThreshold || abs(movedLocation.y - location.y) > dragThreshold {
                    stop.pointee = true
                    if let delegate = delegate, let image = displayedImage {
                        let draggingItem = NSDraggingItem(pasteboardWriter: delegate.pasteboardWriter(for: self))
                        draggingItem.setDraggingFrame(rectForDrawingImage(with: image.size, scaling: imageView.imageScaling), contents: image)
                        beginDraggingSession(with: [draggingItem], event: event, source: self)
                    }
                }
            }
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        backgroundTip.textColor = NSColor.selectedControlColor
        canvasBorder.borderColor = NSColor.selectedControlColor
        var result: NSDragOperation = []
        if let delegate = delegate {
            result = delegate.draggingEntered(for: self, imageCanvasID, sender: sender)
        }
        return result
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return delegate?.performDragOperation(for: self, imageCanvasID, sender: sender) ?? true
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        backgroundTip.textColor = NSColor.quaternaryLabelColor
        canvasBorder.borderColor = NSColor.secondaryLabelColor
    }
    
    override func draggingEnded(_ sender: NSDraggingInfo) {
        backgroundTip.textColor = NSColor.quaternaryLabelColor
        canvasBorder.borderColor = NSColor.secondaryLabelColor
    }
    
    // MARK: NSDraggingSource
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        self.unregisterDraggedTypes()
        if context == .outsideApplication { return [.copy] }
        return []
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        registerDraggedItemTypes()
        delegate.ifDraggingEndedInAnotherCanvas(from: self, imageCanvasID, endedAt: screenPoint)
    }
    
    func reset() {
        imageView.image = nil
        imageInfo.stringValue = ""
        outputCacheURL = nil
        isLoading = false
    }
    
}

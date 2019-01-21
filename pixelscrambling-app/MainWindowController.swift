//
//  MainWindowController.swift
//  pixelscrambling
//
//  Created by Tony Wu on 1/14/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import AppKit

class MainWindowController: NSWindowController {

    @IBOutlet weak var mainWindow: NSWindow!
    func updateWindowSizeForDetailedOptions(_ n: Notification) -> () {
        var offset = CGFloat()
        switch n.userInfo!["buttonState"] as! NSButton.StateValue {
        case .on: offset = CGFloat(kBottomBarHeightExpanded - kBottomBarHeightShrunken)
        case .off: offset = CGFloat(kBottomBarHeightShrunken - kBottomBarHeightExpanded)
        default: break
        }
        let (x, y, w, h) = (mainWindow.frame.origin.x, mainWindow.frame.origin.y - offset, mainWindow.frame.size.width, mainWindow.frame.size.height + offset)
        mainWindow.setFrame(CGRect(x: x, y: y, width: w, height: h), display: true, animate: true)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        mainWindow.delegate = (self.contentViewController as! NSWindowDelegate)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("discloseMoreOptionsResizeWindow"), object: nil, queue: nil, using: updateWindowSizeForDetailedOptions(_:))
        mainWindow.center()
        mainWindow.makeKeyAndOrderFront(nil)
    }

}


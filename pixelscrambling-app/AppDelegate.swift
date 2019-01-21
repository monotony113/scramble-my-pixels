//
//  AppDelegate.swift
//  pixelflipping
//
//  Created by Tony Wu on 1/5/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import AppKit

var cacheDirectoryURL: URL!

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var application: NSApplication!
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        self.application.delegate = self
        do {
            let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: FileManager.default.homeDirectoryForCurrentUser, create: true)
            cacheDirectoryURL = cache.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            application.presentError(error, modalFor: application.mainWindow!, delegate: self, didPresent: nil, contextInfo: nil)
            cacheDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
}


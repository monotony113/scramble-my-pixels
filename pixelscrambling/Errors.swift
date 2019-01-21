//
//  Definitions.swift
//  pixelflipping
//
//  Created by Tony Wu on 1/6/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import Foundation

class RuntimeError {
    static var deviceNotSupported = NSError(domain: Bundle.main.bundleIdentifier!, code: 0, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("no GPU", comment: "")])
    static var resourceNotReadable = NSError(domain: Bundle.main.bundleIdentifier!, code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("no image", comment: "")])
    
    static var lengthMismatch = NSError(domain: Bundle.main.bundleIdentifier!, code: 6, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("length mismatch", comment: "")])
    static var divisionByZero = NSError(domain: Bundle.main.bundleIdentifier!, code: 7, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("division by zero", comment: "")])
    
    static var fileModified = NSError(domain: Bundle.main.bundleIdentifier!, code: 11, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("file moved", comment: "")])
}

//
//  File.swift
//  
//
//  Created by Kevin Mullins on 11/8/23.
//

import Foundation

/// Holds information about a product and when it was purchased on.
open class VersionHistory {
    
    // MARK: - Properties
    /// The version of the app in question.
    public var version:String = ""
    
    /// If `true`, the app was purchased before this version.
    public var wasPurchasedBefore:Bool = false
    
    // MARK: - Initializers
    /// Creates a new instance
    /// - Parameters:
    ///   - version: The version number in question.
    ///   - wasPurchasedBefore: Version history flag.
    public init(version: String, wasPurchasedBefore: Bool = false) {
        self.version = version
        self.wasPurchasedBefore = wasPurchasedBefore
    }
}

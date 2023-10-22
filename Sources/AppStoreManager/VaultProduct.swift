//
//  File.swift
//  
//
//  Created by Kevin Mullins on 10/22/23.
//

import Foundation
import StoreKit
import SwiftletUtilities
import SimpleSerializer

/// Holds a simplified version of a purchased product.
class VaultProduct {
    
    // MARK: - Properties
    /// The unique product identifier.
    var id: String = ""

    /// The type of the product.
    var type: Product.ProductType = .nonConsumable

    /// A localized display name of the product.
    var displayName: String = ""

    /// A localized description of the product.
    var description: String = ""
    
    /// Conversts theobject to a serialized string.
    var serialized:String {
        let serializer = Serializer(divider: "§")
            .append(id)
            .append(type)
            .append(displayName)
            .append(description)
        
        return serializer.value
    }
    
    // MARK: - Initializers
    /// Creates a new empty instance.
    init() {
        
    }
    
    /// Creates a new instance from a serialized string.
    /// - Parameter value: The value holding the object.
    init(from value:String) {
        let deserializer = Deserializer(text: value, divider: "§")
        
        self.id = deserializer.string()
        self.type = Product.ProductType(rawValue: deserializer.string())
        self.displayName = deserializer.string()
        self.description = deserializer.string()
    }
    
    /// Creates a new instance.
    /// - Parameters:
    ///   - id: The id of the product.
    ///   - type: The type of product.
    ///   - displayName: The product's display name.
    ///   - description: The product's description.
    init(id: String, type: Product.ProductType, displayName: String, description: String) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.description = description
    }
    
    /// Creates a new instances off of the given `Product`.
    /// - Parameter product: <#product description#>
    init(clone product:Product) {
        self.id = product.id
        self.type = product.type
        self.displayName = product.displayName
        self.description = product.description
    }
}

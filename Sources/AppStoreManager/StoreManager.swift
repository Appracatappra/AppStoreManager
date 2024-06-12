//
//  StoreManager.swift
//  ReedWriteCycle (iOS)
//
//  Created by Kevin Mullins on 11/30/22.
//

import Foundation
import StoreKit
import Observation
import LogManager
import SwiftletUtilities
import SimpleSerializer

/// Defines an alias for the standard `StoreKit.Transaction`.
public typealias Transaction = StoreKit.Transaction

/// Handles the user making In-App purchase from within the App.
/// The class has built in support for Family Sharable purchases and for Promoted In-App purchases.
/// - Remark: The `StoreManager` requires a `Products.plist` file be included with the build of your App. This file must be a `Dictionary` of `Dictionary` that is in the format `[String:String]`. The `Key` for the outter most `Dictionary` must be the ID of an In-App Purchase Product that you have defined in App Store Connect for your App.
@Observable open class StoreManager {
    /// Type for handling purchase update events.
    public typealias purchaseUpdateHandler = () -> Void
    
    /// Type for handling a product being revoked from the App Store.
    /// - Parameter Transaction: The transaction that is being rekoved by the app store.
    public typealias revokedProductHandler = (Transaction) -> Void
    
    /// Handles a product event being received from the App Store.
    /// - Parameters:
    /// - Product: The product that received the event.
    /// - Bool: `True` if the product event was successful, else `false` if the event failed.
    public typealias productEventHandler = (Product, Bool) -> Void
    
    /// The `Dictionary` of `String` and `String` values that define the attributes of a Product from the `Product.plist` file.
    public typealias productDetails = [String:String]
    
    // MARK: - Static Properties
    /// A shared instance of the StoreManager.
    public nonisolated(unsafe) static let shared:StoreManager = StoreManager()
    
    // MARK: - Properties
    /// A list of available products.
    private(set) var products: [Product] = []
    
    /// A saved set of simplified products.
    @ObservationIgnored private var vault:[VaultProduct] = []
    
    /// A list of purchased products.
    private(set) var purchasedProducts: [Product] = []
    
    /// A collection on optional version history events and their states.
    private var purchaseHistory:[VersionHistory] = []
    
    /// A task that handles background App Store transactions.
    public var updateListenerTask: Task<Void, Error>? = nil
    
    /// A background task that handles the user selecting a Promoted In-App Purchase from the App Store.
    public var promotedPurchaseListenerTask: Task<Void, Error>? = nil
    
    /// A dictionary of In-App purchases available.
    private let productInfo: [String: productDetails]
    
    /// A callback that handles purchases being updated by the App Store.
    public var purchasesUpdated: purchaseUpdateHandler? = nil
    
    /// A callback that handles a transaction for a given product being revoked by the App Store.
    public var productRevoked: revokedProductHandler? = nil
    
    /// A Callback that handles the user selecting a Promoted In-App Purchase from the App Store.
    public var promotedInAppPurchaseEvent: productEventHandler? = nil
    
    // MARK: - Computed Properties
    /// Returns the key to the vault of simplified products.
    private var vaultKey:String {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            return "\(bundleIdentifier).\(HardwareInformation.modelName)"
        } else {
            return "AppStoreManager.\(HardwareInformation.modelName)"
        }
    }
    
    /// Returns the key to the vault of version purchase history.
    private var historyKey:String {
        return vaultKey + ".00"
    }
    
    /// Returns `true` if the purchase history was previously checked.
    public var wasHistoryChecked:Bool {
        return (purchaseHistory.count > 0)
    }
    
    // MARK: - Initializers
    /// Creates a new instance of the object and Starts it running.
    public init() {
        // Read in the product information.
        if let path = Bundle.main.path(forResource: "Products", ofType: "plist"),
           let plist = FileManager.default.contents(atPath: path) {
            productInfo = (try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: productDetails]) ?? [:]
        } else {
            productInfo = [:]
        }
        
        // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()
        
        #if !os(tvOS)
        // Start a promoted purchase transaction listener as close to app launch as possible so you don't miss any transactions.
        promotedPurchaseListenerTask = listenForPromotedPurchases()
        #endif
        
        Task {
            // During store initialization, request products from the App Store.
            await requestProducts()
            
            // Deliver products that the customer purchases.
            await updateCustomerProductStatus()
        }
        
        // Load any app purchase history if available.
        decantHistory()
    }
    
    // MARK: - Deinitializer
    /// De-initializes the object and releases any background tasks it started.
    deinit {
        updateListenerTask?.cancel()
        promotedPurchaseListenerTask?.cancel()
    }
    
    // MARK: - Functions
    /// Releases all handlers that have been attached to the `StoreManager`.
    public func releaseEventHandlers() {
        purchasesUpdated = nil
        productRevoked = nil
        promotedInAppPurchaseEvent = nil
    }
    
    /// Check to see if a version of the app was purchased before a given range of product version and records the history.
    /// - Parameter versions: A list of version history events.
    public func loadPurchaseHistory(for versions:[VersionHistory]) {
        Task {
            await verifyPreviousPurchase(for:versions)
        }
    }
    
    /// Check to see if a version of the app was purchased before a given range of product version and records the history.
    /// - Parameter versions: A list of version history events.
    /// - Remark: From https://developer.apple.com/documentation/storekit/apptransaction?changes=latest_minor
    public func verifyPreviousPurchase(for versions:[VersionHistory]) async  {
        
        // Default all previous versions to unpurchased
        for version in versions {
            version.wasPurchasedBefore = false
        }
        
        do {
            // Get the app transaction history.
            let result:VerificationResult<AppTransaction> = try await AppTransaction.shared
            
            // Take action based on the history.
            switch result {
            case .unverified(let appTransaction, let verificationError):
                Log.error(subsystem: "StoreManager", category: "verifyPreviousPurchase", "\(appTransaction.appVersion) \(verificationError.localizedDescription)")
            case .verified(let appTransaction):
                let originalAppVersion = appTransaction.originalAppVersion
                
                // Convert the origin date.
                if let origin = Float(originalAppVersion) {
                    // Scan all historical versions
                    for history in versions {
                        // Covert the required version.
                        if let version = Float(history.version) {
                            // See if the original transaction version is acceptable.
                            if origin > 0 && origin < version {
                                history.wasPurchasedBefore = true
                            }
                        }
                    }
                }
                
            }
        } catch {
            Log.error(subsystem: "StoreManager", category: "verifyPreviousPurchase", error.localizedDescription)
        }
        
        // Record the history in the Store Manager
        purchaseHistory = versions
        enshrineHistory()
    }
    
    /// This function listens for background transactions from the App Store.
    /// - Returns: A background task to handles transactions from the App Store.
    public func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // Are we removing access?
                    if let revocationDate = transaction.revocationDate {
                        // Force a UI update
                        Log.info(subsystem: "StoreManager", category: "listenForTransactions", "Purchase \(transaction.productID) revoked on \(revocationDate.description)")
                        if let handler = self.productRevoked {
                            handler(transaction)
                        }
                    }
                    
                    // Deliver products to the user.
                    await self.updateCustomerProductStatus()
                    
                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    Log.error(subsystem: "StoreManager", category: "listenForTransactions", "Transaction failed verification")
                }
            }
        }
    }
    
    #if !os(tvOS)
    /// This function listens for the user attempting to purchase a Promoted In-App Purchase from the App Store.
    /// - Returns: A background task to handle the user making the purchase of a Promoted In-App Purchase.
    public func listenForPromotedPurchases() -> Task<Void, Error> {
        return Task.detached {
            for await purchaseIntent in PurchaseIntent.intents {
                // Complete the purchase workflow.
                do {
                    // Has the user already purchased this product?
                    if self.isPurchased(id: purchaseIntent.product.id) {
                        Debug.info(subsystem: "StoreManager", category: "listenForPromotedPurchases", "Attempted purchase of already purchased product: \(purchaseIntent.product.id)")
                        
                        // Inform caller that the purchase attempt succeeded
                        if let handler = self.promotedInAppPurchaseEvent {
                            handler(purchaseIntent.product, true)
                        }
                    } else {
                        Debug.info(subsystem: "StoreManager", category: "listenForPromotedPurchases", "Attempting purchase of: \(purchaseIntent.product.id)")
                        
                        // Attempt to purchase product.
                        let transaction = try await self.purchase(purchaseIntent.product) //purchaseIntent.product.purchase()
                        
                        // Inform caller about the state of the purchase attempt.
                        if let handler = self.promotedInAppPurchaseEvent {
                            handler(purchaseIntent.product, (transaction != nil))
                        }
                    }
                }
                catch {
                    Log.error(subsystem: "StoreManager", category: "listenForTransactions", "Transaction failed verification")
                }
            }
        }
    }
    #endif
    
    @MainActor
    /// Requests available products from the App Store.
    public func requestProducts() async {
        do {
            // Request products from the App Store using the identifiers that the Products.plist file defines.
            let storeProducts = try await Product.products(for: productInfo.keys)
            
            var availableProducts: [Product] = []
            
            // Filter the products into categories based on their type.
            for product in storeProducts {
                switch product.type {
                case .autoRenewable, .nonConsumable, .consumable, .nonRenewable:
                    availableProducts.append(product)
                default:
                    //Ignore this product.
                    Log.notice(subsystem: "StoreManager", category: "requestProducts", "Unknown product")
                }
            }
            
            // Sort each product category by price, lowest to highest, to update the store.
            products = sortByPrice(availableProducts)
        } catch {
            Log.error(subsystem: "StoreManager", category: "requestProducts", "Failed product request from the App Store server: \(error)")
        }
    }
    
    @MainActor
    /// Attempts to purchase the given Product from the App Store.
    /// - Parameter product: The Product to purchase.
    /// - Returns: Returns a `Transaction` is the purchase was successful, else returns `nil`.
    public func purchase(_ product: Product) async throws -> Transaction? {
        // Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            // Check whether the transaction is verified. If it isn't,
            // this function rethrows the verification error.
            let transaction = try checkVerified(verification)
            
            // The transaction is verified. Deliver content to the user.
            await updateCustomerProductStatus()
            
            // Always finish a transaction.
            await transaction.finish()
            
            return transaction
        case .userCancelled, .pending:
            return nil
        default:
            return nil
        }
    }
    
    /// Updates the local cache of purchased Products and informs the UI of the update.
    public func updateCustomerProductStatus() async {
        var purchases: [Product] = []
        
        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                // Check whether the transaction is verified. If it isn’t, catch `failedVerification` error.
                let transaction = try checkVerified(result)
                
                // Check the `productType` of the transaction and get the corresponding product from the store.
                switch transaction.productType {
                case .autoRenewable, .nonConsumable, .consumable, .nonRenewable:
                    if let product = products.first(where: { $0.id == transaction.productID }) {
                        purchases.append(product)
                    }
                default:
                    break
                }
            } catch {
                Log.error(subsystem: "StoreManager", category: "updateCustomerProductStatus", "Error updating customer product status: \(error)")
            }
        }
        
        // Update the store information with the purchased products.
        self.purchasedProducts = purchases
        
        // Save simplified purchases to vault.
        vault = []
        for product in purchasedProducts {
            vault.append(VaultProduct(clone: product))
        }
        
        // Are we conected to the network?
        if NetworkConnection.shared.isConnectedToNetwork {
            // Yes, enshrine the vault
            enshrineVault()
        }
        
        // Inform app that the purchases have changed
        if let handler = purchasesUpdated {
            handler()
        }
    }
    
    /// Converts the vault into a serialized string.
    /// - Returns: The serialized version of the vault.
    private func serializeVault() -> String {
        let serializer = Serializer(divider: "¶")
            .append(HardwareInformation.modelName)
        
        // Serialize the vault
        for product in vault {
            serializer.append(product.serialized)
        }
        
        return serializer.value
    }
    
    /// Converst the version history into a serialized string.
    /// - Returns: The serialized version of the history.
    private func serializeHistory() -> String {
        let serializer = Serializer(divider: "¶")
            .append(HardwareInformation.modelName)
        
        // Serialize the history
        for history in purchaseHistory {
            serializer.append(history.serialized)
        }
        
        return serializer.value
    }
    
    /// Restores the vault from the serialized string.
    /// - Parameter text: The serialized version of the vault.
    private func deserializeVault(from text:String) {
        var item:String = ""
        
        let deserializer = Deserializer(text: text, divider: "¶")
        let modelName = deserializer.string()
        
        // Empty the vault
        vault = []
        
        // Is this a good vaulted value?
        guard modelName == HardwareInformation.modelName else {
            return
        }
        
        // Restore vault
        item = deserializer.string()
        while item != "" {
            vault.append(VaultProduct(from: item))
            item = deserializer.string()
        }
    }
    
    /// Restores the history from the serialized string.
    /// - Parameter text: The serialized version of the history.
    private func deserializeHistory(from text:String) {
        var item:String = ""
        
        let deserializer = Deserializer(text: text, divider: "¶")
        let modelName = deserializer.string()
        
        // Empty the vault
        purchaseHistory = []
        
        // Is this a good vaulted value?
        guard modelName == HardwareInformation.modelName else {
            return
        }
        
        // Restore history
        item = deserializer.string()
        while item != "" {
            purchaseHistory.append(VersionHistory(from: item))
            item = deserializer.string()
        }
    }
    
    /// Mummifies the vault and stores it in a user preference.
    private func enshrineVault() {
        let serialized = serializeVault()
        let checksum = ObfuscationProvider.checksum(serialized)
        
        let serializer = Serializer(divider: "≠")
            .append(serialized)
            .append(checksum)
        
        let deifiedVault = ObfuscationProvider.obfuscate(serializer.value)
        UserDefaults.standard.setValue(deifiedVault, forKey: vaultKey)
    }
    
    /// Mummifies the history and stores it in a user preference.
    private func enshrineHistory() {
        let serialized = serializeHistory()
        let checksum = ObfuscationProvider.checksum(serialized)
        
        let serializer = Serializer(divider: "≠")
            .append(serialized)
            .append(checksum)
        
        let deifiedVault = ObfuscationProvider.obfuscate(serializer.value)
        UserDefaults.standard.setValue(deifiedVault, forKey: historyKey)
    }
    
    /// Pulls the vault from the crypt, unwraps and restores it.
    private func decantVault() {
        let deifiedVault = UserDefaults.standard.string(forKey: vaultKey) ?? ""
        
        // Did we get a returned vault?
        guard deifiedVault != "" else {
            // Empty vault and return
            vault = []
            return
        }
        
        let downcastVault = ObfuscationProvider.deobfuscate(deifiedVault)
        let deserializer = Deserializer(text: downcastVault, divider: "≠")
        let serialized = deserializer.string()
        let checksum = deserializer.int()
        
        // Ensure the vault has not been tampered with or damaged
        guard ObfuscationProvider.verify(text: serialized, checksum: checksum) else {
            return
        }
        
        // Restore the vault
        deserializeVault(from: serialized)
    }
    
    /// Pulls the history from the crypt, unwraps and restores it.
    private func decantHistory() {
        let deifiedVault = UserDefaults.standard.string(forKey: historyKey) ?? ""
        
        // Did we get a returned vault?
        guard deifiedVault != "" else {
            // Empty vault and return
            purchaseHistory = []
            return
        }
        
        let downcastVault = ObfuscationProvider.deobfuscate(deifiedVault)
        let deserializer = Deserializer(text: downcastVault, divider: "≠")
        let serialized = deserializer.string()
        let checksum = deserializer.int()
        
        // Ensure the vault has not been tampered with or damaged
        guard ObfuscationProvider.verify(text: serialized, checksum: checksum) else {
            return
        }
        
        // Restore the history
        deserializeHistory(from: serialized)
    }
    
    /// Checks to see if the given product is in the vault.
    /// - Parameter id: The product id to check.
    /// - Returns: Returns `true` if the product is in the vault, else returns `false`.
    private func isInVault(id:String) -> Bool {
        
        // Scan all items in the vault.
        for product in vault {
            if product.id == id {
                return true
            }
        }
        
        // Not found
        return false
    }
    
    /// Checks to see if a version of the app was purchased before the given version.
    /// - Parameter version: The version in question.
    /// - Returns: Returns `true` if a version of the app was purchased before the given version, else returns `false` if not found or not purchased before.
    public func wasPurchasedBefore(version:String) -> Bool {
        
        // Scan all product history
        for history in purchaseHistory {
            if history.version == version {
                return history.wasPurchasedBefore
            }
        }
        
        // Not found
        return false
    }
    
    /// Tests to see if the given product has been purchased from the App Store.
    /// - Parameter product: The Product to test.
    /// - Returns: Returns `true` if purchased, else returns `false`.
    public func isPurchased(_ product: Product) async throws -> Bool {
        
        // Is this purchase version sensitive?
        let version = getAttribute("version", for: product.id)
        if version != "" {
            // Yes, check to see if a version of the app was purchased before.
            if wasPurchasedBefore(version: version) {
                // The app was before before the cutoff date, grant access to product.
                return true
            }
        }
        
        // Ensure that we have a network connection
        guard NetworkConnection.shared.isConnectedToNetwork else {
            // Attempt to check the vault
            decantVault()
            return isInVault(id: product.id)
        }
        
        // Determine whether the user purchases a given product.
        switch product.type {
        case .autoRenewable, .nonConsumable, .consumable, .nonRenewable:
            return purchasedProducts.contains(product)
        default:
            return false
        }
    }
    
    /// Tests to see if the given product has been purchased from the App Store.
    /// - Parameter id: The ID of the Product to test.
    /// - Returns: Returns `true` if purchased, else returns `false`.
    public func isPurchased(id:String) -> Bool {
        
        // Is this purchase version sensitive?
        let version = getAttribute("version", for: id)
        if version != "" {
            // Yes, check to see if a version of the app was purchased before.
            if wasPurchasedBefore(version: version) {
                // The app was before before the cutoff date, grant access to product.
                return true
            }
        }
        
        // Ensure that we have a network connection
        guard NetworkConnection.shared.isConnectedToNetwork else {
            // Attempt to check the vault
            decantVault()
            return isInVault(id: id)
        }
        
        // Scan all items
        for product in purchasedProducts {
            if product.id == id {
                return true
            }
        }
        
        // Not found
        return false
    }
    
    /// Returns the Product for the given ID.
    /// - Parameter id: The ID of the product to return.
    /// - Returns: Returns the `Product` or `nil` if not found.
    public func productFor(id:String) -> Product? {
        // Scan all items
        for product in products {
            if product.id == id {
                return product
            }
        }
        
        // Not found
        return nil
    }
    
    /// Return a list of products matching the given key.
    /// - Parameter key: The key to return products for.
    /// - Returns: Returns the requested products or an empty list if none were found.
    public func productsFor(key:String) -> [Product] {
        var matching:[Product] = []
        
        for product in products {
            if product.id.contains(key) {
                matching.append(product)
            }
        }
        
        return matching
    }
    
    /// Tests to see if a product is available for the given key.
    /// - Parameter key: The key to check.
    /// - Returns: Returns `true` if a product is available, else returns `false`.
    public func hasProductFor(key:String) -> Bool {
        
        for product in products {
            if product.id.contains(key) {
                return true
            }
        }
        
        return false
    }
    
    /// Reads a given attribute from the `Products` plist that contains information about the given product.
    /// - Parameters:
    ///   - name: The name of the attribute to read.
    ///   - productID: The App Store ID of the product to get the attribute for.
    ///   - defaultValue: The detault value for the attribute is it is not found.
    /// - Returns: Returns the `String` value for the requested attribute or the `defaultValue` if not found.
    public func getAttribute(_ name:String, for productID:String, defaultValue:String = "") -> String {
        
        // Ensure the product is available.
        guard productInfo.keys.contains(productID) else {
            // We don't have the requested product, return the default.
            return defaultValue
        }
        
        // Ensure the attributes collection is defined
        guard let attributes = productInfo[productID] else {
            // No, return the defaul value.
            return defaultValue
        }
        
        // Ensure the attribute is available for the given product
        guard attributes.keys.contains(name) else {
            // No, return the defaul value.
            return defaultValue
        }
        
        // Return the value for the requested attribute
        return attributes[name] ?? defaultValue
    }
    
    /// Checks to see if a given App Store Transaction in valid.
    /// - Parameter result: The App Store Transaction to test.
    /// - Returns: Returns `true` if verified, else returns `false`.
    public func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            // StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            // The result is verified. Return the unwrapped value.
            return safe
        }
    }
    
    /// Sorts the list of products by price in ascending order
    /// - Parameter products: The list of products to sort.
    /// - Returns: The sorted list.
    public func sortByPrice(_ products: [Product]) -> [Product] {
        products.sorted(by: { return $0.price < $1.price })
    }
    
    @MainActor
    /// Requests a refund for the given product/
    /// - Parameters:
    ///   - productID: The ID of the product to get a refund for.
    ///   - completionHandler: A handler that is called whe nthe task is completed.
    public func beginRefundProcess(for productID: String, completionHandler: purchaseUpdateHandler? = nil) {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first else {
            Log.error(subsystem: "StoreManager", category: "beginRefundProcess", "Unable to get main application scene.")
            return
        }
        
        guard let windowScene = scene as? UIWindowScene else {
            Log.error(subsystem: "StoreManager", category: "beginRefundProcess", "Unable to convert scene to UIWindowScene")
            return
        }
        
        Task {
            guard case .verified(let transaction) = await Transaction.latest(for: productID) else { return }
            
            do {
                let status = try await transaction.beginRefundRequest(in: windowScene)
                
                switch status {
                case .userCancelled:
                    if let completionHandler {
                        completionHandler()
                    }
                    break
                case .success:
                    // Maybe show something in the UI indicating that the refund is processing
                    if let completionHandler {
                        completionHandler()
                    }
                    break
                @unknown default:
                    if let completionHandler {
                        completionHandler()
                    }
                    assertionFailure("Unexpected status")
                    break
                }
            } catch {
                if let completionHandler {
                    completionHandler()
                }
                Log.error(subsystem: "StoreManager", category: "beginRefundProcess", "Refund request failed to start: \(error)")
            }
        }
        #endif
    }
}

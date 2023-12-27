# AppStoreManager

![](https://img.shields.io/badge/license-MIT-green) ![](https://img.shields.io/badge/maintained%3F-Yes-green) ![](https://img.shields.io/badge/swift-5.4-green) ![](https://img.shields.io/badge/iOS-17.0-red) ![](https://img.shields.io/badge/macOS-14.0-red) ![](https://img.shields.io/badge/tvOS-17.0-red) ![](https://img.shields.io/badge/watchOS-10.0-red) ![](https://img.shields.io/badge/dependency-LogManager-orange) ![](https://img.shields.io/badge/dependency-SimpleSerializer-orange) ![](https://img.shields.io/badge/dependency-SwiftletUtilities-orange)

`AppStoreManger` is an easy to use, StoreKit 2 based, in-App Purchase manager.

## Support

If you find `AppStoreManger` useful and would like to help support its continued development and maintenance, please consider making a small donation, especially if you are using it in a commercial product:

<a href="https://www.buymeacoffee.com/KevinAtAppra" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

It's through the support of contributors like yourself, I can continue to build, release and maintain high-quality, well documented Swift Packages like `AppStoreManger` for free.

## Installation

**Swift Package Manager** (Xcode 11 and above)

1. In Xcode, select the **File** > **Add Package Dependency…** menu item.
2. Paste `https://github.com/Appracatappra/AppStoreManger.git` in the dialog box.
3. Follow the Xcode's instruction to complete the installation.

> Why not CocoaPods, or Carthage, or etc?

Supporting multiple dependency managers makes maintaining a library exponentially more complicated and time consuming.

Since, the **Swift Package Manager** is integrated with Xcode 11 (and greater), it's the easiest choice to support going further.

## Overview

By simply including `AppStoreManager` in your App Project and defining your `Products.plist` file, it provides automatic support for the following:

* Family Sharing.
* Promoted In-App Purchases.
* Restored Product Purchases.

## Telling AppStoreManager About Your Products

You'll need to include a `Products.plist` in your App's Bundle that defines the Products that you have for sale, along with any useful metadata (such as an Image or Long Description) that you wish to define.

The following is a `SampleProducts.plist` that is included:

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>InAppPurchaseID01</key>
	<dict>
		<key>Image</key>
		<string>ProductImageName01</string>
		<key>Description</key>
		<string>ProductDescription01</string>
	</dict>
	<key>InAppPurchaseID02</key>
	<dict>
		<key>Image</key>
		<string>ProductImageName02</string>
		<key>Description</key>
		<string>ProductDescription02</string>
	</dict>
	<key>InAppPurchaseID03</key>
	<dict>
		<key>Image</key>
		<string>ProductImageName03</string>
		<key>Description</key>
		<string>ProductDescription03</string>
	</dict>
</dict>
</plist>
``` 

The first `Key` in the Products dictionary is critical as should be a valid In-App Purchase ID as defined in App Store Connect for you App.

The sub `Dictionary` includes any metadata attributes that you'd like to associate with the individual products as both a `String` kay and `String` value. In the case of this example, we are including both an **Image Name** and **Long Description**. 

Later we can use a `StoreManager` function to fetch any attribute that we have defined. To get the **Image Name** that we defined above for the last Product, you could use:

```
let imageName = StoreManager.shared.getAttribute("Image", for: "InAppPurchaseID03")
```

## Handling StoreManager Events

There are a few events that you will want to listen to so you can respond to user interaction:

* `purchasesUpdated` - Will get called whenever a In-App Purchase is modified by the App Store, such as when a product is successfully purchased or a purchase fails.
* `productRevoked` - Is called whenever a Purchase Transaction is revoked by the App Store. The `Transaction` is handed to the event.
* `promotedInAppPurchaseEvent` - Handles the user interacting with a Promoted In-App Purchase from the App Store. The events is handed the `Product` and a `Bool` flag for success or failure of the interaction.


For example, in your App's Main Module, you can do the following:

```
WindowGroup {
	...
}
.onChange(of: scenePhase) { oldScenePhase, newScenePhase in
    switch newScenePhase {
    case .active:
        // Listen for Store Manager Events
        StoreManager.shared.productRevoked = {transaction in
            // Handle Revoked Purchase events
            ...
        }
        
        StoreManager.shared.promotedInAppPurchaseEvent = {product, successful in
            // Handle Promoted In-App Purchase events
            ...
        }
    case .inactive:
        break
    case .background:
        // Release Store Manager Events
        StoreManager.shared.releaseEventHandlers()
    @unknown default:
        print("App has entered an unexpected scene: \(oldScenePhase), \(newScenePhase)")
    }
}
```

Before your app quits or enters the background, call `StoreManager.shared.releaseEventHandlers()` to release any handlers that you attached.

## Common Functions

The following functions are the most commonly used:

* **purchase** - `public func purchase(_ product: Product) async throws -> Transaction?` attempts to purchase the given product.
* **isPurchased** - Either `public func isPurchased(_ product: Product) async throws -> Bool` or `public func isPurchased(id:String) -> Bool` will return `true` if a given product is purchased.
* **productFor** - `public func productFor(id:String) -> Product?` Returns the `Product` for the given In-App Purchase ID.
* **getAttribute** - `public func getAttribute(_ name:String, for productID:String, defaultValue:String = "") -> String` Returns an attribute for the given In-App Purchase ID as defined in the `Product.plist` file included in your App Bundle.
* **beginRefundProcess** - `public func beginRefundProcess(for productID: String, completionHandler: purchaseUpdateHandler? = nil)` Begins the refund process for the given In-App Purchase ID.

# Documentation

The **Package** includes full **DocC Documentation** for all of its features.

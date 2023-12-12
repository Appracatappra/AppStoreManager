import XCTest
@testable import AppStoreManager

final class AppStoreManagerTests: XCTestCase {
    func testAppStoreManager() throws {
        let manager:StoreManager? = StoreManager()
        XCTAssert(manager != nil)
    }
}

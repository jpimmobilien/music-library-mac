import XCTest
@testable import StudioEngine

final class StudioEngineSmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(StudioEngineInfo.version, "2.2.0")
    }
}

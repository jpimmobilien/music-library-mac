import XCTest
@testable import AetherCore

final class MacModelTests: XCTestCase {
    func testKnownIdentifiers() throws {
        let mbp13 = try XCTUnwrap(MacModelCatalog.all["MacBookPro15,2"])
        XCTAssertEqual(mbp13.design, .proTouchBar)
        XCTAssertEqual(mbp13.productName, "MacBook Pro 13″")
        XCTAssertEqual(MacModelCatalog.all["MacBookPro16,2"]?.productName, "MacBook Pro 13″")
        XCTAssertEqual(MacModelCatalog.all["MacBookPro14,1"]?.design, .proFunctionKeys)
        XCTAssertEqual(MacModelCatalog.all["MacBookPro16,1"]?.productName, "MacBook Pro 16″")
        XCTAssertEqual(MacModelCatalog.all["MacBookPro18,3"]?.design, .proNotch)
        XCTAssertEqual(MacModelCatalog.all["MacBookPro18,3"]?.productName, "MacBook Pro 14″")
        XCTAssertEqual(MacModelCatalog.all["Mac17,11"]?.design, .proIsland)
        XCTAssertEqual(MacModelCatalog.all["MacBookAir7,2"]?.design, .airClassic)
        XCTAssertEqual(MacModelCatalog.all["MacBookAir10,1"]?.design, .airRetina)
        XCTAssertEqual(MacModelCatalog.all["Mac14,15"]?.productName, "MacBook Air 15″")
        XCTAssertEqual(MacModelCatalog.all["Mac14,2"]?.productName, "MacBook Air 13″")
        XCTAssertEqual(MacModelCatalog.all["MacBook10,1"]?.productName, "MacBook 12″")
        XCTAssertEqual(MacModelCatalog.all["iMac18,2"]?.productName, "iMac 21.5″")
        XCTAssertEqual(MacModelCatalog.all["iMacPro1,1"]?.productName, "iMac Pro")
        XCTAssertEqual(MacModelCatalog.all["Mac16,3"]?.design, .iMac24)
        XCTAssertEqual(MacModelCatalog.all["Mac16,10"]?.design, .miniCompact)
        XCTAssertEqual(MacModelCatalog.all["Macmini8,1"]?.design, .miniClassic)
        XCTAssertEqual(MacModelCatalog.all["Mac15,14"]?.design, .studio)
        XCTAssertEqual(MacModelCatalog.all["MacPro7,1"]?.design, .proTower)
        XCTAssertEqual(MacModelCatalog.all["MacPro6,1"]?.design, .proCylinder)
    }

    func testEveryModelIsConsistent() {
        XCTAssertGreaterThan(MacModelCatalog.all.count, 90)
        for (id, model) in MacModelCatalog.all {
            XCTAssertEqual(model.identifier, id)
            XCTAssertTrue(model.exact)
            XCTAssertGreaterThan(model.width, 100)
            XCTAssertGreaterThan(model.depth, 100)
            XCTAssertEqual(model.design.hasBuiltInDisplay, model.inches != nil, id)
            XCTAssertEqual(model.design.isPortable, [.macBookPro, .macBookAir, .macBook].contains(model.family), id)
        }
    }

    func testDeviceKindFromNewIdentifiers() {
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "Mac14,2"), .macBookAir)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "Mac16,10"), .macMini)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "Mac15,14"), .macStudio)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "iMacPro1,1"), .iMac)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "VirtualMac2,1"), .virtualMachine)
    }

    func testEstimateWhenUnknown() throws {
        let future = try XCTUnwrap(MacModelCatalog.resolve(identifier: "Mac99,1", kind: .macBookPro, appleSilicon: true,
                                                           builtInDisplayInches: 16.2))
        XCTAssertFalse(future.exact)
        XCTAssertEqual(future.design, .proNotch)
        XCTAssertEqual(future.productName, "MacBook Pro 16″")
        let intel = try XCTUnwrap(MacModelCatalog.resolve(identifier: nil, kind: .macBookPro, appleSilicon: false,
                                                          builtInDisplayInches: 15.4))
        XCTAssertEqual(intel.productName, "MacBook Pro 15″")
        XCTAssertEqual(MacModelCatalog.resolve(identifier: "Mac99,2", kind: .macBookAir, appleSilicon: true,
                                               builtInDisplayInches: 15.3)?.productName, "MacBook Air 15″")
        XCTAssertNil(MacModelCatalog.resolve(identifier: "VirtualMac2,1", kind: .virtualMachine, appleSilicon: true))
        // exakte Kennung gewinnt immer
        XCTAssertEqual(MacModelCatalog.resolve(identifier: "MacBookPro16,2", kind: .macBookPro, appleSilicon: false,
                                               builtInDisplayInches: 16)?.productName, "MacBook Pro 13″")
    }

    func testInchLabel() {
        XCTAssertEqual(MacModelInfo.inchLabel(13.3), "13")
        XCTAssertEqual(MacModelInfo.inchLabel(14.2), "14")
        XCTAssertEqual(MacModelInfo.inchLabel(21.5, decimalSeparator: ","), "21,5")
        XCTAssertEqual(MacModelInfo.inchLabel(27), "27")
    }
}

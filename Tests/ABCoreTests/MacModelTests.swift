import XCTest
@testable import ABCore

final class MacModelTests: XCTestCase {
    func testMacBookPro2017HasChinDesign() {
        let m = MacModel(identifier: "MacBookPro14,1", rawName: "MacBook Pro (13-inch, 2017, Two Thunderbolt 3 ports)",
                         chip: "Intel(R) Core(TM) i5-7360U CPU @ 2.30GHz")
        XCTAssertEqual(m.form, .retinaChin)
        XCTAssertEqual(m.familyName, "MacBook Pro")
        XCTAssertEqual(m.detailName, "13 Zoll, 2017, 2 × Thunderbolt 3")
        XCTAssertTrue(MacFinish.options(for: m.form).contains(m.suggestedFinish))
    }

    func testAppleSiliconNotchModels() {
        XCTAssertEqual(MacModel(identifier: "MacBookPro18,3", rawName: "MacBook Pro (14-inch, 2021)").form, .notchPro)
        let m3 = MacModel(identifier: "Mac15,6", rawName: "MacBook Pro (14-inch, Nov 2023)", chip: "Apple M3 Pro")
        XCTAssertEqual(m3.form, .notchPro)
        XCTAssertEqual(m3.suggestedFinish, .spaceBlack)
        XCTAssertEqual(m3.detailName, "14 Zoll, Nov 2023")
        XCTAssertEqual(MacModel(identifier: "Mac14,2", rawName: "MacBook Air (M2, 2022)").form, .notchAir)
        // Ohne Namen über bekannte Kennungen
        XCTAssertEqual(MacModel(identifier: "Mac15,12", rawName: nil).form, .notchAir)
        XCTAssertEqual(MacModel(identifier: "Mac15,12", rawName: nil).familyName, "MacBook Air")
    }

    func testM2MacBookPro13StillHasChin() {
        XCTAssertEqual(MacModel(identifier: "Mac14,7", rawName: "MacBook Pro (13-inch, M2, 2022)").form, .retinaChin)
        XCTAssertEqual(MacModel(identifier: "MacBookPro17,1", rawName: nil).form, .retinaChin)
    }

    func testOlderAndDesktopModels() {
        XCTAssertEqual(MacModel(identifier: "MacBookPro11,4", rawName: nil).form, .classicPro)
        XCTAssertEqual(MacModel(identifier: "MacBookAir7,2", rawName: nil).form, .classicAir)
        XCTAssertEqual(MacModel(identifier: "MacBookAir10,1", rawName: nil).form, .retinaAir)
        XCTAssertEqual(MacModel(identifier: "MacBook10,1", rawName: nil).form, .retinaChin)
        XCTAssertEqual(MacModel(identifier: "iMac19,1", rawName: nil).form, .iMacClassic)
        XCTAssertEqual(MacModel(identifier: "iMac21,1", rawName: nil).form, .iMacColor)
        XCTAssertEqual(MacModel(identifier: "iMacPro1,1", rawName: nil).form, .iMacClassic)
        XCTAssertEqual(MacModel(identifier: "Macmini9,1", rawName: nil).form, .desktop)
        XCTAssertEqual(MacModel(identifier: "Mac13,1", rawName: "Mac Studio (2022)").form, .desktop)
        XCTAssertEqual(MacModel(identifier: "Mac16,10", rawName: nil).form, .desktop)
    }

    func testUnknownIdentifierFallsBackGracefully() {
        let vm = MacModel(identifier: "VirtualMac2,1", rawName: nil)
        XCTAssertEqual(vm.form, .notchPro)
        XCTAssertEqual(vm.marketingName, "Mac")
        XCTAssertNil(vm.detailName)
    }

    func testChipGeneration() {
        XCTAssertEqual(MacModel.chipGeneration("Apple M3 Max"), 3)
        XCTAssertEqual(MacModel.chipGeneration("Apple M1"), 1)
        XCTAssertNil(MacModel.chipGeneration("Intel(R) Core(TM) i7-7820HQ CPU @ 2.90GHz"))
    }
}

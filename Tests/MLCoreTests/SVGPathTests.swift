import XCTest
@testable import MLCore

final class SVGPathTests: XCTestCase {
    func testAbsoluteQuadraticPath() {
        let cmds = SVGPath.parse("M400,840Q334,840 287,793Q240,746 240,680Z")
        XCTAssertEqual(cmds.first, .move(x: 400, y: 840))
        XCTAssertEqual(cmds[1], .quad(cx: 334, cy: 840, x: 287, y: 793))
        XCTAssertEqual(cmds.last, .close)
    }

    func testRelativeSmoothCubicsWithImplicitRepeat() {
        let cmds = SVGPath.parse("M2.4,7.4c2.4,-2.4 4.8,-2.4 7.2,0s4.8,2.4 7.2,0 3.6,-1.8 5,-0.9")
        XCTAssertEqual(cmds.count, 4)
        guard case let .cubic(c1x, c1y, _, _, x, y) = cmds[2] else { return XCTFail() }
        XCTAssertEqual(c1x, 12.0, accuracy: 1e-9) // gespiegelter Kontrollpunkt
        XCTAssertEqual(c1y, 9.8, accuracy: 1e-9)
        XCTAssertEqual(x, 16.8, accuracy: 1e-9)
        XCTAssertEqual(y, 7.4, accuracy: 1e-9)
    }

    func testArcCircleStaysOnRadiusAndEndsExactly() {
        let cmds = SVGPath.parse("M24,54a30,30 0,1 0,60,0a30,30 0,1 0,-60,0Z")
        var last: (Double, Double)?
        for c in cmds {
            if case let .cubic(_, _, _, _, x, y) = c {
                let r = ((x - 54) * (x - 54) + (y - 54) * (y - 54)).squareRoot()
                XCTAssertEqual(r, 30, accuracy: 1e-6)
                last = (x, y)
            }
        }
        XCTAssertEqual(last?.0 ?? 0, 24, accuracy: 1e-9)
        XCTAssertEqual(last?.1 ?? 0, 54, accuracy: 1e-9)
    }

    func testCompactNumbersAndExponent() {
        let cmds = SVGPath.parse("M1.5.5L2-3e1 4 5z")
        XCTAssertEqual(cmds, [.move(x: 1.5, y: 0.5), .line(x: 2, y: -30), .line(x: 4, y: 5), .close])
    }

    func testHorizontalVerticalAndCloseResetsPoint() {
        let cmds = SVGPath.parse("M10,10h5v5H10zl1,1")
        XCTAssertEqual(cmds, [.move(x: 10, y: 10), .line(x: 15, y: 10), .line(x: 15, y: 15), .line(x: 10, y: 15), .close, .line(x: 11, y: 11)])
    }
}

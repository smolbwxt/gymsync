import XCTest
@testable import GymSync

/// The BLE Heart Rate Measurement parse (spec: GATT 0x2A37). Pure — no
/// CoreBluetooth. The flag-selected uint8/uint16 split is the classic
/// wire-format trap: a parser that only handles the uint8 form works with
/// every strap on the bench and then breaks for whichever device pads to
/// uint16.
final class BLEHeartRateParseTests: XCTestCase {

    func testUInt8Format() {
        // flags bit0 = 0 -> bpm is one byte.
        XCTAssertEqual(BLEHeartRateService.parseHeartRate(Data([0x00, 72])), 72)
        XCTAssertEqual(BLEHeartRateService.parseHeartRate(Data([0x16, 155])), 155)
    }

    func testUInt16LittleEndianFormat() {
        // flags bit0 = 1 -> bpm is uint16 LE. 0x00B4 = 180.
        XCTAssertEqual(BLEHeartRateService.parseHeartRate(Data([0x01, 0xB4, 0x00])), 180)
        // Byte-order proof: LE(0xF9, 0x00) = 249, not 0xF900. (The 0-250
        // physiological sanity band lives in handleMeasurement, not here —
        // the parser reports the wire value.)
        XCTAssertEqual(BLEHeartRateService.parseHeartRate(Data([0x01, 0xF9, 0x00])), 249)
        XCTAssertEqual(BLEHeartRateService.parseHeartRate(Data([0x01, 0x00, 0x01])), 256)
    }

    func testTrailingFieldsAreIgnored() {
        // Energy expended + RR intervals after the bpm must not confuse it.
        XCTAssertEqual(BLEHeartRateService.parseHeartRate(Data([0x10, 140, 0x34, 0x02])), 140)
    }

    func testMalformedAndTruncated() {
        XCTAssertNil(BLEHeartRateService.parseHeartRate(Data()))
        XCTAssertNil(BLEHeartRateService.parseHeartRate(Data([0x00])))
        // uint16 flag with only one byte of value.
        XCTAssertNil(BLEHeartRateService.parseHeartRate(Data([0x01, 0x48])))
    }
}

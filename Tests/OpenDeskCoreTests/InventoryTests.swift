import XCTest
@testable import OpenDeskCore

final class InventoryTests: XCTestCase {
    func testParseHardwareFieldsFromSystemProfilerJSON() {
        let json = """
        {
          "SPHardwareDataType": [
            {
              "_name": "hardware_overview",
              "_items": [
                {
                  "machine_name": "MacBook Pro",
                  "machine_model": "Mac16,1",
                  "serial_number": "C02TEST1234",
                  "memory": "32 GB",
                  "chip_type": "Apple M4"
                }
              ]
            }
          ]
        }
        """
        let collector = InventoryCollector()
        XCTAssertEqual(collector.parseModelName(from: json), "MacBook Pro")
        XCTAssertEqual(collector.parseSerial(from: json), "C02TEST1234")
        XCTAssertEqual(collector.parseMemoryMB(from: json), 32768)
    }

    func testParseMemoryHandlesGBAndMB() {
        let collector = InventoryCollector()
        let gbJSON = "{\"SPHardwareDataType\":[{\"_items\":[{\"memory\":\"8 GB\"}]}]}"
        let mbJSON = "{\"SPHardwareDataType\":[{\"_items\":[{\"memory\":\"8192 MB\"}]}]}"
        XCTAssertEqual(collector.parseMemoryMB(from: gbJSON), 8192)
        XCTAssertEqual(collector.parseMemoryMB(from: mbJSON), 8192)
    }

    func testParseToleratesInvalidJSON() {
        let collector = InventoryCollector()
        XCTAssertEqual(collector.parseModelName(from: "not json"), "unknown")
        XCTAssertEqual(collector.parseSerial(from: ""), "unknown")
        XCTAssertEqual(collector.parseMemoryMB(from: ""), 0)
    }

    /// Integration test: runs against the real test machine.
    func testCollectLocalReport() throws {
        let report = try InventoryCollector().collectLocal()
        XCTAssertFalse(report.hostname.isEmpty)
        XCTAssertFalse(report.osVersion.isEmpty)
        XCTAssertFalse(report.chipArchitecture.isEmpty)
        XCTAssertGreaterThan(report.totalMemoryMB, 0)
        XCTAssertFalse(report.installedApps.isEmpty)
    }
}

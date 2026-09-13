import Testing
import Foundation
@testable import OpenDeskCore

@Suite("Scheduler, SmartGroups, Power, RFB")
struct SchedulerPowerRFBTests {

    // MARK: RRULE

    @Test("RRULE parse: weekly with BYDAY and BYHOUR")
    func rruleParse() throws {
        let rule = try Scheduler.parseRRULE("FREQ=WEEKLY;BYDAY=FR;BYHOUR=22")
        #expect(rule.freq == "WEEKLY")
        #expect(rule.byDays == [6]) // Friday
        #expect(rule.byHour == 22)
    }

    @Test("RRULE parse rejects unsupported")
    func rruleRejects() {
        #expect(throws: ScheduleError.self) { _ = try Scheduler.parseRRULE("FREQ=MONTHLY") }
        #expect(throws: ScheduleError.self) { _ = try Scheduler.parseRRULE("INTERVAL=2") }
        #expect(throws: ScheduleError.self) { _ = try Scheduler.parseRRULE("FREQ=WEEKLY;BYDAY=XX") }
    }

    @Test("RRULE next-run: weekly Friday 22:00")
    func rruleNextRun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Anchor: Wednesday 2026-09-09 12:00 UTC
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 9; comps.hour = 12
        let anchor = calendar.date(from: comps)!
        let next = try Scheduler.nextRun(rrule: "FREQ=WEEKLY;BYDAY=FR;BYHOUR=22", after: anchor, calendar: calendar)
        let weekday = calendar.component(.weekday, from: next)
        let hour = calendar.component(.hour, from: next)
        #expect(weekday == 6) // Friday
        #expect(hour == 22)
        #expect(next > anchor)
    }

    @Test("RRULE next-run: daily interval 2")
    func rruleDaily() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 10; comps.hour = 8
        let anchor = calendar.date(from: comps)!
        let next = try Scheduler.nextRun(rrule: "FREQ=DAILY;INTERVAL=2", after: anchor, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: next)).day!
        #expect(days % 2 == 0)
        #expect(next > anchor)
    }

    // MARK: Smart groups

    @Test("Predicate matching: AND/OR/version comparison")
    func predicates() {
        let device = DeviceRecord(
            hostname: "lab-01", osVersion: "15.5", architecture: "arm64",
            rfbAvailable: true, sshAvailable: true, online: true
        )
        let and = SmartGroupPredicate(op: .and, clauses: [
            .init(field: "architecture", op: .eq, value: "arm64"),
            .init(field: "online", op: .eq, value: "true"),
            .init(field: "os_version", op: .lt, value: "26"),
        ])
        #expect(and.matches(device))

        let or = SmartGroupPredicate(op: .or, clauses: [
            .init(field: "architecture", op: .eq, value: "x86_64"),
            .init(field: "hostname", op: .contains, value: "lab"),
        ])
        #expect(or.matches(device))

        let noMatch = SmartGroupPredicate(op: .and, clauses: [
            .init(field: "architecture", op: .eq, value: "x86_64"),
        ])
        #expect(!noMatch.matches(device))
    }

    @Test("Predicate JSON round-trip")
    func predicateJSON() throws {
        let p = SmartGroupPredicate(op: .and, clauses: [
            .init(field: "os_version", op: .lt, value: "26"),
            .init(field: "architecture", op: .eq, value: "arm64"),
            .init(field: "online", op: .eq, value: "true"),
        ])
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8)!
        let decoded = try SmartGroupPredicate.decode(json)
        #expect(decoded == p)
    }

    // MARK: Power

    @Test("Wake-on-LAN packet structure")
    func wolPacket() {
        let packet = PowerController.wakeOnLANPacket(mac: "AA:BB:CC:DD:EE:FF")
        #expect(packet != nil)
        #expect(packet?.count == 102) // 6 + 16*6
        #expect(packet?.prefix(6).elementsEqual([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]) == true)
        // MAC repeated 16 times starting at offset 6.
        #expect(packet?.dropFirst(6).prefix(6).elementsEqual([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]) == true)
        #expect(PowerController.wakeOnLANPacket(mac: "invalid") == nil)
    }

    // MARK: RFB

    @Test("VNC DES challenge-response is deterministic and 16 bytes")
    func vncDES() {
        let challenge = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                              0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        let r1 = RFBClient.vncDES(password: "secret", challenge: challenge)
        let r2 = RFBClient.vncDES(password: "secret", challenge: challenge)
        #expect(r1 == r2)
        #expect(r1.count == 16)
        // Different password -> different response.
        let r3 = RFBClient.vncDES(password: "other", challenge: challenge)
        #expect(r1 != r3)
    }

    @Test("Bit reversal helper")
    func bitReverse() {
        #expect(RFBClient.reverseBits(0b00000001) == 0b10000000)
        #expect(RFBClient.reverseBits(0b11110000) == 0b00001111)
        #expect(RFBClient.reverseBits(0) == 0)
        #expect(RFBClient.reverseBits(0xFF) == 0xFF)
    }

    @Test("RFB security type vocabulary")
    func securityTypes() {
        #expect(RFBSecurityType.none.rawValue == 1)
        #expect(RFBSecurityType.vncAuthentication.rawValue == 2)
        #expect(RFBSecurityType.appleARD.rawValue == 30)
        #expect(RFBSecurityType.none.implemented)
        #expect(RFBSecurityType.vncAuthentication.implemented)
        #expect(!RFBSecurityType.appleARD.implemented)
    }

    @Test("RFB pixel format default")
    func pixelFormat() {
        let pf = RFBPixelFormat.rgba32
        #expect(pf.bitsPerPixel == 32)
        #expect(pf.depth == 24)
        #expect(pf.trueColor)
        #expect(pf.redShift == 0 && pf.greenShift == 8 && pf.blueShift == 16)
    }

    @Test("Framebuffer blit/fill/copyrect")
    func framebufferOps() async throws {
        let client = RFBClient(host: "127.0.0.1", port: 5900)
        client.setFramebuffer(RFBFramebuffer(
            width: 4, height: 4, pixelFormat: .rgba32, name: "test",
            pixels: [UInt8](repeating: 0, count: 64)
        ))
        // Fill a 2x2 rect with red.
        client.fillRect(x: 0, y: 0, w: 2, h: 2, color: [255, 0, 0, 255])
        var fb = client.framebuffer!
        #expect(fb.pixels[0] == 255 && fb.pixels[1] == 0 && fb.pixels[2] == 0)

        // Blit raw green over it.
        let green = Data([0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255])
        client.blitRaw(x: 0, y: 0, w: 2, h: 2, data: green)
        fb = client.framebuffer!
        #expect(fb.pixels[0] == 0 && fb.pixels[1] == 255)

        // CopyRect from (0,0) to (2,2).
        client.copyRect(dstX: 2, dstY: 2, w: 2, h: 2, srcX: 0, srcY: 0)
        fb = client.framebuffer!
        let idx = (2 * 4 + 2) * 4
        #expect(fb.pixels[idx] == 0 && fb.pixels[idx + 1] == 255)
    }
}

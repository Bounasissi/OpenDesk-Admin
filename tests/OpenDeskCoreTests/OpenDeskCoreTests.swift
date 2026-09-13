import Testing
import Foundation
@testable import OpenDeskCore

@Suite("OpenDeskCore")
struct OpenDeskCoreTests {

    @Test("Task defaults to created/immediate")
    func taskDefaults() {
        let device = Device(hostname: "mac-001")
        let task = ODTask(type: .executeCommand, targets: [device.id])
        #expect(task.status == .created)
        #expect(task.execution.mode == .immediate)
        #expect(task.targets.count == 1)
    }

    @Test("Task codable round-trip")
    func taskRoundTrip() throws {
        let task = ODTask(
            type: .installPackage,
            targets: [UUID()],
            parameters: ["package": "/tmp/pkg.pkg"],
            execution: .init(mode: .onReconnect)
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(ODTask.self, from: data)
        #expect(decoded == task)
    }

    @Test("Task type raw values match schema vocabulary")
    func taskTypeVocabulary() {
        #expect(ODTask.TaskType.executeCommand.rawValue == "execute_command")
        #expect(ODTask.TaskType.installPackage.rawValue == "install_package")
        #expect(ODTask.TaskType.lockScreen.rawValue == "lock_screen")
        #expect(ODTask.Status.offlineWait.rawValue == "offline_wait")
        #expect(ODTask.ExecutionMode.onReconnect.rawValue == "on_reconnect")
    }
}

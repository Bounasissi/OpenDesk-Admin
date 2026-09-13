import ArgumentParser
import OpenDeskCore
import Foundation

@main
struct OpenDesk: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opendesk",
        abstract: "OpenDesk Admin — open-source, API-first macOS fleet administration.",
        version: "0.1.0",
        subcommands: [DevicesCommand.self, ExecCommand.self]
    )
}

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List registered devices."
    )

    func run() throws {
        // v0: placeholder — device registry persistence lands with device-registry module.
        print("opendesk devices: registry not yet wired (milestone 3: device discovery)")
    }
}

struct ExecCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a command on target devices via SSH."
    )

    @Argument(help: "Command to execute")
    var command: String

    @Option(name: .shortAndLong, help: "Target group name")
    var group: String?

    func run() throws {
        // v0: placeholder — SSH transport lands with ssh module.
        print("opendesk exec: SSH transport not yet wired (milestone 3: SSH execution)")
        print("command: \(command)\(group.map { " — group: \($0)" } ?? "")")
    }
}

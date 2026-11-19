import Foundation
import Testing

struct CLITests {
  @Test func version() throws {
    let (process, output) = try launchdActivate("--version")
    #expect(process.terminationStatus == 0)
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
  }

  @Test func help() throws {
    let (process, output) = try launchdActivate("--help")
    #expect(process.terminationStatus == 0)
    #expect(output.hasPrefix("usage:"))
  }

  @Test(arguments: ["a", "b", "c", "d"])
  func activateSymlink(agents: String) throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent(agents)
    let (process, output) = try launchdActivate("--dry-run", "--symlink", newAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  @Test(arguments: ["a", "b", "c", "d"])
  func activateCopy(agents: String) throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent(agents)
    let (process, output) = try launchdActivate("--dry-run", "--copy", newAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  @Test(arguments: ["a", "b", "c", "d"])
  func activateNoChange(agents: String) throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent(agents)
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, newAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  @Test func activateUpdate() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("b")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("a")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  @Test func activateAdd() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("d")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("a")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  @Test func activateAddRemove() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("b")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("a")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  @Test func activateOldNotExists() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("b")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("missing")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    #expect(process.terminationStatus == 0, "\(output)")
  }

  func launchdActivate(_ arguments: String...) throws -> (Process, String) {
    let process = Process()
    process.executableURL = productsDirectory.appendingPathComponent("launchd-activate")
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return (process, output)
  }

  var launchAgentsDirectory: URL {
    guard let url = Bundle.module.url(forResource: "LaunchAgents", withExtension: nil) else {
      fatalError("Could not find LaunchAgents directory in bundle resources")
    }
    return url
  }

  // The resource bundle sits beside the executable or inside the test bundle,
  // depending on the SwiftPM build system, so search its ancestors.
  var productsDirectory: URL {
    var url = Bundle.module.bundleURL
    while url.path != "/" {
      url.deleteLastPathComponent()
      if FileManager.default.isExecutableFile(
        atPath: url.appendingPathComponent("launchd-activate").path)
      {
        return url
      }
    }
    fatalError("couldn't find the products directory")
  }
}

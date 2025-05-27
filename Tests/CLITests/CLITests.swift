import XCTest

final class CLITests: XCTestCase {
  func testVersion() throws {
    let (process, output) = try launchdActivate("--version")
    XCTAssertEqual(process.terminationStatus, 0)
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ".")
    XCTAssertEqual(parts.count, 3)
    XCTAssertTrue(parts.allSatisfy { Int($0) != nil })
  }

  func testHelp() throws {
    let (process, output) = try launchdActivate("--help")
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertTrue(output.hasPrefix("usage:"))
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

  func testActivateSymlink() throws {
    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("a")
      let (process, output) = try launchdActivate("--dry-run", "--symlink", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("b")
      let (process, output) = try launchdActivate("--dry-run", "--symlink", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("c")
      let (process, output) = try launchdActivate("--dry-run", "--symlink", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("d")
      let (process, output) = try launchdActivate("--dry-run", "--symlink", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }
  }

  func testActivateCopy() throws {
    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("a")
      let (process, output) = try launchdActivate("--dry-run", "--copy", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("b")
      let (process, output) = try launchdActivate("--dry-run", "--copy", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("c")
      let (process, output) = try launchdActivate("--dry-run", "--copy", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("d")
      let (process, output) = try launchdActivate("--dry-run", "--copy", newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }
  }

  func testActivateNoChange() throws {
    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("a")
      let (process, output) = try launchdActivate("--dry-run", newAgents.path, newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("b")
      let (process, output) = try launchdActivate("--dry-run", newAgents.path, newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("c")
      let (process, output) = try launchdActivate("--dry-run", newAgents.path, newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }

    do {
      let newAgents = launchAgentsDirectory.appendingPathComponent("d")
      let (process, output) = try launchdActivate("--dry-run", newAgents.path, newAgents.path)
      XCTAssertEqual(process.terminationStatus, 0, output)
    }
  }

  func testActivateUpdate() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("b")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("a")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    XCTAssertEqual(process.terminationStatus, 0, output)
  }

  func testActivateAdd() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("d")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("a")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    XCTAssertEqual(process.terminationStatus, 0, output)
  }

  func testActivateAddRemove() throws {
    let newAgents = launchAgentsDirectory.appendingPathComponent("b")
    let oldAgents = launchAgentsDirectory.appendingPathComponent("a")
    let (process, output) = try launchdActivate("--dry-run", newAgents.path, oldAgents.path)
    XCTAssertEqual(process.terminationStatus, 0, output)
  }

  var launchAgentsDirectory: URL {
    guard let url = Bundle.module.url(forResource: "LaunchAgents", withExtension: nil) else {
      fatalError("Could not find LaunchAgents directory in bundle resources")
    }
    return url
  }

  var productsDirectory: URL {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
      return bundle.bundleURL.deletingLastPathComponent()
    }
    fatalError("couldn't find the products directory")
  }
}

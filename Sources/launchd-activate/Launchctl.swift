import Foundation

struct Launchctl {
  var dryRun: Bool = false
}

extension Launchctl {
  enum Error: Swift.Error {
    case nonZeroExit(code: Int32, stderr: String)
    case timeout(service: ServiceTarget)
  }
}

extension Launchctl {
  private struct ProcessResult {
    var stdout: Data = Data()
    var stderr: Data = Data()
    var exitCode: Int32 = 0

    func checkError() throws {
      guard exitCode == 0 else {
        throw Error.nonZeroExit(code: exitCode, stderr: String(data: stderr, encoding: .utf8) ?? "")
      }
    }
  }

  private func run(
    _ arguments: [String],
    dryRun: Bool = false,
    xtrace: Bool = true
  ) throws
    -> ProcessResult
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    if dryRun == true {
      printDryRun("launchctl", arguments)
      return ProcessResult()
    }

    if xtrace {
      printXtrace("launchctl", arguments)
    }

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
      stdout: stdoutData,
      stderr: stderrData,
      exitCode: process.terminationStatus
    )
  }

  func bootstrap(domain: DomainTarget, path: URL...) throws {
    let result = try run(["bootstrap", "\(domain)"] + path.map { $0.path }, dryRun: dryRun)
    try result.checkError()
  }

  func bootout(service: ServiceTarget) throws {
    let result = try run(["bootout", "\(service)"], dryRun: dryRun)
    try result.checkError()
  }
}

extension Launchctl {
  func loadState(service: ServiceTarget) throws -> Bool {
    let result = try run(["print", "\(service)"], dryRun: false, xtrace: false)
    return result.exitCode == 0
  }

  func waitForLoadState(service: ServiceTarget, loaded: Bool, timeout: Duration) throws {
    guard !dryRun else { return }
    guard try loadState(service: service) != loaded else { return }

    let stateStr = loaded ? "load" : "unload"

    let clock = ContinuousClock()
    let start = clock.now
    while try loadState(service: service) != loaded {
      if clock.now - start > timeout {
        var stderr = StandardErrorStream()
        print("[ERROR] Timed out waiting for \(service) to \(stateStr)", to: &stderr)
        throw Launchctl.Error.timeout(service: service)
      }
      Thread.sleep(forTimeInterval: 1)
    }
  }
}

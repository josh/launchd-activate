import Foundation

struct Launchctl {
  let logger: Logger
  var dryRun: Bool = false
}

extension Launchctl {
  enum Error: Swift.Error {
    case nonZeroExit(code: Int32)
    case timeout(service: ServiceTarget)
  }
}

extension Launchctl {
  private func run(_ arguments: [String], sudo: Bool = false) throws {
    if dryRun == true {
      if sudo {
        printDryRun("sudo", ["launchctl"] + arguments)
      } else {
        printDryRun("launchctl", arguments)
      }
      return
    }

    if sudo {
      printXtrace("sudo", ["launchctl"] + arguments)
    } else {
      printXtrace("launchctl", arguments)
    }

    let process = Process()
    if sudo {
      process.executableURL = URL(fileURLWithPath: SUDO_PATH)
      process.arguments = ["--", LAUNCHCTL_PATH] + arguments
    } else {
      process.executableURL = URL(fileURLWithPath: LAUNCHCTL_PATH)
      process.arguments = arguments
    }

    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw Error.nonZeroExit(code: process.terminationStatus)
    }
  }

  func bootstrap(domain: DomainTarget, path: ServicePath...) throws {
    for path in path {
      assert(loadState(domain: domain, path: path) == false)
    }
    try run(["bootstrap", "\(domain)"] + path.map { $0.path }, sudo: domain == .system)
  }

  func bootout(service: ServiceTarget) throws {
    assert(loadState(service: service) == true)
    try run(["bootout", "\(service)"], sudo: service.domain == .system)
  }
}

extension Launchctl {
  func loadState(service: ServiceTarget) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: LAUNCHCTL_PATH)
    process.arguments = ["print", "\(service)"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    try! process.run()
    process.waitUntilExit()

    return process.terminationStatus == 0
  }

  func loadState(domain: DomainTarget, path: ServicePath) -> Bool {
    return loadState(service: domain.service(path: path))
  }

  func waitForLoadState(service: ServiceTarget, loaded: Bool, timeout: Duration) throws {
    guard !dryRun else { return }
    guard loadState(service: service) != loaded else { return }

    let stateStr = loaded ? "load" : "unload"

    let clock = ContinuousClock()
    let start = clock.now
    while loadState(service: service) != loaded {
      if clock.now - start > timeout {
        logger.error("Timed out waiting for \(service) to \(stateStr)")
        throw Launchctl.Error.timeout(service: service)
      }
      Thread.sleep(forTimeInterval: 1)
    }
  }
}

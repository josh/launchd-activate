import Foundation

let version = "0.0.0"

@main
struct Command {
  var domain: DomainTarget = .currentGUI
  var serviceDirectory: ServiceDirectory = .currentUser
  var dryRun: Bool = false
  var verbose: Bool = false
  var logger: Logger = .info
  var installMethod: InstallMethod = .symlink
  var timeout: Duration = .seconds(10)
  var showHelp: Bool = false
  var showVersion: Bool = false

  var newPath: URL!
  var oldPath: URL?

  static func main() {
    do {
      let command = try Command(CommandLine.arguments)
      let exitCode = try command.run()
      exit(exitCode)
    } catch {
      var stderr = StandardErrorStream()
      print("error: \(error)", to: &stderr)
      exit(1)
    }
  }

  init(_ arguments: [String]) throws {
    var args: [String] = []

    for arg in arguments.dropFirst() {
      if arg.hasPrefix("--") {
        switch arg {
        case "-h", "--help":
          self.showHelp = true
        case "-V", "--version":
          self.showVersion = true
        case "-n", "--dry-run":
          self.dryRun = true
        case "-v", "--verbose":
          self.verbose = true
          self.logger = .debug
        case "--system":
          self.domain = .system
          self.serviceDirectory = .system
          self.installMethod = .copy
        case "--user":
          self.domain = .currentGUI
          self.serviceDirectory = .currentUser
        case "--user-all":
          self.domain = .currentGUI
          self.serviceDirectory = .allUsers
          self.installMethod = .copy
        case "--copy":
          self.installMethod = .copy
        case "--symlink":
          self.installMethod = .symlink
        default:
          printUsage()
          logger.error("unknown option: \(arg)")
          exit(1)
        }
      } else {
        args.append(arg)
      }
    }

    if self.showHelp {
      printUsage()
      exit(0)
    }

    if self.showVersion {
      printVersion()
      exit(0)
    }

    if args.isEmpty {
      printUsage()
      exit(1)
    }

    let newPath = URL(fileURLWithPath: args[0]).standardized.resolvingSymlinksInPath()
    if FileManager.default.fileExists(atPath: newPath.path) == false {
      printUsage()
      logger.error("\(newPath) does not exist")
      exit(1)
    }
    self.newPath = newPath

    if args.count > 1 {
      let oldPath = URL(fileURLWithPath: args[1]).standardized.resolvingSymlinksInPath()
      if FileManager.default.fileExists(atPath: oldPath.path) == false {
        printUsage()
        logger.error("\(oldPath) does not exist")
        exit(1)
      }
      self.oldPath = oldPath
    }
  }

  func printUsage() {
    print("usage: launchd-activate [--system | --user | --user-all] NEW [OLD]")
  }

  func printVersion() {
    print(version)
  }

  func run() throws -> Int32 {
    var plan = Plan(logger: logger, installMethod: installMethod)
    plan.prepare(
      domain: domain,
      serviceDirectory: serviceDirectory,
      newPath: newPath,
      oldPath: oldPath
    )
    logger.debug(plan.debugDescription)
    let executionErrors = try plan.execute(
      dryRun: dryRun,
      waitTimeout: timeout
    )
    return Int32(executionErrors)
  }
}

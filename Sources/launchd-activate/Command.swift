import Foundation

let version = "0.0.0"

@main
struct Command {
  var domain: DomainTarget = .currentGUI
  var serviceDirectory: ServiceDirectory = .currentUser
  var dryRun: Bool = false
  var logger: Logger = .default
  var installMethod: InstallMethod = .symlink
  let bootstrapTimeout: Duration = .seconds(10)
  let bootoutTimeout: Duration = .seconds(30)
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
      Logger.default.error("\(error)")
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
      logger.error("\(newPath.path) does not exist")
      exit(1)
    }
    self.newPath = newPath

    if args.count > 1 {
      let oldPath = URL(fileURLWithPath: args[1]).standardized.resolvingSymlinksInPath()
      self.oldPath = oldPath
    }
  }

  func printUsage() {
    var stderr = StandardErrorStream()
    print("usage: launchd-activate [--system | --user | --user-all] NEW [OLD]", to: &stderr)
  }

  func printVersion() {
    print(version)
  }

  func run() throws -> Int32 {
    var plan = Plan(
      logger: logger,
      installMethod: installMethod,
      bootstrapTimeout: bootstrapTimeout,
      bootoutTimeout: bootoutTimeout
    )
    plan.prepare(
      domain: domain,
      serviceDirectory: serviceDirectory,
      newPath: newPath,
      oldPath: oldPath
    )
    let executionErrors = try plan.execute(dryRun: dryRun)
    return Int32(executionErrors)
  }
}

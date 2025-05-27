import Foundation

let version = "0.0.0"

@main
struct Command {
  var domain: DomainTarget = .currentGUI
  var launchServicePath: LaunchServicePath = .currentUser
  var dryRun: Bool = false
  var installMethod: LaunchServicePath.InstallMethod = .symlink
  var timeout: Duration = .seconds(30)
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
    var stderr = StandardErrorStream()

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
        case "--system":
          self.domain = .system
          self.launchServicePath = .system
          self.installMethod = .copy
        case "--user":
          self.domain = .currentGUI
          self.launchServicePath = .currentUser
        case "--user-all":
          self.domain = .currentGUI
          self.launchServicePath = .allUsers
          self.installMethod = .copy
        case "--copy":
          self.installMethod = .copy
        case "--symlink":
          self.installMethod = .symlink
        default:
          printUsage()
          print("error: unknown option: \(arg)", to: &stderr)
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
      print("error: \(newPath) does not exist", to: &stderr)
      exit(1)
    }
    self.newPath = newPath

    if args.count > 1 {
      let oldPath = URL(fileURLWithPath: args[1]).standardized.resolvingSymlinksInPath()
      if FileManager.default.fileExists(atPath: oldPath.path) == false {
        printUsage()
        print("error: \(oldPath) does not exist", to: &stderr)
        exit(1)
      }
      self.oldPath = oldPath
    }
  }

  var launchctl: Launchctl { Launchctl(dryRun: dryRun) }

  func printUsage() {
    print("usage: launchd-activate [--system | --user | --user-all] NEW [OLD]")
  }

  func printVersion() {
    print(version)
  }

  func run() throws -> Int32 {
    let newServices = try readServices(in: self.newPath)

    var oldServices: Set<ServiceTarget> = []
    if let oldPath = self.oldPath {
      oldServices = try readServices(in: oldPath)
    }

    let addedServices = newServices.subtracting(oldServices)
    let removedServices = oldServices.subtracting(newServices)
    let changedServices = newServices.intersection(oldServices)

    let bootoutServices = removedServices.union(changedServices)
    let bootstrapServices = addedServices.union(changedServices)

    let uninstallServices = removedServices
    let installServices = addedServices.union(changedServices)

    var stderr = StandardErrorStream()
    var exitCode: Int32 = 0

    for service in uninstallServices {
      do {
        try self.launchServicePath.uninstall(label: service.label, dryRun: dryRun)
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    for service in installServices {
      do {
        try self.launchServicePath.install(
          label: service.label,
          sourcePath: self.newPath.appendingPathComponent(service.label).appendingPathExtension(
            "plist"),
          method: installMethod,
          dryRun: dryRun
        )
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    for service in bootoutServices {
      do {
        if launchctl.loadState(service: service) == true {
          try launchctl.bootout(service: service)
        }
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    for service in bootoutServices {
      do {
        try launchctl.waitForLoadState(service: service, loaded: false, timeout: self.timeout)
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    for service in bootstrapServices {
      do {
        try launchctl.bootstrap(
          domain: service.domain,
          path: self.launchServicePath.plist(label: service.label)
        )
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    for service in bootstrapServices {
      do {
        try launchctl.waitForLoadState(service: service, loaded: true, timeout: self.timeout)
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    return exitCode
  }

  func readServices(in directory: URL) throws -> Set<ServiceTarget> {
    let contents = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    var services: Set<ServiceTarget> = []
    for url in contents {
      guard url.pathExtension == "plist" else { continue }
      services.insert(domain.service(path: url))
    }
    return services
  }
}

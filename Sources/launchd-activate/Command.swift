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
    let newLabels = try plistFilenames(in: self.newPath)

    var oldLabels: Set<String> = []
    if let oldPath = self.oldPath {
      oldLabels = try plistFilenames(in: oldPath)
    }

    let addedLabels = newLabels.subtracting(oldLabels)
    let removedLabels = oldLabels.subtracting(newLabels)
    let changedLabels = newLabels.intersection(oldLabels)

    let bootoutServices = removedLabels.union(changedLabels).map { domain.service(label: $0) }
    let bootstrapServices = addedLabels.union(changedLabels).map { domain.service(label: $0) }

    let uninstallLabels = removedLabels
    let installLabels = addedLabels.union(changedLabels)

    var stderr = StandardErrorStream()
    var exitCode: Int32 = 0

    for label in uninstallLabels {
      do {
        try self.launchServicePath.uninstall(label: label, dryRun: dryRun)
      } catch {
        print("\(error)", to: &stderr)
        exitCode += 1
      }
    }

    for label in installLabels {
      do {
        try self.launchServicePath.install(
          label: label,
          sourcePath: self.newPath.appendingPathComponent(label).appendingPathExtension("plist"),
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

  func plistFilenames(in directory: URL) throws -> Set<String> {
    let contents = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    var labels: Set<String> = []
    for url in contents {
      guard url.pathExtension == "plist" else { continue }
      labels.insert(url.deletingPathExtension().lastPathComponent)
    }
    return labels
  }
}

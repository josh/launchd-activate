import Foundation

struct Plan {
  let logger: Logger

  var enableServicePaths: [ServicePath: ServicePath] = [:]
  var disableServicePaths: Set<ServicePath> = []

  var bootstrapServices: [ServiceTarget: ServicePath] = [:]
  var bootoutServices: Set<ServiceTarget> = []
}

extension Plan {
  mutating func prepare(
    domain: DomainTarget,
    serviceDirectory: ServiceDirectory,
    newPath: URL,
    oldPath: URL?
  ) {
    let launchctl = Launchctl(logger: logger, dryRun: true)

    let newServicePaths = readServicePaths(in: newPath)

    var oldServicePaths: [String: ServicePath]
    if let oldPath = oldPath {
      oldServicePaths = readServicePaths(in: oldPath)
    } else {
      oldServicePaths = [:]
    }

    let addedServicePaths = newServicePaths.filter { (name, servicePath) in
      !oldServicePaths.keys.contains(name)
    }

    let removedServicePaths = oldServicePaths.filter { (name, servicePath) in
      !newServicePaths.keys.contains(name)
    }

    let changedServicePaths = newServicePaths.filter { (name, servicePath) in
      oldServicePaths.keys.contains(name)
    }

    for (name, servicePath) in addedServicePaths {
      let service = servicePath.serviceTarget(domain: domain)
      let destinationServicePath = serviceDirectory.servicePath(name: name)

      if FileManager.default.fileExists(atPath: destinationServicePath.path) {
        logger.warn("\(destinationServicePath.path) already exists")
      }
      enableServicePaths[destinationServicePath] = servicePath

      if launchctl.loadState(service: service) == true {
        logger.warn("\(service) already loaded")
        bootoutServices.insert(service)
      }
      bootstrapServices[service] = destinationServicePath
    }

    for (name, servicePath) in removedServicePaths {
      let service = servicePath.serviceTarget(domain: domain)
      let destinationServicePath = serviceDirectory.servicePath(name: name)

      if !FileManager.default.fileExists(atPath: destinationServicePath.path) {
        logger.warn("\(destinationServicePath.path) does not exist")
      } else {
        disableServicePaths.insert(destinationServicePath)
      }

      if launchctl.loadState(service: service) == false {
        logger.warn("\(service) already unloaded")
      } else {
        bootoutServices.insert(service)
      }
    }

    for (name, servicePath) in changedServicePaths {
      let service = servicePath.serviceTarget(domain: domain)
      let destinationServicePath = serviceDirectory.servicePath(name: name)

      if !FileManager.default.fileExists(atPath: destinationServicePath.path) {
        logger.warn("\(destinationServicePath.path) does not exist")
      }
      enableServicePaths[destinationServicePath] = servicePath

      if launchctl.loadState(service: service) == false {
        logger.warn("\(service) not loaded")
      } else {
        bootoutServices.insert(service)
      }
      bootstrapServices[service] = destinationServicePath
    }
  }

  private func readServicePaths(in directory: URL) -> [String: ServicePath] {
    do {
      let urls = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      var servicePaths: [String: ServicePath] = [:]
      for url in urls {
        guard url.pathExtension == "plist" else { continue }
        let servicePath = ServicePath(url: url)
        servicePaths[servicePath.name] = servicePath
      }
      return servicePaths
    } catch {
      logger.error("Reading plists from \(directory): \(error)")
      return [:]
    }
  }

  func execute(dryRun: Bool, installMethod: InstallMethod, waitTimeout: Duration) throws -> Int {
    var executionErrors = 0

    let launchctl = Launchctl(logger: logger, dryRun: dryRun)
    let shellUtils = ShellUtils(dryRun: dryRun)

    var waitForServiceToLoad: Set<ServiceTarget> = Set()
    var waitForServiceToUnload: Set<ServiceTarget> = Set()

    for (destinationPath, sourcePath) in enableServicePaths {
      do {
        if installMethod == .symlink {
          try shellUtils.lnSymlink(
            sourceFile: sourcePath.path,
            targetFile: destinationPath.path,
            sudo: destinationPath.needsSudo,
            force: FileManager.default.fileExists(atPath: destinationPath.path)
          )
        } else {
          try shellUtils.cp(
            sourceFile: sourcePath.path,
            targetFile: destinationPath.path,
            sudo: destinationPath.needsSudo
          )
        }
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    for servicePath in disableServicePaths {
      do {
        try shellUtils.rm(file: servicePath.path, sudo: servicePath.needsSudo)
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    for service in bootoutServices {
      do {
        try launchctl.bootout(service: service)
        waitForServiceToUnload.insert(service)
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    for service in waitForServiceToUnload {
      do {
        try launchctl.waitForLoadState(
          service: service,
          loaded: false,
          timeout: waitTimeout
        )
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    for (service, servicePath) in bootstrapServices {
      do {
        try launchctl.bootstrap(domain: service.domain, path: servicePath)
        waitForServiceToLoad.insert(service)
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    for service in waitForServiceToLoad {
      do {
        try launchctl.waitForLoadState(
          service: service,
          loaded: true,
          timeout: waitTimeout
        )
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    return executionErrors
  }
}

extension Plan: CustomDebugStringConvertible {
  var debugDescription: String {
    var description = "Plan execution summary:\n"

    if !enableServicePaths.isEmpty {
      description += "\nFile operations (enable/install):\n"
      for (destinationPath, sourcePath) in enableServicePaths {
        description += "  • Install: \(sourcePath.path) → \(destinationPath.path)\n"
      }
    }

    if !disableServicePaths.isEmpty {
      description += "\nFile operations (disable/remove):\n"
      for servicePath in disableServicePaths {
        description += "  • Remove: \(servicePath.path)\n"
      }
    }

    if !bootoutServices.isEmpty {
      description += "\nServices to bootout (unload):\n"
      for service in bootoutServices {
        description += "  • Bootout: \(service)\n"
      }
    }

    if !bootstrapServices.isEmpty {
      description += "\nServices to bootstrap (load):\n"
      for (service, servicePath) in bootstrapServices {
        description += "  • Bootstrap: \(service) from \(servicePath.path)\n"
      }
    }

    let totalOperations =
      enableServicePaths.count + disableServicePaths.count + bootoutServices.count
      + bootstrapServices.count

    if totalOperations == 0 {
      description += "\nNo operations planned.\n"
    } else {
      description += "\nTotal operations: \(totalOperations)\n"
      description += "  - File installs: \(enableServicePaths.count)\n"
      description += "  - File removals: \(disableServicePaths.count)\n"
      description += "  - Service bootouts: \(bootoutServices.count)\n"
      description += "  - Service bootstraps: \(bootstrapServices.count)\n"
    }

    return description
  }
}

enum InstallMethod {
  case copy
  case symlink
}

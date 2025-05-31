import Foundation

struct Plan {
  let logger: Logger
  let installMethod: InstallMethod
  let bootstrapTimeout: Duration
  let bootoutTimeout: Duration

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
    logger.debug(
      "Preparing plan to activate from \(oldPath?.path ?? "/dev/null") to \(newPath.path)")

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
      let loaded = launchctl.loadState(service: service)
      let contentsEqual = compareFileContents(at: servicePath.url, and: destinationServicePath.url)

      if !FileManager.default.fileExists(atPath: destinationServicePath.path) {
        logger.warn("\(destinationServicePath.path) does not exist")
        assert(!contentsEqual)
      }

      switch installMethod {
      case .symlink:
        let destinationLink = readlink(destinationServicePath.url)
        logger.debug(
          "\(destinationServicePath.path) is a symlink to \(destinationLink?.path ?? "/dev/null")")
        if destinationLink == nil {
          enableServicePaths[destinationServicePath] = servicePath
        } else if destinationLink != servicePath.url {
          enableServicePaths[destinationServicePath] = servicePath
        }
      case .copy:
        if contentsEqual {
          logger.debug("\(destinationServicePath.path) has same contents as \(servicePath.path)")
        } else {
          enableServicePaths[destinationServicePath] = servicePath
        }
      }

      if contentsEqual && loaded {
        logger.debug("\(service) does not need to be restarted")
      } else if !loaded {
        logger.warn("\(service) not loaded")
        bootstrapServices[service] = destinationServicePath
      } else if loaded {
        bootoutServices.insert(service)
        bootstrapServices[service] = destinationServicePath
      }
    }

    logger.debug("\(debugDescription)")
  }

  private func readServicePaths(in directory: URL) -> [String: ServicePath] {
    do {
      let urls = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      var servicePaths: [String: ServicePath] = [:]
      for url in urls {
        guard url.pathExtension == "plist" else { continue }
        let servicePath = ServicePath(url: url.resolvingSymlinksInPath())
        servicePaths[servicePath.name] = servicePath
      }
      return servicePaths
    } catch {
      logger.error("Reading plists from \(directory.path): \(error)")
      return [:]
    }
  }

  private func compareFileContents(at url1: URL, and url2: URL) -> Bool {
    let data1 = try? Data(contentsOf: url1)
    let data2 = try? Data(contentsOf: url2)
    return data1 == data2
  }

  private func readlink(_ url: URL) -> URL? {
    let fileManager = FileManager.default
    do {
      let attr = try fileManager.attributesOfItem(atPath: url.path)
      guard attr[.type] as? FileAttributeType == .typeSymbolicLink else { return nil }
      let path = try fileManager.destinationOfSymbolicLink(atPath: url.path)
      return URL(fileURLWithPath: path)
    } catch {
      return nil
    }
  }

  func execute(dryRun: Bool) throws -> Int {
    logger.debug("Executing activation plan")

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
          timeout: bootoutTimeout
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
          timeout: bootstrapTimeout
        )
      } catch {
        logger.error("\(error)")
        executionErrors += 1
      }
    }

    logger.debug("Plan execution completed with \(executionErrors) errors")

    return executionErrors
  }
}

extension Plan: CustomDebugStringConvertible {
  var debugDescription: String {
    var description = "Plan execution summary:\n"

    if !enableServicePaths.isEmpty {
      description += "\nFile operations (enable/install):\n"
      for (destinationPath, sourcePath) in enableServicePaths {
        switch installMethod {
        case .symlink:
          description += "  • Symlink: \(destinationPath.path) → \(sourcePath.path)\n"
        case .copy:
          description += "  • Copy: \(sourcePath.path) → \(destinationPath.path)\n"
        }
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

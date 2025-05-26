import Foundation

enum LaunchServicePath: Equatable {
  case system
  case allUsers
  case user(URL)

  static var currentUser: Self {
    .user(FileManager.default.homeDirectoryForCurrentUser)
  }
}

extension LaunchServicePath {
  enum InstallMethod {
    case copy
    case symlink
  }
}

extension LaunchServicePath {
  var url: URL {
    switch self {
    case .system:
      return URL(fileURLWithPath: "/Library/LaunchDaemons")
    case .allUsers:
      return URL(fileURLWithPath: "/Library/LaunchAgents")
    case .user(let homeURL):
      return homeURL.appendingPathComponent("Library/LaunchAgents")
    }
  }

  var path: String { url.path }

  func plist(label: String) -> URL {
    url.appendingPathComponent(label).appendingPathExtension("plist")
  }

  var needsSudo: Bool {
    switch self {
    case .system:
      return true
    case .allUsers:
      return true
    case .user(_):
      return false
    }
  }
}

extension LaunchServicePath: CustomStringConvertible {
  var description: String { path }
}

extension LaunchServicePath {
  func install(
    label: String,
    sourcePath: URL,
    method: InstallMethod = .symlink,
    dryRun: Bool = false
  ) throws {
    let destination = plist(label: label)
    let shellUtils = ShellUtils(dryRun: dryRun)

    if method == .symlink {
      try shellUtils.lnSymlink(
        sourceFile: sourcePath.path,
        targetFile: destination.path,
        sudo: needsSudo,
        force: FileManager.default.fileExists(atPath: destination.path)
      )

      if dryRun == false {
        let realpath = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
        assert(realpath == sourcePath.path)
      }
    } else {
      try shellUtils.cp(sourceFile: sourcePath.path, targetFile: destination.path, sudo: needsSudo)

      if dryRun == false {
        assert(FileManager.default.fileExists(atPath: destination.path))
      }
    }
  }

  func uninstall(label: String, dryRun: Bool = false) throws {
    let path = plist(label: label)

    guard FileManager.default.fileExists(atPath: path.path) else {
      return
    }

    try ShellUtils(dryRun: dryRun).rm(file: path.path, sudo: needsSudo)

    assert(!FileManager.default.fileExists(atPath: path.path))
  }
}

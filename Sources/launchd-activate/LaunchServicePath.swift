import Foundation

enum LaunchServicePath {
  case system
  case allUsers
  case user(URL)

  static var currentUser: Self {
    return .user(FileManager.default.homeDirectoryForCurrentUser)
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
    url.appendingPathComponent("\(label).plist")
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
    dryRun: Bool = false,
  ) throws {
    let destination = plist(label: label)

    if method == .symlink {
      guard !dryRun else {
        let force = FileManager.default.fileExists(atPath: destination.path)
        printDryRun("ln", [force ? "-fs" : "-s", sourcePath.path, destination.path])
        return
      }

      if FileManager.default.fileExists(atPath: destination.path) {
        try? FileManager.default.removeItem(atPath: destination.path)
      }

      try FileManager.default.createSymbolicLink(
        atPath: destination.path,
        withDestinationPath: sourcePath.path
      )

      let realpath = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
      assert(realpath == sourcePath.path)

    } else {
      guard !dryRun else {
        printDryRun("cp", [sourcePath.path, destination.path])
        return
      }

      try FileManager.default.copyItem(at: sourcePath, to: destination)
      assert(FileManager.default.fileExists(atPath: destination.path))
    }
  }

  func uninstall(label: String, dryRun: Bool = false) throws {
    let path = plist(label: label)

    guard FileManager.default.fileExists(atPath: path.path) else {
      return
    }

    guard !dryRun else {
      printDryRun("rm", [path.path])
      return
    }

    try FileManager.default.removeItem(atPath: path.path)
    assert(!FileManager.default.fileExists(atPath: path.path))
  }
}

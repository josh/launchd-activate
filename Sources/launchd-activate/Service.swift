import Foundation
import SystemConfiguration

enum DomainTarget {
  case system
  case gui(uid_t)

  static var currentGUI: Self {
    var uid: uid_t = 0
    var gid: gid_t = 0
    if let user = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid),
      user as String != "loginwindow"
    {
      return .gui(uid)
    } else {
      return .gui(0)
    }
  }
}

extension DomainTarget: Hashable {}

extension DomainTarget {
  func service(path: ServicePath) -> ServiceTarget {
    ServiceTarget(domain: self, name: path.name)
  }
}

extension DomainTarget: CustomStringConvertible {
  var description: String {
    switch self {
    case .system:
      return "system"
    case .gui(let uid):
      return "gui/\(uid)"
    }
  }
}

struct ServiceTarget {
  let domain: DomainTarget
  let name: String

  init(domain: DomainTarget, name: String) {
    assert(!name.isEmpty)
    assert(!name.contains(" "))
    assert(!name.hasSuffix(".plist"))
    self.domain = domain
    self.name = name
  }
}

extension ServiceTarget: Hashable {}

extension ServiceTarget: CustomStringConvertible {
  var description: String {
    "\(domain)/\(name)"
  }
}

enum ServiceDirectory {
  case system
  case allUsers
  case user(URL)

  static var currentUser: Self {
    .user(FileManager.default.homeDirectoryForCurrentUser)
  }
}

extension ServiceDirectory {
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
}

extension ServiceDirectory: CustomStringConvertible {
  var description: String { url.path }
}

extension ServiceDirectory {
  func servicePath(name: String) -> ServicePath {
    let url = self.url.appendingPathComponent(name).appendingPathExtension("plist")
    return ServicePath(url: url)
  }
}

struct ServicePath {
  let url: URL

  init(url: URL) {
    assert(url.pathExtension == "plist", "expected .plist extension")
    self.url = url
  }
}

extension ServicePath: Hashable {}

extension ServicePath {
  var path: String { url.path }

  var name: String { url.deletingPathExtension().lastPathComponent }

  var needsSudo: Bool {
    return url.path.hasPrefix("/Library")
  }

  func serviceTarget(domain: DomainTarget) -> ServiceTarget {
    ServiceTarget(domain: domain, name: name)
  }
}

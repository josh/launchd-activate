import Foundation
import SystemConfiguration

enum DomainTarget {
  case system
  case gui(uid_t)

  static var currentGUI: Self {
    var uid: uid_t = 0
    var gid: gid_t = 0
    if let user = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid), user as String != "loginwindow" {
      return .gui(uid)
    } else {
      return .gui(0)
    }
  }
}

extension DomainTarget: Equatable {}

extension DomainTarget: Hashable {}

extension DomainTarget {
  func service(label: String) -> ServiceTarget {
    ServiceTarget(domain: self, label: label)
  }

  func service(path: URL) -> ServiceTarget {
    let label = path.deletingPathExtension().lastPathComponent
    return service(label: label)
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

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

extension DomainTarget {
  func service(label: String) -> ServiceTarget {
    return ServiceTarget(domain: self, label: label)
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

import Foundation

enum Logger: Int {
  case debug = 0
  case info = 1
  case warning = 2
  case error = 3

  static let `default` = Self.info
}

extension Logger: Comparable {
  static func < (lhs: Logger, rhs: Logger) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

extension Logger {
  func debug(_ message: String) {
    guard self <= .debug else { return }
    var stderr = StandardErrorStream()
    print("[DEBUG] \(message)", to: &stderr)
  }

  func info(_ message: String) {
    guard self <= .info else { return }
    var stderr = StandardErrorStream()
    print("[INFO] \(message)", to: &stderr)
  }

  func warn(_ message: String) {
    guard self <= .warning else { return }
    var stderr = StandardErrorStream()
    print("[WARN] \(message)", to: &stderr)
  }

  func error(_ message: String) {
    guard self <= .error else { return }
    var stderr = StandardErrorStream()
    print("[ERROR] \(message)", to: &stderr)
  }
}

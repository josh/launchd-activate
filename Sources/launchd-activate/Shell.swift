import Foundation

struct StandardErrorStream: TextOutputStream {
  func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}

func printXtrace(_ command: String, _ args: [String]) {
  var stderr = StandardErrorStream()
  print("+ \(command) \(shellEscape(args))", to: &stderr)
}

func printDryRun(_ command: String, _ args: [String]) {
  var stderr = StandardErrorStream()
  print("[DRY RUN] \(command) \(shellEscape(args))", to: &stderr)
}

func shellEscape(_ arguments: [String]) -> String {
  let unsafeChars = CharacterSet(charactersIn: "\"'`$&()|[]{}*?!<>;#~%").union(.whitespacesAndNewlines)
  return arguments.map { arg in
    if arg.isEmpty || arg.rangeOfCharacter(from: unsafeChars) != nil {
      return "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\""
    } else {
      return arg
    }
  }.joined(separator: " ")
}

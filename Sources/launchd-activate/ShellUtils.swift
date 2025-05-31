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
  let unsafeChars = CharacterSet(charactersIn: "\"'`$&()|[]{}*?!<>;#~%").union(
    .whitespacesAndNewlines)
  return arguments.map { arg in
    if arg.isEmpty || arg.rangeOfCharacter(from: unsafeChars) != nil {
      return "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\""
    } else {
      return arg
    }
  }.joined(separator: " ")
}

struct ShellUtils {
  var dryRun: Bool = false
}

extension ShellUtils {
  enum Error: Swift.Error {
    case nonZeroExit(code: Int32)
  }
}

extension ShellUtils {
  func lnSymlink(sourceFile: String, targetFile: String, sudo: Bool = false, force: Bool = false)
    throws
  {
    assert(sourceFile != targetFile)
    assert(FileManager.default.fileExists(atPath: sourceFile))

    let opts = force ? "-fs" : "-s"

    if dryRun == true {
      if sudo {
        printDryRun("sudo", ["ln", opts, sourceFile, targetFile])
      } else {
        printDryRun("ln", [opts, sourceFile, targetFile])
      }
      return
    }

    if sudo {
      printXtrace("sudo", ["ln", opts, sourceFile, targetFile])
    } else {
      printXtrace("ln", [opts, sourceFile, targetFile])
    }

    let process = Process()
    if sudo {
      process.executableURL = URL(fileURLWithPath: SUDO_PATH)
      process.arguments = ["--", LN_PATH, opts, sourceFile, targetFile]
    } else {
      process.executableURL = URL(fileURLWithPath: LN_PATH)
      process.arguments = [opts, sourceFile, targetFile]
    }

    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw Error.nonZeroExit(code: process.terminationStatus)
    }
  }

  func cp(sourceFile: String, targetFile: String, sudo: Bool = false) throws {
    assert(sourceFile != targetFile)
    assert(FileManager.default.fileExists(atPath: sourceFile))

    if dryRun == true {
      if sudo {
        printDryRun("sudo", ["cp", sourceFile, targetFile])
      } else {
        printDryRun("cp", [sourceFile, targetFile])
      }
      return
    }

    if sudo {
      printXtrace("sudo", ["cp", sourceFile, targetFile])
    } else {
      printXtrace("cp", [sourceFile, targetFile])
    }

    let process = Process()
    if sudo {
      process.executableURL = URL(fileURLWithPath: SUDO_PATH)
      process.arguments = ["--", CP_PATH, sourceFile, targetFile]
    } else {
      process.executableURL = URL(fileURLWithPath: CP_PATH)
      process.arguments = [sourceFile, targetFile]
    }

    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw Error.nonZeroExit(code: process.terminationStatus)
    }
  }

  func rm(file: String, sudo: Bool = false) throws {
    assert(FileManager.default.fileExists(atPath: file))

    if dryRun == true {
      if sudo {
        printDryRun("sudo", ["rm", file])
      } else {
        printDryRun("rm", [file])
      }
      return
    }

    if sudo {
      printXtrace("sudo", ["rm", file])
    } else {
      printXtrace("rm", [file])
    }

    let process = Process()
    if sudo {
      process.executableURL = URL(fileURLWithPath: SUDO_PATH)
      process.arguments = ["--", RM_PATH, file]
    } else {
      process.executableURL = URL(fileURLWithPath: RM_PATH)
      process.arguments = [file]
    }

    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw Error.nonZeroExit(code: process.terminationStatus)
    }
  }
}

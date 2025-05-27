import Foundation

struct ServiceTarget {
  let domain: DomainTarget
  let label: String

  init(domain: DomainTarget, label: String) {
    assert(!label.isEmpty)
    assert(!label.contains(" "))
    assert(!label.hasSuffix(".plist"))
    self.domain = domain
    self.label = label
  }
}

extension ServiceTarget: Equatable {}

extension ServiceTarget: Hashable {}

extension ServiceTarget: CustomStringConvertible {
  var description: String {
    "\(domain)/\(label)"
  }
}

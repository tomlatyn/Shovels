import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [ProviderSnapshot] = FakeData.snapshots()

    /// Monochrome menu bar text, such as "CC 47%  CX ?".
    var menuBarTitle: String {
        let now = Date.now
        return snapshots.map { snapshot in
            guard !snapshot.isStale(at: now), let percent = snapshot.windows.first?.usedPercent else {
                return "\(snapshot.provider.shortName) ?"
            }
            return "\(snapshot.provider.shortName) \(Int(percent))%"
        }
        .joined(separator: "  ")
    }
}

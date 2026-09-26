#if os(macOS)
import SwiftUI

/// Presents a view model in a utility window, persisting its frame in the supplied defaults.
/// Utility windows do not reopen at app launch; their view models belong to the current session.
@MainActor
public func utilityWindow<Nsp: ViewModelUINamespace>(
    _ namespace: Nsp.Type,
    defaults: UserDefaults
) -> some Scene {
    WindowGroup(id: Nsp.ViewModel.viewModelDefaultKey, for: UUID.self) { id in
        let content = WindowContentView<ViewModelUI<Nsp>>(id: id.wrappedValue)
        content.persistWindowFrame(key: content.frameKey, defaults: defaults)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commandsRemoved()
}
#endif

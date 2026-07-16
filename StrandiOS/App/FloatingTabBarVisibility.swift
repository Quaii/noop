#if os(iOS)
import SwiftUI

private struct SetFloatingTabBarHiddenKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Lets a pushed, immersive page hide the app's custom floating tab bar without coupling that
    /// page to `RootTabView` state. The default no-op keeps previews and other hosts independent.
    var setFloatingTabBarHidden: (Bool) -> Void {
        get { self[SetFloatingTabBarHiddenKey.self] }
        set { self[SetFloatingTabBarHiddenKey.self] = newValue }
    }
}
#endif

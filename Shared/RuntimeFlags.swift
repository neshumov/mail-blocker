import Foundation

enum RuntimeFlags {
    private static let defaults = UserDefaults(suiteName: AppGroup.id)
    private static let disableMessageSecurityKey = "disableMessageSecurityHandlerForTesting"

    static var disableMessageSecurityHandler: Bool {
        defaults?.bool(forKey: disableMessageSecurityKey) ?? false
    }

    static func setDisableMessageSecurityHandler(_ value: Bool) {
        defaults?.set(value, forKey: disableMessageSecurityKey)
    }
}

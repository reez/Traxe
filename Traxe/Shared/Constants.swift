import Foundation

enum AppConstants {
    enum AI {
        static let hotTemperatureThreshold: Double = 75.0
        static let coolTemperatureThreshold: Double = 60.0
        static let lowFanSpeedThreshold: Int = 80
        static let highVarianceThreshold: Double = 15.0
    }
}

enum AIFeatureFlags {
    static var isAvailable: Bool {
        if #available(iOS 18.0, macOS 15.0, *) { return true }
        return false
    }

    static var isEnabledByUser: Bool {
        UserDefaults.standard.bool(forKey: "ai_enabled")
    }

    static var foundationModelsAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return true
            }
        #endif
        return false
    }

    static var useFoundationModels: Bool {
        return foundationModelsAvailable && isEnabledByUser
    }
}

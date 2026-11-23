import Foundation
import Security

actor LocalStore {
    private let testing: Bool
    private let reset: Bool

    init(testing: Bool, reset: Bool) {
        self.testing = testing
        self.reset = reset
    }

    private func file() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let name = testing ? "AirFryerSheet-UITests" : "AirFryerSheet"
        var directory = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory.appendingPathComponent("state.json")
    }

    func load() throws -> AppState {
        let url = try file()
        if testing && reset && FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var state: AppState
        do {
            state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        } catch let readError as CocoaError where readError.code == .fileReadNoSuchFile {
            state = AppState()
        }
        if !testing { reconcileTrialStart(&state.entitlement) }
        return state
    }

    func write(_ state: AppState) throws {
        try JSONEncoder().encode(state).write(to: file(), options: .atomic)
    }

    private func reconcileTrialStart(_ entitlement: inout Entitlement) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.hgsldswk.airfryercheatsheet",
            kSecAttrAccount as String: "trial-start"
        ]
        var read = query
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        read[kSecReturnData as String] = true
        var output: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &output)
        let current = min(entitlement.firstOpen, entitlement.proStartedAt ?? entitlement.firstOpen)
        if status == errSecSuccess, let data = output as? Data,
           let text = String(data: data, encoding: .utf8), let seconds = TimeInterval(text),
           seconds.isFinite, seconds > 0 {
            let original = Date(timeIntervalSince1970: seconds)
            entitlement.firstOpen = min(original, current)
            entitlement.proStartedAt = entitlement.firstOpen
            if current < original {
                let bytes = Data(String(current.timeIntervalSince1970).utf8)
                SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
            }
        } else if status == errSecItemNotFound {
            var add = query
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecValueData as String] = Data(String(current.timeIntervalSince1970).utf8)
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

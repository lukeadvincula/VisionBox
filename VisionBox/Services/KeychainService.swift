//
//  KeychainService.swift
//  VisionBox
//

import Foundation
import Security

/// Minimal Keychain storage for the user's Gemini API key (bring your own key).
///
/// The key lives under an app-specific service identifier with device-only,
/// unlocked-only accessibility. It is never logged, never stored anywhere
/// else (UserDefaults, files, source), and never appears in error values —
/// failures carry only the OSStatus.
nonisolated struct KeychainService {

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private static let service = "Luke.VisionBox.gemini"
    private static let account = "gemini-api-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    /// Stores the API key, replacing any previously stored one.
    func saveAPIKey(_ key: String) throws {
        try deleteAPIKey()
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// The stored API key, or nil when none is stored.
    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.unexpectedStatus(errSecDecode)
            }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the stored API key. Succeeds when no key exists.
    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

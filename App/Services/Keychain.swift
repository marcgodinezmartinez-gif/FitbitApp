import Foundation
import Security
import HealthAPI

/// Llavero del iPhone: *tokens* de Google y claves de IA (nunca en ficheros ni en la BD).
struct Keychain: Sendable {
    let service: String

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func data(_ account: String) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func set(_ data: Data?, _ account: String) {
        SecItemDelete(base(account) as CFDictionary)
        guard let data else { return }
        var add = base(account)
        add[kSecValueData as String] = data
        // Disponible en segundo plano tras el primer desbloqueo y sin copia a otros dispositivos.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func string(_ account: String) -> String? { data(account).map { String(decoding: $0, as: UTF8.self) } }

    func setString(_ value: String?, _ account: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        set((trimmed?.isEmpty ?? true) ? nil : Data(trimmed!.utf8), account)
    }

    func removeAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// *Tokens* OAuth de Google en el Llavero.
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let keychain: Keychain
    private let account = "google.tokens"

    init(keychain: Keychain) { self.keychain = keychain }

    func load() async -> TokenSet? {
        guard let data = keychain.data(account) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(TokenSet.self, from: data)
    }

    func save(_ tokens: TokenSet) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        keychain.set(try? encoder.encode(tokens), account)
    }

    func clear() async { keychain.set(nil, account) }
}

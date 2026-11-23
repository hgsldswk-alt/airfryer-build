import CryptoKit
import Foundation

struct ShareFood: Codable, Equatable, Identifiable {
    var catalogID: String?
    var name: String
    var state: String
    var portion: String
    var settings: Settings

    var id: String { [catalogID ?? "", name, state, portion].joined(separator: "\u{1F}") }

    var valid: Bool {
        [name, state, portion].allSatisfy { value in
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            value.count <= ShareCode.fieldLimit && value.utf8.count <= ShareCode.fieldLimit * 4 &&
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        } && (catalogID.map { id in Foods.starter.contains { $0.id == id } } ?? true) && settings.valid
    }

    func asImportedFood() -> Food {
        Food(id: UUID().uuidString, group: .friend, customName: name, customPortion: portion,
             customState: state, defaults: settings, minC: settings.celsius, maxC: settings.celsius,
             minMinutes: settings.minutes, maxMinutes: settings.minutes)
    }
}

struct ShareCode: Codable, Equatable {
    static let prefix = "AF1:"
    static let fieldLimit = 50
    static let itemLimit = 3
    static let byteLimit = 8_192

    var version = 1
    var foods: [ShareFood]

    private enum Invalid: Error { case code }
    private var valid: Bool {
        version == 1 && (1...Self.itemLimit).contains(foods.count) &&
        Set(foods.map(\.id)).count == foods.count && foods.allSatisfy(\.valid)
    }

    private func json(sorted: Bool = false) throws -> Data {
        guard valid else { throw Invalid.code }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var value = self
        if sorted { value.foods.sort { $0.id < $1.id } }
        return try encoder.encode(value)
    }

    func encode() throws -> String {
        let body = try json().base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.prefix + body
    }

    static func decode(_ text: String) throws -> Self {
        guard text.utf8.count <= byteLimit else { throw Invalid.code }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix(prefix) else { throw Invalid.code }
        let body = cleaned.dropFirst(prefix.count)
        let alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !body.isEmpty, body.unicodeScalars.allSatisfy(alphabet.contains), body.count % 4 != 1 else {
            throw Invalid.code
        }
        let base64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { throw Invalid.code }
        let parsed = try JSONDecoder().decode(Self.self, from: data)
        guard parsed.valid else { throw Invalid.code }
        return parsed
    }

    func fingerprint() throws -> String {
        SHA256.hash(data: try json(sorted: true)).map { String(format: "%02x", $0) }.joined()
    }
}

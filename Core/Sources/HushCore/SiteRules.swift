import Foundation

/// Known password rules for websites, from Apple's password-manager-resources (MIT),
/// bundled so lookups work offline.
public enum SiteRules {
    public struct Match: Equatable, Sendable {
        /// The domain the rules are listed under (may be a parent of what was typed).
        public let domain: String
        public let rulesText: String
        public let rules: PasswordRules
    }

    /// Number of domains with known rules.
    public static var count: Int { table.count }

    /// Commit of apple/password-manager-resources the data comes from.
    public static var sourceCommit: String { PasswordRulesData.sourceCommit }

    /// Looks up rules for a domain or URL: "https://www.Example.com/login", "example.com" and
    /// "login.example.com" all match an entry for "example.com".
    public static func lookup(_ input: String) -> Match? {
        guard let host = normalizedHost(input) else { return nil }
        var labels = host.split(separator: ".").map(String.init)
        while labels.count >= 2 {
            let candidate = labels.joined(separator: ".")
            if let text = table[candidate] {
                return Match(domain: candidate, rulesText: text, rules: PasswordRules(parsing: text))
            }
            labels.removeFirst()
        }
        return nil
    }

    /// The bare host of a domain or URL, lowercased and without "www.". `nil` if it isn't one.
    public static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var host = URLComponents(string: text)?.host, host.contains(".") else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// Every listed domain (for tests and tooling).
    static var allDomainsForTesting: [String] { table.keys.sorted() }

    private static let table: [String: String] = {
        guard let data = PasswordRulesData.json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }()
}

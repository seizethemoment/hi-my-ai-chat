import Foundation

enum SidebarSearchHistoryStore {
    private static let key = "sidebar_recent_search_terms"
    private static let maximumItems = 12

    static func load() -> [String] {
        let values = UserDefaults.standard.stringArray(forKey: key) ?? []
        return values.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    @discardableResult
    static func record(_ term: String) -> [String] {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTerm.isEmpty == false else { return load() }

        var values = load().filter { $0.localizedCaseInsensitiveCompare(trimmedTerm) != .orderedSame }
        values.insert(trimmedTerm, at: 0)
        values = Array(values.prefix(maximumItems))
        UserDefaults.standard.set(values, forKey: key)
        return values
    }

    @discardableResult
    static func remove(_ term: String) -> [String] {
        let values = load().filter { $0.localizedCaseInsensitiveCompare(term) != .orderedSame }
        UserDefaults.standard.set(values, forKey: key)
        return values
    }
}

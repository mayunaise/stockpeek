import Foundation

struct StockGroup: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
}

struct WatchlistState: Codable {
    static let maximumCount = 500
    private(set) var ids: [String]
    var selectedID: String?
    var names: [String: String] = [:]
    var quoteIDs: [String: String] = [:]
    var kinds: [String: String] = [:]
    private(set) var groups: [StockGroup] = []
    private(set) var memberships: [String: [String]] = [:]
    var activeGroupID: String?
    var visibleIDs: [String] {
        guard let activeGroupID else { return ids }
        let members = Set(memberships[activeGroupID] ?? [])
        return ids.filter { members.contains($0) }
    }
    private var version = 2

    init(ids: [String]) {
        var seen = Set<String>()
        self.ids = ids.filter { seen.insert($0).inserted }
        selectedID = self.ids.first
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ids: try box.decode([String].self, forKey: .ids))
        names = try box.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        quoteIDs = try box.decodeIfPresent([String: String].self, forKey: .quoteIDs) ?? [:]
        kinds = try box.decodeIfPresent([String: String].self, forKey: .kinds) ?? [:]
        let decodedGroups = try box.decodeIfPresent([StockGroup].self, forKey: .groups) ?? []
        var groupIDs = Set<String>()
        groups = decodedGroups.filter { !$0.name.isEmpty && groupIDs.insert($0.id).inserted }
        memberships = try box.decodeIfPresent([String: [String]].self, forKey: .memberships) ?? [:]
        memberships = memberships.filter { groupIDs.contains($0.key) }.mapValues { Array(Set($0).intersection(ids)) }
        if let active = try box.decodeIfPresent(String.self, forKey: .activeGroupID), groupIDs.contains(active) { activeGroupID = active }
        let stored = try box.decodeIfPresent(String.self, forKey: .selectedID)
        if let stored, ids.contains(stored) { selectedID = stored }
    }

    @discardableResult mutating func add(_ id: String) -> Bool {
        guard !ids.contains(id), ids.count < Self.maximumCount else { return false }
        ids.insert(id, at: 0)
        if let activeGroupID { memberships[activeGroupID, default: []].append(id) }
        if selectedID == nil { selectedID = id }
        return true
    }

    mutating func remove(_ id: String) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        names.removeValue(forKey: id); quoteIDs.removeValue(forKey: id); kinds.removeValue(forKey: id)
        for group in groups { memberships[group.id]?.removeAll { $0 == id } }
        if selectedID == id { selectedID = ids.isEmpty ? nil : ids[min(index, ids.count - 1)] }
    }

    mutating func reorderStock(_ id: String, to target: String) {
        var visible = visibleIDs
        guard let from = visible.firstIndex(of: id), let to = visible.firstIndex(of: target), from != to else { return }
        visible.insert(visible.remove(at: from), at: to)
        let slots = Set(visible)
        var cursor = 0
        for index in ids.indices where slots.contains(ids[index]) {
            ids[index] = visible[cursor]; cursor += 1
        }
    }
    mutating func reorderGroup(_ id: String, to target: String) {
        guard let from = groups.firstIndex(where: { $0.id == id }), let to = groups.firstIndex(where: { $0.id == target }), from != to else { return }
        groups.insert(groups.remove(at: from), at: to)
    }

    mutating func moveToTop(_ id: String) {
        guard let index = ids.firstIndex(of: id), index > 0 else { return }
        ids.insert(ids.remove(at: index), at: 0)
    }

    mutating func move(_ id: String, by offset: Int) {
        guard let index = ids.firstIndex(of: id) else { return }
        let target = min(max(index + offset, 0), ids.count - 1)
        ids.swapAt(index, target)
    }

    @discardableResult mutating func createGroup(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 20, clean != "全部", !groups.contains(where: { $0.name == clean }) else { return false }
        groups.append(StockGroup(name: clean))
        return true
    }
    @discardableResult mutating func renameGroup(_ id: String, name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 20, clean != "全部", !groups.contains(where: { $0.id != id && $0.name == clean }), let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups[index].name = clean
        return true
    }
    mutating func moveGroupToTop(_ id: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }), index > 0 else { return }
        groups.insert(groups.remove(at: index), at: 0)
    }
    mutating func moveGroup(_ id: String, by offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), groups.count - 1)
        groups.insert(groups.remove(at: index), at: target)
    }
    mutating func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }; memberships.removeValue(forKey: id)
        if activeGroupID == id { activeGroupID = nil }
    }
    mutating func setMemberships(_ stockID: String, groups selected: Set<String>) {
        guard ids.contains(stockID) else { return }
        for group in groups {
            memberships[group.id, default: []].removeAll { $0 == stockID }
            if selected.contains(group.id) { memberships[group.id, default: []].append(stockID) }
        }
    }
    mutating func toggleMembership(_ stockID: String, groupID: String) {
        guard ids.contains(stockID), groups.contains(where: { $0.id == groupID }) else { return }
        if memberships[groupID, default: []].contains(stockID) { memberships[groupID]?.removeAll { $0 == stockID } }
        else { memberships[groupID, default: []].append(stockID) }
    }
    mutating func removeFromGroup(_ id: String, groupID: String) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        memberships[groupID]?.removeAll { $0 == id }
    }

    mutating func advance(paused: Bool, direction: Int = 1) {
        let eligible = visibleIDs
        guard !paused, !eligible.isEmpty else { return }
        guard let selectedID, let index = eligible.firstIndex(of: selectedID) else { self.selectedID = eligible.first; return }
        self.selectedID = eligible[(index + direction + eligible.count) % eligible.count]
    }
}

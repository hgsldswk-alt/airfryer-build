import Foundation

struct AppState: Codable, Equatable {
    var fryers: [Fryer]
    var activeFryerID: UUID
    var unit: TemperatureUnit
    var custom: [CustomFood] = []
    var pinned: [FoodKey]
    var recent: [FoodKey] = []
    var calibrations: [Calibration] = []
    var records: [CookRecord] = []
    var importKeys: Set<String> = []
    var review = CoreReviewProgress()
    var reviewedVersions: Set<String> = []
    var milestoneFryers: Set<UUID> = []
    var timer: CookTimer?
    var entitlement: Entitlement

    init(now: Date = .now, unit: TemperatureUnit = .regional) {
        let id = UUID()
        fryers = [Fryer(id: id)]
        activeFryerID = id
        self.unit = unit
        pinned = ["fries", "broccoli"].map { FoodKey(fryerID: id, foodID: $0) }
        entitlement = Entitlement(firstOpen: now)
    }

    private enum CodingKeys: String, CodingKey {
        case fryers, activeFryerID, unit, custom, pinned, recent, calibrations, records, importKeys
        case review, reviewedVersions, milestoneFryers, timer, entitlement
        case legacyReviewVersion = "reviewedVersion"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        fryers = try values.decodeIfPresent([Fryer].self, forKey: .fryers) ?? defaults.fryers
        if fryers.allSatisfy(\.archived) { fryers.append(Fryer(id: UUID())) }
        let selected = try values.decodeIfPresent(UUID.self, forKey: .activeFryerID)
        let visible = fryers.filter { !$0.archived }
        activeFryerID = visible.first { $0.id == selected }?.id ?? visible[0].id
        unit = try values.decodeIfPresent(TemperatureUnit.self, forKey: .unit) ?? defaults.unit
        custom = try values.decodeIfPresent([CustomFood].self, forKey: .custom) ?? []
        pinned = try values.decodeIfPresent([FoodKey].self, forKey: .pinned)
            ?? ["fries", "broccoli"].map { FoodKey(fryerID: activeFryerID, foodID: $0) }
        recent = try values.decodeIfPresent([FoodKey].self, forKey: .recent) ?? []
        calibrations = try values.decodeIfPresent([Calibration].self, forKey: .calibrations) ?? []
        records = try values.decodeIfPresent([CookRecord].self, forKey: .records) ?? []
        importKeys = try values.decodeIfPresent(Set<String>.self, forKey: .importKeys) ?? []
        review = try values.decodeIfPresent(CoreReviewProgress.self, forKey: .review) ?? CoreReviewProgress()
        reviewedVersions = try values.decodeIfPresent(Set<String>.self, forKey: .reviewedVersions) ?? []
        if let prior = try values.decodeIfPresent(String.self, forKey: .legacyReviewVersion) {
            reviewedVersions.insert(prior)
        }
        milestoneFryers = try values.decodeIfPresent(Set<UUID>.self, forKey: .milestoneFryers) ?? []
        timer = try values.decodeIfPresent(CookTimer.self, forKey: .timer)
        entitlement = try values.decodeIfPresent(Entitlement.self, forKey: .entitlement) ?? defaults.entitlement
    }

    var fryer: Fryer { fryers.first { $0.id == activeFryerID } ?? Fryer(id: activeFryerID) }

    func foods(in id: UUID) -> [Food] {
        Foods.starter + custom.filter { $0.fryerID == id }.map(\.food)
    }

    func food(_ id: String, in fryerID: UUID) -> Food? { foods(in: fryerID).first { $0.id == id } }

    func key(for food: Food, portion: String = "") -> FoodKey {
        FoodKey(fryerID: activeFryerID, foodID: food.id, portion: portion)
    }

    func primaryKey(for food: Food, fryer: UUID? = nil) -> FoodKey {
        let id = fryer ?? activeFryerID
        return calibrations.last { $0.key.fryerID == id && $0.key.foodID == food.id }?.key
            ?? FoodKey(fryerID: id, foodID: food.id)
    }

    func calibration(_ key: FoodKey) -> Calibration? { calibrations.first { $0.key == key } }

    func settings(for food: Food, at key: FoodKey) -> Settings {
        calibration(key)?.settings ?? food.defaults
    }

    var preferred: [Food] {
        var seen = Set<String>()
        let list = pinned + recent
        return list.filter { $0.fryerID == activeFryerID && seen.insert($0.foodID).inserted }
            .compactMap { food($0.foodID, in: activeFryerID) }
            .prefix(4).map { $0 }
    }

    mutating func remember(_ key: FoodKey) {
        recent.removeAll { $0 == key }
        recent.insert(key, at: 0)
        recent = Array(recent.prefix(60))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fryers, forKey: .fryers)
        try values.encode(activeFryerID, forKey: .activeFryerID)
        try values.encode(unit, forKey: .unit)
        try values.encode(custom, forKey: .custom)
        try values.encode(pinned, forKey: .pinned)
        try values.encode(recent, forKey: .recent)
        try values.encode(calibrations, forKey: .calibrations)
        try values.encode(records, forKey: .records)
        try values.encode(importKeys, forKey: .importKeys)
        try values.encode(review, forKey: .review)
        try values.encode(reviewedVersions, forKey: .reviewedVersions)
        try values.encode(milestoneFryers, forKey: .milestoneFryers)
        try values.encodeIfPresent(timer, forKey: .timer)
        try values.encode(entitlement, forKey: .entitlement)
    }

    mutating func finish(_ session: CookTimer, settings: Settings, portion: String, note: String,
                         save: Bool, at date: Date) -> Bool {
        guard timer?.id == session.id, !records.contains(where: { $0.id == session.id }) else { return false }
        var key = session.key
        let ownBefore = Set(calibrations.filter { $0.key.fryerID == key.fryerID }.map { $0.key.foodID })
        if save {
            if let index = custom.firstIndex(where: { $0.fryerID == key.fryerID && $0.food.id == key.foodID }),
               custom[index].food.group == .friend {
                if let original = custom[index].originalID {
                    key.foodID = original
                } else {
                    var promoted = custom[index].food
                    promoted.group = .custom
                    promoted.defaults = settings
                    custom[index].food = promoted
                }
            }
            let input = String(portion.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ShareCode.fieldLimit))
            let imported = session.food.group == .friend
            let baseFood = food(key.foodID, in: key.fryerID) ?? session.food
            let prior = calibration(key)?.portion ?? (imported && session.portion != baseFood.portion ? session.portion : "")
            let savedPortion = input.isEmpty ? prior : (input == baseFood.portion ? "" : input)
            key.portion = savedPortion.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            calibrations.removeAll { $0.key == key }
            calibrations.append(Calibration(key: key, settings: settings, portion: savedPortion, note: String(note.prefix(300))))
        }
        records.append(CookRecord(id: session.id, key: key, name: session.food.name,
                                  settings: settings, completedAt: date))
        let wasThird = save && ownBefore.count == 2 && !ownBefore.contains(key.foodID) &&
            milestoneFryers.insert(key.fryerID).inserted
        review.record(at: date)
        timer = nil
        return wasThird
    }

    mutating func addCard(_ card: ShareCode, to id: UUID) throws -> Bool {
        let key = id.uuidString + ":" + (try card.fingerprint())
        guard !importKeys.contains(key), fryers.contains(where: { $0.id == id && !$0.archived }) else { return false }
        for entry in card.foods {
            let original = entry.catalogID ?? foods(in: id).first {
                $0.group != .friend && $0.name.compare(entry.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }?.id
            let imported = entry.asImportedFood()
            custom.append(CustomFood(fryerID: id, food: imported, originalID: original))
        }
        importKeys.insert(key)
        return true
    }
}

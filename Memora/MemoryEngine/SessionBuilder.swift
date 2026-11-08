import Foundation

/// What the learner asked to study.
struct SessionRequest: Identifiable, Equatable {
    var id: UUID = UUID()
    var mode: StudyMode
    var subjectID: UUID? = nil
    var itemIDs: [UUID]? = nil
    var experimentID: UUID? = nil
    var experimentCondition: ExperimentCondition? = nil
    var experimentPhase: ExperimentPhase? = nil
    var palaceID: UUID? = nil
    var limit: Int? = nil
    var examMinutes: Int? = nil

    /// Pretests and experiment practice never feed FSRS (keeps comparisons clean).
    var countsForScheduling: Bool {
        if mode == .pretest { return false }
        if mode == .experiment && experimentPhase != .test { return false }
        return true
    }
}

/// Chooses which items to study, in which order and in which format.
/// Deterministic for a given database, time and random seed.
struct SessionBuilder {
    let scheduler: FSRSScheduler
    let settings: AppSettings
    let now: Date
    var calendar: Calendar = .current

    // MARK: Priority

    func isDue(_ item: LearningItem) -> Bool {
        !item.isSuspended && scheduler.isDue(item.card, at: now)
    }

    /// Higher = more urgent. Items whose predicted recall is closest to or below the
    /// desired retention ("predicted forgetting point") come first.
    func urgency(_ item: LearningItem) -> Double {
        let r = scheduler.retrievability(of: item.card, at: now)
        let overdueDays = max(0, now.timeIntervalSince(item.card.due) / 86_400)
        let intraDay = (item.card.state == .learning || item.card.state == .relearning) ? 0.2 : 0
        return (scheduler.parameters.desiredRetention - r) + min(overdueDays, 30) * 0.005 + intraDay
    }

    // MARK: Selection

    func selectItems(for request: SessionRequest, in db: AppDatabase, excluded: Set<UUID>, rng: inout SeededGenerator) -> [LearningItem] {
        let limit = max(1, request.limit ?? settings.sessionSize)
        if let ids = request.itemIDs {
            let byID = Dictionary(db.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return ids.compactMap { byID[$0] }
        }
        let pool = db.items.filter {
            !$0.isSuspended && !excluded.contains($0.id) && (request.subjectID == nil || $0.subjectID == request.subjectID)
        }
        let introduced = pool.filter(\.isIntroduced)
        let desired = scheduler.parameters.desiredRetention

        switch request.mode {
        case .smartReview:
            var result = introduced.filter(isDue).sorted { urgency($0) > urgency($1) }
            if result.count < limit {
                let near = introduced.filter {
                    !isDue($0) && $0.card.state == .review && scheduler.retrievability(of: $0.card, at: now) < desired + 0.03
                }.sorted { urgency($0) > urgency($1) }
                result.append(contentsOf: near)
            }
            return Array(result.prefix(limit))
        case .remember:
            let due = introduced.filter(isDue).sorted { urgency($0) > urgency($1) }
            let rest = introduced.filter { !isDue($0) }.sorted { urgency($0) > urgency($1) }
            return Array((due + rest).prefix(limit))
        case .quickDaily:
            return Array(introduced.sorted { urgency($0) > urgency($1) }.prefix(min(limit, 8)))
        case .deepUnderstanding:
            return Array(introduced.sorted {
                ($0.profile.tally(.conceptual).rate ?? 0, $0.card.stability) < ($1.profile.tally(.conceptual).rate ?? 0, $1.card.stability)
            }.prefix(limit))
        case .exam:
            return Array(introduced.sorted { $0.id.uuidString < $1.id.uuidString }.shuffled(using: &rng).prefix(limit))
        case .memoryRescue:
            return Array(introduced.filter {
                $0.card.lapses >= 2 || $0.profile.failureCount >= 2
                    || MemoryStateClassifier.state(of: $0, scheduler: scheduler, now: now) == .weak
            }.sorted { ($0.profile.failureCount + $0.card.lapses) > ($1.profile.failureCount + $1.card.lapses) }.prefix(limit))
        case .longTerm:
            let cutoff = now.addingTimeInterval(-30 * 86_400)
            return Array(introduced.filter {
                $0.card.state == .review && (($0.card.lastReview ?? now) <= cutoff || $0.card.stability >= 30)
            }.sorted { ($0.card.lastReview ?? now) < ($1.card.lastReview ?? now) }.prefix(limit))
        case .successiveRelearning:
            return Array(introduced.filter {
                $0.profile.distinctSuccessfulDays < MemoryStateClassifier.masterySessions && !$0.profile.hasSuccess(on: now, calendar: calendar)
            }.sorted { urgency($0) > urgency($1) }.prefix(limit))
        case .transfer:
            return Array(introduced.filter { !$0.transferProblems.isEmpty }.sorted {
                ($0.profile.tally(.far).rate ?? 0) + ($0.profile.tally(.near).rate ?? 0)
                    < ($1.profile.tally(.far).rate ?? 0) + ($1.profile.tally(.near).rate ?? 0)
            }.prefix(limit))
        case .pretest:
            return Array(pool.filter { $0.card.state == .new && $0.pretestedAt == nil }
                .sorted { $0.createdAt < $1.createdAt }.prefix(limit))
        case .learn:
            return orderedNewItems(pool: pool, links: db.links, limit: remainingNewAllowance(db: db))
        case .blindRecall, .palaceWalk, .experiment:
            return []
        }
    }

    /// Cognitive-load guard: new material per day is capped.
    func remainingNewAllowance(db: AppDatabase) -> Int {
        let introducedToday = db.items.filter { item in
            guard let date = item.introducedAt else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        }.count
        return max(0, settings.dailyNewLimit - introducedToday)
    }

    /// New items ordered so prerequisites come first (Kahn's algorithm), stable by creation date.
    func orderedNewItems(pool: [LearningItem], links: [ConceptLink], limit: Int) -> [LearningItem] {
        let fresh = pool.filter { $0.card.state == .new }.sorted { $0.createdAt < $1.createdAt }
        let ids = Set(fresh.map(\.id))
        var indegree: [UUID: Int] = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, 0) })
        var dependents: [UUID: [UUID]] = [:]
        for link in links where link.kind == .prerequisite && ids.contains(link.fromID) && ids.contains(link.toID) {
            indegree[link.toID, default: 0] += 1
            dependents[link.fromID, default: []].append(link.toID)
        }
        let order = Dictionary(uniqueKeysWithValues: fresh.enumerated().map { ($0.element.id, $0.offset) })
        var ready = fresh.filter { (indegree[$0.id] ?? 0) == 0 }.map(\.id)
        var result: [UUID] = []
        while !ready.isEmpty {
            ready.sort { (order[$0] ?? 0) < (order[$1] ?? 0) }
            let next = ready.removeFirst()
            result.append(next)
            for dependent in dependents[next] ?? [] {
                indegree[dependent, default: 0] -= 1
                if indegree[dependent] == 0 { ready.append(dependent) }
            }
        }
        let leftovers = fresh.map(\.id).filter { !result.contains($0) }
        let byID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        return (result + leftovers).compactMap { byID[$0] }.prefix(limit).map { $0 }
    }

    // MARK: Interleaving

    /// Interleaves related material only. Subjects joined by cross-subject links form one
    /// group; inside a group items rotate between clusters (subject + first tag/kind).
    /// Unrelated groups are kept in blocks rather than mixed randomly.
    func interleave(_ items: [LearningItem], links: [ConceptLink]) -> [LearningItem] {
        guard items.count > 2 else { return items }
        var parent: [UUID: UUID] = [:]
        func find(_ x: UUID) -> UUID {
            var root = x
            while let p = parent[root], p != root { root = p }
            return root
        }
        let subjectOfItem = Dictionary(items.map { ($0.id, $0.subjectID) }, uniquingKeysWith: { a, _ in a })
        for subject in Set(items.map(\.subjectID)) { parent[subject] = subject }
        for link in links {
            guard let a = subjectOfItem[link.fromID], let b = subjectOfItem[link.toID], a != b else { continue }
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        var groupOrder: [UUID] = []
        var groups: [UUID: [LearningItem]] = [:]
        for item in items {
            let g = find(item.subjectID)
            if groups[g] == nil { groupOrder.append(g) }
            groups[g, default: []].append(item)
        }
        return groupOrder.flatMap { roundRobin(groups[$0] ?? []) }
    }

    func roundRobin(_ items: [LearningItem]) -> [LearningItem] {
        var keys: [String] = []
        var clusters: [String: [LearningItem]] = [:]
        for item in items {
            let key = item.subjectID.uuidString + "|" + (item.tags.first ?? item.kind.rawValue)
            if clusters[key] == nil { keys.append(key) }
            clusters[key, default: []].append(item)
        }
        var result: [LearningItem] = []
        var index = 0
        while result.count < items.count {
            for key in keys {
                if let list = clusters[key], index < list.count { result.append(list[index]) }
            }
            index += 1
        }
        return result
    }

    // MARK: Formats

    /// Desirable difficulty: formats get harder as stability grows; never repeats the last format.
    func exerciseType(for item: LearningItem, mode: StudyMode, siblings: [LearningItem], comparison: LearningItem?, rng: inout SeededGenerator) -> ExerciseType {
        let candidates: [ExerciseType]
        switch mode {
        case .deepUnderstanding:
            candidates = [.elaboration, .selfExplanation, .explanation, .comparison]
        case .exam:
            candidates = [.shortAnswer, .multipleChoice, .cloze, .explanation, .transferNear, .freeRecall]
        case .memoryRescue:
            candidates = [.freeRecall, .cloze, .shortAnswer]
        case .longTerm:
            candidates = [.freeRecall]
        case .pretest:
            candidates = [.shortAnswer]
        case .transfer:
            let nearRate = item.profile.tally(.near).rate ?? 0
            candidates = nearRate >= 0.67 && item.transferProblems.contains(where: { $0.level == .far }) ? [.transferFar] : [.transferNear]
        case .successiveRelearning:
            candidates = [.shortAnswer, .freeRecall, .question]
        default:
            let s = item.card.stability
            if s < 2 {
                candidates = [.shortAnswer, .cloze, .multipleChoice, .image]
            } else if s < 10 {
                candidates = [.shortAnswer, .cloze, .reverse, .question, .image, .keyword]
            } else {
                candidates = [.freeRecall, .question, .explanation, .keyword, .reverse]
            }
        }
        var usable = candidates.filter { ExerciseFactory.canBuild($0, item: item, siblings: siblings, comparison: comparison) }
        if usable.count > 1, let last = item.profile.lastExerciseType { usable.removeAll { $0 == last } }
        return usable.randomElement(using: &rng) ?? .shortAnswer
    }

    /// Partner for comparison questions: a linked "contrasts with"/related item, else a sibling.
    func comparisonPartner(for item: LearningItem, in db: AppDatabase) -> LearningItem? {
        let linked = db.links.filter {
            ($0.kind == .contrastsWith || $0.kind == .related) && ($0.fromID == item.id || $0.toID == item.id)
        }.map { $0.fromID == item.id ? $0.toID : $0.fromID }
        if let id = linked.first, let other = db.items.first(where: { $0.id == id && $0.isIntroduced }) { return other }
        return db.items.first { $0.subjectID == item.subjectID && $0.id != item.id && $0.isIntroduced && $0.kind == item.kind }
    }

    // MARK: Build

    func buildExercises(for request: SessionRequest, in db: AppDatabase, excluded: Set<UUID>, rng: inout SeededGenerator) -> [Exercise] {
        if request.mode == .palaceWalk { return palaceExercises(request: request, db: db) }
        if request.mode == .experiment { return experimentExercises(request: request, db: db, rng: &rng) }

        var items = selectItems(for: request, in: db, excluded: excluded, rng: &rng)
        let interleavable: Set<StudyMode> = [.smartReview, .remember, .quickDaily, .exam, .memoryRescue, .longTerm, .deepUnderstanding, .successiveRelearning, .transfer]
        if settings.interleaving && interleavable.contains(request.mode) {
            items = interleave(items, links: db.links)
        }
        return items.map { item in
            let siblings = db.items.filter { $0.subjectID == item.subjectID && $0.id != item.id }
            let partner = comparisonPartner(for: item, in: db)
            let type = exerciseType(for: item, mode: request.mode, siblings: siblings, comparison: partner, rng: &rng)
            return ExerciseFactory.make(type, for: item, siblings: siblings, comparison: type == .comparison ? partner : nil, rng: &rng)
        }
    }

    private func palaceExercises(request: SessionRequest, db: AppDatabase) -> [Exercise] {
        guard let palace = db.palaces.first(where: { $0.id == request.palaceID }) else { return [] }
        return palace.loci.compactMap { locus in
            guard let id = locus.itemID, let item = db.items.first(where: { $0.id == id }) else { return nil }
            return ExerciseFactory.makePalace(for: item, locusName: locus.name)
        }
    }

    private func experimentExercises(request: SessionRequest, db: AppDatabase, rng: inout SeededGenerator) -> [Exercise] {
        guard let experiment = db.experiments.first(where: { $0.id == request.experimentID }) else { return [] }
        let byID = Dictionary(db.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if request.experimentPhase == .test {
            let ids = experiment.allItemIDs.sorted { $0.uuidString < $1.uuidString }.shuffled(using: &rng)
            return ids.compactMap { byID[$0] }.map { item in
                var ex = ExerciseFactory.make(.freeRecall, for: item, siblings: [], rng: &rng)
                ex.contextNote = (experiment.itemIDsA.contains(item.id) ? ExperimentCondition.a : .b).rawValue
                return ex
            }
        }
        guard let condition = request.experimentCondition else { return [] }
        let type = experiment.method(condition).exerciseType
        return experiment.itemIDs(condition).compactMap { byID[$0] }.map { item in
            let siblings = db.items.filter { $0.subjectID == item.subjectID && $0.id != item.id }
            var ex = ExerciseFactory.make(type, for: item, siblings: siblings, rng: &rng)
            if type == .restudy { ex.type = .restudy }
            ex.contextNote = condition.rawValue
            return ex
        }
    }
}

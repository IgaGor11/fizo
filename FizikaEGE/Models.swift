import Foundation

// MARK: - Кодификатор ФИПИ 2026: модели данных
// Всё локально, Codable, без сети.

enum FormulaLevel: String, Codable, CaseIterable {
    case basic = "базовый"
    case advanced = "повышенный"
    case high = "высокий"
}

struct SymbolInfo: Codable, Hashable {
    let meaning: String
    let unit: String
}

struct Formula: Codable, Identifiable, Hashable {
    let id: String
    let section: String
    let topic: String
    let title: String
    let latex: String
    let symbols: [String: SymbolInfo]
    let description: String
    let mnemonic: String
    let level: FormulaLevel

    var sectionKey: String { section }
}

struct FormulasBundle {
    static let sectionsOrder = [
        "Механика",
        "Молекулярная физика и термодинамика",
        "Электродинамика",
        "Оптика",
        "Квантовая физика"
    ]

    /// Последняя ошибка загрузки (для диагностики на экране, а не чёрного списка).
    static var lastError: String?

    static func load() -> [Formula] {
        lastError = nil
        guard let url = Bundle.main.url(forResource: "formulas", withExtension: "json") else {
            lastError = "formulas.json не найден в бандле"
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([Formula].self, from: data)
            if list.isEmpty { lastError = "formulas.json пуст" }
            return list
        } catch {
            lastError = "formulas.json не декодируется: \(error.localizedDescription)"
            return []
        }
    }

    /// Загрузка из бандла при разработке через XcodeGen (тот же Bundle.main).
    static func loadForTests(bundle: Bundle = .main) -> [Formula] {
        guard let url = bundle.url(forResource: "formulas", withExtension: "json") else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Formula].self, from: data)
        } catch { return [] }
    }
}

// MARK: - Прогресс по формуле (FSRS + уровни + статистика)

enum FormulaStatus: String, Codable {
    case untouched = "Не начато"
    case learning = "В процессе"
    case learned = "Выучено"
    case problem = "Проблемная"
}

struct DayResult: Codable {
    var date: Date      // начало дня
    var correct: Int
    var wrong: Int
}

struct ModeStats: Codable {
    var correct: Int = 0
    var total: Int = 0
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

struct FormulaProgress: Codable {
    var formulaId: String
    // FSRS
    var stability: Double = 0      // S, дни
    var difficulty: Double = 0     // D, 1...10
    var intervalDays: Double = 0
    var due: Date = Date()
    var reps: Int = 0
    var lapses: Int = 0
    // Уровни 1...10
    var level: Int = 1
    var streakCorrect: Int = 0
    // Статистика
    var totalAnswers: Int = 0
    var correctAnswers: Int = 0
    var totalTimeSec: Double = 0
    var byMode: [String: ModeStats] = [:]   // flashcards/choice/input/build
    var history: [DayResult] = []
    var lastGrade: Int = 0

    var accuracy: Double {
        totalAnswers == 0 ? 0 : Double(correctAnswers) / Double(totalAnswers)
    }
    var avgTime: Double {
        totalAnswers == 0 ? 0 : totalTimeSec / Double(totalAnswers)
    }
    var status: FormulaStatus {
        if totalAnswers == 0 { return .untouched }
        if lapses >= 4 && accuracy < 0.6 { return .problem }
        if level >= 7 && accuracy >= 0.85 { return .learned }
        return .learning
    }

    mutating func record(date: Date, correct: Bool, mode: String, timeSec: Double) {
        totalAnswers += 1
        totalTimeSec += timeSec
        if correct { correctAnswers += 1 }
        var m = byMode[mode] ?? ModeStats()
        m.total += 1
        if correct { m.correct += 1 }
        byMode[mode] = m
        let day = Calendar.current.startOfDay(for: date)
        if let i = history.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            if correct { history[i].correct += 1 } else { history[i].wrong += 1 }
        } else {
            history.append(DayResult(date: day, correct: correct ? 1 : 0, wrong: correct ? 0 : 1))
        }
        history = Array(history.suffix(60))
    }
}

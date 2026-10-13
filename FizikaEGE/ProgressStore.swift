import Foundation
import Combine

// MARK: - ProgressStore: единый MVVM-источник правды
// Хранит формулы, FSRS-прогресс, XP, streak, активность. Персистентность —
// локальный JSON в Documents (работает с iOS 16, без SwiftData/CoreData).
// Полностью офлайн.

enum TrainMode: String, Codable, CaseIterable {
    case flashcards = "flashcards"
    case choice = "choice"
    case input = "input"
    case build = "build"
    var title: String {
        switch self {
        case .flashcards: return "Карточки"
        case .choice: return "Выбор из 4"
        case .input: return "Ручной ввод"
        case .build: return "Сборка"
        }
    }
}

struct DayActivity: Codable {
    var date: Date
    var answers: Int
    var seconds: Double
}

struct Achievement: Identifiable, Codable {
    var id: String
    var title: String
    var date: Date
    var seen: Bool = false
    var identity: String { id }
}

struct PersistedState: Codable {
    var progress: [String: FormulaProgress] = [:]
    var xp: Int = 0
    var activity: [DayActivity] = []
    var achievements: [Achievement] = []
    var studentName: String = ""
    var totalSeconds: Double = 0
}

final class ProgressStore: ObservableObject {
    @Published var formulas: [Formula] = []
    @Published var progress: [String: FormulaProgress] = [:]
    @Published var xp: Int = 0
    @Published var activity: [DayActivity] = []
    @Published var achievements: [Achievement] = []
    @Published var studentName: String = ""
    @Published var totalSeconds: Double = 0
    @Published var lastLevelUps: [String] = []
    @Published var loadError: String?

    private var saveCancellable: AnyCancellable?

    init(loadBundle: Bool = true) {
        if loadBundle {
            formulas = FormulasBundle.load()
            loadError = FormulasBundle.lastError
        }
        load()
        // Автосейв при изменениях (debounce)
        saveCancellable = Publishers.CombineLatest4($progress, $xp, $activity, $achievements)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    // Для SwiftUI Preview / тестов
    init(formulas: [Formula]) {
        self.formulas = formulas
    }

    // MARK: Persistence
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fizika-progress.json")
    }

    func save() {
        let state = PersistedState(progress: progress, xp: xp, activity: activity,
                                   achievements: achievements, studentName: studentName,
                                   totalSeconds: totalSeconds)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch { print("save error: \(error)") }
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            progress = state.progress; xp = state.xp; activity = state.activity
            achievements = state.achievements; studentName = state.studentName
            totalSeconds = state.totalSeconds
        } catch { /* первый запуск — пусто */ }
    }

    // MARK: Доступ
    func prog(_ id: String) -> FormulaProgress {
        progress[id] ?? FormulaProgress(formulaId: id)
    }

    // MARK: Ответ — единая точка: FSRS + уровень + XP + статистика
    /// grade: 1...4. Возвращает (levelUp, achievementIDs).
    @discardableResult
    func answer(formulaId: String, grade: Int, mode: TrainMode, timeSec: Double, now: Date = Date()) -> (levelUp: Bool, newAchievements: [String]) {
        var p = prog(formulaId)
        let correct = grade >= 3
        FSRS.review(progress: &p, grade: grade, now: now)
        let (up, _) = LevelSystem.apply(progress: &p, correct: correct)
        p.record(date: now, correct: correct, mode: mode.rawValue, timeSec: timeSec)
        // Уровень тянет интервал: сильные формулы живут дольше
        if correct && p.level >= 7 {
            let boost = LevelSystem.baseInterval(for: p.level)
            if p.intervalDays < boost {
                p.intervalDays = boost
                p.due = Calendar.current.date(byAdding: .day, value: Int(boost),
                                             to: Calendar.current.startOfDay(for: now)) ?? now
            }
        }
        progress[formulaId] = p
        // XP: база за повтор + бонус за правильный + бонус за высокую оценку
        let gained = 5 + (correct ? 5 : 0) + max(0, grade - 2) * 2 + (up ? 20 : 0)
        xp += gained
        // Активность дня
        let day = Calendar.current.startOfDay(for: now)
        if let i = activity.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            activity[i].answers += 1; activity[i].seconds += timeSec
        } else {
            activity.append(DayActivity(date: day, answers: 1, seconds: timeSec))
        }
        activity = Array(activity.suffix(365))
        totalSeconds += timeSec
        if up { lastLevelUps = [formulaId] }
        let newA = checkAchievements()
        save()
        objectWillChange.send()
        return (up, newA)
    }

    // MARK: Очередь повторений
    /// Формулы к повторению: due <= сегодня, сначала просроченные и слабые.
    func dueFormulas(scope: [Formula]? = nil, now: Date = Date()) -> [Formula] {
        let list = scope ?? formulas
        let today = Calendar.current.startOfDay(for: now)
        return list.filter { f in
            let p = prog(f.id)
            if p.totalAnswers == 0 { return true }
            return Calendar.current.startOfDay(for: p.due) <= today
        }.sorted { a, b in
            let pa = prog(a.id), pb = prog(b.id)
            if pa.due != pb.due { return pa.due < pb.due }
            return pa.level < pb.level
        }
    }

    func newFormulas(limit: Int = 20) -> [Formula] {
        formulas.filter { prog($0.id).totalAnswers == 0 }.prefix(limit).map { $0 }
    }

    /// Готовый список для сессии: сначала просроченные, затем остальные
    /// формулы области. Сессия покрывает ВСЕ формулы области.
    func sessionFormulas(scope: [Formula], limit: Int? = nil, now: Date = Date()) -> [Formula] {
        let due = dueFormulas(scope: scope, now: now)
        let dueIDs = Set(due.map(\.id))
        let rest = scope.filter { !dueIDs.contains($0.id) }.shuffled()
        let full = due + rest
        return Array(full.prefix(limit ?? full.count))
    }

    // MARK: Adaptive Mix — выбор режима по силе памяти
    func adaptiveMode(for formulaId: String) -> TrainMode {
        let p = prog(formulaId)
        if p.totalAnswers == 0 { return .flashcards }
        switch p.level {
        case 1...3:
            // Слабые — ручной ввод и сборка (глубокая обработка)
            return [.input, .build, .choice].randomElement() ?? .input
        case 4...6:
            return [.choice, .input, .flashcards].randomElement() ?? .choice
        default:
            // Сильные — быстрые карточки
            return [.flashcards, .choice].randomElement() ?? .flashcards
        }
    }

    // MARK: Статистика
    var totalCount: Int { formulas.count }
    var learnedCount: Int { formulas.filter { prog($0.id).status == .learned }.count }
    var learningCount: Int { formulas.filter { prog($0.id).status == .learning }.count }
    var untouchedCount: Int { formulas.filter { prog($0.id).status == .untouched }.count }
    var problemCount: Int { formulas.filter { prog($0.id).status == .problem }.count }
    var progressFraction: Double { totalCount == 0 ? 0 : Double(learnedCount) / Double(totalCount) }
    var avgLevel: Double {
        guard !formulas.isEmpty else { return 0 }
        return Double(formulas.map { prog($0.id).level }.reduce(0, +)) / Double(formulas.count)
    }
    var overallAccuracy: Double {
        let t = formulas.map { prog($0.id).totalAnswers }.reduce(0, +)
        guard t > 0 else { return 0 }
        let c = formulas.map { prog($0.id).correctAnswers }.reduce(0, +)
        return Double(c) / Double(t)
    }

    func stats(section: String) -> (fraction: Double, avgLevel: Double, problems: Int, total: Int) {
        let list = formulas.filter { $0.section == section }
        guard !list.isEmpty else { return (0, 0, 0, 0) }
        let learned = list.filter { prog($0.id).status == .learned }.count
        let probs = list.filter { prog($0.id).status == .problem }.count
        let avg = Double(list.map { prog($0.id).level }.reduce(0, +)) / Double(list.count)
        return (Double(learned) / Double(list.count), avg, probs, list.count)
    }

    func stats(topic: String) -> (fraction: Double, avgLevel: Double, topProblems: [Formula]) {
        let list = formulas.filter { $0.topic == topic }
        guard !list.isEmpty else { return (0, 0, []) }
        let learned = list.filter { prog($0.id).status == .learned }.count
        let avg = Double(list.map { prog($0.id).level }.reduce(0, +)) / Double(list.count)
        let probs = list.filter { prog($0.id).status != .untouched }
            .sorted { prog($0.id).accuracy < prog($1.id).accuracy }.prefix(3).map { $0 }
        return (Double(learned) / Double(list.count), avg, probs)
    }

    var topProblems: [Formula] {
        formulas.filter { prog($0.id).totalAnswers > 0 }
            .sorted { prog($0.id).accuracy < prog($1.id).accuracy }.prefix(10).map { $0 }
    }
    var topStrong: [Formula] {
        formulas.filter { prog($0.id).totalAnswers >= 3 }
            .sorted { prog($0.id).accuracy > prog($1.id).accuracy }.prefix(10).map { $0 }
    }

    // Streak: дней подряд с >=1 ответом
    var streakDays: Int {
        let days = Set(activity.filter { $0.answers > 0 }.map { Calendar.current.startOfDay(for: $0.date) })
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())
        if !days.contains(day) {
            // если сегодня ещё не занимались — считаем от вчера
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while days.contains(day) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    // MARK: Геймификация
    var userRank: String {
        switch xp {
        case 0..<200: return "Новичок"
        case 200..<600: return "Лаборант"
        case 600..<1500: return "Студент"
        case 1500..<3000: return "Инженер"
        case 3000..<6000: return "Кандидат наук"
        default: return "Профессор физики"
        }
    }
    var xpForNextRank: Int {
        let bounds = [200, 600, 1500, 3000, 6000]
        return bounds.first(where: { xp < $0 }) ?? 10000
    }

    @discardableResult
    private func checkAchievements() -> [String] {
        var fresh: [String] = []
        func grant(_ id: String, _ title: String, _ cond: Bool) {
            if cond && !achievements.contains(where: { $0.id == id }) {
                achievements.append(Achievement(id: id, title: title, date: Date()))
                fresh.append(id)
            }
        }
        grant("first10", "Первые 10 повторений", formulas.map { prog($0.id).totalAnswers }.reduce(0, +) >= 10)
        grant("learn50", "50 формул выучено", learnedCount >= 50)
        grant("learn100", "100 формул выучено", learnedCount >= 100)
        grant("streak7", "7 дней подряд", streakDays >= 7)
        grant("streak30", "30 дней подряд", streakDays >= 30)
        grant("expert", "Первая формула-эксперт (10)", formulas.contains { prog($0.id).level >= 10 })
        grant("xp1000", "1000 XP", xp >= 1000)
        return fresh
    }

    // MARK: Проверка ручного ввода
    /// Толерантное сравнение LaTeX: игнор пробелов, \\cdot/\\times/*, скобок,
    /// команд \\text, юникод-букв (Δ→\\Delta и т.п.), порядка слагаемых.
    /// Юникод-карта: что видит человек → что лежит в эталоне.
    static let uniMap: [String: String] = [
        "Δ": "\\Delta", "α": "\\alpha", "β": "\\beta", "γ": "\\gamma",
        "δ": "\\delta", "ε": "\\varepsilon", "η": "\\eta", "θ": "\\theta",
        "λ": "\\lambda", "μ": "\\mu", "ν": "\\nu", "π": "\\pi",
        "ρ": "\\rho", "σ": "\\sigma", "φ": "\\varphi", "ω": "\\omega",
        "τ": "\\tau", "Σ": "\\sum", "Φ": "\\Phi", "ℰ": "\\mathcal{E}",
        "→": "\\vec", "¯": "\\bar", "×": "*", "·": "*", "±": "\\pm", "√": "\\sqrt"
    ]

    static func checkInput(_ user: String, target: String) -> Bool {
        func norm(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            for (k, v) in uniMap { t = t.replacingOccurrences(of: k, with: v) }
            t = t.replacingOccurrences(of: "\\text", with: "")
            t = t.replacingOccurrences(of: "\\mathrm", with: "")
            t = t.replacingOccurrences(of: " ", with: "")
            t = t.replacingOccurrences(of: "\\cdot", with: "*")
            t = t.replacingOccurrences(of: "\\times", with: "*")
            t = t.replacingOccurrences(of: "\\,", with: "")
            t = t.replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
            t = t.replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            return t.lowercased()
        }
        let u = norm(user), v = norm(target)
        if u == v { return true }
        // Порядок слагаемых: разбиваем по '=' и '+'/'-' и сравниваем как множества
        func parts(_ s: String) -> [String] {
            s.replacingOccurrences(of: "-", with: "+-").split(separator: "+").map(String.init).sorted()
        }
        let us = u.split(separator: "=").map(String.init), vs = v.split(separator: "=").map(String.init)
        if us.count == 2 && vs.count == 2 {
            let leftOK = parts(us[0]) == parts(vs[0]) || parts(us[0]) == parts(vs[1])
            let rightOK = parts(us[1]) == parts(vs[1]) || parts(us[1]) == parts(vs[0])
            if leftOK && rightOK { return true }
        }
        return false
    }

    /// Часть формулы для режима «Выбор из 4»: всё после ПЕРВОГО «=».
    /// Название-левая часть прячется, внутренние «=» у многосоставных
    /// формул остаются (иначе от них ничего не останется).
    static func displayFormula(_ latex: String) -> String {
        guard let r = latex.range(of: "=") else { return latex }
        let tail = latex[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? latex : String(tail)
    }

    /// Обозначение-символ формулы: часть до первого «=» (показываем рядом
    /// с названием в вариантах ответа).
    static func symbolOf(_ latex: String) -> String {
        if let r = latex.range(of: "=") {
            let head = latex[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { return String(head) }
        }
        return latex
    }

    /// Блоки для режима сборки: только ЧЕЛОВЕЧЕСКИЕ знаки, никаких команд.
    /// Дробь идёт естественным порядком: числитель, черта «⁄», знаменатель.
    /// Проверка — точное совпадение порядка блоков с эталоном.
    static func buildTokens(for latex: String) -> [String] {
        var out: [String] = []
        let chars = Array(latex)
        var i = 0
        func skipSpaces() {
            while i < chars.count && chars[i] == " " { i += 1 }
        }
        /// Читает {...} с учётом вложенности, возвращает содержимое без скобок.
        func readGroup() -> String? {
            skipSpaces()
            guard i < chars.count && chars[i] == "{" else { return nil }
            i += 1
            var depth = 1
            let start = i
            while i < chars.count && depth > 0 {
                if chars[i] == "{" { depth += 1 }
                else if chars[i] == "}" { depth -= 1 }
                i += 1
            }
            guard depth == 0 else { return nil }
            return String(chars[start..<(i - 1)])
        }
        func emit(_ s: String) {
            if !s.trimmingCharacters(in: .whitespaces).isEmpty { out.append(s) }
        }
        func emitAll(_ innerLatex: String) {
            out.append(contentsOf: buildTokens(innerLatex))
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                i += 1
                var name = ""
                while i < chars.count && chars[i].isLetter { name.append(chars[i]); i += 1 }
                if name.isEmpty {
                    if i < chars.count { emit(String(chars[i])); i += 1 }
                    continue
                }
                switch name {
                case "frac":
                    // числитель → черта → знаменатель
                    if let num = readGroup(), let den = readGroup() {
                        emitAll(num)
                        emit("⁄")
                        emitAll(den)
                    } else {
                        emit("⁄")
                    }
                case "sqrt": emit("√")
                case "vec": emit("→")
                case "bar": emit("¯")
                case "text", "mathrm":
                    if let inner = readGroup() {
                        for ch in inner where ch != " " { emit(String(ch)) }
                    }
                case "mathcal":
                    if let inner = readGroup() {
                        emit(inner == "E" ? "ℰ" : inner)
                    } else {
                        emit(name)
                    }
                default:
                    if let g = MathParser.greek[name] { emit(g) }
                    else if let s = MathParser.symbols[name] { emit(s) }
                    else { emit(name) }
                }
            } else if c == "{" || c == "}" || c == " " || c == "&" || c == "\n" {
                i += 1 // служебное — не показываем
            } else if c == "_" {
                emit("˅"); i += 1
            } else if c == "^" {
                emit("˄"); i += 1
            } else {
                emit(String(c)); i += 1
            }
        }
        return out
    }
}

import SwiftUI

// MARK: - Slot-based сборка: формула — это дерево слотов, а не строка.
// Пользователь заполняет структурные гнёзда (числитель/знаменатель,
// индексы, ряд), а не выкладывает плоские токены в ряд.

// MARK: Роли чипов (цвет + подсказка)

enum LeafRole: String, CaseIterable {
    case value, number, op, relation, greek, function, constant

    var color: Color {
        switch self {
        case .value: return .blue
        case .number: return .teal
        case .op: return .orange
        case .relation: return .purple
        case .greek: return .cyan
        case .function: return .green
        case .constant: return .red
        }
    }

    var nameRU: String {
        switch self {
        case .value: return "величина"
        case .number: return "число"
        case .op: return "действие"
        case .relation: return "знак равенства"
        case .greek: return "греческая буква"
        case .function: return "функция"
        case .constant: return "константа"
        }
    }
}

// MARK: Дерево

struct BuildLeaf: Identifiable, Hashable {
    let id = UUID()
    let latex: String
    let role: LeafRole
}

indirect enum BuildNode {
    case row([BuildNode])
    case fraction(num: BuildNode, den: BuildNode)
    case scripts(base: BuildNode, sub: BuildNode?, sup: BuildNode?)
    case sqrt(radicand: BuildNode)
    case fixed(String)
    case leaf(BuildLeaf)

    /// Все листья в порядке обхода (in-order) — это и есть слоты.
    var leaves: [BuildLeaf] {
        switch self {
        case .row(let a): return a.flatMap { $0.leaves }
        case .fraction(let n, let d): return n.leaves + d.leaves
        case .scripts(let b, let s, let u): return b.leaves + (s?.leaves ?? []) + (u?.leaves ?? [])
        case .sqrt(let r): return r.leaves
        case .fixed: return []
        case .leaf(let l): return [l]
        }
    }
}

// MARK: Парсер LaTeX → дерево

enum BuildParser {
    static let funcCmds: Set<String> = ["sin", "cos", "tan", "ln", "log"]
    static let opCmds: Set<String> = ["pm", "cdot", "times", "div"]
    static let relCmds: Set<String> = ["approx", "neq", "leq", "geq"]
    static let greekCmds: Set<String> = ["alpha", "beta", "gamma", "Gamma", "delta", "Delta",
                                         "varepsilon", "epsilon", "zeta", "eta", "theta",
                                         "lambda", "mu", "nu", "pi", "rho", "sigma",
                                         "Phi", "phi", "varphi", "omega", "Omega", "tau"]
    static let constLetters: Set<String> = ["g", "c", "G", "e", "h", "k"]
    static let skipCmds: Set<String> = ["quad"]

    static func parse(_ latex: String) -> BuildNode {
        let s = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .row([]) }

        // 1. вся строка — дробь
        if s.hasPrefix("\\frac"),
           let g = readGroups(s, from: s.index(s.startIndex, offsetBy: 5), count: 2),
           g.rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return .fraction(num: parse(g.list[0]), den: parse(g.list[1]))
        }
        // 2. вся строка — корень
        if s.hasPrefix("\\sqrt"),
           let g = readGroups(s, from: s.index(s.startIndex, offsetBy: 5), count: 1),
           g.rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return .sqrt(radicand: parse(g.list[0]))
        }
        // 3. вся строка в скобках (...) или |...|
        if let inner = stripWrapped(s) {
            return .row([.fixed(String(s.prefix(1))), parse(inner), .fixed(String(s.suffix(1)))])
        }
        // 4. вся строка — атом \vec{} \bar{} \mathcal{} \text{}
        if s.hasPrefix("\\") {
            let (cmd, afterCmd) = readCommand(s, from: s.index(after: s.startIndex))
            if ["vec", "bar", "mathcal"].contains(cmd),
               let g = readGroups(s, from: afterCmd, count: 1),
               g.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return .leaf(BuildLeaf(latex: s, role: .value))
            }
            if cmd == "text" || cmd == "mathrm",
               let g = readGroups(s, from: afterCmd, count: 1),
               g.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return .leaf(BuildLeaf(latex: g.list[0], role: .value))
            }
        }
        // 5. \frac / \sqrt внутри выражения
        if let f = splitAround(s, command: "frac", groups: 2) {
            return assembleSplit(before: f.before, node: .fraction(num: parse(f.list[0]), den: parse(f.list[1])), after: f.after)
        }
        if let f = splitAround(s, command: "sqrt", groups: 1) {
            return assembleSplit(before: f.before, node: .sqrt(radicand: parse(f.list[0])), after: f.after)
        }
        // 6. индексы/степени на всю строку
        if let (node, rest) = matchScripts(s), rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return node
        }
        // 7. операторы верхнего уровня (= + - / \pm \cdot …) и запятые-разделители
        if let parts = splitTopLevel(s), parts.count > 1 {
            return .row(parts.map(parse))
        }
        // 8. индексы/степени с хвостом (I^2 R)
        if let (node, rest) = matchScripts(s) {
            let r = rest.trimmingCharacters(in: .whitespaces)
            if !r.isEmpty { return .row([node, parse(r)]) }
            return node
        }
        // 9. скобки (...) или |...| внутри выражения: m(g±a)
        if let b = splitWrappedMid(s) {
            var kids: [BuildNode] = []
            if !b.before.trimmingCharacters(in: .whitespaces).isEmpty { kids.append(parse(b.before)) }
            kids.append(.row([.fixed(b.open), parse(b.inner), .fixed(b.close)]))
            if !b.after.trimmingCharacters(in: .whitespaces).isEmpty { kids.append(parse(b.after)) }
            return kids.count == 1 ? kids[0] : .row(kids)
        }
        // 10. ведущий знак (-k …)
        if (s.hasPrefix("-") || s.hasPrefix("+")) && s.count > 1 {
            let sign = String(s.prefix(1))
            let rest = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                return .row([.leaf(BuildLeaf(latex: sign, role: .op)), parse(rest)])
            }
        }
        // 11. число в начале (2\pi R, 13,6, 100\%)
        if let d = s.first, d.isNumber {
            var j = s.startIndex
            while j < s.endIndex && (s[j].isNumber || s[j] == "," || s[j] == ".") { j = s.index(after: j) }
            let num = String(s[..<j])
            let rest = String(s[j...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return .leaf(BuildLeaf(latex: num, role: .number)) }
            return .row([.leaf(BuildLeaf(latex: num, role: .number)), parse(rest)])
        }
        // 12. префикс \команда
        if s.hasPrefix("\\") {
            // экраны \% и пробельные (\;, \,, \:, \!, \&, backslash-space)
            if let second = s.dropFirst().first, !second.isLetter {
                if second == "%" && s.count == 2 {
                    return .leaf(BuildLeaf(latex: "\\%", role: .number))
                }
                return parse(String(s.dropFirst(2)))
            }
            let (cmd, afterCmd) = readCommand(s, from: s.index(after: s.startIndex))
            if skipCmds.contains(cmd) {
                return parse(String(s[afterCmd...]))
            }
            // \text{X} или \vec{X} в середине строки: атом + разбор хвоста
            if cmd == "text" || cmd == "mathrm",
               let g = readGroups(s, from: afterCmd, count: 1) {
                let tail = g.rest.trimmingCharacters(in: .whitespaces)
                let head = BuildNode.leaf(BuildLeaf(latex: g.list[0], role: .value))
                if tail.isEmpty { return head }
                return .row([head, parse(tail)])
            }
            if ["vec", "bar", "mathcal"].contains(cmd),
               let g = readGroups(s, from: afterCmd, count: 1) {
                let nx = s.index(s.endIndex, offsetBy: -g.rest.count)
                let whole = String(s[s.startIndex..<nx])
                let tail = g.rest.trimmingCharacters(in: .whitespaces)
                let head = BuildNode.leaf(BuildLeaf(latex: whole, role: .value))
                if tail.isEmpty { return head }
                return .row([head, parse(tail)])
            }
            if cmd == "frac" || cmd == "sqrt" {
                return .leaf(BuildLeaf(latex: s, role: .value)) // страховка, сюда не должны попадать
            }
            let rest = String(s[afterCmd...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                return .leaf(BuildLeaf(latex: s, role: roleOfCommand(cmd)))
            }
            return .row([.leaf(BuildLeaf(latex: "\\" + cmd, role: roleOfCommand(cmd))), parse(rest)])
        }
        // 13. атомы через пробел (m g, \Delta x уже разобрано выше)
        if s.contains(" ") {
            return .row(s.split(separator: " ").map { parse(String($0)) })
        }
        // 14. бэкслэш внутри (k\lambda)
        if let bi = topBackslash(s), bi != s.startIndex {
            let before = String(s[..<bi]).trimmingCharacters(in: .whitespaces)
            let after = String(s[bi...])
            if !before.isEmpty && !after.isEmpty {
                return .row([parse(before), parse(after)])
            }
        }
        // 15. слитные буквы (pV) — по одной
        if s.count > 1 && s.allSatisfy({ $0.isLetter }) {
            return .row(s.map { BuildNode.leaf(BuildLeaf(latex: String($0), role: roleOfChunk(String($0)))) })
        }
        // 16. неделимый атом
        return .leaf(BuildLeaf(latex: s, role: roleOfChunk(s)))
    }

    // MARK: helpers

    struct GroupRead { let list: [String]; let rest: String }

    /// Читает count групп {...} с позиции (вложенность учитывается).
    static func readGroups(_ s: String, from: String.Index, count: Int) -> GroupRead? {
        var idx = from
        var out: [String] = []
        for _ in 0..<count {
            while idx < s.endIndex && s[idx] == " " { idx = s.index(after: idx) }
            guard idx < s.endIndex && s[idx] == "{" else { return nil }
            var depth = 0
            let start = s.index(after: idx)
            var j = idx
            while j < s.endIndex {
                if s[j] == "{" { depth += 1 }
                else if s[j] == "}" {
                    depth -= 1
                    if depth == 0 {
                        out.append(String(s[start..<j]))
                        idx = s.index(after: j)
                        break
                    }
                }
                j = s.index(after: j)
            }
            if depth != 0 { return nil }
        }
        return GroupRead(list: out, rest: String(s[idx...]))
    }

    /// Читает имя команды после backslash.
    static func readCommand(_ s: String, from: String.Index) -> (String, String.Index) {
        var name = ""
        var j = from
        while j < s.endIndex && s[j].isLetter { name.append(s[j]); j = s.index(after: j) }
        return (name, j)
    }

    /// Вся строка обёрнута в (...) или |...| → вернуть внутренность.
    static func stripWrapped(_ s: String) -> String? {
        guard s.count >= 2 else { return nil }
        if s.hasPrefix("(") {
            var depth = 0
            var j = s.startIndex
            while j < s.endIndex {
                if s[j] == "(" { depth += 1 }
                else if s[j] == ")" {
                    depth -= 1
                    if depth == 0 {
                        if s.index(after: j) == s.endIndex {
                            return String(s[s.index(after: s.startIndex)..<j])
                        }
                        return nil
                    }
                }
                j = s.index(after: j)
            }
            return nil
        }
        if s.hasPrefix("|") && s.hasSuffix("|") && s.filter({ $0 == "|" }).count == 2 {
            return String(s.dropFirst().dropLast())
        }
        return nil
    }

    struct MidWrap { let before: String; let open: String; let inner: String; let close: String; let after: String }

    /// Первые скобки (...) внутри выражения: m(g±a).
    static func splitWrappedMid(_ s: String) -> MidWrap? {
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1 }
            else if c == "(" && depth == 0 {
                var d2 = 0
                var j = i
                while j < s.endIndex {
                    if s[j] == "(" { d2 += 1 }
                    else if s[j] == ")" {
                        d2 -= 1
                        if d2 == 0 {
                            return MidWrap(
                                before: String(s[..<i]),
                                open: "(", inner: String(s[s.index(after: i)..<j]),
                                close: ")", after: String(s[s.index(after: j)...]))
                        }
                    }
                    j = s.index(after: j)
                }
                return nil
            }
            i = s.index(after: i)
        }
        return nil
    }

    struct AroundCmd { let before: String; let list: [String]; let after: String }

    /// Первый \frac / \sqrt верхнего уровня: до, группы, после.
    static func splitAround(_ s: String, command: String, groups: Int) -> AroundCmd? {
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "{" || c == "(" { depth += 1 }
            else if c == "}" || c == ")" { depth -= 1 }
            else if c == "\\" && depth == 0 {
                let (cmd, after) = readCommand(s, from: s.index(after: i))
                if cmd == command, let g = readGroups(s, from: after, count: groups) {
                    return AroundCmd(before: String(s[..<i]), list: g.list, after: g.rest)
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    static func assembleSplit(before: String, node: BuildNode, after: String) -> BuildNode {
        var kids: [BuildNode] = []
        if !before.trimmingCharacters(in: .whitespaces).isEmpty { kids.append(parse(before)) }
        kids.append(node)
        if !after.trimmingCharacters(in: .whitespaces).isEmpty { kids.append(parse(after)) }
        return kids.count == 1 ? kids[0] : .row(kids)
    }

    /// Разбиение по операторам верхнего уровня. Операторы — отдельные части,
    /// запятые-разделители выбрасываются.
    static func splitTopLevel(_ s: String) -> [String]? {
        var parts: [String] = []
        var cur = ""
        var depth = 0
        var found = false
        var i = s.startIndex

        func prevSignificant() -> Character? {
            let t = cur.trimmingCharacters(in: .whitespaces)
            return t.last
        }
        func isBinaryContext() -> Bool {
            guard let p = prevSignificant() else { return false }
            return p.isLetter || p.isNumber || p == "}" || p == ")" || p == "]"
        }

        while i < s.endIndex {
            let c = s[i]
            if c == "{" || c == "(" { depth += 1; cur.append(c) }
            else if c == "}" || c == ")" { depth -= 1; cur.append(c) }
            else if depth == 0 && c == "=" {
                parts.append(cur); parts.append("="); cur = ""; found = true
            } else if depth == 0 && c == "+" {
                parts.append(cur); parts.append("+"); cur = ""; found = true
            } else if depth == 0 && c == "-" && isBinaryContext() {
                parts.append(cur); parts.append("-"); cur = ""; found = true
            } else if depth == 0 && c == "/" {
                parts.append(cur); parts.append("/"); cur = ""; found = true
            } else if depth == 0 && c == "," {
                // запятая-разделитель (", ") — выбрасываем; десятичная ("13,6") — оставляем
                var j = s.index(after: i)
                while j < s.endIndex && s[j] == " " { j = s.index(after: j) }
                if j < s.endIndex && !s[j].isNumber {
                    parts.append(cur); cur = ""; found = true
                } else {
                    cur.append(c)
                }
            } else if depth == 0 && c == "\\" {
                let nx = s.index(after: i)
                if nx < s.endIndex && s[nx].isLetter {
                    let (cmd, after) = readCommand(s, from: nx)
                    if opCmds.contains(cmd) {
                        parts.append(cur); parts.append("\\" + cmd); cur = ""; found = true
                        i = after
                        continue
                    }
                    // обычная команда — целиком в текущий кусок, не разрывать
                    cur.append(contentsOf: "\\" + cmd)
                    i = after
                    continue
                } else {
                    // экранированный символ: \% значимый, пробельные (\;, \,) выбрасываем
                    let nx2 = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                    let esc = String(s[i..<nx2])
                    if esc == "\\%" { cur.append(contentsOf: esc) }
                    i = nx2
                    continue
                }
            } else {
                cur.append(c)
            }
            i = s.index(after: i)
        }
        if !found { return nil }
        parts.append(cur)
        let cleaned = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.count > 1 ? cleaned : nil
    }

    /// Читает один юнит для sub/sup: {...} | \cmd{...} | \cmd | символ.
    /// Возвращает узел, индекс продолжения и (для групп) исходное содержимое.
    static func readUnit(_ s: String, from: String.Index) -> (BuildNode, String.Index, String?)? {
        var j = from
        while j < s.endIndex && s[j] == " " { j = s.index(after: j) }
        guard j < s.endIndex else { return nil }
        if s[j] == "{" {
            guard let g = readGroups(s, from: j, count: 1) else { return nil }
            let nx = s.index(s.endIndex, offsetBy: -g.rest.count)
            return (parse(g.list[0]), nx, g.list[0])
        }
        if s[j] == "\\" {
            let (cmd, after) = readCommand(s, from: s.index(after: j))
            if ["vec", "bar", "mathcal", "text", "mathrm"].contains(cmd) {
                guard let g = readGroups(s, from: after, count: 1) else { return nil }
                let nx = s.index(s.endIndex, offsetBy: -g.rest.count)
                if cmd == "text" || cmd == "mathrm" {
                    return (.leaf(BuildLeaf(latex: g.list[0], role: .value)), nx, nil)
                }
                return (.leaf(BuildLeaf(latex: String(s[j..<nx]), role: .value)), nx, nil)
            }
            if cmd.isEmpty { return nil }
            return (.leaf(BuildLeaf(latex: "\\" + cmd, role: roleOfCommand(cmd))), after, nil)
        }
        return (.leaf(BuildLeaf(latex: String(s[j]), role: roleOfChunk(String(s[j])))), s.index(after: j), nil)
    }

    /// Склеивает ряд простых листьев подиндекса в один чип: {0x} → один слот.
    static func maybeMerge(_ node: BuildNode, original: String?) -> BuildNode {
        guard let original, case .row(let kids) = node, kids.count > 1 else { return node }
        let plain: [LeafRole] = [.value, .number, .greek, .constant]
        for k in kids {
            guard case .leaf(let l) = k, plain.contains(l.role) else { return node }
        }
        return .leaf(BuildLeaf(latex: "{" + original + "}", role: .value))
    }

    /// Индексы/степени: база + опциональные sub/sup. Возвращает узел и хвост.
    /// nil — если sub/sup нет (нечего вешать).
    static func matchScripts(_ s: String) -> (BuildNode, String)? {
        var idx = s.startIndex
        guard idx < s.endIndex else { return nil }
        let base: BuildNode
        if s[idx] == "{" {
            guard let g = readGroups(s, from: idx, count: 1) else { return nil }
            base = parse(g.list[0])
            // конец группы = длина строки минус хвост
            idx = s.index(s.endIndex, offsetBy: -g.rest.count)
        } else if s[idx] == "\\" {
            let (cmd, after) = readCommand(s, from: s.index(after: idx))
            if ["vec", "bar", "mathcal", "text", "mathrm"].contains(cmd) {
                guard let g = readGroups(s, from: after, count: 1) else { return nil }
                let whole = String(s[idx...]).prefix(s.count - g.rest.count)
                base = .leaf(BuildLeaf(latex: String(whole), role: .value))
                idx = s.index(s.endIndex, offsetBy: -g.rest.count)
            } else if cmd.isEmpty {
                return nil
            } else {
                base = .leaf(BuildLeaf(latex: "\\" + cmd, role: roleOfCommand(cmd)))
                idx = after
            }
        } else if s[idx] == "(" || s[idx] == ")" || s[idx] == " " {
            return nil
        } else {
            base = .leaf(BuildLeaf(latex: String(s[idx]), role: roleOfChunk(String(s[idx]))))
            idx = s.index(after: idx)
        }
        while idx < s.endIndex && s[idx] == " " { idx = s.index(after: idx) }
        var sub: BuildNode?
        var sup: BuildNode?
        if idx < s.endIndex && s[idx] == "_" {
            if let (u, nx, raw) = readUnit(s, from: s.index(after: idx)) {
                sub = maybeMerge(u, original: raw)
                idx = nx
            }
        }
        while idx < s.endIndex && s[idx] == " " { idx = s.index(after: idx) }
        if idx < s.endIndex && s[idx] == "^" {
            if let (u, nx, raw) = readUnit(s, from: s.index(after: idx)) {
                sup = maybeMerge(u, original: raw)
                idx = nx
            }
        }
        if sub == nil && sup == nil { return nil }
        return (.scripts(base: base, sub: sub, sup: sup), String(s[idx...]))
    }

    /// Первый бэкслэш верхнего уровня (k\lambda).
    static func topBackslash(_ s: String) -> String.Index? {
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{" || s[i] == "(" { depth += 1 }
            else if s[i] == "}" || s[i] == ")" { depth -= 1 }
            else if s[i] == "\\" && depth == 0 { return i }
            i = s.index(after: i)
        }
        return nil
    }

    // MARK: роли

    static func roleOfCommand(_ cmd: String) -> LeafRole {
        if funcCmds.contains(cmd) { return .function }
        if opCmds.contains(cmd) { return .op }
        if relCmds.contains(cmd) { return .relation }
        if cmd == "pi" { return .number }
        if greekCmds.contains(cmd) { return .greek }
        return .value
    }

    static func roleOfChunk(_ s: String) -> LeafRole {
        if s == "=" { return .relation }
        if s == "+" || s == "-" || s == "*" || s == "/" { return .op }
        if s == "..." || s == "%" { return .op }
        if !s.isEmpty && s.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) { return .number }
        if s.count == 1 && constLetters.contains(s) { return .constant }
        return .value
    }
}

// MARK: - Состояние сборки одной карточки

final class BuildState: ObservableObject {
    let tree: BuildNode
    let slots: [BuildLeaf]
    @Published var pool: [BuildLeaf]
    @Published var placement: [UUID: UUID] = [:]
    @Published var selectedID: UUID?
    @Published var results: [UUID: Bool]?
    @Published var hintID: UUID?
    @Published var hintText: String?
    @Published var hintsLeft = 2
    @Published var revealed = false

    init(formula: Formula) {
        let tree = BuildParser.parse(formula.latex)
        self.tree = tree
        let slots = tree.leaves
        self.slots = slots
        self.pool = slots.shuffled()
    }

    var placedIDs: Set<UUID> { Set(placement.values) }
    var available: [BuildLeaf] { pool.filter { !placedIDs.contains($0.id) } }
    var isComplete: Bool { !slots.isEmpty && placement.count == slots.count }
    var allCorrect: Bool {
        guard let r = results else { return false }
        return !r.isEmpty && r.values.allSatisfy { $0 }
    }
    var locked: Bool { revealed || allCorrect }
    var score: Double {
        guard let r = results, !slots.isEmpty else { return 0 }
        return Double(r.values.filter { $0 }.count) / Double(slots.count)
    }

    static func grade(for score: Double) -> Int {
        if score >= 0.9 { return 3 }
        if score >= 0.6 { return 2 }
        return 1
    }

    func toggleSelect(_ id: UUID) {
        guard !locked else { return }
        Haptics.tap()
        selectedID = (selectedID == id) ? nil : id
    }

    func place(_ leafID: UUID, to slotID: UUID) {
        guard !locked else { return }
        Haptics.tap()
        placement[slotID] = leafID
        selectedID = nil
        results = nil
        if hintID == slotID { hintID = nil }
    }

    func unplace(_ slotID: UUID) {
        guard !locked else { return }
        Haptics.tap()
        placement.removeValue(forKey: slotID)
        results = nil
    }

    func reset() {
        Haptics.tap()
        placement = [:]
        selectedID = nil
        results = nil
        hintID = nil
        hintText = nil
        hintsLeft = 2
        revealed = false
    }

    func clearWrong() {
        Haptics.tap()
        guard let r = results else { return }
        for (k, v) in r where !v { placement.removeValue(forKey: k) }
        results = nil
        hintID = nil
    }

    func reveal() {
        for s in slots { placement[s.id] = s.id }
        results = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, true) })
        revealed = true
        hintID = nil
    }

    @discardableResult
    func check() -> (score: Double, allCorrect: Bool) {
        var res: [UUID: Bool] = [:]
        var ok = 0
        for s in slots {
            let good = placement[s.id] == s.id
            res[s.id] = good
            if good { ok += 1 }
        }
        results = res
        let score = slots.isEmpty ? 1 : Double(ok) / Double(slots.count)
        if score >= 1 { Haptics.success() } else { Haptics.error() }
        return (score, ok == slots.count)
    }

    /// Подсказка: подсвечивает случайный пустой слот и называет его роль.
    func hint() {
        guard !locked && hintsLeft > 0 else { return }
        Haptics.tap()
        let empty = slots.filter { placement[$0.id] == nil }
        guard let slot = empty.randomElement() else { return }
        hintID = slot.id
        hintText = "сюда нужна: \(slot.role.nameRU)"
        hintsLeft -= 1
    }
}

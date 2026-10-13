import SwiftUI
import UIKit

// MARK: - LatexView: нативный офлайн-рендер LaTeX (без WebView, без SPM)
// Покрывает подмножество, используемое в formulas.json:
// дроби \frac, корни \sqrt, верхние/нижние индексы _ ^, \vec, греческие буквы,
// \cdot \times \pm \sum, \text{}, \mathcal{E}, \cos \sin, \quad-пробелы.
// Неизвестные команды показываются как есть — формула всегда читаема.

struct LatexView: View {
    let latex: String
    var fontSize: CGFloat = 22

    var body: some View {
        MiniLatex(latex: latex, fontSize: fontSize)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
            .accessibilityLabel("Формула: \(latex)")
    }
}

// MARK: Parser
indirect enum MathNode {
    case text(String)
    case group([MathNode])
    case frac(MathNode, MathNode)
    case sqrt(MathNode)
    case sup(MathNode, MathNode)
    case sub(MathNode, MathNode)
}

enum MathParser {
    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "Gamma": "Γ",
        "delta": "δ", "Delta": "Δ", "varepsilon": "ε", "epsilon": "ϵ",
        "zeta": "ζ", "eta": "η", "theta": "θ", "lambda": "λ",
        "mu": "μ", "nu": "ν", "pi": "π", "rho": "ρ",
        "sigma": "σ", "Phi": "Φ", "phi": "φ", "varphi": "φ",
        "omega": "ω", "Omega": "Ω"
    ]
    static let symbols: [String: String] = [
        "cdot": "·", "times": "×", "pm": "±", "sum": "Σ",
        "int": "∫", "infty": "∞", "approx": "≈", "neq": "≠",
        "leq": "≤", "geq": "≥", "rightarrow": "→", "cos": "cos",
        "sin": "sin", "tan": "tan", "ln": "ln", "log": "log",
        "quad": "  ", ",": " ", ";": " ", ":": " ", " ": " "
    ]

    static func parse(_ s: String) -> MathNode {
        let parser = LatexCursor(chars: Array(s))
        return parser.parseGroup()
    }
}

// MARK: Рекурсивный спуск — отдельным классом, чтобы методы могли
// свободно вызывать друг друга (вложенные func так не умеют).
private final class LatexCursor {
    let chars: [Character]
    var i = 0

    init(chars: [Character]) {
        self.chars = chars
    }

    func parseGroup() -> MathNode {
        var nodes: [MathNode] = []
        while i < chars.count {
            let c = chars[i]
            if c == "}" { i += 1; break }
            if c == "\\" {
                i += 1
                var name = ""
                while i < chars.count && chars[i].isLetter { name.append(chars[i]); i += 1 }
                if name.isEmpty && i < chars.count {
                    // экранированный символ: \{ \} \% \& — показать как есть
                    nodes.append(.text(String(chars[i]))); i += 1; continue
                }
                switch name {
                case "frac":
                    let a = parseArg(); let b = parseArg()
                    nodes.append(.frac(a, b))
                case "sqrt":
                    nodes.append(.sqrt(parseArg()))
                case "vec":
                    let v = parseArg()
                    nodes.append(.group([v, .text("⃗")])) // стрелка поверх (combining)
                case "text", "mathrm", "textup":
                    nodes.append(.text(collectArg()))
                case "mathcal":
                    let inner = collectArg()
                    nodes.append(.text(inner == "E" ? "ℰ" : inner))
                default:
                    if let g = MathParser.greek[name] { nodes.append(.text(g)) }
                    else if let sym = MathParser.symbols[name] { nodes.append(.text(sym)) }
                    else if !name.isEmpty { nodes.append(.text(name)) }
                }
            } else if c == "{" {
                i += 1
                nodes.append(parseGroup())
            } else if c == "_" || c == "^" {
                let isSub = (c == "_")
                i += 1
                let arg = parseSingle()
                if let last = nodes.popLast() {
                    nodes.append(isSub ? .sub(last, arg) : .sup(last, arg))
                } else {
                    nodes.append(arg)
                }
            } else if c == "&" || c == "\n" {
                i += 1 // выравнивание таблиц — пропускаем
            } else {
                var t = ""
                while i < chars.count && !"\\{}_^&".contains(chars[i]) { t.append(chars[i]); i += 1 }
                if !t.isEmpty { nodes.append(.text(t)) }
            }
        }
        if nodes.count == 1 { return nodes[0] }
        return .group(nodes)
    }

    func parseArg() -> MathNode {
        while i < chars.count && chars[i] == " " { i += 1 }
        if i < chars.count && chars[i] == "{" { i += 1; return parseGroup() }
        return parseSingle()
    }

    func parseSingle() -> MathNode {
        while i < chars.count && chars[i] == " " { i += 1 }
        guard i < chars.count else { return .text("") }
        if chars[i] == "{" { i += 1; return parseGroup() }
        if chars[i] == "\\" {
            i += 1
            var name = ""
            while i < chars.count && chars[i].isLetter { name.append(chars[i]); i += 1 }
            if let g = MathParser.greek[name] { return .text(g) }
            if let sym = MathParser.symbols[name] { return .text(sym) }
            if name == "vec" { return .group([parseArg(), .text("⃗")]) }
            if name == "mathcal" {
                let s = collectArg()
                return .text(s == "E" ? "ℰ" : s)
            }
            return .text(name)
        }
        let c = String(chars[i]); i += 1
        return .text(c)
    }

    func collectArg() -> String {
        let n = parseArg()
        var out = ""
        walk(n, into: &out)
        return out
    }

    private func walk(_ node: MathNode, into out: inout String) {
        switch node {
        case .text(let s): out += s
        case .group(let a): for n in a { walk(n, into: &out) }
        case .frac(let a, let b): walk(a, into: &out); out += "/"; walk(b, into: &out)
        case .sqrt(let a): walk(a, into: &out)
        case .sup(let a, let b): walk(a, into: &out); out += "^"; walk(b, into: &out)
        case .sub(let a, let b): walk(a, into: &out); out += "_"; walk(b, into: &out)
        }
    }
}

// MARK: Renderer — отдельной View-структурой: рекурсия через
// номинальный тип компилируется, рекурсивная func с some View — нет.
struct MathNodeView: View {
    let node: MathNode
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        switch node {
        case .text(let s):
            Text(s).font(.system(size: size)).multilineTextAlignment(.center)
        case .group(let arr):
            HStack(spacing: 1) {
                ForEach(arr.indices, id: \.self) { idx in
                    MathNodeView(node: arr[idx], size: size)
                }
            }
        case .frac(let a, let b):
            VStack(spacing: 1) {
                MathNodeView(node: a, size: size * 0.85)
                Divider().frame(minWidth: 20)
                MathNodeView(node: b, size: size * 0.85)
            }
        case .sqrt(let a):
            HStack(spacing: 0) {
                Text("√").font(.system(size: size))
                MathNodeView(node: a, size: size * 0.9)
                    .overlay(alignment: .top) { Rectangle().frame(height: 1).opacity(0.9) }
            }
        case .sup(let base, let exp):
            HStack(alignment: .top, spacing: 0) {
                MathNodeView(node: base, size: size)
                MathNodeView(node: exp, size: size * 0.62).offset(y: -size * 0.28)
            }
        case .sub(let base, let exp):
            HStack(alignment: .bottom, spacing: 0) {
                MathNodeView(node: base, size: size)
                MathNodeView(node: exp, size: size * 0.62).offset(y: size * 0.18)
            }
        }
    }
}

struct MiniLatex: View {
    let latex: String
    var fontSize: CGFloat = 22

    var body: some View {
        MathNodeView(node: MathParser.parse(latex), size: fontSize)
    }
}

// MARK: - Мелкие UI-компоненты

struct LevelStars: View {
    let level: Int
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .foregroundStyle(level >= 7 ? .yellow : .secondary)
            Text("\(level) · \(LevelSystem.name(for: level))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Уровень \(level)")
    }
}

struct StatusBadge: View {
    let status: FormulaStatus
    var body: some View {
        Text(status.rawValue)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch status {
        case .untouched: return .gray
        case .learning: return .blue
        case .learned: return .green
        case .problem: return .red
        }
    }
}

/// Конфетти при milestone (лёгкая анимация, без зависимостей).
struct ConfettiView: View {
    @State private var animate = false
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<40, id: \.self) { i in
                Circle()
                    .fill([Color.yellow, .green, .blue, .pink, .orange][i % 5])
                    .frame(width: 8, height: 8)
                    .position(
                        x: animate ? CGFloat.random(in: 0...geo.size.width) : geo.size.width / 2,
                        y: animate ? CGFloat.random(in: 0...geo.size.height) : -20
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).delay(Double(i) * 0.01), value: animate)
            }
            .onAppear { animate = true }
        }
        .allowsHitTesting(false)
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

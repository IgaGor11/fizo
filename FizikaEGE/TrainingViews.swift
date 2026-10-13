import SwiftUI

// MARK: - Сессия тренировки

enum SessionMode: String, Identifiable, CaseIterable {
    case flashcards, choice, input, build, mixed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flashcards: return "Карточки"
        case .choice: return "Выбор из 4"
        case .input: return "Ручной ввод"
        case .build: return "Сборка"
        case .mixed: return "Смешанный"
        }
    }
    var icon: String {
        switch self {
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .choice: return "list.bullet.circle"
        case .input: return "keyboard"
        case .build: return "puzzlepiece"
        case .mixed: return "shuffle"
        }
    }
    var hint: String {
        switch self {
        case .flashcards: return "Вспомни и оцени себя"
        case .choice: return "Узнай правильное название"
        case .input: return "Напиши формулу сам"
        case .build: return "Собери из блоков"
        case .mixed: return "Приложение подберёт само"
        }
    }
}

struct TrainingSession: Identifiable {
    let id = UUID()
    let formulas: [Formula]
    let mode: SessionMode
}

// MARK: - Старт тренировки: сначала раздел, потом режим
struct TrainingScope: Hashable {
    let title: String
    let formulas: [Formula]
}

struct StartTrainingView: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) var dismiss
    @State private var scope: TrainingScope?
    @State private var session: TrainingSession?

    var body: some View {
        NavigationStack {
            if scope == nil {
                List {
                    Section {
                        Button {
                            Haptics.tap()
                            scope = TrainingScope(title: "Итоговый зачёт", formulas: store.formulas)
                        } label: {
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                Text("Итоговый зачёт").font(.headline)
                                Spacer()
                                Text("все разделы").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    Section("Разделы") {
                        ForEach(FormulasBundle.sectionsOrder, id: \.self) { sec in
                            let list = store.formulas.filter { $0.section == sec }
                            let due = store.dueFormulas(scope: list).count
                            Button {
                                Haptics.tap()
                                scope = TrainingScope(title: sec, formulas: list)
                            } label: {
                                HStack {
                                    Text(sec).font(.headline)
                                    Spacer()
                                    Text("к повторению: \(due)").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .navigationTitle("Что тренируем?")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(SessionMode.allCases) { m in
                            ModeCard(mode: m) {
                                start(mode: m)
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle(scope?.title ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Разделы") { scope = nil }
                    }
                }
            }
        }
        .fullScreenCover(item: $session) { s in
            TrainingHost(session: s).environmentObject(store)
        }
    }

    private func start(mode: SessionMode) {
        guard let scope else { return }
        let list = store.sessionFormulas(scope: scope.formulas)
        guard !list.isEmpty else { return }
        Haptics.tap()
        session = TrainingSession(formulas: list, mode: mode)
    }
}

struct ModeCard: View {
    let mode: SessionMode
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.title)
                    .frame(width: 48)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.headline)
                    Text(mode.hint).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .frame(minHeight: 88)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct TrainingHost: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) var dismiss
    let session: TrainingSession
    @State private var index = 0
    @State private var correctCount = 0
    @State private var done = false
    @State private var cardStart = Date()
    @State private var effectiveMode: TrainMode = .flashcards

    var body: some View {
        NavigationStack {
            VStack {
                if done {
                    sessionSummary
                } else if index < session.formulas.count {
                    let f = session.formulas[index]
                    ProgressView(value: Double(index) / Double(session.formulas.count))
                        .padding(.horizontal)
                    Text("Карточка \(index + 1) из \(session.formulas.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    currentCard(f)
                        .onAppear {
                            effectiveMode = resolveMode(for: f)
                            cardStart = Date()
                        }
                        .id(f.id)
                }
            }
            .navigationTitle(session.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { store.save(); dismiss() }
                }
            }
        }
    }

    private func resolveMode(for f: Formula) -> TrainMode {
        switch session.mode {
        case .flashcards: return .flashcards
        case .choice: return .choice
        case .input: return .input
        case .build: return .build
        case .mixed: return store.adaptiveMode(for: f.id)
        }
    }

    @ViewBuilder
    private func currentCard(_ f: Formula) -> some View {
        switch effectiveMode {
        case .flashcards:
            FlashcardTrain(formula: f, onGrade: grade)
        case .choice:
            ChoiceTrain(formula: f, all: store.formulas, onResult: gradeBool)
        case .input:
            InputTrain(formula: f, onResult: gradeBool)
        case .build:
            BuildTrain(formula: f, onResult: gradeBool)
        }
    }

    private func grade(grade g: Int) {
        let f = session.formulas[index]
        let dt = Date().timeIntervalSince(cardStart)
        let res = store.answer(formulaId: f.id, grade: g, mode: effectiveMode, timeSec: dt)
        if g >= 3 { correctCount += 1; Haptics.success() } else { Haptics.error() }
        if res.levelUp { Haptics.success() }
        advance()
    }

    private func gradeBool(correct: Bool) {
        grade(grade: correct ? 3 : 1)
    }

    private func advance() {
        if index + 1 >= session.formulas.count {
            done = true
        } else {
            index += 1
            effectiveMode = resolveMode(for: session.formulas[index])
            cardStart = Date()
        }
    }

    private var sessionSummary: some View {
        VStack(spacing: 12) {
            let total = session.formulas.count
            Text(correctCount == total ? "Идеальная сессия! 🎉" : "Сессия завершена")
                .font(.title2).bold()
            Text("Верно: \(correctCount) из \(total) (\(total == 0 ? 0 : Int(Double(correctCount) / Double(total) * 100))%)")
            if correctCount == total && total >= 5 {
                ConfettiView().frame(height: 120)
            }
            Button("Готово") { store.save(); dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Режим 1: Карточки (retrieval practice + самооценка для FSRS)
struct FlashcardTrain: View {
    let formula: Formula
    let onGrade: (Int) -> Void
    @State private var flipped = false

    var body: some View {
        VStack(spacing: 14) {
            Text(formula.title).font(.headline).multilineTextAlignment(.center)
            if !flipped {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 8) {
                            Text("Вспомните формулу…").font(.title3)
                            Text("Нажмите, чтобы перевернуть").font(.caption).foregroundStyle(.secondary)
                        }
                    )
                    .onTapGesture { withAnimation { flipped = true }; Haptics.tap() }
            } else {
                LatexView(latex: formula.latex, fontSize: 24)
                    .rotation3DEffect(.degrees(flipped ? 0 : 90), axis: (x: 0, y: 1, z: 0))
                Text("Насколько хорошо вспомнили?").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        GradeButton("Не помню", color: .red) { onGrade(1) }
                        GradeButton("Смутно", color: .orange) { onGrade(2) }
                    }
                    HStack(spacing: 8) {
                        GradeButton("Помню", color: .blue) { onGrade(3) }
                        GradeButton("Легко", color: .green) { onGrade(4) }
                    }
                }
            }
        }
        .padding()
    }
}

struct GradeButton: View {
    let title: String; let color: Color; let action: () -> Void
    init(_ title: String, color: Color, action: @escaping () -> Void) {
        self.title = title; self.color = color; self.action = action
    }
    var body: some View {
        Button(title, action: action)
            .font(.title3)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Режим 2: Выбор из 4 (дистракторы из той же темы)
struct ChoiceTrain: View {
    let formula: Formula
    let all: [Formula]
    let onResult: (Bool) -> Void
    @State private var picked: String?
    @State private var options: [Formula] = []

    var body: some View {
        VStack(spacing: 12) {
            Text("Какое название у формулы?").font(.subheadline).foregroundStyle(.secondary)
            LatexView(latex: formula.latex, fontSize: 24)
            ForEach(options) { o in
                Button {
                    picked = o.id
                    Haptics.tap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onResult(o.id == formula.id)
                    }
                } label: {
                    HStack {
                        Text(o.title).font(.title3).multilineTextAlignment(.leading)
                        Spacer()
                        if picked == o.id {
                            Image(systemName: o.id == formula.id ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(o.id == formula.id ? .green : .red)
                        }
                    }
                    .padding(18)
                    .frame(minHeight: 64)
                    .background(bg(for: o))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(picked != nil)
            }
        }
        .padding()
        .onAppear(perform: buildOptions)
    }

    private func buildOptions() {
        var pool = all.filter { $0.topic == formula.topic && $0.id != formula.id }
        if pool.count < 3 { pool = all.filter { $0.id != formula.id } }
        options = (Array(pool.shuffled().prefix(3)) + [formula]).shuffled()
    }

    private func bg(for o: Formula) -> Color {
        guard let p = picked else { return Color.secondary.opacity(0.12) }
        if o.id == formula.id { return Color.green.opacity(0.25) }
        if o.id == p { return Color.red.opacity(0.25) }
        return Color.secondary.opacity(0.08)
    }
}

// MARK: - Режим 3: Ручной ввод (толерантная проверка LaTeX + своя клавиатура)
struct InputTrain: View {
    let formula: Formula
    let onResult: (Bool) -> Void
    @StateObject private var input = FormulaInput()
    @State private var verdict: Bool?

    var body: some View {
        VStack(spacing: 12) {
            Text(formula.title).font(.headline).multilineTextAlignment(.center)
            Text("Введите формулу — поможет клавиатура ниже").font(.caption).foregroundStyle(.secondary)
            FormulaTextField(input: input)
            FormulaKeyboard(input: input)
            if let v = verdict {
                Text(v ? "Верно! ✅" : "Не совсем — сравните с эталоном")
                    .foregroundStyle(v ? .green : .orange).bold()
                LatexView(latex: formula.latex, fontSize: 22)
                Button(v ? "Дальше" : "Пропустить (не засчитано)") { onResult(v) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                HStack {
                    Button("Проверить") {
                        let ok = ProgressStore.checkInput(input.text, target: formula.latex)
                        verdict = ok
                        if ok { Haptics.success() } else { Haptics.error() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(input.text.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Не помню") { verdict = false }
                        .controlSize(.large)
                }
            }
        }
        .padding()
    }
}

// MARK: - Своя клавиатура для ввода формул (офлайн, без системной)
// Три вкладки: 123 (цифры и операторы), αβ (греческие), fx (LaTeX-шаблоны).
// Вставка — в позицию курсора; у шаблонов курсор встаёт внутрь скобок.

final class FormulaInput: ObservableObject {
    @Published var text = ""
    weak var field: UITextField?

    func insert(_ s: String, backBy: Int = 0) {
        Haptics.tap()
        guard let f = field else { text += s; return }
        if f.selectedTextRange == nil {
            f.becomeFirstResponder()
        }
        if let range = f.selectedTextRange {
            f.replace(range, withText: s)
            if backBy > 0,
               let cur = f.selectedTextRange?.start,
               let target = f.position(from: cur, offset: -backBy) {
                f.selectedTextRange = f.textRange(from: target, to: target)
            }
        } else {
            text += s
            f.text = text
            return
        }
        text = f.text ?? ""
    }

    func backspace() {
        Haptics.tap()
        guard let f = field else {
            if !text.isEmpty { text.removeLast() }
            return
        }
        if let range = f.selectedTextRange, !range.isEmpty {
            f.replace(range, withText: "")
        } else {
            f.deleteBackward()
        }
        text = f.text ?? ""
    }
}

struct FormulaTextField: UIViewRepresentable {
    @ObservedObject var input: FormulaInput

    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.placeholder = "Ваш ответ…"
        f.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        f.borderStyle = .roundedRect
        f.autocapitalizationType = .none
        f.autocorrectionType = .no
        f.addTarget(context.coordinator, action: #selector(Coord.edited(_:)), for: .editingChanged)
        input.field = f
        return f
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != input.text { uiView.text = input.text }
    }

    func makeCoordinator() -> Coord { Coord(input: input) }

    final class Coord: NSObject {
        let input: FormulaInput
        init(input: FormulaInput) { self.input = input }
        @objc func edited(_ f: UITextField) { input.text = f.text ?? "" }
    }
}

struct FormulaKey: Hashable {
    let title: String
    let insert: String
    let backBy: Int
    init(_ title: String, insert: String? = nil, backBy: Int = 0) {
        self.title = title
        self.insert = insert ?? title
        self.backBy = backBy
    }
}

struct FormulaKeyboard: View {
    @ObservedObject var input: FormulaInput
    @State private var page = 0

    private let digits: [[FormulaKey]] = [
        [.init("7"), .init("8"), .init("9"), .init("+"), .init("−", insert: "-"), .init("×", insert: "*")],
        [.init("4"), .init("5"), .init("6"), .init("("), .init(")"), .init("÷", insert: "/")],
        [.init("1"), .init("2"), .init("3"), .init("="), .init("."), .init("±", insert: "\\pm ")],
        [.init("0"), .init("x"), .init("t"), .init("·", insert: "\\cdot "), .init("⌫")]
    ]
    private let greek: [[FormulaKey]] = [
        [.init("α", insert: "\\alpha "), .init("β", insert: "\\beta "), .init("γ", insert: "\\gamma "), .init("Δ", insert: "\\Delta "), .init("δ", insert: "\\delta ")],
        [.init("ε", insert: "\\varepsilon "), .init("η", insert: "\\eta "), .init("θ", insert: "\\theta "), .init("λ", insert: "\\lambda "), .init("μ", insert: "\\mu ")],
        [.init("ν", insert: "\\nu "), .init("π", insert: "\\pi "), .init("ρ", insert: "\\rho "), .init("σ", insert: "\\sigma "), .init("φ", insert: "\\varphi ")],
        [.init("ω", insert: "\\omega "), .init("Σ", insert: "\\sum "), .init("Φ", insert: "\\Phi "), .init("ℰ", insert: "\\mathcal{E} "), .init("⌫")]
    ]
    private let latex: [[FormulaKey]] = [
        [.init("a/b", insert: "\\frac{}{}", backBy: 3), .init("x²", insert: "^{}", backBy: 1), .init("x₀", insert: "_{}", backBy: 1)],
        [.init("√", insert: "\\sqrt{}", backBy: 1), .init("⃗", insert: "\\vec{}", backBy: 1), .init("sin", insert: "\\sin ")],
        [.init("cos", insert: "\\cos "), .init("Δx", insert: "\\Delta "), .init("⌫")]
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                PageTab("123", index: 0)
                PageTab("αβ", index: 1)
                PageTab("fx", index: 2)
                Spacer()
                Button("Очистить") { input.text = ""; input.field?.text = "" }
                    .font(.caption)
            }
            let rows = page == 0 ? digits : (page == 1 ? greek : latex)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { k in
                        if k.title == "⌫" {
                            Button("⌫") { input.backspace() }
                                .buttonStyle(KeyStyle())
                        } else {
                            Button(k.title) { input.insert(k.insert, backBy: k.backBy) }
                                .buttonStyle(KeyStyle())
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.1)))
    }

    @ViewBuilder
    private func PageTab(_ title: String, index: Int) -> some View {
        Button(title) { page = index; Haptics.tap() }
            .font(.caption).bold()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(page == index ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.monospaced())
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.3 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Режим 4: Сборка формулы из блоков
struct BuildTrain: View {
    let formula: Formula
    let onResult: (Bool) -> Void
    @State private var shuffled: [String] = []
    @State private var picked: [Int] = []
    @State private var verdict: Bool?

    var assembled: String { picked.map { shuffled[$0] }.joined(separator: " ") }

    var body: some View {
        VStack(spacing: 12) {
            Text(formula.title).font(.headline).multilineTextAlignment(.center)
            Text("Соберите формулу из блоков по порядку").font(.caption).foregroundStyle(.secondary)
            WrapChips(texts: picked.map { shuffled[$0] }, color: .blue) { idx in
                picked.remove(at: idx); verdict = nil
            }
            .frame(minHeight: 60)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
            if let v = verdict {
                Text(v ? "Верно! ✅" : "Попробуйте ещё или пропустите")
                    .foregroundStyle(v ? .green : .orange).bold()
                if !v { LatexView(latex: formula.latex, fontSize: 20) }
                HStack {
                    if !v {
                        Button("Ещё раз") { picked = []; verdict = nil }
                    }
                    Button(v ? "Дальше" : "Пропустить (не засчитано)") { onResult(v) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                WrapChips(texts: availableTexts, color: .gray) { idx in
                    picked.append(availableIndices[idx]); Haptics.tap()
                }
                Button("Проверить") {
                    let ok = ProgressStore.checkInput(assembled, target: formula.latex)
                    verdict = ok
                    if ok { Haptics.success() } else { Haptics.error() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(picked.isEmpty)
            }
        }
        .padding()
        .onAppear {
            shuffled = ProgressStore.tokens(for: formula.latex).shuffled()
        }
    }

    private var availableIndices: [Int] {
        shuffled.indices.filter { !picked.contains($0) }
    }
    private var availableTexts: [String] { availableIndices.map { shuffled[$0] } }
}

struct WrapChips: View {
    let texts: [String]
    let color: Color
    let onTap: (Int) -> Void
    var body: some View {
        FlexibleWrap {
            ForEach(texts.indices, id: \.self) { i in
                Button(texts[i]) { onTap(i) }
                    .font(.body.monospaced())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(color.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
}

/// Простой flow-layout для чипов.
struct FlexibleWrap<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        // Упрощённо: вертикальный стек с переносом через LazyVGrid недостаточно гибок,
        // поэтому используем VStack из HStack-строк через GeometryReader-free подход:
        // SwiftUI-нативный WrappingHStack недоступен — эмулируем через ScrollView + LazyVGrid adaptive.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
            content()
        }
    }
}

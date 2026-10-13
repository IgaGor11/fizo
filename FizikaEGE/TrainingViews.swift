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
    @State private var pickedSection: String?
    @State private var scope: TrainingScope?
    @State private var session: TrainingSession?

    var topicsInSection: [String] {
        guard let sec = pickedSection else { return [] }
        var seen: [String] = []
        for f in store.formulas where f.section == sec {
            if !seen.contains(f.topic) { seen.append(f.topic) }
        }
        return seen
    }

    var body: some View {
        NavigationStack {
            if scope != nil {
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
                        Button("Назад") { scope = nil }
                    }
                }
            } else if let sec = pickedSection {
                List {
                    Section {
                        Button {
                            Haptics.tap()
                            let list = store.formulas.filter { $0.section == sec }
                            scope = TrainingScope(title: sec, formulas: list)
                        } label: {
                            HStack {
                                Image(systemName: "books.vertical.fill").foregroundStyle(.blue)
                                Text("Весь раздел").font(.title3).bold()
                                Spacer()
                                Text("\(store.formulas.filter { $0.section == sec }.count) формул")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    Section("Подразделы") {
                        ForEach(topicsInSection, id: \.self) { topic in
                            let list = store.formulas.filter { $0.topic == topic }
                            let due = store.dueFormulas(scope: list).count
                            Button {
                                Haptics.tap()
                                scope = TrainingScope(title: topic, formulas: list)
                            } label: {
                                HStack {
                                    Text(topic).font(.headline)
                                    Spacer()
                                    Text("к повторению: \(due)").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .navigationTitle(sec)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Разделы") { pickedSection = nil }
                    }
                }
            } else {
                List {
                    Section {
                        Button {
                            Haptics.tap()
                            scope = TrainingScope(title: "Итоговый зачёт", formulas: store.formulas)
                        } label: {
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                Text("Итоговый зачёт").font(.title3).bold()
                                Spacer()
                                Text("все разделы").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    Section("Разделы") {
                        ForEach(FormulasBundle.sectionsOrder, id: \.self) { sec in
                            let list = store.formulas.filter { $0.section == sec }
                            let due = store.dueFormulas(scope: list).count
                            Button {
                                Haptics.tap()
                                pickedSection = sec
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
            VStack(spacing: 8) {
                if done {
                    sessionSummary
                } else if index < session.formulas.count {
                    let f = session.formulas[index]
                    Text("Карточка \(index + 1) из \(session.formulas.count)")
                        .font(.headline).foregroundStyle(.secondary)
                    ScrollView {
                        currentCard(f)
                            .onAppear {
                                effectiveMode = resolveMode(for: f)
                                cardStart = Date()
                            }
                            .id(f.id)
                    }
                    ProgressView(value: Double(index) / Double(session.formulas.count))
                        .padding(.horizontal)
                        .padding(.bottom, 4)
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
            BuildTrain(formula: f, onGrade: grade)
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
            Text(formula.title).font(.title2).bold().multilineTextAlignment(.center)
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
                LatexView(latex: formula.latex, fontSize: 28)
                    .rotation3DEffect(.degrees(flipped ? 0 : 90), axis: (x: 0, y: 1, z: 0))
                // Информация о формуле, как в каталоге
                VStack(alignment: .leading, spacing: 6) {
                    if !formula.symbols.isEmpty {
                        ForEach(formula.symbols.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            HStack(spacing: 6) {
                                MiniLatex(latex: k, fontSize: 17)
                                Text("— \(v.meaning), \(v.unit)")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(formula.mnemonic).font(.callout)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.12)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Насколько хорошо вспомнили?").font(.headline).foregroundStyle(.secondary)
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
            Text("Какое название у формулы?").font(.headline).foregroundStyle(.secondary)
            // Показываем формулу БЕЗ левой части: чему она равна — угадывает ученик
            LatexView(latex: ProgressStore.displayFormula(formula.latex), fontSize: 28)
            ForEach(options) { o in
                Button {
                    picked = o.id
                    Haptics.tap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onResult(o.id == formula.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.title).font(.title3).multilineTextAlignment(.leading)
                            // Обозначение-символ рядом с названием
                            MiniLatex(latex: ProgressStore.symbolOf(o.latex), fontSize: 17)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if picked == o.id {
                            Image(systemName: o.id == formula.id ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(o.id == formula.id ? .green : .red)
                        }
                    }
                    .padding(18)
                    .frame(minHeight: 72)
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
    @State private var cursorOn = true

    /// Текст, разрезанный по курсору, для рисованного курсора как в PhotoMath.
    private func previewParts() -> (String, String) {
        let clamped = max(0, min(input.cursor, input.text.count))
        let idx = input.text.index(input.text.startIndex, offsetBy: clamped,
                                   limitedBy: input.text.endIndex) ?? input.text.endIndex
        return (String(input.text[..<idx]), String(input.text[idx...]))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(formula.title).font(.title2).bold().multilineTextAlignment(.center)
            // Как в PhotoMath: большая красивая формула с мигающим курсором
            HStack(spacing: 0) {
                let parts = previewParts()
                MiniLatex(latex: parts.0, fontSize: 28)
                Text("▍")
                    .font(.system(size: 28)).bold()
                    .foregroundStyle(.green)
                    .opacity(cursorOn ? 1 : 0.15)
                MiniLatex(latex: parts.1, fontSize: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.08)))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    cursorOn.toggle()
                }
            }
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                input.field?.becomeFirstResponder()
            }
        }
    }
}

// MARK: - Своя клавиатура для ввода формул (офлайн, без системной)
// Три вкладки: 123 (цифры и операторы), αβ (греческие), fx (LaTeX-шаблоны).
// Вставка — в позицию курсора; у шаблонов курсор встаёт внутрь скобок.

final class FormulaInput: ObservableObject {
    @Published var text = ""
    /// Позиция курсора в символах (для рисованного курсора в предпросмотре).
    @Published var cursor = 0
    weak var field: UITextField?

    func insert(_ s: String, backBy: Int = 0) {
        Haptics.tap()
        guard let f = field else {
            text += s
            cursor = text.count
            return
        }
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
            cursor = text.count
            return
        }
        text = f.text ?? ""
        syncCursor()
    }

    func backspace() {
        Haptics.tap()
        guard let f = field else {
            if !text.isEmpty { text.removeLast() }
            cursor = text.count
            return
        }
        if let range = f.selectedTextRange, !range.isEmpty {
            f.replace(range, withText: "")
        } else {
            f.deleteBackward()
        }
        text = f.text ?? ""
        syncCursor()
    }

    /// Сдвинуть курсор на delta символов (стрелки ◀ ▶).
    func moveCursor(_ delta: Int) {
        Haptics.tap()
        guard let f = field else { return }
        f.becomeFirstResponder()
        let cur = f.selectedTextRange?.start ?? f.endOfDocument
        if let target = f.position(from: cur, offset: delta) {
            f.selectedTextRange = f.textRange(from: target, to: target)
        }
        syncCursor()
    }

    /// Прочитать нативный курсор UITextField в наши символы.
    func syncCursor() {
        guard let f = field, let r = f.selectedTextRange else { return }
        let off16 = f.offset(from: f.beginningOfDocument, to: r.start)
        cursor = Self.charOffset(of: off16, in: text)
    }

    static func charOffset(of off16: Int, in text: String) -> Int {
        let u16 = text.utf16
        let clamped = max(0, min(off16, u16.count))
        let i16 = u16.index(u16.startIndex, offsetBy: clamped)
        guard let i = String.Index(i16, within: text) else { return text.count }
        return text.distance(from: text.startIndex, to: i)
    }
}

struct FormulaTextField: UIViewRepresentable {
    @ObservedObject var input: FormulaInput

    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.placeholder = "Набирайте на клавиатуре ниже…"
        f.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        f.borderStyle = .roundedRect
        f.autocapitalizationType = .none
        f.autocorrectionType = .no
        // Только наша клавиатура: системную не показываем, поле нужно для курсора
        f.inputView = UIView()
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coord.edited(_:)), for: .editingChanged)
        input.field = f
        return f
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != input.text { uiView.text = input.text }
    }

    func makeCoordinator() -> Coord { Coord(input: input) }

    final class Coord: NSObject, UITextFieldDelegate {
        let input: FormulaInput
        init(input: FormulaInput) { self.input = input }
        @objc func edited(_ f: UITextField) {
            input.text = f.text ?? ""
            input.syncCursor()
        }
        func textFieldDidChangeSelection(_ textField: UITextField) {
            input.syncCursor()
        }
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
    @State private var upper = false

    private let digits: [[FormulaKey]] = [
        [.init("7"), .init("8"), .init("9"), .init("+"), .init("−", insert: "-"), .init("×", insert: "*")],
        [.init("4"), .init("5"), .init("6"), .init("(", insert: "()", backBy: 1), .init(")"), .init("÷", insert: "/")],
        [.init("1"), .init("2"), .init("3"), .init("="), .init("."), .init("±", insert: "\\pm ")],
        [.init("0"), .init("x"), .init("y"), .init("t"), .init("·", insert: "\\cdot "), .init("⌫")]
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
    private let abcLetters = ["A","B","C","D","E","F","G","H","I","J","K","L","M",
                              "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                PageTab("123", index: 0)
                PageTab("αβ", index: 1)
                PageTab("Aa", index: 2)
                PageTab("fx", index: 3)
                Spacer()
                Button("◀") { input.moveCursor(-1) }
                    .font(.caption).bold()
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Button("▶") { input.moveCursor(1) }
                    .font(.caption).bold()
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Button("Очистить") { input.text = ""; input.cursor = 0; input.field?.text = "" }
                    .font(.caption)
            }
            if page == 2 {
                abcRows
            } else {
                let rows = page == 0 ? digits : (page == 1 ? greek : latex)
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(rows[r], id: \.self) { k in
                            keyButton(k)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.1)))
    }

    private var abcRows: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(abcLetters[r * 7..<min(r * 7 + 7, abcLetters.count)], id: \.self) { l in
                        let t = upper ? l : l.lowercased()
                        Button(t) { input.insert(t) }
                            .buttonStyle(KeyStyle())
                    }
                }
            }
            HStack(spacing: 6) {
                Button(upper ? "АБВ…" : "абв…") { upper.toggle(); Haptics.tap() }
                    .font(.caption).bold()
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor.opacity(upper ? 0.4 : 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("⌫") { input.backspace() }
                    .buttonStyle(KeyStyle())
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ k: FormulaKey) -> some View {
        if k.title == "⌫" {
            Button("⌫") { input.backspace() }
                .buttonStyle(KeyStyle())
        } else {
            Button(k.title) { input.insert(k.insert, backBy: k.backBy) }
                .buttonStyle(KeyStyle())
        }
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

// MARK: - Режим 4: Сборка формулы из слотов (структурный конструктор)
struct BuildTrain: View {
    let formula: Formula
    let onGrade: (Int) -> Void
    @StateObject private var st: BuildState

    init(formula: Formula, onGrade: @escaping (Int) -> Void) {
        self.formula = formula
        self.onGrade = onGrade
        _st = StateObject(wrappedValue: BuildState(formula: formula))
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(formula.title).font(.title2).bold().multilineTextAlignment(.center)
            if st.slots.isEmpty {
                // страховка: дерево пустое — показываем формулу как есть
                LatexView(latex: formula.latex, fontSize: 24)
                Button("Дальше") { onGrade(3) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                TemplateView(node: st.tree, st: st)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))

                if let hint = st.hintText {
                    Text("💡 \(hint)").font(.callout).foregroundStyle(.yellow)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Блоки").font(.headline).foregroundStyle(.secondary)
                    FlexibleWrap {
                        ForEach(st.available, id: \.id) { leaf in
                            ChipView(leaf: leaf, selected: st.selectedID == leaf.id)
                                .onTapGesture { st.toggleSelect(leaf.id) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 150)

                if st.results == nil {
                    HStack {
                        Button("💡 \(st.hintsLeft)") { st.hint() }
                            .controlSize(.large)
                            .disabled(st.hintsLeft == 0 || st.locked)
                        Spacer()
                        Button("Сбросить") { st.reset() }
                            .controlSize(.large)
                            .disabled(st.placement.isEmpty)
                        Button("Проверить") { st.check() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!st.isComplete)
                    }
                } else if st.allCorrect || st.revealed {
                    Text(st.revealed ? "Вот эталон — запомните его" : "Идеально! ✅")
                        .font(.title3).bold().foregroundStyle(.green)
                    Button("Дальше") { onGrade(st.revealed ? 1 : BuildState.grade(for: st.score)) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Text("Верно \(Int(st.score * Double(st.slots.count))) из \(st.slots.count) — красное исправьте")
                        .font(.title3).foregroundStyle(.orange).bold()
                    HStack {
                        Button("Ещё раз") { st.clearWrong() }.controlSize(.large)
                        Spacer()
                        Button("Эталон") { st.reveal() }.controlSize(.large)
                        Button("Пропустить") { onGrade(1) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Чип с настоящим LaTeX-рендером, окрашенный по роли
struct ChipView: View {
    let leaf: BuildLeaf
    var selected = false
    var result: Bool? = nil
    var fontSize: CGFloat = 18

    var body: some View {
        MiniLatex(latex: leaf.latex, fontSize: fontSize)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(leaf.role.color.opacity(selected ? 0.55 : 0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: selected ? 3 : 1.5)
            )
            .scaleEffect(selected ? 1.08 : 1)
            .draggable(leaf.id.uuidString)
    }

    private var borderColor: Color {
        if result == true { return .green }
        if result == false { return .red }
        return leaf.role.color
    }
}

// MARK: - Слот: пустое гнездо или поставленный чип
struct SlotBox: View {
    let leaf: BuildLeaf
    var scale: CGFloat = 1
    @ObservedObject var st: BuildState

    var body: some View {
        Group {
            if let pid = st.placement[leaf.id],
               let placed = st.pool.first(where: { $0.id == pid }) {
                ChipView(leaf: placed, result: st.results?[leaf.id], fontSize: 18 * scale)
                    .onTapGesture { st.unplace(leaf.id) }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(st.hintID == leaf.id ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(st.hintID == leaf.id ? .yellow : Color.secondary)
                }
                .frame(width: boxWidth, height: 52 * scale)
                .scaleEffect(st.hintID == leaf.id ? 1.1 : 1)
                .onTapGesture {
                    if let sel = st.selectedID { st.place(sel, to: leaf.id) }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let uuid = UUID(uuidString: raw) else { return false }
                    st.place(uuid, to: leaf.id)
                    return true
                }
            }
        }
    }

    private var boxWidth: CGFloat {
        let base: CGFloat = (leaf.role == .operator || leaf.role == .relation) ? 48 : 64
        return base * scale
    }
}

// MARK: - Шаблон: дерево со слотами (дроби — настоящая черта, индексы — места)
struct TemplateView: View {
    let node: BuildNode
    var scale: CGFloat = 1
    @ObservedObject var st: BuildState

    @ViewBuilder
    var body: some View {
        switch node {
        case .row(let a):
            HStack(spacing: 8 * scale) {
                ForEach(a.indices, id: \.self) { i in
                    TemplateView(node: a[i], scale: scale, st: st)
                }
            }
        case .fraction(let n, let d):
            VStack(spacing: 2) {
                TemplateView(node: n, scale: scale * 0.9, st: st)
                Divider().frame(minWidth: 56 * scale)
                TemplateView(node: d, scale: scale * 0.9, st: st)
            }
        case .scripts(let b, let s, let u):
            HStack(alignment: .center, spacing: 2) {
                TemplateView(node: b, scale: scale, st: st)
                VStack(spacing: 0) {
                    if let u = u {
                        TemplateView(node: u, scale: scale * 0.62, st: st)
                    } else if s != nil {
                        Spacer()
                    }
                    if let s = s {
                        TemplateView(node: s, scale: scale * 0.62, st: st)
                    } else if u != nil {
                        Spacer()
                    }
                }
            }
        case .sqrt(let r):
            HStack(spacing: 0) {
                Text("√").font(.system(size: 26 * scale))
                VStack(spacing: 0) {
                    TemplateView(node: r, scale: scale * 0.9, st: st)
                    Rectangle().frame(height: 2).opacity(0.9)
                }
            }
        case .fixed(let t):
            Text(t).font(.system(size: 24 * scale))
        case .leaf(let l):
            SlotBox(leaf: l, scale: scale, st: st)
        }
    }
}

/// Простой flow-layout для чипов.
struct FlexibleWrap<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        // SwiftUI-нативного переноса строк нет — эмулируем через LazyVGrid adaptive.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 10) {
            content()
        }
    }
}

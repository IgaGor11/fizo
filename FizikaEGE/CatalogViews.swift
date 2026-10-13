import SwiftUI
import Charts

// MARK: - Каталог: разделы → темы → формулы → карточка формулы

struct CatalogView: View {
    @EnvironmentObject var store: ProgressStore
    var body: some View {
        NavigationStack {
            List(FormulasBundle.sectionsOrder, id: \.self) { sec in
                let s = store.stats(section: sec)
                NavigationLink {
                    SectionView(section: sec)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sec).font(.headline)
                        HStack {
                            ProgressView(value: s.fraction).frame(maxWidth: 140)
                            Text("\(Int(s.fraction * 100))% · ур. \(String(format: "%.1f", s.avgLevel))")
                                .font(.caption).foregroundStyle(.secondary)
                            if s.problems > 0 {
                                Text("⚠ \(s.problems)").font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Каталог")
        }
    }
}

struct SectionView: View {
    @EnvironmentObject var store: ProgressStore
    let section: String
    var topics: [String] {
        Array(Set(store.formulas.filter { $0.section == section }.map(\.topic))).sorted()
    }
    var body: some View {
        List(topics, id: \.self) { topic in
            let s = store.stats(topic: topic)
            NavigationLink {
                TopicView(topic: topic)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic).font(.headline)
                    Text("\(Int(s.fraction * 100))% · средний уровень \(String(format: "%.1f", s.avgLevel))")
                        .font(.caption).foregroundStyle(.secondary)
                    if s.avgLevel < 4 && s.fraction < 1 {
                        Text("Эта тема требует больше внимания").font(.caption2).foregroundStyle(.orange)
                    }
                    if !s.topProblems.isEmpty {
                        Text("Сложное: " + s.topProblems.map(\.title).joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.red).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle(section)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TopicView: View {
    @EnvironmentObject var store: ProgressStore
    let topic: String
    @State private var session: TrainingSession?
    var list: [Formula] { store.formulas.filter { $0.topic == topic } }
    var body: some View {
        List(list) { f in
            NavigationLink { FormulaDetailView(formula: f) } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(f.title).font(.subheadline)
                        LevelStars(level: store.prog(f.id).level)
                    }
                    Spacer()
                    StatusBadge(status: store.prog(f.id).status)
                }
            }
        }
        .navigationTitle(topic)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Тренировать") {
                let list = store.sessionFormulas(scope: list)
                if !list.isEmpty {
                    session = TrainingSession(formulas: list, mode: .mixed)
                }
            }
        }
        .sheet(item: $session) { s in TrainingHost(session: s).environmentObject(store) }
    }
}

// MARK: - Карточка формулы: данные + статистика + кривая забывания
struct FormulaDetailView: View {
    @EnvironmentObject var store: ProgressStore
    let formula: Formula
    @State private var session: TrainingSession?

    var p: FormulaProgress { store.prog(formula.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StatusBadge(status: p.status)
                    Spacer()
                    LevelStars(level: p.level)
                }
                Text(formula.title).font(.title2).bold()
                LatexView(latex: formula.latex, fontSize: 24)
                if !formula.symbols.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Обозначения").font(.headline)
                        ForEach(formula.symbols.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            HStack {
                                Text(k).font(.body.monospaced()).frame(minWidth: 60, alignment: .leading)
                                Text(v.meaning).font(.subheadline)
                                Spacer()
                                Text(v.unit).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Text(formula.description).font(.body).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Мнемоника").font(.headline)
                    Text(formula.mnemonic).font(.callout)
                        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.12)))
                }
                statsBlock
                Button("Тренировать эту формулу") {
                    session = TrainingSession(formulas: [formula], mode: .mixed)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $session) { s in TrainingHost(session: s).environmentObject(store) }
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Статистика формулы").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatTile(title: "Точность", value: "\(Int(p.accuracy * 100))%")
                StatTile(title: "Ответов", value: "\(p.correctAnswers)/\(p.totalAnswers)")
                StatTile(title: "Интервал", value: intervalText)
                StatTile(title: "Следующее", value: nextText)
                StatTile(title: "Среднее время", value: String(format: "%.1f c", p.avgTime))
                StatTile(title: "Уровень", value: "\(p.level)/10")
            }
            if !p.byMode.isEmpty {
                VStack(alignment: .leading) {
                    Text("По режимам").font(.subheadline).bold()
                    ForEach(p.byMode.sorted(by: { $0.key < $1.key }), id: \.key) { mode, st in
                        Text("\(TrainMode(rawValue: mode)?.title ?? mode): \(Int(st.accuracy * 100))% (\(st.correct)/\(st.total))")
                            .font(.caption)
                    }
                }
            }
            if p.history.count >= 1 {
                Text("История ответов").font(.subheadline).bold()
                Chart(p.history, id: \.date) { d in
                    BarMark(x: .value("День", d.date, unit: .day), y: .value("Верно", d.correct))
                        .foregroundStyle(.green)
                    BarMark(x: .value("День", d.date, unit: .day), y: .value("Ошибки", d.wrong))
                        .foregroundStyle(.red)
                }
                .frame(height: 120)
                Text("Кривая забывания: R(t) при S=\(String(format: "%.1f", p.stability)) дн.").font(.caption).foregroundStyle(.secondary)
                Chart(0..<30, id: \.self) { t in
                    LineMark(
                        x: .value("Дни", t),
                        y: .value("R", FSRS.retrievability(elapsedDays: Double(t), stability: max(0.5, p.stability)))
                    )
                }
                .chartYScale(domain: 0...1)
                .frame(height: 120)
            } else {
                Text("Пока нет истории — начните тренировку.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
    }

    private var intervalText: String {
        p.intervalDays < 1 ? "сегодня" : "\(Int(p.intervalDays)) дн."
    }
    private var nextText: String {
        let f = DateFormatter(); f.dateStyle = .short; f.locale = Locale(identifier: "ru_RU")
        return f.string(from: p.due)
    }
}

struct StatTile: View {
    let title: String; let value: String
    var body: some View {
        VStack {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
    }
}

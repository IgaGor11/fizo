import SwiftUI
import Charts

// MARK: - Развёрнутая статистика

struct StatsView: View {
    @EnvironmentObject var store: ProgressStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    heatmapCard
                    sectionsCard
                    problemsCard
                    NavigationLink {
                        ReportView().environmentObject(store)
                    } label: {
                        Label("Отчёт для учителя", systemImage: "doc.text.fill")
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Статистика")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сводка").font(.headline)
            HStack(spacing: 16) {
                PieSlice(learned: store.learnedCount, learning: store.learningCount,
                         problem: store.problemCount, untouched: store.untouchedCount)
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Выучено \(store.learnedCount)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label("В процессе \(store.learningCount)", systemImage: "hourglass").foregroundStyle(.blue)
                    Label("Проблемные \(store.problemCount)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Label("Не начато \(store.untouchedCount)", systemImage: "circle").foregroundStyle(.gray)
                }
                .font(.caption)
            }
            Divider()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatTile(title: "Streak", value: "\(store.streakDays) дн.")
                StatTile(title: "Точность", value: "\(Int(store.overallAccuracy * 100))%")
                StatTile(title: "Средний уровень", value: String(format: "%.1f", store.avgLevel))
                StatTile(title: "Время", value: hoursText)
                StatTile(title: "XP", value: "\(store.xp) · \(store.userRank)")
                StatTile(title: "До ранга", value: "\(store.xpForNextRank - store.xp) XP")
            }
            learningCurve
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }

    private var hoursText: String {
        let m = Int(store.totalSeconds / 60)
        return m < 60 ? "\(m) мин" : String(format: "%.1f ч", Double(m) / 60)
    }

    private var learningCurve: some View {
        VStack(alignment: .leading) {
            Text("Активность: ответы по дням (30 дней)").font(.caption).foregroundStyle(.secondary)
            Chart(last30, id: \.date) { d in
                BarMark(x: .value("День", d.date, unit: .day), y: .value("Ответы", d.answers))
                    .foregroundStyle(.blue)
            }
            .frame(height: 120)
        }
    }

    private var last30: [DayActivity] {
        let cal = Calendar.current
        let days = (0..<30).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
        return days.reversed().map { d in
            store.activity.first(where: { cal.isDate($0.date, inSameDayAs: d) }) ?? DayActivity(date: d, answers: 0, seconds: 0)
        }
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тепловая карта (12 недель)").font(.headline)
            HeatmapView(activity: store.activity)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("По разделам").font(.headline)
            ForEach(FormulasBundle.sectionsOrder, id: \.self) { sec in
                let s = store.stats(section: sec)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(sec).font(.subheadline)
                        Spacer()
                        Text("\(Int(s.fraction * 100))% · \(s.problems) пробл.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: s.fraction)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }

    private var problemsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Топ-10 проблемных").font(.headline)
            if store.topProblems.isEmpty {
                Text("Пока чисто — начните тренировки.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.topProblems, id: \.id) { f in
                let p = store.prog(f.id)
                HStack {
                    Text(f.title).font(.caption).lineLimit(2)
                    Spacer()
                    Text("ур.\(p.level) · \(Int(p.accuracy * 100))%").font(.caption2).foregroundStyle(.red)
                }
            }
            Text("Топ-10 сильных").font(.headline).padding(.top, 8)
            ForEach(store.topStrong, id: \.id) { f in
                let p = store.prog(f.id)
                HStack {
                    Text(f.title).font(.caption).lineLimit(2)
                    Spacer()
                    Text("ур.\(p.level) · \(Int(p.accuracy * 100))%").font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }
}

struct PieSlice: View {
    let learned, learning, problem, untouched: Int
    var total: Int { max(1, learned + learning + problem + untouched) }
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var a = -Double.pi / 2
            let parts = [(Double(learned), Color.green), (Double(learning), Color.blue),
                         (Double(problem), Color.red), (Double(untouched), Color.gray.opacity(0.4))]
            for (v, col) in parts {
                let sweep = v / Double(total) * 2 * Double.pi
                let path = Path { p in
                    p.move(to: c); p.addArc(center: c, radius: r, startAngle: .radians(a), endAngle: .radians(a + sweep), clockwise: false); p.closeSubpath()
                }
                ctx.fill(path, with: .color(col))
                a += sweep
            }
        }
    }
}

struct HeatmapView: View {
    let activity: [DayActivity]
    private let cols = Array(repeating: GridItem(.fixed(14), spacing: 3), count: 12)
    var body: some View {
        let cells = last84()
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(cells, id: \.date) { d in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: d.answers))
                    .frame(width: 14, height: 14)
            }
        }
    }
    private func last84() -> [DayActivity] {
        let cal = Calendar.current
        let days = (0..<84).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
        return days.reversed().map { d in
            activity.first(where: { cal.isDate($0.date, inSameDayAs: d) }) ?? DayActivity(date: d, answers: 0, seconds: 0)
        }
    }
    private func color(for answers: Int) -> Color {
        switch answers {
        case 0: return Color.secondary.opacity(0.15)
        case 1...4: return Color.green.opacity(0.35)
        case 5...14: return Color.green.opacity(0.6)
        default: return Color.green
        }
    }
}

// MARK: - Отчёт для учителя: экран + экспорт PDF
struct ReportView: View {
    @EnvironmentObject var store: ProgressStore
    @State private var pdfURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Отчёт о подготовке к ЕГЭ по физике")
                    .font(.title2).bold()
                let name = store.studentName.isEmpty ? "Ученик" : store.studentName
                Text("\(name) · \(Date().formatted(date: .long, time: .omitted)) · физика, ЕГЭ (ФИПИ 2026)")
                    .font(.callout).foregroundStyle(.secondary)

                reportSection("Общий прогресс") {
                    Text("Выучено: \(store.learnedCount)/\(store.totalCount) (\(Int(store.progressFraction * 100))%)")
                    Text("Средний уровень: \(String(format: "%.1f", store.avgLevel)) · Точность: \(Int(store.overallAccuracy * 100))%")
                    Text("Streak: \(store.streakDays) дн. · XP: \(store.xp) (\(store.userRank))")
                }

                reportSection("По разделам") {
                    ForEach(FormulasBundle.sectionsOrder, id: \.self) { sec in
                        let s = store.stats(section: sec)
                        Text("\(sec): \(Int(s.fraction * 100))% · уровень \(String(format: "%.1f", s.avgLevel)) · проблемных: \(s.problems)")
                    }
                }

                reportSection("По темам") {
                    ForEach(allTopics, id: \.self) { t in
                        let s = store.stats(topic: t)
                        let mark = s.fraction >= 0.8 ? "Освоено" : (s.fraction >= 0.4 ? "В процессе" : "Требует внимания")
                        Text("\(t): \(Int(s.fraction * 100))% · \(mark)")
                    }
                }

                reportSection("Топ проблемных формул") {
                    if store.topProblems.isEmpty {
                        Text("Пока нет данных — начните тренировки.")
                    }
                    ForEach(store.topProblems, id: \.id) { f in
                        let p = store.prog(f.id)
                        Text("• \(f.title) — уровень \(p.level), точность \(Int(p.accuracy * 100))%")
                    }
                }

                reportSection("Топ сильных формул") {
                    ForEach(store.topStrong, id: \.id) { f in
                        let p = store.prog(f.id)
                        Text("• \(f.title) — уровень \(p.level), точность \(Int(p.accuracy * 100))%")
                    }
                }

                reportSection("Рекомендации") {
                    ForEach(TeacherReport.recommendations(store: store), id: \.self) { r in
                        Text("• \(r)")
                    }
                }

                Text("Шкала: 1–3 «Не освоено», 4–6 «Частично освоено», 7–8 «Освоено», 9–10 «Отлично».")
                    .font(.caption).foregroundStyle(.secondary)

                if let url = pdfURL {
                    ShareLink(item: url) {
                        Label("Отправить PDF (AirDrop, Mail, Telegram)", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Отчёт для учителя")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if pdfURL == nil {
                pdfURL = TeacherReport.makePDF(store: store)
                Haptics.success()
            }
        }
    }

    private var allTopics: [String] {
        Array(Set(store.formulas.map(\.topic))).sorted()
    }

    @ViewBuilder
    private func reportSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3).bold()
            content().font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
    }
}

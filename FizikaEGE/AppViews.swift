import SwiftUI

@main
struct FizikaEGEApp: App {
    @StateObject private var store = ProgressStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark) // тёмная тема по умолчанию, в настройках можно сменить
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: ProgressStore
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("Учиться", systemImage: "graduationcap.fill") }
                .tag(0)
            CatalogView()
                .tabItem { Label("Каталог", systemImage: "books.vertical.fill") }
                .tag(1)
            StatsView()
                .tabItem { Label("Статистика", systemImage: "chart.bar.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Ещё", systemImage: "gearshape.fill") }
                .tag(3)
        }
    }
}

// MARK: - Главный экран
struct HomeView: View {
    @EnvironmentObject var store: ProgressStore
    @Binding var tab: Int
    @State private var session: TrainingSession?
    @State private var showConfetti = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    continueCard
                    countsRow
                    sectionsQuick
                }
                .padding()
            }
            .navigationTitle("Физика · ЕГЭ")
            .sheet(item: $session) { s in
                TrainingHost(session: s).environmentObject(store)
            }
            .overlay { if showConfetti { ConfettiView() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Общий прогресс").font(.headline)
            ProgressView(value: store.progressFraction)
            HStack {
                Text("\(Int(store.progressFraction * 100))% выучено · \(store.learnedCount)/\(store.totalCount)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Label("\(store.streakDays) дн.", systemImage: "flame.fill")
                    .font(.caption).foregroundStyle(.orange)
                Label("\(store.xp) XP · \(store.userRank)", systemImage: "star.fill")
                    .font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
    }

    private var continueCard: some View {
        let due = store.dueFormulas()
        return VStack(alignment: .leading, spacing: 8) {
            Text("К повторению: \(due.count)").font(.headline)
            Text(due.isEmpty ? "Всё повторено! Загляните завтра или возьмите новые формулы." : "FSRS подобрал самое срочное — начните с него.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                session = TrainingSession(formulas: Array(due.prefix(20)), mode: .mixed)
            } label: {
                Label("Продолжить тренировку", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(due.isEmpty)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.12)))
    }

    private var countsRow: some View {
        HStack(spacing: 12) {
            CountChip(title: "Выучено", value: store.learnedCount, color: .green, icon: "checkmark.circle.fill")
            CountChip(title: "В процессе", value: store.learningCount, color: .blue, icon: "hourglass")
            CountChip(title: "Проблемные", value: store.problemCount, color: .red, icon: "exclamationmark.triangle.fill")
            CountChip(title: "Не начато", value: store.untouchedCount, color: .gray, icon: "circle")
        }
    }

    private var sectionsQuick: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Разделы").font(.headline)
            ForEach(FormulasBundle.sectionsOrder, id: \.self) { sec in
                let s = store.stats(section: sec)
                NavigationLink {
                    SectionView(section: sec)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(sec).font(.subheadline).bold()
                            Spacer()
                            Text("\(Int(s.fraction * 100))%").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: s.fraction)
                    }
                    .padding(.vertical, 6)
                }
            }
            Button("Открыть каталог") { tab = 1 }
                .font(.caption)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }
}

struct CountChip: View {
    let title: String; let value: Int; let color: Color; let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(value)").font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ProgressStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Ученик") {
                    TextField("ФИО для отчёта учителю", text: $store.studentName)
                }
                Section("О приложении") {
                    LabeledContent("Формул", value: "\(store.totalCount)")
                    LabeledContent("Алгоритм", value: "FSRS + уровни 1–10")
                    LabeledContent("Режим", value: "Полностью офлайн")
                }
            }
            .navigationTitle("Ещё")
        }
    }
}

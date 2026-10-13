import Foundation
import UIKit

// MARK: - Отчёт для учителя: локальная генерация PDF
// Титул, прогресс, таблицы по разделам/темам, топ-10 слабых/сильных,
// динамика 30 дней, рекомендации, шкала интерпретации. Показ — экран ReportView, отправка — ShareLink.

enum TeacherReport {
    static func makePDF(store: ProgressStore) -> URL? {
        let name = store.studentName.isEmpty ? "Ученик" : store.studentName
        let df: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "ru_RU"); return f }()
        let dateStr = df.string(from: Date())

        let pageW: CGFloat = 595  // A4 @72dpi
        let margin: CGFloat = 40
        let contentW = pageW - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: 842))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fizika-ege-report.pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = margin
                func draw(_ text: String, font: UIFont, color: UIColor = .black, gap: CGFloat = 6) {
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let h = (text as NSString).boundingRect(with: CGSize(width: contentW, height: 1000),
                        options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height
                    if y + h > 800 { ctx.beginPage(); y = margin }
                    (text as NSString).draw(in: CGRect(x: margin, y: y, width: contentW, height: h + 4), withAttributes: attrs)
                    y += h + gap
                }
                let title = UIFont.boldSystemFont(ofSize: 20)
                let h1 = UIFont.boldSystemFont(ofSize: 15)
                let body = UIFont.systemFont(ofSize: 11)
                let small = UIFont.systemFont(ofSize: 10)

                draw("Отчёт о подготовке к ЕГЭ по физике", font: title)
                draw("Ученик: \(name) · Дата: \(dateStr) · Предмет: физика, ЕГЭ (кодификатор ФИПИ 2026)", font: body)
                draw("Streak: \(store.streakDays) дн. · XP: \(store.xp) (\(store.userRank)) · Время: \(Int(store.totalSeconds / 60)) мин", font: body)

                draw("Общий прогресс", font: h1)
                draw("Выучено: \(store.learnedCount)/\(store.totalCount) (\(Int(store.progressFraction * 100))%) · " +
                     "Средний уровень: \(String(format: "%.1f", store.avgLevel)) · Точность: \(Int(store.overallAccuracy * 100))% · " +
                     "В процессе: \(store.learningCount) · Проблемные: \(store.problemCount) · Не начато: \(store.untouchedCount)", font: body)

                draw("По разделам", font: h1)
                for sec in FormulasBundle.sectionsOrder {
                    let s = store.stats(section: sec)
                    draw("\(sec): \(Int(s.fraction * 100))% · средний уровень \(String(format: "%.1f", s.avgLevel)) · проблемных: \(s.problems)", font: body, gap: 3)
                }

                draw("По темам", font: h1)
                let topics = Array(Set(store.formulas.map(\.topic))).sorted()
                for t in topics {
                    let s = store.stats(topic: t)
                    let mark = s.fraction >= 0.8 ? "Освоено" : (s.fraction >= 0.4 ? "В процессе" : "Требует внимания")
                    draw("\(t): \(Int(s.fraction * 100))% · ур. \(String(format: "%.1f", s.avgLevel)) · \(mark)", font: small, gap: 2)
                }

                draw("Топ-10 проблемных формул", font: h1)
                if store.topProblems.isEmpty { draw("— нет данных —", font: body) }
                for f in store.topProblems {
                    let p = store.prog(f.id)
                    draw("• \(f.title) (\(f.topic)) — уровень \(p.level), точность \(Int(p.accuracy * 100))%, ошибок \(p.totalAnswers - p.correctAnswers). Рекомендация: повторить в режиме ручного ввода.", font: small, gap: 2)
                }

                draw("Топ-10 сильных формул", font: h1)
                for f in store.topStrong {
                    let p = store.prog(f.id)
                    draw("• \(f.title) — уровень \(p.level), точность \(Int(p.accuracy * 100))%.", font: small, gap: 2)
                }

                draw("Рекомендации", font: h1)
                for r in recommendations(store: store) { draw("• \(r)", font: body, gap: 3) }

                draw("Как интерпретировать уровни: 1–3 «Не освоено», 4–6 «Частично освоено», 7–8 «Освоено», 9–10 «Отлично». " +
                     "Статусы: «Выучено» (уровень ≥7 и точность ≥85%), «Проблемная» (≥4 провалов и точность <60%).", font: small)
            }
            return url
        } catch {
            print("PDF error: \(error)")
            return nil
        }
    }

    static func recommendations(store: ProgressStore) -> [String] {
        var out: [String] = []
        // Самый слабый раздел
        let secs = FormulasBundle.sectionsOrder.map { ($0, store.stats(section: $0)) }
        if let worst = secs.min(by: { $0.1.avgLevel < $1.1.avgLevel }), worst.1.avgLevel < 5 {
            out.append("Обратить внимание на раздел «\(worst.0)» — средний уровень \(String(format: "%.1f", worst.1.avgLevel)) ниже среднего.")
        }
        // Слабые темы
        let topics = Array(Set(store.formulas.map(\.topic))).sorted()
        let weak = topics.map { ($0, store.stats(topic: $0)) }.filter { $0.1.avgLevel < 4 && $0.1.fraction < 1 }.prefix(3)
        for (t, _) in weak { out.append("Тема «\(t)» требует больше внимания: тренируйте ежедневно по 10–15 минут.") }
        if store.streakDays < 3 { out.append("Занимайтесь каждый день: streak сейчас \(store.streakDays) дн., цель — 7+.") }
        if store.problemCount > 0 { out.append("Проблемных формул: \(store.problemCount) — разберите их мнемоники и повторите в режиме «Сборка».") }
        if out.isEmpty { out.append("Отличная динамика! Держите streak и повторяйте по расписанию FSRS.") }
        return out
    }
}

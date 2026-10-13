import Foundation

// MARK: - FSRS: Free Spaced Repetition Scheduler (упрощённый FSRS-4.5)
// Трёхкомпонентная модель памяти: Retrievability (R), Stability (S), Difficulty (D).
// Grades: 1 «Не помню» / 2 «Смутно» / 3 «Помню» / 4 «Легко».
// Источник идеи: Ye et al., FSRS (github.com/open-spaced-repetition/fsrs4anki).
// Здесь — компактная честная реализация формул FSRS-4.5 с дефолтными весами,
// достаточная для офлайн-приложения. Параметры сохраняются в FormulaProgress.

enum FSRS {
    /// Дефолтные веса FSRS-4.5 (17 параметров).
    static let w: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956,
        6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835,
        0.0614, 0.2629, 1.5501, 0.0072, 0.2
    ]

    static let decay: Double = -0.5
    static let factor: Double = 0.9  // целевое удержание 90%

    /// R(t,S) — вероятность вспомнить через t дней при стабильности S.
    static func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        guard s > 0, t >= 0 else { return t <= 0 ? 1.0 : 0.0 }
        return pow(1 + factor * t / s, decay)
    }

    /// Начальная стабильность для первой оценки.
    static func initStability(grade g: Int) -> Double {
        precondition(1...4 ~= g)
        return max(0.1, w[g - 1])
    }

    /// Начальная сложность для первой оценки.
    static func initDifficulty(grade g: Int) -> Double {
        let d = w[4] - exp((Double(g) - 3) * w[5])
        return min(10, max(1, d))
    }

    /// Обновление сложности: линейное затухание к среднему + коррекция на оценку.
    static func nextDifficulty(d: Double, grade g: Int) -> Double {
        let delta = -w[6] * (Double(g) - 3)
        let next = d + delta * (10 - d) / 9
        return min(10, max(1, next))
    }

    /// Обновление стабильности при успешном повторении.
    static func nextRecallStability(d: Double, s: Double, r: Double, grade g: Int) -> Double {
        let hardPenalty: Double = (g == 2) ? w[15] : 1.0
        let easyBonus: Double = (g == 4) ? w[16] : 1.0
        let inc = exp(w[8])
            * (11 - d)
            * pow(s, -w[9])
            * (exp(w[10] * (1 - r)) - 1)
            * hardPenalty
            * easyBonus
        return max(0.1, s * (1 + max(0, inc)))
    }

    /// Обновление стабильности при провале (grade == 1).
    static func nextForgetStability(d: Double, s: Double, r: Double) -> Double {
        let v = w[11]
            * pow(d, -w[12])
            * (pow(s + 1, w[13]) - 1)
            * exp(w[14] * (1 - r))
        return max(0.1, min(s, v))
    }

    /// Следующий интервал в днях для целевого удержания 0.9.
    static func nextInterval(stability s: Double, easyBonus: Double = 1.0) -> Double {
        let ivl = s / factor * (pow(factor, 1 / decay) - 1)
        return max(0, ivl * easyBonus)
    }

    /// Fuzz: лёгкий джиттер, чтобы карточки не сбивались в один день.
    static func fuzzed(_ ivl: Double) -> Double {
        guard ivl >= 2.5 else { return ivl }
        let r = Double.random(in: -0.05...0.05)
        return max(1, (ivl * (1 + r)).rounded())
    }

    /// Один шаг FSRS. Возвращает (stability, difficulty, intervalDays, due).
    /// - Parameters:
    ///   - progress: текущий прогресс (inout обновляются S/D/interval/due/reps/lapses)
    ///   - grade: 1...4
    ///   - now: момент ответа
    ///   - elapsedDays: сколько дней прошло с прошлого повторения (для R)
    static func review(progress: inout FormulaProgress, grade: Int, now: Date = Date()) {
        precondition(1...4 ~= grade)
        let elapsed = max(0, now.timeIntervalSince(progress.due) / 86400 + progress.intervalDays)
        if progress.reps == 0 {
            // Первое знакомство
            progress.stability = initStability(grade: grade)
            progress.difficulty = initDifficulty(grade: grade)
        } else {
            let r = retrievability(elapsedDays: elapsed, stability: max(0.1, progress.stability))
            progress.difficulty = nextDifficulty(d: progress.difficulty, grade: grade)
            if grade == 1 {
                progress.stability = nextForgetStability(d: progress.difficulty, s: progress.stability, r: r)
                progress.lapses += 1
            } else {
                progress.stability = nextRecallStability(d: progress.difficulty, s: progress.stability, r: r, grade: grade)
            }
        }
        var ivl: Double
        switch grade {
        case 1: ivl = 0                              // провал: показать снова сегодня
        case 2: ivl = max(1, nextInterval(stability: progress.stability) * 0.7)
        case 3: ivl = max(1, nextInterval(stability: progress.stability))
        case 4:
            ivl = max(2, nextInterval(stability: progress.stability, easyBonus: 1.3))
        default: ivl = 1
        }
        // Короткие интервалы первого дня: grade 1 → сегодня, grade 2 → завтра
        if progress.reps == 0 && grade == 1 { ivl = 0 }
        if progress.reps == 0 && grade == 2 { ivl = 1 }
        progress.intervalDays = grade == 1 && progress.reps == 0 ? 0 : fuzzed(ivl)
        progress.due = Calendar.current.date(byAdding: .day, value: Int(progress.intervalDays), to: Calendar.current.startOfDay(for: now)) ?? now
        progress.reps += 1
        progress.lastGrade = grade
    }
}

import Foundation

// MARK: - Система уровней формул 1...10
// Повышение: N правильных подряд (порог растёт с уровнем).
// Понижение: ошибка → уровень −1 (минимум 1), счётчик сбрасывается.
// Порог: threshold(level) = round(3 + level * 1.5).
// L1→2: 5, L9→10: 17. Уровень влияет на стартовый интервал FSRS.

enum LevelSystem {
    static func threshold(for level: Int) -> Int {
        let l = min(10, max(1, level))
        return Int((3.0 + Double(l) * 1.5).rounded())
    }

    static func name(for level: Int) -> String {
        switch level {
        case 1...2: return "Новичок"
        case 3...4: return "Ученик"
        case 5...6: return "Практик"
        case 7...8: return "Знаток"
        default: return "Эксперт"
        }
    }

    /// Начальный интервал (дней) для нового повторения по уровню.
    static func baseInterval(for level: Int) -> Double {
        switch level {
        case 1: return 1
        case 2: return 2
        case 3: return 4
        case 4: return 7
        case 5: return 12
        case 6: return 20
        case 7...8: return 30
        default: return 45
        }
    }

    /// Применить результат ответа к прогрессу. correct = grade >= 3.
    /// Возвращает (levelUp, levelDown).
    @discardableResult
    static func apply(progress: inout FormulaProgress, correct: Bool) -> (up: Bool, down: Bool) {
        if correct {
            progress.streakCorrect += 1
            if progress.level < 10 && progress.streakCorrect >= threshold(for: progress.level) {
                progress.level += 1
                progress.streakCorrect = 0
                return (true, false)
            }
            return (false, false)
        } else {
            progress.streakCorrect = 0
            if progress.level > 1 {
                progress.level -= 1
                return (false, true)
            }
            return (false, false)
        }
    }

    /// Критерий учителя по уровню.
    static func teacherMark(for level: Int) -> String {
        switch level {
        case 1...3: return "Не освоено"
        case 4...6: return "Частично освоено"
        case 7...8: return "Освоено"
        default: return "Отлично"
        }
    }
}

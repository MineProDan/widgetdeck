import Foundation

/// Grade arithmetic for S-06. Pure functions, no I/O.
public enum GradeMath {
    /// A course's current percentage (0…100+), or `nil` with no graded work.
    ///
    /// - No categories: total points earned / total points possible.
    /// - With categories: each category's points percentage, weighted by its weight. Categories with
    ///   no graded entries yet are left out and the remaining weights are re-normalised, so the
    ///   number is "your grade so far". Uncategorised entries (or entries whose category was
    ///   deleted) form one extra bucket that takes the weight not assigned to any category
    ///   (100 − Σ weights); when that's 0 they don't count.
    public static func coursePercent(entries: [GradeEntry], categories: [GradeCategory]) -> Double? {
        let graded = entries.filter { $0.maxScore > 0 }
        guard !graded.isEmpty else { return nil }
        if categories.isEmpty { return pointsPercent(graded) }

        let known = Set(categories.map(\.id))
        var weighted = 0.0
        var weightUsed = 0.0
        for category in categories where category.weight > 0 {
            let inCategory = graded.filter { $0.categoryID == category.id }
            guard let percent = pointsPercent(inCategory) else { continue }
            weighted += percent * category.weight
            weightUsed += category.weight
        }
        let loose = graded.filter { $0.categoryID.map { !known.contains($0) } ?? true }
        let looseWeight = max(0, 100 - categories.reduce(0) { $0 + max(0, $1.weight) })
        if looseWeight > 0, let percent = pointsPercent(loose) {
            weighted += percent * looseWeight
            weightUsed += looseWeight
        }
        return weightUsed > 0 ? weighted / weightUsed : nil
    }

    /// Σ score / Σ max × 100.
    public static func pointsPercent(_ entries: [GradeEntry]) -> Double? {
        let possible = entries.reduce(0) { $0 + max(0, $1.maxScore) }
        guard possible > 0 else { return nil }
        return entries.reduce(0) { $0 + $1.score } / possible * 100
    }

    /// Letter and grade points for a percentage on `scale`.
    public static func grade(for percent: Double, scale: GradeScale) -> (letter: String, points: Double) {
        // Round to 2 decimals first so 89.999… (float noise) doesn't drop a band.
        let value = (percent * 100).rounded() / 100
        let band = scale.bands.first { value >= $0.min } ?? scale.bands[scale.bands.count - 1]
        return (band.letter, band.points)
    }

    /// Credit-weighted GPA over courses that have a percentage. `nil` when none do.
    /// - Parameter courses: (percent, credits); credits ≤ 0 count as 1.
    public static func gpa(_ courses: [(percent: Double, credits: Double)], scale: GradeScale) -> Double? {
        guard !courses.isEmpty else { return nil }
        var points = 0.0
        var credits = 0.0
        for course in courses {
            let weight = course.credits > 0 ? course.credits : 1
            points += grade(for: course.percent, scale: scale).points * weight
            credits += weight
        }
        return points / credits
    }

    /// "What do I need on the final?"
    public enum FinalNeed: Equatable, Sendable {
        /// The target is already guaranteed (even 0% on the final reaches it).
        case secured
        /// The final score (percent) needed.
        case needs(Double)
        /// More than `max` percent would be needed (default 100).
        case outOfReach(Double)
        /// The final's weight must be between 0 and 100 (exclusive of 0).
        case invalid
    }

    /// The score needed on a final worth `finalWeight` percent of the course to finish at `target`
    /// percent, given `current` percent on everything else:
    /// `target = current × (1 − w) + final × w` → `final = (target − current × (1 − w)) / w`.
    public static func neededOnFinal(current: Double, target: Double, finalWeight: Double, maxScore: Double = 100) -> FinalNeed {
        guard finalWeight > 0, finalWeight <= 100 else { return .invalid }
        let w = finalWeight / 100
        let needed = (target - current * (1 - w)) / w
        // Tolerance for float noise: 89.99999 counts as 90.
        let rounded = (needed * 100).rounded() / 100
        if rounded <= 0 { return .secured }
        if rounded > maxScore { return .outOfReach(rounded) }
        return .needs(rounded)
    }
}

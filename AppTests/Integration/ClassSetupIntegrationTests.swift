import CoreKit
import Foundation
import StudentFeature
import Testing

/// Class setup answers must reach the saved course (the setup flow is hard to drive in the Simulator).
@MainActor
@Suite("Class setup saves answers")
struct ClassSetupIntegrationTests {
    @Test func leaveHeadsUpTurnsOnAutoLeaveBy() async throws {
        let repo = FileStudentRepository(appGroup: AppGroupContainer.temporary())
        let course = Course(code: "ICS 31", paint: .coral)
        try await repo.save(course)
        let store = StudentStore(repository: repo)
        await store.applySetup(.init(room: "ICS 192", travel: .driving, headsUp: .leave), to: course)
        let saved = try #require(try await repo.courses().first)
        #expect(saved.leaveAuto == true)
        #expect(saved.travelMode == .driving)
        #expect(saved.room == "ICS 192")
        #expect(saved.isSetUp == true)
    }

    @Test func before15MakesAReminderRule() async throws {
        let repo = FileStudentRepository(appGroup: AppGroupContainer.temporary())
        let course = Course(code: "ICS 31", paint: .coral)
        try await repo.save(course)
        let store = StudentStore(repository: repo)
        await store.applySetup(.init(room: "", travel: nil, headsUp: .before15), to: course)
        let rule = try #require(try await repo.reminderRules().first)
        #expect(rule.isEnabled)
        #expect(rule.courseID == course.id)
    }
}

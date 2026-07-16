import XCTest
@testable import Strand

@MainActor
final class CoachConversationStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoachConversationStoreTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("conversations.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testConversationRoundTripPreservesMessagesAndSelection() {
        let first = ChatMessage(role: .user, text: "How is my sleep trending?")
        let reply = ChatMessage(role: .assistant, text: "Your rest score is improving.")
        let store = CoachConversationStore(fileURL: fileURL)

        XCTAssertEqual(store.restoreInitialMessages(currentMessages: [first, reply]), [first, reply])
        XCTAssertEqual(store.selectedConversation?.title, "How is my sleep trending?")

        let reloaded = CoachConversationStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.selectedConversation?.chatMessages, [first, reply])
    }

    func testNewConversationKeepsThePreviousTranscript() {
        let first = ChatMessage(role: .user, text: "Plan today's training")
        let store = CoachConversationStore(fileURL: fileURL)
        _ = store.restoreInitialMessages(currentMessages: [first])

        XCTAssertEqual(store.startNewConversation(currentMessages: [first]), [])
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertNil(store.selectedConversation)
        XCTAssertTrue(store.conversations.contains { $0.chatMessages == [first] })
    }

    func testEmptyCoachDoesNotCreateASavedConversation() {
        let store = CoachConversationStore(fileURL: fileURL)

        XCTAssertEqual(store.restoreInitialMessages(currentMessages: []), [])
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertNil(store.selectedID)
    }

    func testFirstMessageCreatesConversationLazily() {
        let message = ChatMessage(role: .user, text: "Start when I actually send")
        let store = CoachConversationStore(fileURL: fileURL)
        _ = store.restoreInitialMessages(currentMessages: [])

        store.updateSelected(with: [message])

        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.selectedConversation?.chatMessages, [message])
    }

    func testMalformedArchiveFallsBackToAnEmptyStore() throws {
        try Data("not-json".utf8).write(to: fileURL)

        let store = CoachConversationStore(fileURL: fileURL)

        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertNil(store.selectedID)
    }

    func testLegacyEmptyPlaceholderIsDiscarded() throws {
        let placeholder = CoachConversation()
        try JSONEncoder().encode([placeholder]).write(to: fileURL)

        let store = CoachConversationStore(fileURL: fileURL)

        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertNil(store.selectedID)
    }

    func testSavingAnUnchangedTranscriptDoesNotChangeItsTimestamp() {
        let message = ChatMessage(role: .user, text: "Keep this timestamp stable")
        let store = CoachConversationStore(fileURL: fileURL)
        _ = store.restoreInitialMessages(currentMessages: [message])
        let timestamp = store.selectedConversation?.updatedAt

        store.updateSelected(with: [message])

        XCTAssertEqual(store.selectedConversation?.updatedAt, timestamp)
    }

    func testDeletingSelectedConversationActivatesTheNextConversation() {
        let first = ChatMessage(role: .user, text: "First")
        let second = ChatMessage(role: .user, text: "Second")
        let store = CoachConversationStore(fileURL: fileURL)
        _ = store.restoreInitialMessages(currentMessages: [first])
        _ = store.startNewConversation(currentMessages: [first])
        store.updateSelected(with: [second])
        let selected = store.selectedID

        let replacement = store.delete(selected!, currentMessages: [second])

        XCTAssertEqual(replacement, [first])
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.selectedConversation?.chatMessages, [first])
    }
}

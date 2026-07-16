import Foundation
import Combine

/// One locally stored Coach conversation. The provider/network engine continues to own the active
/// message array; this archive only lets the iOS chat UI switch between local transcripts.
struct CoachConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [CoachConversationMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         title: String = String(localized: "New conversation"),
         messages: [ChatMessage] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages.map(CoachConversationMessage.init)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var chatMessages: [ChatMessage] {
        messages.compactMap(\.chatMessage)
    }
}

struct CoachConversationMessage: Codable, Equatable {
    let id: UUID
    let role: String
    let text: String

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role.rawValue
        text = message.text
    }

    var chatMessage: ChatMessage? {
        guard let role = ChatMessage.Role(rawValue: role) else { return nil }
        return ChatMessage(id: id, role: role, text: text)
    }
}

/// File-backed, device-local transcript archive for the Coach conversation drawer.
///
/// Conversation text can contain health context, so it stays in Application Support and uses
/// complete file protection on iOS. It is never uploaded or added to a provider request by this
/// store; selecting a conversation simply restores its messages into the existing engine.
@MainActor
final class CoachConversationStore: ObservableObject {
    @Published private(set) var conversations: [CoachConversation]
    @Published private(set) var selectedID: UUID?

    private let fileURL: URL
    private let fileManager: FileManager
    private static let conversationTitleLimit = 72

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        conversations = Self.load(from: self.fileURL)
            .sorted { $0.updatedAt > $1.updatedAt }
        selectedID = conversations.first?.id
    }

    var selectedConversation: CoachConversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    /// Select the newest saved conversation, or create one around the engine's current messages.
    func restoreInitialMessages(currentMessages: [ChatMessage]) -> [ChatMessage] {
        if let selectedConversation {
            if selectedConversation.messages.isEmpty, !currentMessages.isEmpty {
                updateSelected(with: currentMessages)
                return currentMessages
            }
            return selectedConversation.chatMessages
        }

        // An empty Coach is not a saved conversation. Keep the drawer honestly empty until the
        // user sends something; this also avoids a permanent "New conversation" row on first open.
        guard !currentMessages.isEmpty else { return [] }

        let conversation = CoachConversation(
            title: Self.title(for: currentMessages),
            messages: currentMessages
        )
        conversations = [conversation]
        selectedID = conversation.id
        persist()
        return currentMessages
    }

    /// Save the current transcript and return a fresh empty conversation.
    func startNewConversation(currentMessages: [ChatMessage]) -> [ChatMessage] {
        updateSelected(with: currentMessages)
        selectedID = nil
        return []
    }

    /// Save the current transcript, switch selection, and return the selected transcript.
    func select(_ id: UUID, currentMessages: [ChatMessage]) -> [ChatMessage]? {
        guard id != selectedID,
              let target = conversations.first(where: { $0.id == id }) else { return nil }
        updateSelected(with: currentMessages)
        selectedID = id
        persist()
        return target.chatMessages
    }

    func updateSelected(with messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }

        guard let selectedID else {
            let conversation = CoachConversation(
                title: Self.title(for: messages),
                messages: messages
            )
            conversations.insert(conversation, at: 0)
            self.selectedID = conversation.id
            persist()
            return
        }

        guard let index = conversations.firstIndex(where: { $0.id == selectedID }) else { return }
        let archivedMessages = messages.map(CoachConversationMessage.init)
        guard conversations[index].messages != archivedMessages else { return }
        conversations[index].messages = archivedMessages
        conversations[index].title = Self.title(for: messages)
        conversations[index].updatedAt = Date()
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ id: UUID, currentMessages: [ChatMessage]) -> [ChatMessage]? {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return nil }
        let deletingSelected = selectedID == id
        if !deletingSelected {
            updateSelected(with: currentMessages)
        }
        conversations.remove(at: index)

        guard deletingSelected else {
            persist()
            return nil
        }

        if let next = conversations.first {
            selectedID = next.id
            persist()
            return next.chatMessages
        }

        selectedID = nil
        persist()
        return []
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(conversations)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
        } catch {
            // Conversation history is a convenience layer around the live engine. A failed local
            // archive write must never block asking the Coach or alter its provider behavior.
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("NOOP", isDirectory: true)
            .appendingPathComponent("CoachConversations.json", isDirectory: false)
    }

    private static func load(from fileURL: URL) -> [CoachConversation] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CoachConversation].self, from: data) else {
            return []
        }
        // Early Coach UI builds persisted an empty "New conversation" row as soon as the page
        // opened. Empty transcripts are not conversations, so discard those stale placeholders.
        return decoded.filter { !$0.messages.isEmpty }
    }

    private static func title(for messages: [ChatMessage]) -> String {
        guard let first = messages.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return String(localized: "New conversation")
        }

        let firstLine = first.text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? String(localized: "New conversation")
        guard firstLine.count > conversationTitleLimit else { return firstLine }
        return String(firstLine.prefix(conversationTitleLimit)) + "…"
    }
}

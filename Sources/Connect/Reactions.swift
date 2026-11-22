import SwiftUI

// MARK: - Reactions

/// A reaction travels as its own row in the notes table with the body
/// "[react:<note id>:<emoji>]", so the database doesn't need to change. Each person has at most
/// one reaction per note: the newest row wins, and an empty emoji takes the reaction back.
struct Reaction {
    static let choices = ["❤️", "😂", "🥰", "😮", "😢", "👍"]

    let noteID: UUID
    let emoji: String

    static func token(for noteID: UUID, emoji: String) -> String {
        "[react:\(noteID.uuidString.lowercased()):\(emoji)]"
    }

    init?(body: String) {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard b.hasPrefix("[react:"), b.hasSuffix("]") else { return nil }
        let inner = b.dropFirst(7).dropLast()
        guard let colon = inner.firstIndex(of: ":"),
              let id = UUID(uuidString: String(inner[..<colon])) else { return nil }
        noteID = id
        emoji = String(inner[inner.index(after: colon)...])
    }
}

extension Note {
    var reaction: Reaction? { Reaction(body: body) }
}

/// The reactions on one note, plus a button to add yours when it's from your partner.
struct ReactionBar: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    @State private var picking = false

    var body: some View {
        let given = store.reactions(on: note.id)
        let canReact = !store.isMine(note)
        if !given.isEmpty || canReact {
            HStack(spacing: 4) {
                ForEach(given, id: \.email) { r in
                    let mine = r.email == store.myEmail
                    Text(r.emoji)
                        .font(.system(size: 13))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(mine ? Theme.accentSoft : Theme.glass2))
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                        .help(mine ? "You reacted · click to take it back" : "\(firstName(store.partnerName)) reacted")
                        .onTapGesture { if mine { store.react(to: note, with: "") } }
                }
                if canReact {
                    Button { picking.toggle() } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.ink3)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.glass))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("React")
                    .popover(isPresented: $picking, arrowEdge: .bottom) {
                        picker(current: given.first(where: { $0.email == store.myEmail })?.emoji)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
        }
    }

    private func picker(current: String?) -> some View {
        HStack(spacing: 2) {
            ForEach(Reaction.choices, id: \.self) { e in
                Button {
                    store.react(to: note, with: e == current ? "" : e)
                    picking = false
                } label: {
                    Text(e).font(.system(size: 20))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(e == current ? Theme.accentSoft : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
    }
}

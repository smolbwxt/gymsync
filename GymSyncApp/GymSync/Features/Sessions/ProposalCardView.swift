import SwiftUI
import Supabase

/// Presentational card for a single routine proposal.
/// Receives all data and callbacks; owns no async work itself.
struct ProposalCardView: View {
    let proposal: RoutineProposal
    let votes: [ProposalVote]
    let usernames: [UUID: String]
    let myID: UUID?
    let onApprove: () async -> Void
    let onVeto:    () async -> Void

    private var approveCount: Int { votes.filter { $0.vote == .approve }.count }
    private var vetoCount: Int    { votes.filter { $0.vote == .veto }.count }
    private var myVote: ProposalVote? { votes.first { $0.userID == myID } }
    private var isOpen: Bool { proposal.status == .open }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: proposer + status tint
            HStack {
                Text(proposerLabel)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                statusBadge
            }

            // Description
            Text(proposalDescription)
                .font(.footnote)
                .foregroundStyle(proposal.status == .vetoed ? .secondary : .primary)
                .strikethrough(proposal.status == .vetoed)

            // Vote counts
            HStack(spacing: 16) {
                Label("\(approveCount)", systemImage: "hand.thumbsup")
                    .font(.caption).foregroundStyle(.green)
                Label("\(vetoCount)", systemImage: "hand.thumbsdown")
                    .font(.caption).foregroundStyle(.red)
            }

            // Action buttons (only when open and I haven't voted)
            if isOpen, myVote == nil {
                HStack(spacing: 12) {
                    Button {
                        Task { await onApprove() }
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button {
                        Task { await onVeto() }
                    } label: {
                        Label("Veto", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(rowBackground)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var statusBadge: some View {
        switch proposal.status {
        case .open:
            Text("Open")
                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        case .approved:
            Text("Approved")
                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        case .vetoed:
            Text("Vetoed")
                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
        case .superseded:
            Text("Superseded")
                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch proposal.status {
        case .approved:  Color.green.opacity(0.06)
        case .vetoed:    Color.secondary.opacity(0.04)
        default:         Color.clear
        }
    }

    // MARK: - Helpers

    private var proposerLabel: String {
        let name = usernames[proposal.proposerID] ?? "Someone"
        return "\(name) proposed:"
    }

    private var proposalDescription: String {
        switch proposal.proposalType {
        case .addExercise:
            let sets   = proposal.payload?["target_sets"]?.doubleValue.map { "\(Int($0)) sets" }
            let reps   = proposal.payload?["target_reps"]?.stringValue.map { "\($0) reps" }
            let parts  = [sets, reps].compactMap { $0 }
            let suffix = parts.isEmpty ? "" : " — \(parts.joined(separator: ", "))"
            return "Add exercise\(suffix)"
        case .removeExercise:
            return "Remove exercise"
        case .editExercise:
            var parts: [String] = []
            if let s = proposal.payload?["target_sets"]?.doubleValue  { parts.append("\(Int(s)) sets") }
            if let r = proposal.payload?["target_reps"]?.stringValue   { parts.append("\(r) reps") }
            if let w = proposal.payload?["target_weight"]?.stringValue { parts.append("@ \(w)") }
            return parts.isEmpty ? "Edit exercise" : "Edit: \(parts.joined(separator: ", "))"
        case .reorder:
            return "Reorder exercises"
        }
    }
}

// MARK: - AnyJSON convenience helpers (only values needed in this view)

private extension AnyJSON {
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

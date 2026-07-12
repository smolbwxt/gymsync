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

    @Environment(\.gsTheme) private var theme

    private var approveCount: Int { votes.filter { $0.vote == .approve }.count }
    private var vetoCount: Int    { votes.filter { $0.vote == .veto }.count }
    private var myVote: ProposalVote? { votes.first { $0.userID == myID } }
    private var isOpen: Bool { proposal.status == .open }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: kicker "Proposal · from <name>"
            HStack(alignment: .firstTextBaseline) {
                Text(proposerKicker)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(theme.neutral500)
                Spacer()
                statusBadge
            }

            // Description — struck through + dimmed when vetoed
            Text(proposalDescription)
                .font(GSFont.bold(16, relativeTo: .headline))
                .foregroundStyle(proposal.status == .vetoed ? theme.neutral500 : theme.text)
                .strikethrough(proposal.status == .vetoed, color: theme.neutral500)

            // Vote progress bar: accent for approve portion, neutral400 for veto
            voteMeter

            // Vote counts + action buttons
            HStack(alignment: .center) {
                Text("\(approveCount) approve · \(vetoCount) veto")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)

                Spacer()

                // Action buttons only when open and I haven't voted
                if isOpen, myVote == nil {
                    HStack(spacing: 6) {
                        Button {
                            Task { await onVeto() }
                        } label: {
                            Text("Veto")
                                .font(GSFont.bold(12, relativeTo: .caption))
                                .foregroundStyle(theme.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(theme.surface)
                                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await onApprove() }
                        } label: {
                            Text("Approve")
                                .font(GSFont.bold(12, relativeTo: .caption))
                                .foregroundStyle(theme.bg)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(theme.accent)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(rowBackground)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        .listRowBackground(theme.bg)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var statusBadge: some View {
        switch proposal.status {
        case .open:
            Text("Open")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.accent100)
        case .approved:
            Text("Approved")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(Color.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
        case .vetoed:
            Text("Vetoed")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.neutral500)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.neutral300)
        case .superseded:
            Text("Superseded")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.neutral500)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.neutral300)
        }
    }

    // Canvas: thin progress bar, accent fill for approve portion, neutral400 for veto
    @ViewBuilder
    private var voteMeter: some View {
        let total = approveCount + vetoCount
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: geo.size.width * CGFloat(approveCount) / CGFloat(total))
                    Rectangle()
                        .fill(theme.neutral400)
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch proposal.status {
        case .approved:  theme.accent100
        case .vetoed:    theme.neutral100
        default:         theme.surface
        }
    }

    // MARK: - Helpers

    private var proposerKicker: String {
        let name = usernames[proposal.proposerID] ?? "Someone"
        return "PROPOSAL · FROM \(name.uppercased())"
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

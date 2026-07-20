import Foundation
import Supabase

/// Drives the campaign detail screen's live community progress bar via
/// `postgres_changes` on `campaign_progress` — channel `campaign:{campaign_
/// id}` (master spec's channel-naming table, :970: "campaign:{campaign_id}
/// <- postgres_changes (campaign_progress updates)"; wire shape :1049-1051:
/// "postgres_changes on campaign_progress WHERE campaign_id = ?. When any
/// participant's progress ticks up, the community progress bar animates.
/// Individual leaderboards re-sort."). Shape mirrors `SessionLiveService`
/// exactly (stream-before-subscribe, one channel, `withTaskGroup` fan-out,
/// full teardown) — the established postgres_changes idiom in this
/// codebase, per the task brief's own pointer.
///
/// Channel-guard doctrine (debt-zero sprint, `BroadcastChannelDecision.
/// swift`): that doctrine exists for BROADCAST topics that two different
/// call sites can both reach — a disposable send-only instance and a
/// held receive-side instance racing on the SAME topic string
/// (`session:{id}:hr`/`session:{id}` in that case). `campaign:{campaign_id}`
/// has no such second caller anywhere in this app — this service is the
/// ONLY code that ever calls `client.channel("campaign:...")`, exactly like
/// `SessionLiveService` is the only caller of `session:{id}:live` — so the
/// "never tear down a topic you don't hold" rule is satisfied trivially:
/// `unsubscribe()` only ever removes the channel THIS instance created in
/// `subscribe()`, never looked up from the registry. postgres_changes ≠
/// broadcast (no disposable-send path exists for postgres_changes at all —
/// there is nothing to "send" here), but the same channel-lifecycle
/// discipline (subscribe once, own it, tear down only what you own)
/// applies and is followed here by construction, not by a registry check.
@MainActor
final class CampaignLiveService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

    /// Subscribe to `campaign_progress` changes for one campaign.
    ///
    /// - Parameters:
    ///   - campaignID:   Campaign to watch.
    ///   - onProgressChange: Called on any INSERT/UPDATE to that campaign's
    ///     `campaign_progress` rows. Coarse (no decoded payload, matching
    ///     `SessionLiveService.onParticipantsChange`'s own "caller
    ///     refetches" shape) — the detail screen already needs to refetch
    ///     both the community-aggregate RPC (a SUM, not derivable from a
    ///     single changed row) and, for participants, the roster-ranked
    ///     leaderboard, so decoding the single changed row here would still
    ///     leave a second round trip either way.
    func subscribe(
        campaignID: UUID,
        onProgressChange: @escaping @MainActor () -> Void
    ) async {
        // Tear down any previous subscription first — same idiom as
        // SessionLiveService.subscribe.
        await unsubscribe()

        let ch = SupabaseService.shared.client
            .channel("campaign:\(campaignID.uuidString)")

        // ── Stream registrations (must happen BEFORE subscribe) ──────────
        let progressInserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "campaign_progress",
            filter: "campaign_id=eq.\(campaignID.uuidString)"
        )
        let progressUpdates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "campaign_progress",
            filter: "campaign_id=eq.\(campaignID.uuidString)"
        )

        channel = ch
        await ch.subscribe()

        streamTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await _ in progressInserts { onProgressChange() }
                }
                group.addTask { @MainActor in
                    for await _ in progressUpdates { onProgressChange() }
                }
            }
        }
    }

    /// Cancel all stream tasks and remove the realtime channel — this
    /// instance's own channel only, never one it merely looked up.
    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
}

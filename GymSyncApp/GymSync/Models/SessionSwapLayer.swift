import Foundation
import Supabase

// MARK: - SessionSwapLayer
//
// THE DURABLE SWAP LAYER AS A VALUE — `{slot id: replacement exercise id}`.
//
// Two columns carry this exact shape (Phase C1 D1, 20260919000101):
//
//   * `session_participants.self_swaps` — MY OWN quiet swap. Written by a
//     direct own-row UPDATE through the policy that already exists
//     ("participant updates own check-in", no column list), exactly as
//     `todays_scale` is written.
//   * `sessions.squad_swaps` — the crew's agreed swap. Written ONLY by
//     `public.apply_squad_swap`; `private.session_round_guard` refuses a
//     client write on UPDATE and `private.session_venue_insert_guard`
//     refuses one on INSERT.
//
// KEYED BY THE ROUTINE-EXERCISE ROW ID — THE SLOT — NOT THE EXERCISE ID.
// A routine may name one lift twice. Keyed by exercise id, swapping slot 3's
// bench swapped slot 7's bench too, and slot 7's sets counted toward slot 3.
// The columns' own comments say the same thing; this type is the app's half
// of that contract.
//
// NULL AND `{}` MEAN THE SAME THING and the codec says so: an absent column
// decodes to `nil` at the call site, which every caller turns into the empty
// layer, and an empty layer encodes as `{}`. The app never writes `{}` where
// NULL would mean the same thing — it simply never has an empty layer to
// write, because nothing in either body removes a swap.
//
// A KEY THIS ROUTINE DOES NOT CARRY IS INERT, never an error: a routine
// edited after a swap was applied can orphan a slot id (there is no foreign
// key, deliberately — see the migration header). `RoutineLayering.apply`
// looks the layer up BY ROW, so an unknown slot id simply never matches and
// changes nothing.
struct SessionSwapLayer: Equatable, Sendable {

    /// slot (routine_exercises.id) → replacement exercises.id.
    private(set) var bySlot: [UUID: UUID]

    init(_ bySlot: [UUID: UUID] = [:]) { self.bySlot = bySlot }

    var isEmpty: Bool { bySlot.isEmpty }

    subscript(slotID: UUID) -> UUID? { bySlot[slotID] }

    /// Everything in `other` that this layer does not already name.
    ///
    /// THE DURABLE ROW SEEDS, IT DOES NOT OVERWRITE. A swap applied a
    /// moment ago and still in flight must not be erased by the reload that
    /// lands while its write is travelling. That is exact rather than
    /// merely safe, because neither body has an un-swap: the layer only
    /// ever grows within a session, so a union can never lose a decision.
    func merging(_ other: SessionSwapLayer) -> SessionSwapLayer {
        SessionSwapLayer(other.bySlot.merging(bySlot) { _, mine in mine })
    }
}

// MARK: - Codec
//
// The wire is `{"<uuid>": "<uuid>"}`. A malformed key or value is DROPPED
// rather than failing the whole decode: this layer rides on a row the rest
// of the session is read from (`session_participants`), and one bad entry
// must not cost the roster.
extension SessionSwapLayer: Codable {
    init(from decoder: Decoder) throws {
        let raw = try [String: String](from: decoder)
        var parsed: [UUID: UUID] = [:]
        for (key, value) in raw {
            guard let slot = UUID(uuidString: key),
                  let replacement = UUID(uuidString: value) else { continue }
            parsed[slot] = replacement
        }
        self.init(parsed)
    }

    func encode(to encoder: Encoder) throws {
        var raw: [String: String] = [:]
        for (slot, replacement) in bySlot {
            raw[slot.uuidString] = replacement.uuidString
        }
        try raw.encode(to: encoder)
    }
}

// MARK: - SessionSwapPendingStore
//
// THE LIFTER'S OWN LAYER IS NEVER ONLY IN THE VIEW (ruling F1).
//
// S1 replaced the 2026-09-18 hotfix's in-memory mirror with a durable row,
// which is strictly better on every path the write SUCCEEDS on — and strictly
// worse on the one it does not. With the mirror gone, a refused `self_swaps`
// write left the swap in exactly one place, `@State soloSwapOverrides`, which
// a swipe-down destroys; the lifter came back on the lift they had swapped
// away and logged its sets a second time. That is the TestFlight-1031 report
// this phase exists to end, re-opened through the failure leg.
//
// So the row is the truth and this is the OUTBOX. It is app-level and
// in-memory — deliberately NOT the old `AppState.LiveSoloSession` field,
// which was a snapshot of a view's state carried on a session handle. This is
// keyed by session id, holds only THIS lifter's own layer, and carries the
// one fact the view cannot: whether the row has caught up.
//
// THE LIFECYCLE, in one place:
//   record   — before every write attempt. The layer is now pending: it
//              applies on this phone whatever the network says.
//   confirm  — the write landed. The layer stays as a read-through cache;
//              `isDirty` goes false.
//   flush    — re-attempt a dirty layer at the next natural opportunity
//              (a seed/reload, a successful set log, a foreground) until it
//              lands. Silent: a retry that fails is not news.
//   clear    — the session finished or was discarded.
//
// IT IS NOT DURABLE ACROSS A PROCESS DEATH, and it does not need to be: the
// row is, and a layer that never reached the row is one the lifter watched
// fail. What it covers is the gap the row cannot — the minutes between a
// refused write and the next connection, which is exactly when a lifter in a
// basement gym swipes down.
@MainActor
final class SessionSwapPendingStore {
    static let shared = SessionSwapPendingStore()
    /// Public so a test can own its own store rather than mutate a singleton.
    init() {}

    private struct Entry {
        var layer: SessionSwapLayer
        var isDirty: Bool
    }
    private var bySession: [UUID: Entry] = [:]

    /// What this phone believes MY layer to be — empty when it has never
    /// been told.
    func layer(for sessionID: UUID) -> SessionSwapLayer {
        bySession[sessionID]?.layer ?? SessionSwapLayer()
    }

    /// True while a recorded layer has not been confirmed into the row.
    func isDirty(_ sessionID: UUID) -> Bool { bySession[sessionID]?.isDirty ?? false }

    /// Record BEFORE attempting the write, never after. A layer recorded and
    /// then lost to a crash is a layer the row may already hold; a layer
    /// written and then not recorded is the bug this store exists to close.
    func record(_ layer: SessionSwapLayer, for sessionID: UUID) {
        bySession[sessionID] = Entry(layer: layer, isDirty: true)
    }

    /// The row caught up — WITH THE LAYER THAT WAS ACTUALLY WRITTEN. The
    /// layer is kept (it is what a FAILED read falls back to) and only the
    /// dirty flag drops, and only when the store still holds the very layer
    /// this write carried.
    ///
    /// MATCHING, NOT BY SESSION (ruling F1a). Two swaps inside one write's
    /// latency interleave: swap 1 records L1 and starts its write; swap 2
    /// records L2 ⊃ L1 and starts its own; write 1 returns first. A
    /// by-session confirm would mark L2 clean while the row held only L1, so
    /// a failing write 2 would never retry — `flushIfDirty` short-circuits on
    /// `isDirty` — although the notice it showed promised exactly that. The
    /// equality is on the whole layer because that is what `saveSelf` writes:
    /// `self_swaps` is a plain jsonb column with no server-side merge, so a
    /// write either put this object in the row or it did not.
    func confirm(_ sessionID: UUID, matching layer: SessionSwapLayer) {
        guard var entry = bySession[sessionID], entry.layer == layer else { return }
        entry.isDirty = false
        bySession[sessionID] = entry
    }

    func clear(_ sessionID: UUID) { bySession[sessionID] = nil }

    /// THE SEED: the database value with a pending layer laid over it, slot
    /// by slot, PENDING WINNING. A dirty entry outranks the row because the
    /// row is behind by definition; a clean entry agrees with it, so the
    /// merge is a union either way and neither can lose a decision (neither
    /// body has an un-swap).
    func seeded(from row: SessionSwapLayer, for sessionID: UUID) -> SessionSwapLayer {
        layer(for: sessionID).merging(row)
    }

    /// Re-attempt a dirty layer. Silent on failure — this is a retry, not an
    /// action the lifter just took, and the notice for the failure they DID
    /// take has already been shown.
    ///
    /// - Returns: true when there is nothing outstanding.
    @discardableResult
    func flushIfDirty(_ sessionID: UUID) async -> Bool {
        guard let entry = bySession[sessionID], entry.isDirty else { return true }
        guard !entry.layer.isEmpty else {
            confirm(sessionID, matching: entry.layer); return true
        }
        do {
            try await SessionSwapRepository.saveSelf(sessionID: sessionID, layer: entry.layer)
            confirm(sessionID, matching: entry.layer)
            return true
        } catch {
            AppLogger.sessions.error(
                "self_swaps retry failed: \(error, privacy: .public)")
            return false
        }
    }
}

// MARK: - SessionSwapSeeding
//
// WHOSE LAYER IS WHAT, AT A SEED — and it is pure because the leg it exists
// for is the one where there is no roster (final review F2).
//
// The live body used to consult the outbox INSIDE `for (participant, _) in
// participants`, and `participants` is `@State … = []` that a failed fetch
// leaves empty. So on the one connection state the outbox was built for —
// airplane mode, a refused `self_swaps` write, MINIMISE, re-entry, still
// offline — the loop body never ran and the pending layer was never applied.
// The notice that produced it says "it applies on this phone", and it did
// not.
//
// MY OWN LAYER IS THEREFORE SEEDED BEFORE AND INDEPENDENT OF THE ROSTER,
// exactly as the retired `WorkoutSessionView.adoptSwapLayer` does it: the
// outbox is keyed by SESSION and holds only MY layer, so it needs no row to
// be readable. The roster then only ADDS what the database knows — for me
// and for everyone else — and pending still wins per slot, because the row
// is behind by definition.
enum SessionSwapSeeding {

    /// One roster row, reduced to the two things a seed reads.
    struct Row: Equatable {
        var userID: UUID
        var layer: SessionSwapLayer

        init(userID: UUID, layer: SessionSwapLayer) {
            self.userID = userID
            self.layer = layer
        }
    }

    /// The durable layer to apply per lifter: every roster row's own, with MY
    /// pending layer laid over mine whether or not the roster carries me.
    ///
    /// An EMPTY roster and a `nil` `selfID` are both ordinary, not errors: the
    /// first is a failed fetch (and the whole point of this function), the
    /// second is a body whose profile has not resolved, where there is no
    /// "mine" to seed.
    static func layers(roster: [Row],
                       selfID: UUID?,
                       pendingSelf: SessionSwapLayer) -> [UUID: SessionSwapLayer] {
        var byUser: [UUID: SessionSwapLayer] = [:]
        for row in roster { byUser[row.userID] = row.layer }
        guard let selfID else { return byUser }
        byUser[selfID] = pendingSelf.merging(byUser[selfID] ?? SessionSwapLayer())
        return byUser
    }
}

// MARK: - SessionSwapRepository
//
// The two homes' read and write paths, and the ONE RPC.
//
// EVERY ERROR IS SURVIVABLE (controller ruling, Phase C1). None of these
// four calls is on the critical path of Start, the log, or the round: a
// refused write leaves the in-memory layer standing for this lifter, and
// the screen says what happened where it was asked. That is the same
// best-effort stance `SessionRepository.setTodaysScale`'s callers take.
enum SessionSwapRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    private struct SelfSwapsRow: Decodable {
        let selfSwaps: SessionSwapLayer?
        enum CodingKeys: String, CodingKey { case selfSwaps = "self_swaps" }
    }

    private struct SquadSwapsRow: Decodable {
        let squadSwaps: SessionSwapLayer?
        enum CodingKeys: String, CodingKey { case squadSwaps = "squad_swaps" }
    }

    private struct SelfSwapsUpdate: Encodable {
        let selfSwaps: SessionSwapLayer
        enum CodingKeys: String, CodingKey { case selfSwaps = "self_swaps" }
    }

    /// MY OWN layer for this session. The projection is one column of one
    /// row — the solo body has no roster fetch to ride on, unlike the live
    /// body, which reads every participant's layer off
    /// `SessionParticipant.selfSwaps` for free.
    static func loadSelf(sessionID: UUID) async throws -> SessionSwapLayer {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [SelfSwapsRow] = try await client
                .from("session_participants")
                .select("self_swaps")
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute().value
            return rows.first?.selfSwaps ?? SessionSwapLayer()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Write MY OWN layer. A direct own-row UPDATE, not an RPC, for the
    /// reason `setTodaysScale`'s doc comment records at length: the shipped
    /// "participant updates own check-in" policy is
    /// `USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())`
    /// with NO COLUMN LIST, so a third policy would grant nothing while
    /// looking like it granted something.
    ///
    /// `layer` is NOT optional and callers never hand it an empty one:
    /// nothing in either body removes a swap, so the only honest write is a
    /// non-empty object.
    static func saveSelf(sessionID: UUID, layer: SessionSwapLayer) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .from("session_participants")
                .update(SelfSwapsUpdate(selfSwaps: layer))
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// The crew's layer for this session, read straight off the row.
    ///
    /// A PROJECTED SELECT RATHER THAN A FIELD ON `WorkoutSession`: that type
    /// is INSERTED whole by `SessionRepository.startSolo`, and
    /// `private.session_venue_insert_guard` raises P0001 on any insert
    /// carrying a non-NULL `squad_swaps`. Keeping the column off the model
    /// means no future construction site can put one there by accident.
    static func loadSquad(sessionID: UUID) async throws -> SessionSwapLayer {
        do {
            let rows: [SquadSwapsRow] = try await client
                .from("sessions")
                .select("squad_swaps")
                .eq("id", value: sessionID.uuidString)
                .execute().value
            return rows.first?.squadSwaps ?? SessionSwapLayer()
        } catch { throw ErrorMapping.map(error) }
    }

    /// THE ONLY WRITER OF `sessions.squad_swaps`
    /// (`public.apply_squad_swap(p_session_id, p_slot_id, p_replacement_id)`,
    /// SECURITY DEFINER, `authenticated` only; `anon` holds no EXECUTE).
    ///
    /// Four P0001 messages, each of which `ErrorMapping` surfaces verbatim
    /// through `.validation(pg.message)`: `sign-in required`,
    /// `not a participant of this session`,
    /// `replacement is not a known exercise`,
    /// `slot is not part of this session's routine`. The last one means
    /// this client's routine is stale for the slot it named.
    ///
    /// THE MERGED OBJECT THE FUNCTION RETURNS IS DELIBERATELY NOT DECODED.
    /// The caller already knows the one entry it asked for, and the crew's
    /// whole layer arrives on the next `reload()` through `loadSquad`. A
    /// decode here could only ever turn a write that LANDED into an error
    /// the lifter sees — the failure mode this call exists to avoid.
    static func applySquad(sessionID: UUID, slotID: UUID,
                           replacementID: UUID) async throws {
        do {
            _ = try await client
                .rpc("apply_squad_swap", params: [
                    "p_session_id": sessionID.uuidString,
                    "p_slot_id": slotID.uuidString,
                    "p_replacement_id": replacementID.uuidString
                ])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}

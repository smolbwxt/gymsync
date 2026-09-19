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

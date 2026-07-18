// payloads.ts — pure event -> APNs content map. No DB access, no fetch, no
// env reads. Takes exactly what a push_queue row carries (event name +
// its jsonb payload, as written by the triggers in
// supabase/migrations/20260716000001_push_schema.sql and the cron enqueuer
// in 20260716000003_push_cron.sql) and returns display content.
//
// Keeping this pure (no DB joins) is a deliberate scope boundary: the
// triggers control exactly what goes into push_queue.payload, and this
// module is the single place that turns that payload into user-facing
// copy. See the two "COPY NOTE" comments below for the two events where
// this constrains the wording versus the dossier's example copy.

export interface NotificationContent {
  title: string;
  body: string;
  /** UNNotificationCategory identifier — drives which action buttons iOS shows. */
  category: string;
  /** Groups related pushes for the same session/group thread on-device. */
  threadId?: string;
}

/**
 * Category ids, per the task brief's 7-id list. Thirteen events map onto
 * seven categories because the brief's id list doesn't have a 1:1 slot for
 * every event — events whose action is a plain "View"/"Reply" (no bespoke
 * action buttons beyond opening the app to the right place) all share
 * SESSION_VIEW.
 *
 *   FRIEND_REQUEST  — friend_request              (Accept / Decline)
 *   SESSION_INVITE  — session_invite               (View / Decline)
 *   SESSION_VIEW    — session_reminder_15min       (View)
 *                    partner_pr                    (View)
 *                    chat_mention                  (Reply — no dedicated
 *                                                    REPLY category exists
 *                                                    in the brief's list, so
 *                                                    it shares the generic
 *                                                    "open and look" bucket)
 *                    streak_milestone               (View — Phase S, no
 *                                                    bespoke action either)
 *                    streak_at_risk                 (View)
 *                    leaderboard_passed             (View Leaderboard —
 *                                                    Phase L, no bespoke
 *                                                    action either)
 *   OPEN_LOBBY      — session_lobby_open           (Open Lobby)
 *   OPEN_SESSION    — your_turn                    (Open Session)
 *   ROAST           — lateness_chirp               (Roast)
 *   IDLE_ACTIONS    — session_idle_30min           (Wrap Up / Still Going)
 *                    session_idle_60min            (Wrap Up / Still Going)
 */
const CATEGORY = {
  FRIEND_REQUEST: "FRIEND_REQUEST",
  SESSION_INVITE: "SESSION_INVITE",
  SESSION_VIEW: "SESSION_VIEW",
  OPEN_LOBBY: "OPEN_LOBBY",
  OPEN_SESSION: "OPEN_SESSION",
  ROAST: "ROAST",
  IDLE_ACTIONS: "IDLE_ACTIONS",
} as const;

type PushPayload = Record<string, unknown>;

function str(payload: PushPayload, key: string): string | undefined {
  const v = payload[key];
  return typeof v === "string" && v.length > 0 ? v : undefined;
}

function num(payload: PushPayload, key: string): number | undefined {
  const v = payload[key];
  return typeof v === "number" ? v : undefined;
}

/**
 * Returns null for an event name the dispatcher doesn't recognize (should
 * never happen for rows enqueued by the schema's own triggers/cron, but a
 * push_queue row is just a text column — defend the boundary anyway).
 */
export function buildNotificationPayload(
  event: string,
  payload: PushPayload,
): NotificationContent | null {
  switch (event) {
    case "friend_request":
      // Payload: { from_user_id }. No username join available here (pure
      // map, no DB access) — generic copy.
      return {
        title: "Friend Request",
        body: "You have a new friend request on GymSync.",
        category: CATEGORY.FRIEND_REQUEST,
      };

    case "session_invite": {
      // COPY NOTE: dossier §A.3 gives the example "Tommy invited you to
      // Push Day." — but the push_session_invite trigger's payload
      // (20260716000001_push_schema.sql) only carries
      // { session_id, organizer_id, organizer_username }, not a
      // session/routine name ("Push Day" was the routine name in that
      // mockup). Substituting organizer_username (which IS available)
      // keeps the same shape/spirit without inventing a field the trigger
      // doesn't emit.
      const organizer = str(payload, "organizer_username") ?? "Someone";
      const sessionId = str(payload, "session_id");
      return {
        title: "Session Invite",
        body: `${organizer} invited you to a session.`,
        category: CATEGORY.SESSION_INVITE,
        threadId: sessionId,
      };
    }

    case "session_reminder_15min": {
      // COPY NOTE: dossier §A.3 gives "Push Day starts in 15 min. Tap to
      // enter lobby." — same constraint as session_invite above; the cron
      // enqueuer's payload (20260716000003_push_cron.sql,
      // enqueue_scheduled_pushes) is only { session_id }. Generic copy.
      const sessionId = str(payload, "session_id");
      return {
        title: "Starting Soon",
        body: "Your session starts in 15 min. Tap to enter lobby.",
        category: CATEGORY.SESSION_VIEW,
        threadId: sessionId,
      };
    }

    case "session_lobby_open": {
      const sessionId = str(payload, "session_id");
      return {
        title: "Lobby Open",
        body: "The lobby is open. Tap to join.",
        category: CATEGORY.OPEN_LOBBY,
        threadId: sessionId,
      };
    }

    case "your_turn": {
      const sessionId = str(payload, "session_id");
      return {
        title: "Your Turn",
        body: "It's your turn on the bar.",
        category: CATEGORY.OPEN_SESSION,
        threadId: sessionId,
      };
    }

    case "partner_pr": {
      // Payload: { group_id, message_id, pr_user_id }. No username join
      // available here — generic copy (the chat message itself, already
      // fanned out by announce_pr(), carries the formatted name).
      const groupId = str(payload, "group_id");
      return {
        title: "Crew PR",
        body: "Someone in your crew just hit a new PR.",
        category: CATEGORY.SESSION_VIEW,
        threadId: groupId,
      };
    }

    case "lateness_chirp": {
      const sessionId = str(payload, "session_id");
      return {
        title: "Late Arrival",
        body: "Someone's running late. Send a roast.",
        category: CATEGORY.ROAST,
        threadId: sessionId,
      };
    }

    case "session_idle_30min": {
      const sessionId = str(payload, "session_id");
      return {
        title: "Session Idle",
        body: "Your session's been quiet for 30 min. Wrap up or keep going?",
        category: CATEGORY.IDLE_ACTIONS,
        threadId: sessionId,
      };
    }

    case "session_idle_60min": {
      const sessionId = str(payload, "session_id");
      return {
        title: "Session Idle",
        body: "Your session's been quiet for 60 min. Wrap up or keep going?",
        category: CATEGORY.IDLE_ACTIONS,
        threadId: sessionId,
      };
    }

    case "chat_mention": {
      // Payload: { group_id, message_id, mentioned_username }.
      // mentioned_username is the recipient's own username (they ARE the
      // mention target) — not the author, so it isn't useful to interpolate
      // ("You were mentioned" already says who).
      const groupId = str(payload, "group_id");
      return {
        title: "Mentioned",
        body: "You were mentioned in chat.",
        category: CATEGORY.SESSION_VIEW,
        threadId: groupId,
      };
    }

    case "streak_milestone": {
      // Payload (20260719000008_streak_pushes.sql):
      //   user  case: { streak, kind: 'user' }
      //   group case: { streak, kind: 'group', group_id }
      // Both raw event names share one notification_prefs category ('streak')
      // — same "shared toggle, distinct raw events" precedent as
      // session_idle_30min/60min above — but the copy differs by whose
      // streak it is, so that's branched on here, not in the DB layer.
      const streak = num(payload, "streak");
      const isGroup = payload["kind"] === "group";
      const groupId = str(payload, "group_id");
      const body = isGroup
        ? `Your crew just hit a ${streak ?? "new"}-session streak!`
        : `You just hit a ${streak ?? "new"}-session streak!`;
      return {
        title: "Streak Milestone",
        body,
        category: CATEGORY.SESSION_VIEW,
        ...(isGroup && groupId ? { threadId: groupId } : {}),
      };
    }

    case "leaderboard_passed": {
      // Payload (leaderboard_social_effects_on_completion,
      // 20260723000002_attempt_plumbing.sql): { routine_id, attempt_id,
      // passing_user_id, new_rank }. No username/routine-name join available
      // here (pure map, no DB access) — generic copy, same constraint as
      // every other case in this file. No natural session/group thread for
      // a cross-session leaderboard event (the pass can happen from a
      // completely unrelated session), so no threadId — same as
      // friend_request above, which has no natural grouping surface either.
      // Category: the task brief's 7-id list has no bespoke "View
      // Leaderboard" action button, so this shares SESSION_VIEW — the same
      // generic "open and look" bucket partner_pr/chat_mention/
      // streak_milestone/streak_at_risk already use.
      return {
        title: "Leaderboard",
        body: "Someone just passed you on the leaderboard.",
        category: CATEGORY.SESSION_VIEW,
      };
    }

    case "streak_at_risk": {
      // COPY NOTE: Flow 7's tunables example is "🔥 Your 12-session streak
      // needs you. Push Day starts soon." — "Push Day" was the mockup's
      // routine name, and (per the other COPY NOTEs above) the enqueuer's
      // payload (enqueue_streak_at_risk_pushes, 20260719000008) only carries
      // { session_id, streak }, not a routine name, so generic "your
      // session" substitutes. The leading emoji is also dropped here,
      // matching every other case in this file — none of the 10 original
      // events carry emoji in push copy (only chat_messages system rows do),
      // so this stays consistent with that established convention rather
      // than the mockup's literal text.
      const sessionId = str(payload, "session_id");
      const streak = num(payload, "streak");
      return {
        title: "Streak at Risk",
        body: `Your ${streak ?? "current"}-session streak needs you. Your session starts soon.`,
        category: CATEGORY.SESSION_VIEW,
        threadId: sessionId,
      };
    }

    default:
      return null;
  }
}

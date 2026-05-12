const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });

console.log(`FlowState WebSocket server running on port ${PORT}`);

// ─── In-Memory Store ──────────────────────────────────────────────────────────
//
// rooms: Map<room_id, Room>
//
// Room shape:
// {
//   roomId: string,
//   hostId: string,
//   state: 'waiting' | 'active' | 'ended',
//   sessionConfig: { sessionMinutes, splitMinutes, breakMinutes, numSplits },
//   users: Map<user_id, UserEntry>,
//   currentPhase: 'study' | 'break' | null,
//   currentSplitIndex: number,
//   phaseStartedAt: Date | null,
//   phaseTimer: Timeout | null,
// }
//
// UserEntry shape:
// {
//   displayName: string,
//   ws: WebSocket,
//   isReady: boolean,
//   studySecondsEarned: number,      // accumulated completed study splits
//   personalBreakSeconds: number,    // total personal break time during study phases
//   personalBreakStartedAt: Date | null, // when current personal break started (null if not on personal break)
// }

const rooms = new Map();

// ─── Utilities ────────────────────────────────────────────────────────────────

function broadcastToRoom(roomId, message) {
  const room = rooms.get(roomId);
  if (!room) return;
  const data = JSON.stringify(message);
  for (const [, user] of room.users) {
    if (user.ws.readyState === 1) {
      user.ws.send(data);
    }
  }
}

function sendToUser(ws, message) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(message));
  }
}

function getRoomSnapshot(room) {
  const users = {};
  for (const [uid, u] of room.users) {
    users[uid] = {
      display_name: u.displayName,
      is_ready: u.isReady,
      is_host: uid === room.hostId,
      study_seconds_earned: u.studySecondsEarned,
    };
  }
  return {
    type: "room_snapshot",
    room_id: room.roomId,
    host_id: room.hostId,
    state: room.state,
    session_config: room.sessionConfig,
    current_phase: room.currentPhase,
    current_split_index: room.currentSplitIndex,
    phase_ends_at: room.phaseStartedAt
      ? new Date(
          room.phaseStartedAt.getTime() + getPhaseDurationMs(room)
        ).toISOString()
      : null,
    users,
  };
}

function getPhaseDurationMs(room) {
  if (!room.sessionConfig) return 0;
  const { splitMinutes, breakMinutes } = room.sessionConfig;
  // splitMinutes=0 → treat the full sessionMinutes as one study block
  if (room.currentPhase === "study") {
    const mins = splitMinutes > 0 ? splitMinutes : room.sessionConfig.sessionMinutes;
    return mins * 60 * 1000;
  }
  if (room.currentPhase === "break") return breakMinutes * 60 * 1000;
  return 0;
}

function calcNumSplits(sessionMinutes, splitMinutes) {
  // splitMinutes=0 means no splits — run the whole session as one block with no breaks.
  if (!splitMinutes || splitMinutes <= 0) return 1;
  return Math.max(1, Math.floor(sessionMinutes / splitMinutes));
}

function findUserRoom(ws) {
  for (const [, room] of rooms) {
    for (const [uid, u] of room.users) {
      if (u.ws === ws) return { room, userId: uid };
    }
  }
  return null;
}

// ─── Personal Break Helpers ───────────────────────────────────────────────────

// Flush any in-progress personal break penalty into personalBreakSeconds.
// Call this before reading the final penalty or before pausing the penalty timer.
function flushPersonalBreak(user) {
  if (user.personalBreakStartedAt) {
    const elapsed = Math.floor((Date.now() - user.personalBreakStartedAt.getTime()) / 1000);
    user.personalBreakSeconds += elapsed;
    user.personalBreakStartedAt = null;
  }
}

// Net study seconds for a user: earned minus personal break penalty.
// Never goes below zero.
function netStudySeconds(user) {
  return Math.max(0, user.studySecondsEarned - user.personalBreakSeconds);
}

// ─── Session Timer Logic ──────────────────────────────────────────────────────

function startPhase(room) {
  if (room.phaseTimer) clearTimeout(room.phaseTimer);

  const durationMs = getPhaseDurationMs(room);
  room.phaseStartedAt = new Date();

  if (room.currentPhase === "break") {
    // Scheduled break started: pause personal break timers for anyone on personal break.
    // We flush what they accumulated during the study phase so far, then stop the clock.
    for (const [, u] of room.users) {
      if (u.personalBreakStartedAt) {
        flushPersonalBreak(u);
        // Mark that they were on personal break when the scheduled break started,
        // so we can resume their timer when study resumes.
        u.personalBreakPausedForScheduledBreak = true;
      }
    }
  } else if (room.currentPhase === "study") {
    // Study phase resumed: restart personal break timer for anyone who was
    // still on personal break when the scheduled break interrupted them.
    for (const [, u] of room.users) {
      if (u.personalBreakPausedForScheduledBreak) {
        u.personalBreakStartedAt = new Date();
        u.personalBreakPausedForScheduledBreak = false;
      }
    }
  }

  broadcastToRoom(room.roomId, {
    type: "phase_change",
    phase: room.currentPhase,
    split_index: room.currentSplitIndex,
    duration_seconds: Math.floor(durationMs / 1000),
    ends_at: new Date(Date.now() + durationMs).toISOString(),
  });

  room.phaseTimer = setTimeout(() => onPhaseEnd(room), durationMs);
}

function onPhaseEnd(room) {
  if (room.currentPhase === "study") {
    const splitSeconds = getPhaseDurationMs(room) / 1000; // use actual duration, not raw splitMinutes
    for (const [, u] of room.users) {
      u.studySecondsEarned += splitSeconds;
      flushPersonalBreak(u);
    }

    const isLastSplit = room.currentSplitIndex >= room.sessionConfig.numSplits - 1;
    if (isLastSplit) {
      endSession(room);
    } else if (room.sessionConfig.breakMinutes > 0) {
      // Only enter a break phase if break length is non-zero
      room.currentPhase = "break";
      startPhase(room);
    } else {
      // breakMinutes=0: skip break, go straight to next study split
      room.currentSplitIndex += 1;
      room.currentPhase = "study";
      startPhase(room);
    }
  } else {
    room.currentSplitIndex += 1;
    room.currentPhase = "study";
    startPhase(room);
  }
}

function endSession(room) {
  room.state = "ended";
  room.currentPhase = null;
  if (room.phaseTimer) clearTimeout(room.phaseTimer);

  const studyTimePerUser = {};
  for (const [uid, u] of room.users) {
    // Flush any in-progress personal break before finalising
    flushPersonalBreak(u);
    studyTimePerUser[uid] = netStudySeconds(u);
  }

  broadcastToRoom(room.roomId, {
    type: "session_ended",
    room_id: room.roomId,
    study_time_per_user: studyTimePerUser,
  });

  console.log(`Room ${room.roomId} session ended. Study times:`, studyTimePerUser);
}

function partialStudySecondsNow(room) {
  if (room.currentPhase !== "study" || !room.phaseStartedAt) return 0;
  return Math.floor((Date.now() - room.phaseStartedAt.getTime()) / 1000);
}

// ─── Message Handlers ─────────────────────────────────────────────────────────

function handleCreateRoom(ws, msg) {
  const { room_id, host_id, display_name, session_config } = msg;

  if (!room_id || !host_id || !display_name || !session_config) {
    return sendToUser(ws, { type: "error", message: "create_room: missing fields." });
  }
  if (rooms.has(room_id)) {
    return sendToUser(ws, { type: "error", message: `Room ${room_id} already exists.` });
  }

  const { session_minutes, split_minutes, break_minutes } = session_config;
  // split_minutes=0 → one continuous block, no splits, no breaks
  const effectiveSplitMinutes = (!split_minutes || split_minutes <= 0) ? 0 : split_minutes;
  const numSplits = calcNumSplits(session_minutes, effectiveSplitMinutes);

  const room = {
    roomId: room_id,
    hostId: host_id,
    state: "waiting",
    sessionConfig: { sessionMinutes: session_minutes, splitMinutes: effectiveSplitMinutes, breakMinutes: break_minutes ?? 0, numSplits },
    users: new Map(),
    currentPhase: null,
    currentSplitIndex: 0,
    phaseStartedAt: null,
    phaseTimer: null,
  };

  room.users.set(host_id, {
    displayName: display_name,
    ws,
    isReady: true,
    studySecondsEarned: 0,
    personalBreakSeconds: 0,
    personalBreakStartedAt: null,
    personalBreakPausedForScheduledBreak: false,
  });

  rooms.set(room_id, room);
  console.log(`Room created: ${room_id} by ${display_name} (${host_id}). Splits: ${numSplits}`);
  sendToUser(ws, getRoomSnapshot(room));
}

function handleJoinRoom(ws, msg) {
  const { room_id, user_id, display_name } = msg;

  if (!room_id || !user_id || !display_name) {
    return sendToUser(ws, { type: "error", message: "join_room: missing fields." });
  }

  const room = rooms.get(room_id);
  if (!room) {
    return sendToUser(ws, { type: "error", message: `Room ${room_id} not found.` });
  }
  if (room.state !== "waiting") {
    return sendToUser(ws, { type: "error", message: "Room has already started. Cannot join." });
  }

  room.users.set(user_id, {
    displayName: display_name,
    ws,
    isReady: false,
    studySecondsEarned: 0,
    personalBreakSeconds: 0,
    personalBreakStartedAt: null,
    personalBreakPausedForScheduledBreak: false,
  });

  console.log(`${display_name} joined room ${room_id}.`);
  broadcastToRoom(room_id, getRoomSnapshot(room));
}

function handleSetReady(ws, msg) {
  const { room_id, user_id } = msg;
  const room = rooms.get(room_id);

  if (!room || room.state !== "waiting") return;
  if (user_id === room.hostId) return;

  const user = room.users.get(user_id);
  if (!user) return;

  user.isReady = !user.isReady;
  broadcastToRoom(room_id, getRoomSnapshot(room));
}

function handleStartSession(ws, msg) {
  const { room_id, host_id } = msg;
  const room = rooms.get(room_id);

  if (!room) return sendToUser(ws, { type: "error", message: "Room not found." });
  if (host_id !== room.hostId) return sendToUser(ws, { type: "error", message: "Only the host can start." });
  if (room.state !== "waiting") return sendToUser(ws, { type: "error", message: "Session already started." });

  room.state = "active";
  room.currentPhase = "study";
  room.currentSplitIndex = 0;

  console.log(`Room ${room_id} session started. ${room.sessionConfig.numSplits} splits.`);

  broadcastToRoom(room_id, {
    type: "session_started",
    room_id,
    started_at: new Date().toISOString(),
    session_config: {
      session_minutes: room.sessionConfig.sessionMinutes,
      split_minutes: room.sessionConfig.splitMinutes,
      break_minutes: room.sessionConfig.breakMinutes,
      num_splits: room.sessionConfig.numSplits,
    },
  });

  startPhase(room);
}

function handlePersonalBreakStart(ws, msg) {
  const { room_id, user_id } = msg;
  const room = rooms.get(room_id);
  if (!room || room.state !== "active") return;

  const user = room.users.get(user_id);
  if (!user) return;

  if (room.currentPhase === "study" && !user.personalBreakStartedAt) {
    user.personalBreakStartedAt = new Date();
    console.log(`${user.displayName} started personal break in room ${room_id}.`);
  }

  // Notify everyone so their presence tracker updates
  broadcastToRoom(room_id, {
    type: "personal_break_update",
    user_id,
    on_personal_break: true,
  });
}

function handlePersonalBreakEnd(ws, msg) {
  const { room_id, user_id } = msg;
  const room = rooms.get(room_id);
  if (!room || room.state !== "active") return;

  const user = room.users.get(user_id);
  if (!user) return;

  flushPersonalBreak(user);
  user.personalBreakPausedForScheduledBreak = false;
  console.log(`${user.displayName} ended personal break. Total penalty: ${user.personalBreakSeconds}s`);

  // Notify everyone so their presence tracker updates
  broadcastToRoom(room_id, {
    type: "personal_break_update",
    user_id,
    on_personal_break: false,
  });
}

function handleLeaveRoom(ws, msg) {
  const { room_id, user_id } = msg;
  removeUserFromRoom(room_id, user_id, ws);
}

function removeUserFromRoom(roomId, userId, ws) {
  const room = rooms.get(roomId);
  if (!room) return;

  const user = room.users.get(userId);
  if (!user) return;

  // Flush any in-progress personal break penalty
  flushPersonalBreak(user);

  // Add partial study seconds for the current split if leaving mid-study
  let finalStudySeconds = user.studySecondsEarned;
  if (room.state === "active" && room.currentPhase === "study") {
    finalStudySeconds += partialStudySecondsNow(room);
  }

  // Subtract personal break penalty and clamp
  finalStudySeconds = Math.max(0, finalStudySeconds - user.personalBreakSeconds);

  room.users.delete(userId);
  console.log(`${user.displayName} left room ${roomId}. Net study seconds: ${finalStudySeconds}`);

  broadcastToRoom(roomId, {
    type: "user_left",
    room_id: roomId,
    user_id: userId,
    display_name: user.displayName,
    study_seconds_earned: finalStudySeconds,
  });

  if (room.users.size > 0) {
    broadcastToRoom(roomId, getRoomSnapshot(room));
  }

  if (room.users.size === 0) {
    if (room.phaseTimer) clearTimeout(room.phaseTimer);
    rooms.delete(roomId);
    console.log(`Room ${roomId} deleted (empty).`);
    return;
  }

  if (userId === room.hostId && room.state === "waiting") {
    const newHostId = room.users.keys().next().value;
    room.hostId = newHostId;
    broadcastToRoom(roomId, {
      type: "host_changed",
      room_id: roomId,
      new_host_id: newHostId,
    });
  }
}

// ─── Connection Handler ───────────────────────────────────────────────────────

wss.on("connection", (ws) => {
  console.log(`New WebSocket connection. Total clients: ${wss.clients.size}`);

  const allowedTypes = [
    "create_room", "join_room", "set_ready", "start_session",
    "leave_room", "personal_break_start", "personal_break_end",
  ];

  ws.on("message", (data) => {
    let parsed;
    try {
      parsed = JSON.parse(data);
    } catch {
      console.error("Invalid JSON:", data);
      return;
    }

    console.log("Received:", parsed);

    if (!allowedTypes.includes(parsed.type)) {
      console.warn("Unknown message type:", parsed.type);
      return sendToUser(ws, { type: "error", message: `Unknown message type: ${parsed.type}` });
    }

    switch (parsed.type) {
      case "create_room":          handleCreateRoom(ws, parsed);         break;
      case "join_room":            handleJoinRoom(ws, parsed);           break;
      case "set_ready":            handleSetReady(ws, parsed);           break;
      case "start_session":        handleStartSession(ws, parsed);       break;
      case "leave_room":           handleLeaveRoom(ws, parsed);          break;
      case "personal_break_start": handlePersonalBreakStart(ws, parsed); break;
      case "personal_break_end":   handlePersonalBreakEnd(ws, parsed);   break;
    }
  });

  ws.on("close", () => {
    const found = findUserRoom(ws);
    if (found) {
      removeUserFromRoom(found.room.roomId, found.userId, ws);
    }
    console.log(`Connection closed. Remaining clients: ${wss.clients.size}`);
  });

  ws.on("error", (err) => {
    console.error("WebSocket error:", err.message);
    const found = findUserRoom(ws);
    if (found) {
      removeUserFromRoom(found.room.roomId, found.userId, ws);
    }
  });
});

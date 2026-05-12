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
//   currentSplitIndex: number,      // 0-based, which study split we are on
//   phaseStartedAt: Date | null,
//   phaseTimer: Timeout | null,
// }
//
// UserEntry shape:
// {
//   displayName: string,
//   ws: WebSocket,
//   isReady: boolean,
//   studySecondsEarned: number,   // accumulated completed study splits
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
          room.phaseStartedAt.getTime() +
            getPhaseDurationMs(room) 
        ).toISOString()
      : null,
    users,
  };
}

// Returns the ms duration of the CURRENT phase
function getPhaseDurationMs(room) {
  if (!room.sessionConfig) return 0;
  const { splitMinutes, breakMinutes } = room.sessionConfig;
  if (room.currentPhase === "study") return splitMinutes * 60 * 1000;
  if (room.currentPhase === "break") return breakMinutes * 60 * 1000;
  return 0;
}

// Derive numSplits from sessionMinutes / splitMinutes, clamped to at least 1
function calcNumSplits(sessionMinutes, splitMinutes) {
  return Math.max(1, Math.floor(sessionMinutes / splitMinutes));
}

// Find which room a given ws belongs to. Returns { room, userId } or null.
function findUserRoom(ws) {
  for (const [, room] of rooms) {
    for (const [uid, u] of room.users) {
      if (u.ws === ws) return { room, userId: uid };
    }
  }
  return null;
}

// ─── Session Timer Logic ──────────────────────────────────────────────────────

function startPhase(room) {
  if (room.phaseTimer) clearTimeout(room.phaseTimer);

  const durationMs = getPhaseDurationMs(room);
  room.phaseStartedAt = new Date();

  // Broadcast phase_change so clients can start their local countdown
  broadcastToRoom(room.roomId, {
    type: "phase_change",
    phase: room.currentPhase,
    split_index: room.currentSplitIndex,
    duration_seconds:
      room.currentPhase === "study"
        ? room.sessionConfig.splitMinutes * 60
        : room.sessionConfig.breakMinutes * 60,
    ends_at: new Date(Date.now() + durationMs).toISOString(),
  });

  room.phaseTimer = setTimeout(() => onPhaseEnd(room), durationMs);
}

function onPhaseEnd(room) {
  if (room.currentPhase === "study") {
    // Credit completed study split to all currently connected users
    const splitSeconds = room.sessionConfig.splitMinutes * 60;
    for (const [, u] of room.users) {
      u.studySecondsEarned += splitSeconds;
    }

    const nextBreakIndex = room.currentSplitIndex; // breaks are 0-indexed same as split
    const isLastSplit = room.currentSplitIndex >= room.sessionConfig.numSplits - 1;

    if (isLastSplit) {
      endSession(room);
    } else {
      // Transition to break
      room.currentPhase = "break";
      startPhase(room);
    }
  } else {
    // Break ended → next study split
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
    studyTimePerUser[uid] = u.studySecondsEarned;
  }

  broadcastToRoom(room.roomId, {
    type: "session_ended",
    room_id: room.roomId,
    study_time_per_user: studyTimePerUser,
  });

  console.log(`Room ${room.roomId} session ended. Study times:`, studyTimePerUser);
}

// How many study seconds has the current user earned so far IN the live phase?
// Only call this during an active study phase.
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
  const numSplits = calcNumSplits(session_minutes, split_minutes);

  const room = {
    roomId: room_id,
    hostId: host_id,
    state: "waiting",
    sessionConfig: { sessionMinutes: session_minutes, splitMinutes: split_minutes, breakMinutes: break_minutes, numSplits },
    users: new Map(),
    currentPhase: null,
    currentSplitIndex: 0,
    phaseStartedAt: null,
    phaseTimer: null,
  };

  room.users.set(host_id, {
    displayName: display_name,
    ws,
    isReady: true, // host is always "ready"
    studySecondsEarned: 0,
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
  });

  console.log(`${display_name} joined room ${room_id}.`);

  // Broadcast full snapshot to everyone so all tabs stay in sync
  broadcastToRoom(room_id, getRoomSnapshot(room));
}

function handleSetReady(ws, msg) {
  const { room_id, user_id } = msg;
  const room = rooms.get(room_id);

  if (!room || room.state !== "waiting") return;
  if (user_id === room.hostId) return; // host is always ready, can't toggle

  const user = room.users.get(user_id);
  if (!user) return;

  // Toggle ready state
  user.isReady = !user.isReady;

  // Broadcast full snapshot so everyone's room presence table updates
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

function handleLeaveRoom(ws, msg) {
  const { room_id, user_id } = msg;
  removeUserFromRoom(room_id, user_id, ws);
}

function removeUserFromRoom(roomId, userId, ws) {
  const room = rooms.get(roomId);
  if (!room) return;

  const user = room.users.get(userId);
  if (!user) return;

  // Calculate partial study seconds if leaving mid-study-split
  let finalStudySeconds = user.studySecondsEarned;
  if (room.state === "active" && room.currentPhase === "study") {
    finalStudySeconds += partialStudySecondsNow(room);
  }

  room.users.delete(userId);
  console.log(`${user.displayName} left room ${roomId}. Study seconds: ${finalStudySeconds}`);

  // Notify everyone of the study seconds this user earned (for Firebase guy)
  broadcastToRoom(roomId, {
    type: "user_left",
    room_id: roomId,
    user_id: userId,
    display_name: user.displayName,
    study_seconds_earned: finalStudySeconds,
  });

  // Also broadcast updated snapshot so remaining users' presence tables sync
  if (room.users.size > 0) {
    broadcastToRoom(roomId, getRoomSnapshot(room));
  }

  // Clean up empty rooms
  if (room.users.size === 0) {
    if (room.phaseTimer) clearTimeout(room.phaseTimer);
    rooms.delete(roomId);
    console.log(`Room ${roomId} deleted (empty).`);
    return;
  }

  // If host left and session is still waiting, assign a new host
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

  const allowedTypes = ["create_room", "join_room", "set_ready", "start_session", "leave_room"];

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
      case "create_room":    handleCreateRoom(ws, parsed);    break;
      case "join_room":      handleJoinRoom(ws, parsed);      break;
      case "set_ready":      handleSetReady(ws, parsed);      break;
      case "start_session":  handleStartSession(ws, parsed);  break;
      case "leave_room":     handleLeaveRoom(ws, parsed);     break;
    }
  });

  ws.on("close", () => {
    // Find which room this ws belonged to and clean up
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

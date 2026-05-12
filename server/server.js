const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });

// Map of WebSocket -> user info
const clients = new Map();

console.log(`FlowState WebSocket server running on port ${PORT}`);

// Build the full room snapshot (all users, statuses, overtime, session config)
function getRoomSnapshot() {
  const users = {};
  for (const [, user] of clients) {
    if (user.userId) {
      users[user.userId] = {
        display_name: user.displayName,
        status: user.status,
        overtime: user.overtime || null,
        session_config: user.sessionConfig || null,
      };
    }
  }
  return users;
}

// Broadcast a message to all connected clients
function broadcast(message) {
  const data = JSON.stringify(message);
  for (const [ws] of clients) {
    if (ws.readyState === 1) {
      ws.send(data);
    }
  }
}

wss.on("connection", (ws) => {
  // Register client with empty info until they send a status_update
  clients.set(ws, { userId: null, displayName: null, status: "online" });
  console.log(`Client connected. Total: ${clients.size}`);

  // Send current room state to the new client
  ws.send(JSON.stringify({
    type: "room_snapshot",
    users: getRoomSnapshot(),
  }));

  ws.on("message", (data) => {
    let parsed;
    try {
      parsed = JSON.parse(data);
    } catch {
      console.error("Invalid JSON:", data);
      return;
    }

    console.log("Received:", parsed);

    const allowedTypes = [
      "timer_start", "timer_pause", "timer_reset",
      "status_update", "session_config", "overtime",
    ];
    if (!allowedTypes.includes(parsed.type)) {
      console.warn("Unknown message type:", parsed.type);
      return;
    }

    if (parsed.type === "status_update") {
      // Update this client's stored info and clear any overtime
      const current = clients.get(ws);
      clients.set(ws, {
        ...current,
        userId: parsed.user_id,
        displayName: parsed.display_name,
        status: parsed.status,
        overtime: null,
      });

      broadcast({ type: "room_snapshot", users: getRoomSnapshot() });

    } else if (parsed.type === "overtime") {
      // Update overtime state for this client
      const current = clients.get(ws);
      clients.set(ws, {
        ...current,
        userId: parsed.user_id,
        displayName: parsed.display_name,
        overtime: {
          type: parsed.overtime_type,
          seconds_over: parsed.seconds_over,
        },
      });

      broadcast({ type: "room_snapshot", users: getRoomSnapshot() });

    } else if (parsed.type === "session_config") {
      // Store session config and broadcast to everyone
      const current = clients.get(ws);
      clients.set(ws, {
        ...current,
        userId: parsed.user_id,
        displayName: parsed.display_name,
        sessionConfig: {
          total_minutes: parsed.total_minutes,
          split_minutes: parsed.split_minutes,
          break_minutes: parsed.break_minutes,
        },
      });

      broadcast({ type: "room_snapshot", users: getRoomSnapshot() });

    } else {
      // Timer events — broadcast to everyone except sender
      const outgoing = JSON.stringify(parsed);
      for (const [client] of clients) {
        if (client !== ws && client.readyState === 1) {
          client.send(outgoing);
        }
      }
    }
  });

  ws.on("close", () => {
    const user = clients.get(ws);
    clients.delete(ws);
    console.log(`Client disconnected (${user?.displayName || "unknown"}). Total: ${clients.size}`);

    // Broadcast updated room after someone leaves
    broadcast({
      type: "room_snapshot",
      users: getRoomSnapshot(),
    });
  });

  ws.on("error", (err) => {
    console.error("WebSocket error:", err.message);
    clients.delete(ws);
  });
});

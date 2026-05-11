const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });

// Track all connected clients
const clients = new Set();

console.log(`FlowState WebSocket server running on port ${PORT}`);

wss.on("connection", (ws) => {
  clients.add(ws);
  console.log(`Client connected. Total: ${clients.size}`);

  // Send a welcome message to the new client
  ws.send(JSON.stringify({ type: "connected", message: "Welcome to FlowState!" }));

  ws.on("message", (data) => {
    let parsed;

    try {
      parsed = JSON.parse(data);
    } catch {
      console.error("Invalid JSON received:", data);
      return;
    }

    console.log("Received:", parsed);

    // Validate message type
    const allowedTypes = [
      "timer_start",
      "timer_pause",
      "timer_reset",
      "status_update",
    ];

    if (!allowedTypes.includes(parsed.type)) {
      console.warn("Unknown message type:", parsed.type);
      return;
    }

    // Broadcast to all OTHER connected clients
    for (const client of clients) {
      if (client !== ws && client.readyState === 1) {
        client.send(JSON.stringify(parsed));
      }
    }
  });

  ws.on("close", () => {
    clients.delete(ws);
    console.log(`Client disconnected. Total: ${clients.size}`);
  });

  ws.on("error", (err) => {
    console.error("WebSocket error:", err.message);
    clients.delete(ws);
  });
});

const express = require("express");
const cors = require("cors");
const bodyParser = require("body-parser");
const path = require("path"); // <-- Add this line

const app = express();
app.use(cors());
app.use(bodyParser.json());

// This is our in-memory store for active client connections.
// In a production app, you might scale this with Redis.
// The key is the 'id', and the value is the 'response' object.
const activeClients = new Map();

/**
 * @route GET /sse/:id
 * @desc This is the endpoint a client (your Flutter app) connects to.
 * It establishes the persistent Server-Sent Event connection.
 */
app.get("/sse/:id", (req, res) => {
  const { id } = req.params;

  // 1. Set SSE headers
  const headers = {
    "Content-Type": "text/event-stream",
    Connection: "keep-alive",
    "Cache-Control": "no-cache",
  };
  res.writeHead(200, headers);

  console.log(`Client ${id} connected`);

  // 2. Store this client's response object
  activeClients.set(id, res);

  // 3. Send an initial "connected" message
  const initialMessage = JSON.stringify({
    message: "SSE connection established",
  });
  res.write(`data: ${initialMessage}\n\n`);

  // 4. Handle client disconnect
  req.on("close", () => {
    console.log(`Client ${id} disconnected`);
    activeClients.delete(id); // CRITICAL: Remove client to prevent memory leaks
    res.end();
  });
});

/**
 * @route GET /docs/sse
 * @desc Serves a simple HTML page to test the SSE connection.
 */
app.get("/docs/sse", (req, res) => {
  // This sends the new HTML file we are about to create
  res.sendFile(path.join(__dirname, "sse-docs.html"));
});

/**
 * @route POST /send/:id
 * @desc This is the endpoint YOU call from your server logic to send
 * a message to a specific user.
 */
app.post("/send/:id", (req, res) => {
  const { id } = req.params;
  const { message } = req.body;

  // Send the message to the specific client, if they are connected
  const success = sendMessageToClient(id, message);

  if (success) {
    return res.status(200).json({ status: "Message sent via SSE" });
  } else {
    //
    // @pushNotification LOGIC WOULD RUN HERE
    //
    console.log(
      `Client ${id} is not connected. Triggering push notification...`
    );
    // --- TODO: Add your push notification logic ---
    // e.g., sendPushNotification(id, message);
    // ---------------------------------------------

    return res
      .status(200)
      .json({ status: "Client offline, push notification sent" });
  }
});

/**
 * Helper function to send a message to a specific client
 * @param {string} id - The client's ID
 * @param {any} message - The message payload (will be stringified)
 * @returns {boolean} - True if sent, false if client not found
 */
function sendMessageToClient(id, message) {
  const clientResponse = activeClients.get(id);

  if (clientResponse) {
    // Format the message as an SSE data event
    const sseMessage = `data: ${JSON.stringify(message)}\n\n`;
    clientResponse.write(sseMessage);
    return true;
  }

  return false;
}

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`SSE server running on http://localhost:${PORT}`);
});

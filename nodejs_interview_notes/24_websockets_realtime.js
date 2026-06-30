/*
===============================================================================================
                       WEBSOCKETS & REALTIME (Socket.io / ws)
===============================================================================================
Node is a GREAT fit for realtime (it's I/O-bound + event-driven). This is directly relevant to
my WhatsApp chatbot/CRM project (live chat, delivery receipts, status updates) and is the
ActionCable equivalent from Rails.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Why WebSockets, and how they differ from HTTP
-----------------------------------------------------------------------------------------------
Answer -> HTTP is request/response: the client asks, the server answers, the connection closes.
That's bad for realtime (the server can't push). WebSockets give a PERSISTENT, full-DUPLEX
connection: after an HTTP "upgrade" handshake, both sides can send messages anytime over one
long-lived TCP connection. Perfect for chat, live notifications, dashboards, presence, gaming.

  Node is well-suited because each connection is cheap (no thread per connection) — the event
  loop juggles thousands of idle-but-open sockets, which is exactly Node's strength.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Realtime options (and where Socket.io fits)
-----------------------------------------------------------------------------------------------
Answer ->
  - ws         -> a low-level, fast WebSocket library. You build your own protocol on top.
  - Socket.io  -> higher-level: rooms, namespaces, auto-reconnect, acknowledgements, and
                  FALLBACK to HTTP long-polling when WebSockets are blocked. Most popular for apps.
  - SSE (Server-Sent Events) -> one-way server->client stream over HTTP; simpler when you only
                  need server push (live feeds, notifications), no client->server channel needed.
  - WebTransport / WebRTC -> for advanced/low-latency/media cases.

  Socket.io ≈ Rails ActionCable in spirit (channels/rooms, pub/sub, broadcast).
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Socket.io basics (server + rooms)
-----------------------------------------------------------------------------------------------
Answer ->
  const { Server } = require('socket.io');
  const io = new Server(httpServer, { cors: { origin: process.env.CLIENT_URL } });

  // authenticate on connect (middleware)
  io.use((socket, next) => {
    try { socket.user = jwt.verify(socket.handshake.auth.token, SECRET); next(); }
    catch { next(new Error('unauthorized')); }
  });

  io.on('connection', (socket) => {
    socket.join(`user:${socket.user.id}`);            // a room per user (targeted push)

    socket.on('chat:send', async (msg) => {            // receive an event from this client
      const saved = await saveMessage(socket.user.id, msg);
      io.to(`conversation:${msg.conversationId}`).emit('chat:new', saved);  // broadcast to room
    });

    socket.on('disconnect', () => updatePresence(socket.user.id, 'offline'));
  });

  Emit patterns:
    socket.emit(...)            -> to this one client
    socket.broadcast.emit(...)  -> to everyone EXCEPT this client
    io.emit(...)                -> to everyone
    io.to('room').emit(...)     -> to a room (rooms = the killer feature for targeting)
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: The #1 realtime SCALING problem — multiple instances
-----------------------------------------------------------------------------------------------
Answer -> WebSockets are STATEFUL: a client holds a long-lived connection to ONE server
instance. When you scale to multiple instances (cluster/PM2/k8s), a problem appears:
  - User A is connected to instance 1, User B to instance 2.
  - A sends a message that must reach B, but instance 1 doesn't know about B's socket.

  FIX: a pub/sub BACKPLANE so instances can broadcast to each other. For Socket.io that's the
  Redis adapter:

  const { createAdapter } = require('@socket.io/redis-adapter');
  io.adapter(createAdapter(pubClient, subClient));   // now io.to(room).emit reaches all instances

  Now any instance can emit to a room and Redis fans it out to every instance holding matching
  sockets. Same Redis again. Also: configure STICKY SESSIONS at the load balancer (or use the
  adapter) so a client's polling/handshake hits the same instance.

  This is THE realtime systems-design question, and it ties to my WhatsApp project + my Rails
  scaling knowledge (stateless web tier + shared Redis).
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Other realtime production concerns
-----------------------------------------------------------------------------------------------
Answer ->
  - AUTH: verify a token on connect (handshake), not just on HTTP routes; re-check on sensitive
    events. Don't trust the client's claimed identity.
  - BACKPRESSURE / slow clients: a client that can't keep up buffers messages in server memory;
    bound queues, drop or coalesce, monitor buffer sizes.
  - HEARTBEAT / dead connections: ping/pong to detect and clean up zombie sockets (Socket.io
    does this; with raw ws you implement it).
  - DELIVERY GUARANTEES: WebSockets are fire-and-forget. For "must-deliver" (my WhatsApp
    delivery receipts), persist messages + use acknowledgements + reconcile on reconnect; don't
    rely on the socket alone. Durable stuff still goes through the DB + a queue.
  - SECURITY: validate every inbound event payload (same as HTTP input), rate-limit events,
    lock down CORS/origins.
  - HORIZONTAL SCALE: Redis adapter + sticky sessions (above), and keep per-socket state in
    Redis, not in process memory, so any instance can serve.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: How I'd describe the WhatsApp realtime piece in Node
-----------------------------------------------------------------------------------------------
Answer ->
  "Incoming WhatsApp events arrive as webhooks (HTTP), which I'd ingest on a thin Express
   endpoint and push to a BullMQ queue for reliable processing. For the live CRM/agent UI I'd
   use Socket.io: agents join rooms per conversation, and when a worker processes an inbound
   message or a delivery/status update, it emits to that room. To scale across instances I'd
   add the Socket.io Redis adapter so broadcasts reach every node, with sticky sessions at the
   load balancer. Durable delivery is guaranteed by persisting messages + statuses in the DB
   and reconciling on reconnect — the socket is the live channel, not the source of truth.
   Node is ideal here because webhook ingestion and thousands of open sockets are I/O-bound,
   which is exactly what the event loop does best."
*/

module.exports = {};

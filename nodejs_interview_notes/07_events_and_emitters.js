/*
===============================================================================================
                            EVENTS and the EventEmitter PATTERN
===============================================================================================
Node is "event-driven." A huge amount of core Node (streams, HTTP server, process) is built on
EventEmitter. Understanding it shows you grasp Node's architecture.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is the EventEmitter and the observer pattern?
-----------------------------------------------------------------------------------------------
Answer -> EventEmitter is a core class (require('events')) that implements the publish/
subscribe (observer) pattern: one object EMITS named events, and any number of LISTENERS
subscribe to those events and react. It decouples the thing that produces an event from the
things that respond to it.

  const EventEmitter = require('events');
  const emitter = new EventEmitter();

  // subscribe (listener)
  emitter.on('userRegistered', (user) => {
    console.log(`send welcome email to ${user.email}`);
  });
  emitter.on('userRegistered', (user) => {
    console.log(`track analytics for ${user.id}`);   // multiple listeners, run in order
  });

  // publish (emit) — synchronous call to each listener, in registration order
  emitter.emit('userRegistered', { id: 1, email: 'a@b.com' });

This is conceptually like ActiveSupport::Notifications / Rails callbacks / a pub-sub bus —
fire an event, let decoupled handlers react.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Core methods of EventEmitter
-----------------------------------------------------------------------------------------------
Answer ->
  emitter.on(event, listener)      -> subscribe (alias: addListener)
  emitter.once(event, listener)    -> subscribe, but auto-remove after the FIRST emit
  emitter.emit(event, ...args)     -> fire the event synchronously, passing args to listeners
  emitter.off(event, listener)     -> unsubscribe (alias: removeListener)
  emitter.removeAllListeners(event)
  emitter.listenerCount(event)
  emitter.prependListener(...)     -> add to the FRONT of the listener list

  Important behaviors:
   - Listeners run SYNCHRONOUSLY in the order they were added, on the same call stack as emit().
   - emit() returns true if there were listeners, false otherwise.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: The special 'error' event (a real production trap)
-----------------------------------------------------------------------------------------------
Answer -> 'error' is special. If an EventEmitter emits an 'error' event and there is NO
listener for it, Node THROWS the error and CRASHES the process (unhandled exception).

  const emitter = new EventEmitter();
  emitter.emit('error', new Error('boom'));   // CRASHES — no 'error' listener

  // ALWAYS attach an error listener to emitters/streams you use:
  stream.on('error', (err) => logger.error(err));

This is why "always handle the stream's error event" keeps coming up — streams are emitters.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: maxListeners and memory-leak warnings
-----------------------------------------------------------------------------------------------
Answer -> By default Node warns if you add more than 10 listeners to the SAME event on one
emitter ("possible EventEmitter memory leak detected"). It's a heads-up that you might be
adding listeners in a loop/request without removing them.

  emitter.setMaxListeners(20);    // raise the limit if you legitimately need more

Real leak cause: adding a listener on every request but never calling .off() -> listeners
accumulate forever. Use .once() for one-shot, and remove listeners when done.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Building your own emitter-based class
-----------------------------------------------------------------------------------------------
Answer -> Extend EventEmitter to give a domain object pub/sub powers:

  const EventEmitter = require('events');

  class OrderService extends EventEmitter {
    async placeOrder(order) {
      // ... persist order ...
      this.emit('order:placed', order);      // decoupled side-effects
      return order;
    }
  }

  const orders = new OrderService();
  orders.on('order:placed', (o) => sendConfirmationEmail(o));   // email module
  orders.on('order:placed', (o) => updateInventory(o));          // inventory module
  orders.on('order:placed', (o) => pushAnalytics(o));            // analytics module

  Benefit: placeOrder doesn't know or care who reacts. New side-effects = new listeners, no
  change to placeOrder. (Same decoupling value as Rails model callbacks/observers — but be
  careful, see the caution below.)
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Sync emit vs async work — and when NOT to use EventEmitter
-----------------------------------------------------------------------------------------------
Answer -> emit() is SYNCHRONOUS: it calls every listener right then, on the same stack. So:
  - If a listener throws, it can break the emitter call (unless caught).
  - If a listener does heavy work, it blocks until done (it's on the event loop thread).
  - 'error' with no listener crashes the process.

When NOT to use it:
  - For DURABLE, cross-process, or retryable work (sending emails, processing payments) DON'T
    rely on an in-memory EventEmitter — if the process crashes, the event is lost. Use a real
    message queue / job queue (BullMQ on Redis) for that. EventEmitter is in-memory, single-
    process, fire-and-forget.

  Rule: EventEmitter = lightweight in-process decoupling. BullMQ/Kafka/RabbitMQ = durable,
  distributed, retryable eventing. Don't confuse the two in a system design answer.

  For async listeners, prefer the events.once() promise helper or libraries, and be aware that
  emit() won't await your async listeners.

  const { once } = require('events');
  const [data] = await once(emitter, 'ready');   // await a one-time event as a Promise
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Where EventEmitter shows up in core Node
-----------------------------------------------------------------------------------------------
Answer -> Almost everywhere event-y:
  - HTTP server: server.on('request', ...), server.on('connection', ...)
  - Streams: readable.on('data'/'end'/'error'), writable.on('finish'/'drain')
  - process: process.on('exit'), process.on('SIGTERM'), process.on('uncaughtException')
  - Sockets, child_process, etc.
  Recognizing that these are all EventEmitters means one mental model covers a lot of Node.
*/

module.exports = {};

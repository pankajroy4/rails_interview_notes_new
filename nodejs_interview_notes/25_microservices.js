/*
===============================================================================================
                       MICROSERVICES & MESSAGE QUEUES (Node context)
===============================================================================================
My Rails notes already cover microservices concepts; this file focuses on how they look in a
Node stack. Node's lightweight processes make it a popular microservices runtime.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Monolith vs microservices (the honest take)
-----------------------------------------------------------------------------------------------
Answer -> A MONOLITH is one deployable app (my Rails apps). MICROSERVICES split the system into
small, independently deployable services owning their own data, communicating over the network.

  Microservices PROS: independent deploy/scale, tech/team autonomy, fault isolation, scale hot
  services separately.
  Microservices CONS: distributed-systems complexity — network failures, eventual consistency,
  distributed transactions, observability across services, more ops overhead.

  SENIOR TAKE: "Start with a well-structured monolith (modular monolith) and extract services
  only when there's a real scaling/team reason. Microservices solve organizational + scaling
  problems at the cost of huge operational complexity — they're not a default." Don't over-
  architect; interviewers respect this judgment.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: How Node services communicate
-----------------------------------------------------------------------------------------------
Answer ->
  SYNCHRONOUS (request/response, caller waits):
   - REST over HTTP (simplest, ubiquitous).
   - gRPC (HTTP/2 + protobuf): fast, strongly-typed contracts, great for internal service-to-
     service calls. (@grpc/grpc-js)
   - GraphQL federation (a gateway stitches multiple services' schemas).

  ASYNCHRONOUS (events/messages, fire-and-forget, decoupled):
   - Message brokers: RabbitMQ (queues, routing), Kafka (high-throughput event streaming/log),
     Redis Streams, NATS, cloud queues (SQS/SNS).
   - Producers publish events; consumers react. Services don't call each other directly ->
     loose coupling + resilience (a down consumer doesn't fail the producer).

  Rule: use SYNC when the caller needs an immediate answer; use ASYNC events for decoupling,
  durability, and spiky workloads. This is the same EventEmitter-vs-queue distinction from
  file 07, scaled up to a distributed system.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Message queues vs job queues (clarify the overlap)
-----------------------------------------------------------------------------------------------
Answer ->
  - BullMQ (Redis) = a JOB queue: background tasks within an app/system, with retries, scheduling,
    concurrency. My Sidekiq-style use cases.
  - Kafka / RabbitMQ = MESSAGE brokers for inter-SERVICE communication / event streaming, often
    cross-team, high scale, with pub/sub topics, consumer groups, ordering, replayability (Kafka).

  Overlap exists, but the framing matters: "BullMQ for in-app background jobs; Kafka/RabbitMQ
  for cross-service event-driven architecture." Choosing the right one is a maturity signal.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Core distributed-systems patterns (name + explain a few)
-----------------------------------------------------------------------------------------------
Answer ->
  - API GATEWAY: a single entry point that routes to services, handles auth, rate limiting,
    aggregation (Kong, Nginx, or a Node BFF). Clients talk to the gateway, not 12 services.
  - SERVICE DISCOVERY: services find each other dynamically (Consul, k8s DNS/Services).
  - CIRCUIT BREAKER: stop calling a failing dependency to avoid cascading failures; fail fast +
    recover (opossum in Node). Pair with timeouts + retries-with-backoff + bulkheads.
  - SAGA: manage a transaction spanning services via a sequence of local transactions +
    compensating actions (since you can't do a distributed ACID transaction). Choreography
    (events) or orchestration (a coordinator).
  - OUTBOX PATTERN: to publish an event reliably with a DB write, write the event to an "outbox"
    table in the same transaction, then a relay publishes it — avoids the dual-write problem.
  - IDEMPOTENT CONSUMERS: messages are at-least-once, so consumers must dedupe (same idempotency
    discipline as my job-queue notes — file 16).
  - EVENTUAL CONSISTENCY: accept that data converges over time across services; design for it.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Resilience between Node services (concrete)
-----------------------------------------------------------------------------------------------
Answer -> When service A calls service B over HTTP:
  - TIMEOUTS on every outbound call (never wait forever — a hung call exhausts your event loop's
    pending work and your connection pool).
  - RETRIES with exponential backoff + jitter, but ONLY for idempotent operations.
  - CIRCUIT BREAKER (opossum) so repeated failures trip open and you fail fast / serve a fallback
    instead of piling up requests.
  - BULKHEADS / bounded concurrency so one slow dependency can't consume all resources.
  - Graceful degradation: return cached/partial data when a non-critical dependency is down.

  // sketch
  const CircuitBreaker = require('opossum');
  const breaker = new CircuitBreaker(callServiceB, { timeout: 3000, errorThresholdPercentage: 50,
                                                     resetTimeout: 10000 });
  breaker.fallback(() => cachedValue);
  const result = await breaker.fire(args);
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Deployment & ops (containers, the modern default)
-----------------------------------------------------------------------------------------------
Answer ->
  - Each service = a small Docker image (multi-stage build: build with full toolchain, run on a
    slim base; run as non-root; one process per container).
  - Orchestrate with Kubernetes (or ECS): replicas for scale, health/readiness probes, rolling
    deploys, autoscaling, secrets/config injection. k8s plays the PM2/cluster role across nodes.
  - Observability is non-negotiable in distributed systems: centralized structured logging,
    metrics (Prometheus/Grafana), and DISTRIBUTED TRACING (OpenTelemetry) with a correlation ID
    propagated across service calls so you can follow one request end-to-end.
  - CI/CD per service; contract testing (Pact) so services don't break each other's APIs.

  My Docker/AWS/CI-CD experience from Rails carries straight over — the container + pipeline +
  observability story is language-agnostic.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: A balanced closing answer
-----------------------------------------------------------------------------------------------
Answer ->
  "Node's cheap processes and I/O strength make it a common microservices runtime, and the
   patterns are the standard ones — API gateway, async messaging with Kafka/RabbitMQ for
   decoupling, sync gRPC/REST when a caller needs an answer, circuit breakers and timeouts for
   resilience, sagas/outbox for cross-service consistency, and idempotent consumers because
   delivery is at-least-once. But I'd only split a monolith when team or scaling pressure
   justifies the distributed-systems tax. I'd usually start with a clean modular monolith and
   extract services deliberately."
*/

module.exports = {};

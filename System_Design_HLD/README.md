# System Design — From Zero to Interview-Ready

This folder is the System Design companion to `dsa.rb`. Where `dsa.rb` builds pattern
recognition for algorithmic problems, this folder builds pattern recognition for
**architectural** problems: how to take a vague product requirement ("design
WhatsApp") and turn it into a concrete, defensible technical design.

## What is System Design, in one paragraph?

System design is the practice of defining the architecture, components, data models,
APIs, and trade-offs of a software system so it satisfies both its **functional
requirements** (what it must do) and its **non-functional requirements** (how well it
must do it — scale, latency, availability, cost, consistency). Unlike a DSA problem,
there is rarely one "correct" answer — there is only a set of trade-offs, and your job
in an interview (and in your actual job) is to navigate them deliberately and explain
*why* you chose what you chose. File `01_Concepts/01_what_is_system_design.md` goes
into this in full, assuming zero prior knowledge.

## How to use this folder

Go in order the first time through — later files assume you already know the earlier
ones. Once you've done a full pass, `02_Interview_Questions/` is where the concepts
get exercised together, the same way solving problems in `dsa.rb` exercises DSA
patterns.

## 01_Concepts/ — the building blocks

| # | File | What it covers |
|---|------|-----------------|
| 01 | what_is_system_design.md | What SD actually is, functional vs non-functional requirements, how it differs from DSA, the mindset shift |
| 02 | scalability_and_estimation.md | Vertical vs horizontal scaling, latency vs throughput, availability (the "nines"), SLA/SLO/SLI, back-of-envelope estimation, latency numbers every engineer should know |
| 03 | networking_and_apis.md | DNS, TCP vs UDP, HTTP/HTTPS, WebSockets/SSE/long-polling, REST vs GraphQL vs gRPC, API Gateway |
| 04 | load_balancing.md | L4 vs L7 load balancing, algorithms, consistent hashing, health checks, sticky sessions |
| 05 | caching.md | Cache-aside/write-through/write-back/write-around, eviction policies (LRU/LFU), CDNs, Redis/Memcached, cache invalidation, thundering herd |
| 06 | databases_fundamentals.md | SQL vs NoSQL (KV, document, column, graph), ACID vs BASE, indexing, normalization vs denormalization |
| 07 | database_scaling.md | Replication, sharding/partitioning strategies, consistent hashing in depth, federation, hot shard problems |
| 08 | cap_theorem_and_consistency.md | CAP theorem, PACELC, consistency models (strong/eventual/causal), quorums, vector clocks |
| 09 | distributed_systems_core.md | Consensus (Paxos/Raft), leader election, gossip protocol, 2PC/Saga, idempotency, distributed locks, clock sync |
| 10 | message_queues_and_streaming.md | Pub/sub, Kafka/RabbitMQ/SQS, event-driven architecture, stream processing |
| 11 | microservices_and_patterns.md | Monolith vs microservices, service discovery, service mesh, circuit breaker, bulkhead, retries, API gateway, BFF |
| 12 | storage_systems.md | Object/blob storage, file systems, data lakes vs warehouses, CDN origin storage |
| 13 | search_and_indexing.md | Inverted index, Elasticsearch basics, typeahead/autocomplete design |
| 14 | security_basics.md | AuthN vs AuthZ, OAuth2/JWT, rate limiting algorithms, encryption basics, DDoS mitigation |
| 15 | observability.md | Logging, metrics, tracing, alerting, health checks |
| 16 | interview_framework.md | The step-by-step framework for ANY system design interview question, common mistakes, how to communicate |

## 02_Interview_Questions/ — worked problems

Ordered roughly easy → hard, the way `dsa.rb`'s Easy → Medium → Advanced progression
works. Each file follows the same shape: clarify requirements → estimate scale →
high-level design (with an architecture diagram) → deep dive on the hard parts →
bottlenecks & trade-offs → how to extend further.

| # | File | System |
|---|------|--------|
| 01 | distributed_id_generator.md | Unique ID generator (Snowflake-style) |
| 02 | rate_limiter.md | API rate limiter |
| 03 | url_shortener.md | URL shortener (bit.ly / TinyURL) |
| 04 | typeahead_autocomplete.md | Search typeahead / autocomplete |
| 05 | web_crawler.md | Web crawler |
| 06 | distributed_cache.md | Distributed cache (Redis-like) |
| 07 | notification_system.md | Notification system (push/SMS/email fan-out) |
| 08 | news_feed.md | News feed (Facebook/Instagram) |
| 09 | chat_application.md | Chat app (WhatsApp/Messenger) |
| 10 | twitter_x.md | Twitter / X |
| 11 | video_streaming.md | Video streaming (YouTube/Netflix) |
| 12 | ride_sharing_uber.md | Ride-sharing (Uber/Lyft) |
| 13 | cloud_file_storage.md | Cloud file storage & sync (Dropbox/Drive) |
| 14 | payment_system.md | Payment / transaction processing system |
| 15 | ecommerce_platform.md | E-commerce platform (Amazon-style catalog/cart/checkout) |
| 16 | ticket_booking_system.md | Ticket/seat booking (BookMyShow/Ticketmaster) |
| 17 | distributed_key_value_store.md | Distributed key-value store (DynamoDB/Cassandra-style) |
| 18 | collaborative_document_editor.md | Collaborative document editor (Google Docs) |
| 19 | ad_click_aggregation.md | Ad click event aggregation / analytics pipeline |
| 20 | search_engine.md | Web search engine (crawling + indexing + ranking at scale) |
| 21 | leaderboard_system.md | Real-time leaderboard (gaming/sports ranking) |
| 22 | distributed_job_scheduler.md | Distributed job scheduler (cron at scale) |
| 23 | proximity_service.md | Proximity/nearby search (Yelp-style) |
| 24 | content_delivery_network.md | Content Delivery Network (build a simplified CDN) |

## Status

This folder is being generated in stages. If a file listed above doesn't exist yet or
looks thin, it's still being written — ask to have it filled in or check back shortly.

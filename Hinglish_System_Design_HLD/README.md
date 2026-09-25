# System Design — Zero se Interview-Ready tak

Yeh folder `dsa.rb` ka System Design companion hai. Jaise `dsa.rb` algorithmic problems ke liye pattern recognition banata hai, waise hi yeh folder **architectural** problems ke liye pattern recognition banata hai: ek vague product requirement ("design WhatsApp") ko kaise ek concrete, defensible technical design mein convert karna hai.

## System Design kya hai, ek paragraph mein?

System design ek practice hai jisme aap kisi software system ki architecture, components, data models, APIs, aur trade-offs define karte ho taaki wo apni **functional requirements** (usko kya karna hai) aur **non-functional requirements** (usko kitna achha karna hai — scale, latency, availability, cost, consistency) dono satisfy kare. DSA problem ke unlike, yahan shayad hi koi ek "correct" answer hota hai — sirf trade-offs ka ek set hota hai, aur interview mein (aur apni actual job mein bhi) aapka kaam hai unhe deliberately navigate karna aur explain karna ki *why* aapne wahi choose kiya jo choose kiya. File `01_Concepts/01_what_is_system_design.md` isme poori tarah jaati hai, zero prior knowledge assume karke.

## Is folder ko kaise use karein

Pehli baar mein order mein jaao — baad ki files assume karti hain ki aapko pehle wali files pata hain. Ek full pass ho jaane ke baad, `02_Interview_Questions/` wo jagah hai jahan concepts saath mein exercise hote hain, waise hi jaise `dsa.rb` mein problems solve karna DSA patterns ko exercise karta hai.

## 01_Concepts/ — building blocks

| # | File | Kya cover karta hai |
|---|------|-----------------|
| 01 | what_is_system_design.md | SD actually kya hai, functional vs non-functional requirements, yeh DSA se kaise alag hai, mindset shift |
| 02 | scalability_and_estimation.md | Vertical vs horizontal scaling, latency vs throughput, availability (the "nines"), SLA/SLO/SLI, back-of-envelope estimation, latency numbers jo har engineer ko pata hone chahiye |
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
| 16 | interview_framework.md | Kisi bhi system design interview question ke liye step-by-step framework, common mistakes, kaise communicate karein |

## 02_Interview_Questions/ — worked problems

Roughly easy → hard order mein hai, waise hi jaise `dsa.rb` ka Easy → Medium → Advanced progression kaam karta hai. Har file same shape follow karti hai: requirements clarify karna → scale estimate karna → high-level design (architecture diagram ke saath) → hard parts pe deep dive → bottlenecks & trade-offs → aage kaise extend karein.

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
| 24 | content_delivery_network.md | Content Delivery Network (ek simplified CDN banana) |

## Status

Yeh folder stages mein generate ho raha hai. Agar upar list ki koi file abhi exist nahi karti ya thin lag rahi hai, toh iska matlab hai wo abhi likhi ja rahi hai — us file ko fill karwane ke liye bolo ya thodi der baad check karo.

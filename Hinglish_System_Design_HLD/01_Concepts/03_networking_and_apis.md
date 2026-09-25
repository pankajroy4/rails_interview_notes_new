# Networking and APIs

## Yeh important kyun hai

Har distributed system, neeche se, processes ka ek collection hota hai jo network ke over baat karte hain — aur network unreliable hota hai, usme latency hoti hai, aur woh partition ho sakta hai. Is layer par liye gaye choices (kaunsa protocol, kaunsa communication pattern, clients servers ko kaise discover karte hain) directly decide karti hain ki aapka system fail over jaldi kar sakta hai ya nahi, real-time features feasible hain ya nahi, aur internal services independently evolve kar sakti hain ya nahi. DNS TTLs galat set karo aur ek failover jo seconds mein hona chahiye woh ek hour le leta hai. Ek chatty REST API pick karo ek latency-sensitive mobile client ke liye aur aap user ki battery aur data plan ek screen render karne ke liye 15 round trips mein burn kar dete ho. Yeh layer invisible hoti hai jab kaam karti hai aur sabse pehli cheez hoti hai jise blame kiya jaata hai jab kaam nahi karti.

## DNS (Domain Name System)

**DNS** human-readable domain names (`api.example.com`) ko IP addresses mein translate karta hai jinpar machines actually traffic route karti hain. Yeh effectively internet ki phone book hai, aur yeh ek lever system bhi hai jo system designers load balancing aur failover ke liye use karte hain.

**Resolution chain** (simplified, ek uncached lookup ke liye):

```text
client
  -> recursive resolver (usually aapka ISP ya 8.8.8.8/1.1.1.1)
       -> root nameserver          (kehta hai: ".com TLD server se poochho")
            -> TLD nameserver      (.com — kehta hai: "example.com ke authoritative server se poochho")
                 -> example.com ke liye authoritative nameserver
                      (api.example.com ka actual IP address return karta hai)
  <- recursive resolver cache karta hai aur IP client ko return karta hai
```

Practice mein, zyaadatar lookups recursive resolver ke cache se (ya browser/OS se bhi) hi serve ho jaate hain root tak pahunchne se pehle hi — poori chain sirf ek cold cache par run hoti hai.

**DNS system design mein kyun matter karta hai:**

- **DNS-based load balancing / GSLB (Global Server Load Balancing)**: same hostname ke liye ek DNS query alag-alag IP addresses return kar sakti hai depending on querying client ki location, current server health, ya load par — users ko nearest ya least-loaded regional deployment par route karta hai isse pehle ki ek bhi packet aapke infrastructure tak pahunche.
- **TTL (Time To Live) aur failover speed**: har DNS record ki ek TTL hoti hai jo resolvers ko batati hai ki answer ko kitni der cache karna hai. Ek long TTL (jaise, 24 hours) ka matlab hai stale IPs (jaise, ek decommissioned server) client's cached answer ke through use hote rehte hain, jisse failover slow ho jaata hai. Ek short TTL (jaise, 30-60 seconds) aapko ek failed region se traffic ko jaldi redirect karne deta hai, thoda zyada DNS query volume ke cost par aur cold caches wale clients ke liye thodi zyada per-request DNS lookup overhead ke cost par.
- **CDN edge selection**: CDNs (Content Delivery Networks) commonly DNS ka use karke client ko geographically/network-nearest edge server par route karte hain, toh DNS answer khud iska part hota hai ki content ek single origin door se serve hone ke bajaye nearby location se kaise serve hota hai.

## TCP vs UDP

Dono transport-layer protocols hain — IP ke upar sit karte hain — lekin yeh reliability aur speed ke beech opposite trade-offs banate hain.

| | TCP | UDP |
|---|---|---|
| Connection | Connection-oriented (data flow hone se pehle handshake) | Connectionless (bas packets bhej do) |
| Reliability | Guaranteed delivery — lost packets retransmit hote hain | Koi delivery guarantee nahi — lost packets bas gaye |
| Ordering | Guaranteed in-order delivery | Koi ordering guarantee nahi |
| Overhead | Zyada (handshake, acks, retransmission, flow control) | Kam (minimal framing, koi acks nahi) |
| Speed | Reliability machinery ki wajah se slower | Faster — acknowledgment/retransmission ka wait nahi karna padta |
| Typical use | APIs, databases, file transfer, jahan correctness zaroori ho | Video calls, gaming, DNS, live streaming |

**Har ek kyun choose kiya jaata hai:** TCP lagbhag sabhi application-layer traffic (HTTP APIs, database connections) ke liye default hai kyunki ek API response ya SQL query result ka ek byte lose ya reorder hona unacceptable hai — correctness extra milliseconds ki overhead se zyada matter karti hai. UDP tab choose kiya jaata hai jab ek occasional dropped packet uski retransmission ke delay se better ho: ek video call mein, ek lost frame jo 200ms late retransmit hota hai woh use skip karke current frame par move on karne se worse hai; ek stale video frame late hone ke baad useful nahi rehta. DNS khud typically usi wajah se UDP par run karta hai — ek quick, single-round-trip lookup jahan ek client timeout par simply retry kar sakta hai, TCP ka connection setup cost har query ke liye pay karne ke bajaye.

## HTTP/HTTPS aur protocol versions

**HTTP** (HyperText Transfer Protocol) woh application-layer protocol hai jispar zyaadatar APIs aur web traffic run karte hain, TCP ke upar built (ya, HTTP/3 mein, UDP ke upar). **HTTPS** hai HTTP over **TLS** (Transport Layer Security) — yeh connection ko encrypt kar deta hai taaki data transit mein read ya tamper na kiya ja sake. HTTPS aaj default hai (sirf logins/payments ke liye nahi) kyunki: kisi bhi untrusted network par traffic (public wifi, ek ISP, ek compromised router) otherwise transit mein readable aur modifiable hota hai; browsers aur search engines plain HTTP ko actively penalize/warn karte hain; aur TLS aapko server identity verification bhi deta hai (aapko silently kisi impersonator se baat karne se rokta hai).

| | HTTP/1.1 | HTTP/2 | HTTP/3 |
|---|---|---|---|
| Transport | TCP | TCP | UDP (QUIC ke through) |
| Multiplexing | Nahi — per connection ek request wait karta hai (browsers isse compensate karne ke liye kayi connections open karte hain) | Haan — kayi requests/responses ek connection par interleaved | Haan, aur transport level par bhi |
| Header compression | Nahi (headers baar-baar plain text mein bheje jaate hain) | Haan (HPACK) | Haan (QPACK) |
| Head-of-line blocking | Haan, badly | HTTP layer par kam ho jaata hai, lekin ek lost TCP packet phir bhi *sabhi* multiplexed streams ko block kar deta hai (TCP-level HOL blocking) | Avoid ho jaata hai — QUIC har stream ko independently handle karta hai, isliye ek lost packet sirf apne hi stream ko block karta hai |
| Kab matter karta hai | Legacy/simple cases | Zyaadatar modern web/API traffic ke liye default | High-latency ya lossy networks (mobile), jahan TCP ki HOL blocking sabse zyada hurt karti hai |

System design ke liye practical takeaway: HTTP/2 ki multiplexing hi wajah hai ki ab aapko per-connection request limits ke around kaam karne ke liye domain sharding ya spriting jaisi tricks ki zaroorat nahi padti, aur HTTP/3 ka QUIC-over-UDP par move specifically us case ko fix karne ke liye hai jahan ek flaky mobile connection par lost packet poore in-flight requests ko us TCP connection par stall kar deta tha.

## Real-Time Communication Options

Jab ek server ko client ko updates push karne hote hain bina client se baar-baar "kuch naya hai?" poochhne ke, tab kayi patterns hote hain jinke cost/complexity profiles bahut alag hote hain.

| | Direction | Connection overhead | Support | Kab use karein |
|---|---|---|---|---|
| Short polling | Client fixed interval par baar-baar poochhta hai | Har interval par naya HTTP request — high overhead, kuch change na hone par wasted requests | Universal (plain HTTP) | Simplicity freshness se zyada matter karti hai; updates infrequent hain (jaise, status check ke liye har 30s poll) |
| Long polling | Client poochhta hai, server request ko tab tak hold karta hai jab tak data na ho (ya timeout), client turant re-ask karta hai | Short polling se kam wasted round trips, lekin phir bhi repeated connection setup | Universal (plain HTTP) | Near-real-time updates chahiye lekin WebSockets use nahi kar sakte (jaise, restrictive proxies/firewalls) |
| Server-Sent Events (SSE) | Unidirectional: server se client tak hi | Ek long-lived HTTP connection, low overhead, browser API mein built-in auto-reconnect | Native browser support (`EventSource`), plain HTTP/HTTPS, sabhi mobile/native clients par same tarah support nahi | Server updates ki ek stream push karta hai aur client ko kabhi data wapas bhejne ki zaroorat nahi (jaise, live news feed, stock ticker, notification stream) |
| WebSockets | Bidirectional, full-duplex | Ek initial HTTP upgrade handshake ke baad ek persistent connection; uske baad low per-message overhead | Broadly supported, lekin aisi infra chahiye jo long-lived connections open rakh sake (LBs/proxies ko upgrade support karna chahiye) | Client aur server dono ko continuously low latency ke saath data bhejna hai (jaise, chat, multiplayer games, collaborative editing) |

Rule of thumb: freshness requirement ko jo simplest option satisfy kare woh use karo. Agar update frequency low hai toh pehle short polling; agar sirf server-to-client hai toh SSE; WebSockets sirf tab jab client ko genuinely real time mein data bhi wapas bhejna ho, kyunki yeh chaaron mein sabse zyada operationally expensive hai (scale par persistent bidirectional connections ka matlab hai aapki infrastructure ko har connected client ke liye state hold aur route karna).

## API Paradigms: REST vs GraphQL vs gRPC

| | REST | GraphQL | gRPC |
|---|---|---|---|
| Data fetching model | Fixed endpoints, har ek fixed shape return karta hai | Client exactly wahi fields specify karta hai jo use ek query mein chahiye | Defined RPC (Remote Procedure Call) methods strict request/response schemas ke saath |
| Over/under-fetching | Common — ek endpoint zaroorat se zyada fields return kar sakta hai (over-fetching) ya poori view assemble karne ke liye multiple calls force kar sakta hai (under-fetching) | Dono solve karta hai — client ek round trip mein exactly wahi maangta hai jo use chahiye | Really applicable nahi hai — har call ek precise, purpose-built method hoti hai |
| Schema/typing | Usually loose (JSON, optionally OpenAPI spec upar se) | Strongly typed schema GraphQL ka core hi hai | Protocol Buffers (.proto files) ke through strongly typed, code-generated clients/servers |
| Performance | Reasonable; JSON + HTTP/1.1 ya HTTP/2 | Wire par REST jaisa hi, lekin kam round trips se overall win ho sakta hai | Sabse fast — binary Protobuf serialization + HTTP/2 multiplexing, JSON se kaafi chhote payloads |
| Typical use case | Public-facing APIs; simple, cacheable, widely understood | Mobile/frontend clients jinhe kayi resources ke across flexible queries chahiye bina over-fetching ke | Internal service-to-service (microservice) communication jahan performance aur strict contracts matter karte hain |

**Use-case split kyun hai**: REST ki simplicity, cacheability (standard HTTP caching semantics naturally kaam karte hain), aur universal tooling isse ek public API ke liye safe default banate hain jise kayi unknown clients consume karte hain. GraphQL apni complexity tab earn karta hai jab ek frontend/mobile client ko kayi underlying resources se data assemble karna ho aur multiple REST calls ki network round-trip cost (ya slow mobile connection par over-fetched fields ki waste) ek real problem ho. gRPC ka binary format aur HTTP/2 multiplexing isse internal microservice-to-microservice calls ke liye default choice banate hain, jahan dono ends aapka apna code hai (isliye ek generated, strongly-typed client/server pair ek benefit hai, constraint nahi) aur raw performance/low overhead wire format ki human-readability se zyada matter karta hai.

## API Gateway

Ek **API Gateway** ek single entry point hai jo external clients aur aapki internal services ke beech baithta hai, aur cross-cutting concerns handle karta hai taaki individual services ko unhe khud-khud reimplement na karna pade:

- **Authentication** — verify karna ki caller kaun hai isse pehle ki request internal services tak pahunche.
- **Rate limiting** — clients ko throttle karna backend services ko overwhelm hone se bachane ke liye (ek abusive client ya accidental retry storm se).
- **Request routing** — ek request ko path, header, ya kisi doosre rule ke basis par sahi internal service par direct karna.
- **Response aggregation** — kayi internal services ko call karna aur unke responses ko client ke liye ek response mein combine karna (client-side round trips kam karna).
- **Protocol translation** — jaise, externally REST expose karna jabki internal services gRPC ke through communicate karte hain.

```text
                         +-------------------+
 client (web/mobile) --> |    API Gateway    |
                         | (auth, rate limit, |
                         |  routing, aggreg.) |
                         +---------+---------+
                                   |
                 +-----------------+------------------+
                 |                 |                   |
                 v                 v                   v
          +-------------+  +-------------+     +-------------+
          | User Service|  | Order Service|    | Payment Svc |
          +-------------+  +-------------+     +-------------+
```

Gateway un concerns ko centralize kar deta hai jo otherwise har internal service mein duplicate hote (aur inevitably inconsistently implement hote), aur isse internal services apna khud ka protocol/implementation freely change kar sakti hain jab tak gateway ka external contract stable rehta hai.

## Trade-offs

| Decision | Trade-off |
|---|---|
| Short DNS TTL | Faster failover, lekin zyada DNS query load aur thodi zyada cold-lookup latency |
| TCP over UDP | Reliability/ordering guaranteed, latency aur overhead ke cost par |
| WebSockets over SSE/polling | Full bidirectional real-time capability, infrastructure mein kayi persistent connections hold karne ke cost par |
| GraphQL over REST | Flexible, efficient client queries, simple HTTP caching lose karne aur query-complexity/abuse risks server-side add hone ke cost par |
| gRPC over REST | Kaafi better performance/type-safety, human-readability aur broad external client compatibility ke cost par (browsers ko gRPC-Web jaisi proxy layer chahiye) |

## Interview Tips

Networking/API questions usually ek larger design ke andar sub-decision ki tarah surface hote hain ("client ko live updates kaise milenge?" ya "yeh REST ya gRPC hona chahiye?") na ki standalone question ki tarah. Interviewers check karte hain ki aapko pata hai ki yeh interchangeable defaults nahi hain — ki aap justify kar sakte ho *kyun* WebSockets over polling, ya gRPC over REST, actual requirement ke basis par (bidirectional need, internal vs external consumer, latency sensitivity), na ki sabse trendy option pick karke. DNS TTLs ka mention karna failover time discuss karte waqt, ya yeh mention karna ki ek API Gateway wahi jagah hai jahan aap rate limiting/auth daaloge instead of har service mein — yeh specific details hain jo real hands-on exposure signal karti hain, memorized buzzwords nahi.

## Quick Recall — Self-Test

**Q1: Ek server fail ho jaaye aur aapko usse traffic redirect karna ho toh ek bahut long DNS TTL ka practical effect kya hoga?**
Clients aur resolvers jinhone already old IP cache kar li thi woh usi ko use karte rehte hain jab tak TTL expire nahi hoti, isliye failover slow hota hai — traffic dead server par hi hit karta rehta hai jitni der TTL specify karti hai, chahe DNS already update ho chuka ho.

**Q2: DNS typically TCP ke bajaye UDP kyun use karta hai?**
DNS lookups chhote, single-round-trip request/response exchanges hote hain jahan ek occasional lost query ko client simply retry kar sakta hai; har lookup ke liye TCP ka connection-setup overhead pay karna unnecessary latency add karega us use case ke liye jise TCP ki ordering/reliability guarantees ki zaroorat hi nahi.

**Q3: HTTP/3 (QUIC) kaunsa specific problem solve karta hai jo HTTP/2 mein abhi bhi hai?**
HTTP/2 ek TCP connection par kayi streams multiplex karta hai, lekin ek single lost TCP packet phir bhi un sabhi streams ko block kar deta hai (TCP-level head-of-line blocking) kyunki TCP bytes ko strict order mein deliver karta hai. HTTP/3 QUIC/UDP ke upar run karta hai, jahan har stream independently handle hota hai, isliye ek lost packet sirf apne hi stream ko stall karta hai.

**Q4: Ek dashboard ko client ko live stock prices dikhani hain lekin client kabhi data wapas nahi bhejta. Konsa real-time option best fit karta hai, aur WebSockets kyun nahi?**
Server-Sent Events (SSE) best fit karta hai — yeh unidirectional server-to-client hai, jo requirement ko exactly match karta hai, ek full-duplex connection se kam overhead rakhta hai, aur browsers mein built-in reconnect support hota hai. WebSockets kaam toh karega lekin unnecessary complexity/overhead hai kyunki client-to-server direction kabhi use hi nahi hoti.

**Q5: Internal microservice-to-microservice calls ke liye gRPC generally REST se preferred kyun hai, lekin public API ke liye nahi?**
gRPC ke binary Protobuf payloads aur HTTP/2 multiplexing kaafi better performance aur strict, code-generated type safety dete hain, jo ideal hai jab aap call ke dono ends control karte ho. Ek public API ke liye, REST ka human-readable JSON, broad tooling/client support, aur native HTTP caching ise arbitrary external consumers ke liye zyada accessible banate hain.

**Q6: GraphQL kaunsa problem solve karta hai jo plain REST mein commonly hota hai, aur ise solve karne ke liye woh kya give up karta hai?**
Yeh over-fetching (endpoint zaroorat se zyada fields return karta hai) aur under-fetching (ek poori view assemble karne ke liye multiple REST calls chahiye) solve karta hai, client ko ek single query mein exactly wahi fields specify karne dekar jo use chahiye. Yeh REST ki simple, standard HTTP caching semantics give up kar deta hai aur query cost/abuse protection ke around server-side complexity add karta hai.

**Q7: Ek API Gateway ki teen responsibilities list karo aur explain karo ki unhe wahan centralize karna kyun better hai har service ke unhe independently handle karne se.**
Authentication, rate limiting, aur request routing (aur response aggregation aur protocol translation bhi) typical responsibilities hain. Inhe centralize karna har internal service ko wahi cross-cutting logic dobara (inconsistently) implement karne se bachata hai, aur gateway ka external contract stable rehta hai chahe internal services aur protocols peeche change hote rahein.

**Q8: TCP database connections aur API calls ke liye default choice kyun hai, jabki UDP video calls ke liye choose kiya jaata hai?**
Database queries aur API responses complete, uncorrupted, aur order mein aane chahiye — ek dropped ya reordered byte ek correctness bug hai, isliye TCP ki reliability guarantees zaroori hain. Ek video call mein, ek dropped frame jo retransmit hone tak stale ho chuka hai woh use skip karne se worse hai, isliye UDP ki lower latency (koi retransmission wait nahi) guaranteed delivery se preferred hai.

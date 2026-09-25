# Design an API Rate Limiter

## Problem Statement

"Humara public API bahut hammer ho raha hai — kuch misbehaving clients (aur
kabhi-kabhi ek bot attack) kisi bhi reasonable client se kaafi zyada
requests bhej rahe hain, aur isse baaki sabke liye service degrade ho rahi
hai. Ek rate limiter design karo jo humare API ke saamne baithe aur un
clients ko throttle kare jo ek configured request quota exceed karte hain,
bina khud bottleneck bane aur bina yeh diye ki ek gateway instance ka local
counter requests ko instances ke across spread karke trivially bypass ho
jaaye."

Yeh dono tarah se poocha jaata hai — standalone system ki tarah ("ek rate
limiter design karo jaisa AWS API Gateway ya Stripe offer karta hai") aur
bade designs ke andar embedded ek component ki tarah bhi (koi bhi
high-traffic API jo tumse design karne ko kaha jaaye, eventually usko ek
rate limiter chahiye hoga).

## Step 1: Clarify Requirements

**Functional Requirements**
- Ek defined time window ke andar client ke requests ki number limit karo
  (jaise, 100 requests/minute).
- Multiple, independently configurable limiting rules support karo — per
  user, per IP address, per API key, aur per endpoint (`/login` endpoint ko
  `/search` endpoint se kaafi strict limit chahiye).
- Jab ek client apni limit exceed kar de, request ko ek clear signal
  (HTTP 429) ke saath reject karo aur client ko batao ki woh kab retry kar
  sakta hai.
- Limits ko bina full redeploy ke configure karna possible hona chahiye
  (product/ops teams frequently quotas change karte hain — nayi pricing
  tiers, abuse response, waghera).

**Non-Functional Requirements**
- **Accuracy vs. performance trade-off**: limiter ko perfectly precise
  hone ki zaroorat nahi (ek boundary pe client ko thodi extra requests
  slip karne dena acceptable hai) lekin yeh kabhi itna galat nahi hona
  chahiye ki koi attacker isko poori tarah bypass kar de.
- **Latency**: rate-limiting check khud har single API request pe
  negligible overhead add kare — sub-millisecond se lekar kuch
  milliseconds, kyunki yeh 100% traffic ke hot path pe baithta hai, sirf
  ek fraction pe nahi.
- **Availability**: limiter poore API ke liye ek single point of failure
  nahi banna chahiye — agar limiter ka apna storage unreachable ho jaaye,
  API ka ek defined, deliberate fallback behavior hona chahiye (dekho
  Step 6.4 mein fail-open/closed), sirf crash nahi karna chahiye.
- **Distributed correctness**: limit ko many gateway/service instances ke
  fleet ke across, jo same client ka traffic concurrently handle kar rahe
  hain, correctly hold karna chahiye — ek per-instance in-memory counter
  acceptable nahi hai kyunki isse client ki effective limit yeh depend
  karne lagti hai ki kitne instances uske requests receive kar rahe hain.
- **Scale**: bahut high aggregate request volume handle karna chahiye
  (Step 2 mein hum poore fleet ke across 500,000 requests/sec ke liye size
  karenge) while per-request overhead ko kam rakhte hue.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: ek API platform jo 50,000 active API keys serve karta hai,
jisme ek typical client 100 requests/minute pe capped hai aur average
utilization cap ka lagbhag 30% hai, plus overall platform traffic
(higher-tier clients included) peak pe total 500,000 requests/sec.

**Rate-limit check throughput**
- 500,000 requests/sec mein se har ek ko rate-limit check se guzarna hai,
  kyunki check request ko process hone se pehle gate karta hai — toh
  limiter ki apni storage layer ko kam se kam 500,000 reads + 500,000
  writes/sec sustain karni hain (ek counter check karna aur increment
  karna), yaani roughly 1,000,000 ops/sec.
- Ek single Redis instance comfortably 100,000-200,000 simple ops/sec
  handle karta hai; 1,000,000 ops/sec hit karne ke liye humein ek
  **sharded Redis cluster** chahiye, roughly 6-10 shards, even key
  distribution assume karte hue (Redis Cluster ya hashing se client-side
  sharding by rate-limit key).

**Storage size**
- Har active rate-limit counter entry: ek key (jaise,
  `ratelimit:user:12345:endpoint:/search`, ~40 bytes) plus ek chhoti value
  (ek integer counter ya timestamps ki ek short list, 8-64 bytes algorithm
  ke depend karte hue) plus Redis ka per-key overhead (~50-100 bytes) ≈
  roughly 150-250 bytes per active limiter key.
- 50,000 API keys x average ~5 distinct endpoints har ek pe separately
  track hote hue = 250,000 active keys, ~200 bytes each pe ≈ 50 MB. Even
  10x us scale pe (2.5M active keys ek kaafi bade platform ke liye),
  storage 1 GB se neeche hi rehta hai — rate-limit counter state chhota
  hota hai; bottleneck hamesha **ops/sec** hota hai, storage volume nahi.
- Counters expire (TTL'd) ho jaate hain unki window close hone ke thode
  hi der baad, toh yeh storage footprint unbounded grow nahi karta — yeh
  sirf currently-active window ko reflect karta hai, historical data ko
  nahi.

**Bandwidth**
- Har check ek tiny Redis command hai (ek Lua script call ya `INCR` +
  `EXPIRE`), request+response order of 100-200 bytes ka.
- 1,000,000 ops/sec x ~150 bytes ≈ 150 MB/sec internal traffic gateway
  instances aur Redis cluster ke beech — ek datacenter-local network ke
  liye trivial, lekin iska matlab yeh hai ki Redis cluster ko gateways ke
  paas (low-latency) baithna chahiye, kisi WAN link ke across nahi.

## Step 3: High-Level Design

Rate limiter ko best implement kiya jaata hai **API gateway layer pe
middleware ki tarah**, jo kisi bhi backend service ko route hone se pehle
check hota hai, backed by ek **shared, distributed counter store** (Redis)
se taaki har gateway instance ek given client ke liye same up-to-date count
dekhe.

```text
                                +------------------------+
                                |   Rate Limit Rules      |
                                |   Config Store          |
                                |  (per-user/IP/key/      |
                                |   endpoint limits)       |
                                +-----------+--------------+
                                            | (read/watch)
                                            v
Client --> [ Load Balancer ] --> +----------------------+
                                  |   API Gateway (N      |
                                  |   instances)           |
                                  |                        |
                                  |  1. extract client key  |
                                  |     (user/IP/API key)   |
                                  |  2. check + incr count  |----+
                                  |     against shared store|    |
                                  |  3. allow -> forward     |    |
                                  |     deny  -> 429          |    |
                                  +-----------+--------------+    |
                                              | (allowed)          |
                                              v                    v
                                    +------------------+   +----------------+
                                    |  Backend Services |   |  Redis Cluster  |
                                    |  (business logic)  |   |  (shared counter|
                                    +------------------+   |   state, sharded)|
                                                            +----------------+
```

Key architectural decision: counter state har gateway instance ke **bahar
ek shared store** mein rehta hai, kisi ek instance ki local memory mein
nahi — yehi cheez limit ko correct banati hai chahe koi bhi instance(s)
kisi given client ke requests handle karein, aur chahe kitne bhi gateway
instances chal rahe hon.

## Step 4: API Design

Rate limiter usually khud ek client-facing API nahi hota — yeh middleware
hai — lekin yeh kuch operational interfaces expose karta hai.

**Effective interface har API request ke liye (response headers ke through), jaise `GET /v1/search?q=...`**
```
Response headers on success:
  X-RateLimit-Limit: 100
  X-RateLimit-Remaining: 37
  X-RateLimit-Reset: 1757740860   (unix timestamp when the window resets)

Response on limit exceeded:
  HTTP/1.1 429 Too Many Requests
  Retry-After: 23                 (seconds until the client should retry)
  { "error": "rate_limit_exceeded", "retry_after_seconds": 23 }
```

**Internal check, gateway middleware dwara har request pe call hota hai**
```
check_and_increment(key: "user:12345:endpoint:/search", limit: 100, window_sec: 60)
  -> { allowed: true, remaining: 37, reset_at: 1757740860 }
```

**`PUT /admin/v1/rate-limit-rules/{rule_id}` (config management, low volume)**
```json
Request: {
  "match": { "endpoint": "/login", "tier": "free" },
  "limit": 5,
  "window_seconds": 60
}
Response: { "rule_id": "r-882", "status": "active" }
```

**`GET /admin/v1/rate-limit-status/{client_key}` (ops/debugging, low volume)**
```json
Response: {
  "client_key": "user:12345",
  "endpoints": [
    { "endpoint": "/search", "current_count": 63, "limit": 100, "resets_in_sec": 41 }
  ]
}
```

## Step 5: Data Model

Core state ek **cache/key-value store (Redis)** hai, na ki SQL ya document
database, kyunki rate-limit counters exactly wahi shape hai jiske liye
Redis bana hai: high-frequency atomic increments, native per-key TTLs
(taaki purani windows automatically expire ho jaayein bina kisi cleanup
job ke), aur sub-millisecond in-memory access. Ek relational database
har-request unacceptable latency add karega aur usko manual expiry/cleanup
process chahiye hoga; ek general document store mein woh atomic increment
+ TTL primitives nahi hote jo check ko race-free banate hain (dekho
Step 6.3).

**Token bucket, ek Redis hash ki tarah store hota hai:**
```
Key:   ratelimit:bucket:{client_key}:{endpoint}
Value: { tokens: 42, last_refill_ts: 1757740800123 }
TTL:   refreshed on each access, expires after a period of inactivity
```

**Sliding window counter, ek Redis string TTL ke saath, ya ek sorted set ki tarah store hota hai:**
```
# Fixed-window-with-smoothing variant (single counter + previous window read):
Key:   ratelimit:window:{client_key}:{endpoint}:{current_minute_bucket}
Value: 63                              (INCR'd atomically)
TTL:   120 seconds (2x window, so the previous window's value is still
                     readable for the sliding calculation)

# Sliding-log variant (sorted set of individual request timestamps):
Key:    ratelimit:log:{client_key}:{endpoint}
Value:  ZSET of { score: request_timestamp_ms, member: unique_request_id }
TTL:    window_seconds
```

**Rule configuration** (low write volume, read-heavy, har gateway instance
ki local memory mein aggressively cache hota hai aur periodically refresh
hota hai) ek regular **SQL table** (ya ek config service) mein fit baithta
hai kyunki yeh chhota hai, relational hai ("yeh rule is tier + is endpoint
pe apply hota hai"), aur usko Redis ki raw throughput nahi chahiye:
```sql
CREATE TABLE rate_limit_rules (
  id            BIGINT PRIMARY KEY,
  match_tier    VARCHAR(50),
  match_endpoint VARCHAR(255),
  limit_count   INT,
  window_seconds INT,
  updated_at    TIMESTAMP
);
```

## Step 6: Deep Dive

### 6.1 Limit ko kahan enforce karein

- **Client SDK**: client library request bhejne se pehle hi khud ko
  throttle kar leti hai. Well-behaved clients ke liye wasted network
  round trips kam ho jaate hain, lekin **zero actual protection** deta
  hai — koi malicious ya buggy client bas SDK use nahi karta, ya usko
  patch karke bypass kar deta hai. Yeh sirf real enforcement ke upar ek
  courtesy layer ki tarah useful hai, khud enforcement ki tarah kabhi
  nahi.
- **API Gateway (standard answer)**: centrally enforce hota hai, kisi bhi
  request ke backend service tak pahunchne se pehle. Har client ka har
  request isse guzarta hai, toh yeh ek jagah hai jahan limit guaranteed
  check hoti hai chahe client kaisa bhi behave kare. Operationally bhi
  yeh sabse natural jagah hai — gateways pehle se auth aur TLS terminate
  karte hain, toh client identity (user ID, API key, IP) extract karna,
  jo limiter ko key karne ke liye chahiye, wahan pehle se ho raha hota
  hai.
- **Individual service**: har backend service pe enforce karna sabse
  fine-grained control deta hai (ek service khud ko specifically protect
  kar sakti hai, jaise ek "search" service expensive queries ko general
  API traffic se independently limit kar sakti hai) lekin iska matlab hai
  har service apna limiting logic reimplement karti hai aur shared
  counter store se separately baat karti hai, jo Redis ko network hops
  ki number aur operational surface area dono ko multiply kar deta hai.
  Practically, zyadatar systems **dono** karte hain: gateway pe
  coarse-grained limiting (sasti, zyadatar abuse jaldi pakadti hai) plus
  specific expensive services ke andar ek stricter, resource-aware limit
  (jaise, ek search ya ML-inference endpoint jisko generic CRUD endpoints
  se kaafi kam ceiling chahiye).

### 6.2 Algorithm choice: token bucket vs. sliding window counter

**Token bucket**
- Har client ka ek "bucket" hota hai jisme `capacity` tokens tak hold ho
  sakte hain (jaise, 100). Tokens ek steady `refill_rate` pe refill hote
  hain (jaise, 100 tokens/60 sec ≈ 1.67 tokens/sec). Har request ek token
  consume karta hai; agar bucket empty ho, request reject ho jaata hai.
- **Redis implementation**: `{tokens, last_refill_timestamp}` per client
  key store karo. Har request pe: `elapsed = now - last_refill_timestamp`
  compute karo, `elapsed * refill_rate` tokens add karo (capped at
  `capacity`), phir check karo `tokens >= 1` — agar haan, decrement karke
  allow karo; nahi toh reject karo. Yeh "lazy refill" approach (refill
  amount ko read time pe compute karna, ek background timer chalane ki
  jagah) per client ek scheduled job ki zaroorat avoid kar deta hai.
- **Kyun popular hai**: bucket capacity tak naturally short bursts allow
  karta hai (ek client jo idle rahi ho achanak `capacity` requests ek
  saath bhej sakti hai, jo real client behavior se match karta hai —
  jaise, ek page load jo ek saath several API calls fire karta hai) while
  phir bhi time ke saath steady average rate enforce karta rehta hai. Yeh
  burst tolerance usually ek feature hai, bug nahi.

**Sliding window counter**
- Do flavors:
  - **Sliding log**: har individual request ka timestamp ek Redis sorted
    set (`ZADD`) mein store karo, aur har check pe, `ZREMRANGEBYSCORE` se
    window se purani entries hataao, phir `ZCARD` se jo bacha hai woh
    count karo. Perfectly precise hai (trailing window mein requests ka
    exact count) lekin sabse memory- aur CPU-expensive — storage request
    volume ke saath grow karta hai, sirf client count ke saath nahi.
  - **Sliding window with weighted counts (common production approach)**:
    do fixed-window counters rakho — current window ka count aur previous
    window ka count — aur sliding count ko `previous_window_count *
    (overlap_fraction) + current_window_count` ki tarah estimate karo,
    jahan `overlap_fraction` yeh batata hai ki previous window ka kitna
    hissa abhi bhi trailing N seconds ke andar aata hai. Yeh ek
    approximation hai (previous window ke andar requests ki uniform
    distribution assume karta hai) lekin sliding log se kaafi sasta hai:
    per client bas do `INCR`-able integers, ek growing set ki jagah.
- **Kyun matter karta hai naive fixed windows ke upar**: ek naive fixed
  window (har 60 seconds pe clock pe counter reset karna) client ko ek
  window boundary ke thik pehle `limit` requests aur uske thik baad ek
  aur `limit` requests bhejne deta hai — effectively boundary ke around
  ek short span mein `2x limit`. Sliding approaches is gap ko close karte
  hain.
- **Practical choice**: token bucket generally preferred hai jab
  burst-tolerance desirable ho (zyadatar public APIs); weighted sliding
  window counter preferred hai jab precise, smooth rate enforcement burst
  allowance se zyada matter karti ho (jaise, ek fragile downstream
  resource ko protect karna jo genuinely koi bhi burst handle nahi kar
  sakta). Dono production mein sliding log se kaafi zyada common hain,
  memory cost ke difference ki wajah se.

### 6.3 Distributed gateway instances ke across correctness

Ek distributed deployment mein per-gateway-instance ek in-memory counter
fundamentally broken hai: agar ek client ke requests 10 gateway instances
ke across load-balanced ho jaate hain, aur har instance apne local counter
se independently "100 requests/minute" enforce karta hai, toh client
actually 10 x 100 = 1,000 requests/minute achieve kar sakta hai requests
ko evenly spread karke — limit bas is wajah se bypass ho jaata hai kyunki
traffic ek instance pe concentrate nahi ki gayi.

- **Fix**: saare gateway instances ek single external counter store
  (Redis) share karte hain, taaki "check and increment" ek shared value ke
  against ho, chahe koi bhi instance request handle kare.
- **Isse introduce hone waala race condition**: agar "current count check
  karna" aur "count increment karna" do separate Redis calls hain, toh
  same client ke do concurrent requests, jo same instant pe do different
  gateway instances handle kar rahe hon, dono `count = 99` read kar
  sakte hain (limit 100), dono "allowed" conclude kar sakte hain, aur dono
  increment kar sakte hain — jisse 100 ki jagah 101 requests through ho
  jaayenge. Yeh ek classic check-then-act race condition hai.
- **Fix 1 — atomic `INCR` with `EXPIRE`**: fixed/sliding-window-counter
  approach ke liye, Redis ka `INCR` (jo apne aap mein atomic hai) use
  karke counter ko bump karo aur *returned* value ko limit ke against
  compare karo, pehle read aur baad mein increment karne ki jagah:
  ```
  count = INCR(key)
  if count == 1: EXPIRE(key, window_seconds)   # set TTL only on first increment
  if count > limit: reject
  else: allow
  ```
  Yeh isliye kaam karta hai kyunki `INCR` atomically post-increment value
  return karta hai — koi separate read step nahi hai jispe race ho sake.
  First increment pe `EXPIRE` ko apni khud ki care chahiye (`INCR` aur
  `EXPIRE` ke beech ek crash ek key ko bina TTL ke chhod sakta hai);
  standard fix yeh hai ki dono ko ek single Lua script mein wrap kar diya
  jaaye.
- **Fix 2 — compound operations ke liye Lua script (token bucket ke liye
  zaroori)**: token bucket algorithm ko current token count read karna,
  refill compute karna, `capacity` ke against check karna, aur
  conditionally decrement karna padta hai — multiple steps jo atomically
  hone chahiye warna wahi race wapas aa jaata hai. Redis ek Lua script ko
  ek single atomic operation ki tarah execute karta hai (jab tak script
  mid-way mein hai, koi doosra client ka command interleave nahi hota),
  toh poori "read tokens, compute refill, check, decrement" sequence ek
  `EVAL` call ki tarah bhejta hai aur Redis guarantee karta hai ki yeh
  bina interruption ke start-se-finish tak chalega. Yeh Redis mein token
  bucket ke liye standard production pattern hai.
- **Distributed lock kyun nahi?** Ek lock (jaise Redlock ke through)
  check-then-act sequence ke around bhi is race ko fix kar sakta hai,
  lekin yahan yeh strictly worse hai: isse har single request ke hot path
  pe lock-acquire/release round trips add ho jaate hain, jabki ek Lua
  script same atomicity ek round trip mein deta hai bina kisi lock
  contention ya lock-timeout failure modes ke jinke baare mein sochna
  pade.

### 6.4 Rate-limiting keys aur differentiated limits

- **Per-user**: authenticated APIs ke liye sabse common key — limit ko ek
  logged-in identity se tie karta hai chahe woh koi bhi device ya IP use
  kare. Isko chahiye ki request pehle se authenticated ho rate check hone
  se pehle (ya check auth ke baad middleware chain mein hota hai).
- **Per-IP address**: unauthenticated endpoints (login, signup, password
  reset) ke liye zaroori hai jahan abhi koi user identity nahi hai key
  karne ke liye. Weaker signal hai — bahut se real users ek IP share kar
  sakte hain (corporate NAT, mobile carrier NAT), toh IP-based limits
  user-based limits se zyada generous hone chahiye taaki ek shared IP ke
  peeche innocent users collaterally throttle na ho jaayein.
- **Per-API-key**: B2B/developer-platform APIs ke liye standard hai,
  jahan key client ki pricing tier bhi encode karti hai (free tier: 100
  req/min, paid tier: 10,000 req/min) — rule lookup API key ko uski tier
  se join karta hai applicable limit choose karne ke liye.
- **Per-endpoint**: limits cost/sensitivity ke hisaab se sharply differ
  karni chahiye — ek cheap, cacheable `GET /products/{id}` shayad 1,000
  req/min allow kare, jabki ek expensive `POST /search` ya ek
  security-sensitive `POST /login` (credential-stuffing attacks ka
  target) shayad 5-20 req/min pe capped ho.
- **Practically composite keys**: real systems dimensions ko combine
  karte hain, jaise key literally `{api_key}:{endpoint}:{window}` hota
  hai, taaki ek client ki `/search` quota aur `/login` quota poori tarah
  independently track aur enforce ho, Step 5 ke rule table ke according.

### 6.5 Response contract aur fail-open vs. fail-closed

- **HTTP 429 Too Many Requests** hi sahi status code hai (403 nahi, jo ek
  permissions problem imply karta hai, ya 503, jo server khud down hone
  ko imply karta hai) — yeh specifically "tum, yeh client, ne bahut
  zyada requests bheji hain" communicate karta hai, jisse client-side
  logic "back off aur retry karo" ko "kuch broken hai, retry mat karo" se
  distinguish kar sakta hai.
- **`Retry-After` header**: client ko exactly batata hai kitne seconds
  (ya ek HTTP-date) wait karna hai retry karne se pehle, window ke reset
  time se compute hota hai. Well-behaved clients (aur zyadatar HTTP
  libraries) isko automatically respect karte hain, jo warna har
  throttled client ke turant tight loop mein retry karne se hone waali
  retry storm ko kam karta hai.
- **Redis unreachable hone pe fail-open vs. fail-closed**: yeh ek
  genuine, deliberate trade-off hai, koi oversight nahi jo fix karni ho.
  - **Fail open** (jab limiter ka storage down ho toh saari requests
    through hone dena): overall API availability ko protect karta hai —
    ek Redis outage poore API ko down nahi karta — cost pe abuse
    protection kho jaata hai exactly tab jab shayad sabse zyada zaroorat
    ho (jaise, agar woh Redis outage khud ek attack se trigger hui ho).
    Zyadatar general-purpose consumer APIs isko choose karte hain, kyunki
    total API unavailability temporarily unlimited access se worse hai.
  - **Fail closed** (jab limiter ka storage down ho toh saari requests
    reject kar dena): backend systems ko har cost pe overwhelm hone se
    protect karta hai, cost pe rate limiter khud poore API ke liye ek
    naya single point of failure ban jaata hai — ek Redis blip ab ek
    full outage ka matlab hai. Yeh un endpoints ke liye choose hota hai
    jo ek fragile ya expensive downstream resource ko protect karte hain
    jahan unlimited traffic temporary unavailability se zyada worse
    damage karega (jaise, ek endpoint jo ek expensive ML inference ya ek
    third-party paid API call trigger karta hai).
  - Bahut si production systems general traffic ke liye fail open karti
    hain lekin ek short list ke specifically fragile/expensive endpoints
    ke liye fail closed karti hain — per-rule configured, system-wide
    nahi.

## Step 7: Bottlenecks & Trade-offs

- **Shared dependency ki tarah Redis**: ab har request ko hot path pe ek
  extra network hop Redis tak chahiye. High scale pe is hop ki latency
  (typically ek datacenter ke andar sub-millisecond se kuch ms tak) har
  single API call mein add ho jaati hai, aur Redis ko khud shard karna
  padta hai (Step 2) aggregate ops/sec ke saath keep up karne ke liye —
  ek single Redis instance is design mein sabse pehle break hone waali
  cheez hogi jab traffic ek instance ki handling capacity se aage badh
  jaayega.
- **Hot-key contention**: ek single bahut-high-traffic client (ya ek
  coarse key jaise "per-IP" ek large NAT ke peeche) ek Redis key pe
  enormous request volume concentrate kar deta hai, jo Redis cluster ke
  andar ek hot shard ban sakta hai chahe cluster ki aggregate capacity
  theek ho — isko mitigate karo enough cardinality waali keys choose
  karke (jaise, IP ko ek secondary dimension ke saath combine karke) ya,
  genuinely extreme cases ke liye, count ko per-gateway-instance locally
  approximate karke periodic reconciliation ke saath, fully synchronous
  shared counter ki jagah.
- **Accuracy vs. cost trade-off, revisited**: weighted sliding-window
  approximation (Step 6.2) window boundaries ke paas non-uniform traffic
  ke neeche ek bounded margin se off ho sakta hai — yeh accept kiya jaata
  hai kyunki true precision (sliding log) scale pe memory aur Redis CPU
  mein kaafi zyada costs karta hai, aur perfect precision actually ek
  functional requirement hi nahi hai (Step 1).
- **Fail-open/fail-closed trade-off, revisited**: jo bhi choose kiya
  jaaye ek ceiling set karta hai — fail-open abuse protection ki
  guarantee ko "jab tak Redis up hai" tak cap karta hai, fail-closed API
  availability ki guarantee ko wahi cheez pe cap karta hai. Koi bhi
  configuration nahi hai jo is trade-off ko poori tarah avoid kar de;
  bas per-endpoint yeh choose karna hota hai ki kaunsa failure mode zyada
  acceptable hai.
- **Gateway instances ke beech clock skew**: token-bucket refill math aur
  fixed-window boundaries dono `now()` pe depend karte hain — gateway
  instances ke across meaningful clock drift effective limits mein
  chhoti inconsistencies cause kar sakta hai, halaanki yeh Snowflake ID
  generator ke clock-backwards issue se kaafi softer problem hai, kyunki
  ek rate limiter ka thoda-sa zyada generous ya strict ho jaana koi
  correctness catastrophe nahi hai.

## Follow-up Questions an Interviewer Might Ask

- **"CDN/edge layer pe rate-limit kaise karoge, traffic ke apne datacenter
  tak pahunchne se pehle hi?"** Edge nodes (jaise Cloudflare Workers ya
  similar edge runtime) pe ek coarser, cheaper first-pass limit push karo
  local, eventually-consistent counters use karke jo periodically sync
  hote hain — edge pe looser accuracy accept karo, badle mein obvious
  abuse (jaise, ek volumetric attack) ko block karne ke liye, isse pehle
  ki woh koi bhi origin bandwidth consume kare, phir precise, Redis-backed
  limit apply karo jab traffic gateway tak pahunche.
- **"Agar koi attacker limit dodge karne ke liye hazaaron IPs ya API keys
  rotate kare toh?"** Ek secondary, coarser limit layer in karo jo ek zyada
  attacker-resistant signal (device fingerprint, TLS fingerprint,
  behavioral anomaly score) pe key ho, primary per-key limit ke alawa, aur
  suspicious patterns ko ek separate abuse-detection pipeline mein feed
  karo, sirf per-key rate limiting se hi solve karne ki koshish karne ki
  jagah.
- **"Ek legitimate client ko temporarily unki limit se upar burst kaise
  karne doge (jaise, ek batch import job)?"** Ek explicit, time-boxed
  quota-increase mechanism expose karo (ek admin API ya self-service
  "request a burst window" feature) jo temporarily us client ke rule ko
  config store mein rewrite kar de, traffic shape se legitimate bursts ko
  automatically infer karne ki koshish karne ki jagah.
- **"Yeh design ek globally distributed, multi-region deployment ke liye
  kaise change hoga?"** Regions ke across ek single global Redis cluster
  har check mein cross-region latency add kar deta hai; common approach
  hai per-region Redis clusters ke saath ek thoda zyada regional limit
  (total limit split ya regions ke across thoda overallocated), ek
  strongly consistent global counter ki jagah, perfect global accuracy ko
  regional low latency ke liye trade karte hue — CAP-theorem ke
  trade-offs ke consistent.
- **"Concurrency ke neeche limiter actually correct hai yeh kaise test
  karoge?"** Ek single client identity se simultaneously bahut se gateway
  instances/threads se concurrent requests ke saath load-test karo aur
  verify karo ki accepted count kabhi bhi configured limit ko algorithm ke
  known bounded error margin se zyada exceed na kare — yeh specifically
  Step 6.3 mein describe kiya gaya race condition exercise karta hai.
- **"Kya rate limit rule changes ko redeploy chahiye?"** Nahi — rules ek
  config store ya database mein rehne chahiye jise gateway poll kare ya
  subscribe kare (jaise, etcd/Redis mein ek key watch karke, ya har kuch
  seconds mein ek rules table poll karke), har gateway instance current
  rules ko locally cache kare taaki har single request pe ek config
  lookup na karna pade.

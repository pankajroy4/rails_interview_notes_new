# Design a URL Shortener (bit.ly / TinyURL)

## Problem Statement

"Ek service design karo bit.ly jaisi: ek user ek long URL submit karta hai
aur usko ek short URL milta hai (jaise, `short.ly/aZ9kLp`); short URL visit
karne pe browser original long URL pe redirect ho jaana chahiye. Custom
aliases support karo, aur assume karo ki system read-heavy hoga — bahut
zyada log short links pe click karte hain, unko create karne waalon se.
Isko end to end design karo: short-code generation strategy, redirect path,
aur scale pe redirects ko fast kaise rakhoge."

Yeh sabse commonly asked system design questions mein se ek hai exactly
isliye kyunki yeh simple dikhta hai lekin isme kai genuinely non-obvious
decisions chhupe hote hain (code generation strategy, 301 vs 302, read-heavy
caching).

## Step 1: Clarify Requirements

**Functional Requirements**
- Ek long URL diya gaya ho, ek unique short URL (short code) generate karo
  aur mapping store karo.
- Ek short URL diya gaya ho, client ko original long URL pe redirect karo.
- User-specified **custom aliases** support karo (jaise,
  `short.ly/my-conference-talk`) system-generated codes ke alawa.
- Link **expiration** support karo (ek link ek configured date ke baad, ya
  N uses ke baad, resolve karna band kar de, plan/feature ke depend
  karte hue).
- Har short link ke liye basic click analytics track karo (click count,
  referrer, timestamp) — commonly ek paid/pro feature, aur yeh directly
  affect karta hai ki hum HTTP 301 redirects use kar sakte hain ya nahi
  (dekho Step 6.2).

**Non-Functional Requirements**
- **Read:write ratio heavily reads ki taraf skewed hai.** Link creation
  link clicks ke relative rare hai — ek baar create hui link shayad
  hazaaron baar click ho. Isko hum Step 2 mein quantify karenge, aur yeh
  Step 6 mein caching aur redirect-status-code decisions ka sabse bada
  driver hai.
- **Redirect latency**: short link pe click karna instantaneous feel hona
  chahiye — target well under 100ms server-side processing time, kyunki
  redirect user ke actual destination ke critical path pe hai.
- **Redirects ke liye strict consistency se zyada availability**: agar
  system briefly inconsistent ho (ek bahut recently create hui link kuch
  seconds lagaye saare caches tak propagate hone mein), yeh acceptable
  hai; ek redirect service ka *down* hona acceptable nahi hai — broken
  links turant trust erode kar dete hain aur highly visible hote hain
  (social media pe share hote hain, physical materials pe print hote
  hain). Yahan strong consistency se zyada availability prioritize ki
  jaati hai (ek AP choice).
- **Uniqueness**: do different long URLs kabhi bhi accidentally same short
  code pe map nahi hone chahiye, aur code generation ko heavy coordination
  ki zaroorat nahi honi chahiye jo scale pe link creation ko slow kar de.
- **Short code length**: jitna practical ho utna short hona chahiye (kam
  characters = zyada shareable, print mein achha lagta hai, SMS/social
  character limits mein fit ho jaata hai) while enough keyspace provide
  karte hue taaki years tak khatam na ho.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: har month 100 million naye short URLs create hote hain;
ek conservative 100:1 read:write ratio (har link average 100 baar click
hoti hai apni life ke dauran, aur clicks naturally spread out hote hain,
lekin early concentrate karte hain).

**Write (creation) QPS**
- 100,000,000 / (30 days x 86,400 sec) ≈ 38.6 creations/sec average.
- Even ek generous 5x peak multiplier ke saath launch-day traffic spikes
  ke liye, yeh 200 creations/sec se kam hai — kisi bhi reasonable single
  write path ke liye ek trivially low write load.

**Read (redirect) QPS**
- 100:1 ratio -> 100,000,000 x 100 = 10,000,000,000 redirects/month.
- 10,000,000,000 / (30 x 86,400) ≈ 3,858 redirects/sec average.
- Ek 3x peak multiplier pe (redirect traffic spikes real-world events ke
  saath align karte hain — ek viral link, ek marketing campaign): ≈
  11,574 redirects/sec peak. Yeh read load, write load nahi, wahi hai jise
  absorb karne ke liye architecture build hona chahiye — Step 1 mein call
  out kiya gaya read-heavy skew confirm ho raha hai.

**Storage**
- Har URL mapping record: short_code (7 bytes) + long_url (avg ~100 bytes,
  URLs kaafi zyada lambe ho sakte hain lekin yeh ek reasonable average
  hai) + user_id (8 bytes) + created_at/expires_at (16 bytes) + metadata
  ≈ 200 bytes/row.
- 100M naye rows/month x 200 bytes ≈ 20 GB/month.
- 5 saalon mein: 20 GB x 60 months = 1.2 TB. Ek sharded relational ya
  key-value store ke liye poori tarah manageable hai, aur itna chhota hai
  ki *hot* subset ka zyadatar hissa cache mein reh sakta hai (dekho
  Step 6.4).

**Keyspace sizing (short code length drive karta hai — dekho Step 6.1)**
- Base62 alphabet (a-z, A-Z, 0-9) = 62 symbols.
- 7 characters: 62^7 ≈ 3.52 trillion unique codes — 100M naye
  codes/month (1.2B/year) pe, yeh keyspace exhaustion se pehle roughly
  2,900+ years chalega, comfortable headroom. 6 characters (62^6 ≈ 56.8
  billion) is rate pe phir bhi ~47 years chalega, toh 6-7 characters sahi
  ballpark hai; zyadatar real systems exactly isi wajah se yahin land
  karte hain.

**Bandwidth**
- Redirect response tiny hota hai (ek HTTP 301/302 with a `Location`
  header, koi body ki zaroorat nahi) — maybe 300-500 bytes headers ke
  saath.
- 11,574 redirects/sec x ~400 bytes ≈ 4.6 MB/sec peak pe — negligible
  network load; bottleneck request *rate* hai (connection handling,
  lookup latency), payload bandwidth nahi.

## Step 3: High-Level Design

```text
                         +----------------------+
      Create flow        |     API Gateway /      |
   User -> POST /shorten ->    Load Balancer       |
                         +-----------+------------+
                                     |
                                     v
                         +----------------------+
                         |   URL Shortening       |
                         |   Service               |
                         |  - validate long URL     |
                         |  - generate/reserve       |
                         |    short code (Step 6.1)  |
                         |  - write mapping           |
                         +-----+---------------+----+
                               |                |
                               v                v
                  +--------------------+   +------------------+
                  |  Primary Datastore  |   |  Key-Generation   |
                  |  (short_code ->     |   |  Service (KGS) /   |
                  |   long_url mapping) |   |  pre-generated code|
                  |  sharded by         |   |  range pool         |
                  |  short_code hash    |   +------------------+
                  +--------------------+

                         Redirect flow (the hot path)
      User clicks short.ly/aZ9kLp
              |
              v
     +------------------+     cache hit (>90% of traffic)
     |   CDN / Edge       | ------------------------------+
     |   Cache (optional)  |                                |
     +--------+-----------+                                |
              | cache miss                                  |
              v                                              v
     +------------------+        +------------------+   +----------+
     |  Redirect Service  |  -->  |  Redis Cache      |   |  Browser  |
     |  (stateless,        |      |  (short_code ->    |-->  gets     |
     |   horizontally      |<-----|   long_url, hot     |   302/301  |
     |   scaled)            |      |   keys)             |   response |
     +--------+-----------+        +------------------+   +----------+
              | cache miss (rare)
              v
     +------------------+
     |  Primary Datastore |
     +------------------+
     (async: click event -> analytics pipeline / message queue)
```

Creation aur redirect paths deliberately do separate services ki tarah
draw kiye gaye hain jo independently scale ho sakte hain — creation
low-QPS hai aur zyada latency tolerate kar sakta hai (yeh ek one-time user
action hai); redirects high-QPS aur latency-critical hote hain, isliye
redirect service ko minimal rakha jaata hai (cache lookup, phir ek 3xx
response) aur baaki sab kuch non-essential (click analytics) critical
path se hata ke ek async queue pe daal diya jaata hai.

## Step 4: API Design

**`POST /api/v1/shorten` — ek short URL create karna**
```json
Request: {
  "long_url": "https://example.com/some/very/long/path?with=params",
  "custom_alias": "my-conference-talk",   // optional
  "expires_at": "2027-01-01T00:00:00Z"     // optional
}
Response: {
  "short_url": "https://short.ly/my-conference-talk",
  "short_code": "my-conference-talk",
  "long_url": "https://example.com/some/very/long/path?with=params",
  "created_at": "2026-09-13T10:00:00Z",
  "expires_at": "2027-01-01T00:00:00Z"
}
Errors: 409 Conflict if custom_alias is already taken.
```

**`GET /{short_code}` — redirect (hot path)**
```
Request:  GET /aZ9kLp
Response: HTTP/1.1 301 Moved Permanently   (or 302, see Step 6.2)
          Location: https://example.com/some/very/long/path?with=params
```

**`GET /api/v1/urls/{short_code}` — metadata fetch karna (dashboard use, redirect path nahi)**
```json
Response: {
  "short_code": "aZ9kLp",
  "long_url": "https://example.com/...",
  "click_count": 1523,
  "created_at": "2026-09-13T10:00:00Z",
  "is_expired": false
}
```

**`DELETE /api/v1/urls/{short_code}` — ek short link disable karna**
```json
Response: { "short_code": "aZ9kLp", "status": "deactivated" }
```

**`GET /api/v1/urls/{short_code}/analytics` — click analytics**
```json
Response: {
  "short_code": "aZ9kLp",
  "total_clicks": 1523,
  "clicks_by_day": [{ "date": "2026-09-12", "count": 210 }, "..."],
  "top_referrers": [{ "referrer": "twitter.com", "count": 480 }]
}
```

## Step 5: Data Model

Core mapping ek simple key-value lookup hai short_code se — yeh naturally
ek **NoSQL key-value store ya ek sharded relational table** mein fit
baithta hai jo `short_code` pe keyed ho (access pattern hamesha "exact
short_code se lookup karo" hai, kabhi range scan ya complex join nahi),
jiske aage ek **cache** (Redis) hot redirect path ke liye lagi hoti hai,
kyunki redirects ko high QPS pe sub-millisecond lookups chahiye hote hain
jo ek database akela, chahe woh kitna bhi fast ho, unnecessary latency aur
load add kar deta hai.

**Primary mapping table (SQL, short_code ke hash se sharded, ya ek NoSQL
KV store jaisa DynamoDB/Cassandra — dono chalega; clarity ke liye SQL
dikhaya gaya hai aur custom-alias uniqueness constraints easy bana deta
hai):**
```sql
CREATE TABLE url_mappings (
  short_code   VARCHAR(10) PRIMARY KEY,
  long_url     TEXT NOT NULL,
  user_id      BIGINT,
  created_at   TIMESTAMP,
  expires_at   TIMESTAMP NULL,
  is_custom_alias BOOLEAN DEFAULT FALSE,
  is_active    BOOLEAN DEFAULT TRUE
);
-- shard key: hash(short_code) -> shard N
```

**Cache layer (Redis), 90%+ redirects ke liye actual lookup path:**
```
Key:   redirect:{short_code}
Value: long_url string (plus is_active/expires_at flags, or a "gone" tombstone)
TTL:   long (e.g., 24h), refreshed on access; short-lived negative-cache
       entries for deleted/expired codes to avoid repeatedly hitting the
       DB for dead links
```

**Click analytics (write-heavy, append-only, time-series shaped)** — yeh
mapping table se ek separate store hai, kyunki analytics writes (shayad
har click pe ek, full 11,574/sec peak redirect rate pe) warna mapping
table ke read traffic ke saath contend karengi. Ek **wide-column /
time-series store** (ya ek message queue jo ek data warehouse mein feed
karti ho — dekho `01_Concepts/12_storage_systems.md` warehouse-vs-
operational-store distinction ke liye) relational mapping table pe yeh
sab daalne se better fit baithta hai:
```
click_events: { short_code, timestamp, referrer, user_agent, ip_country }
```
Users ko dikhaaye jaane waale click counts usually periodically
pre-aggregate kiye jaate hain (jaise, hourly rollups), har analytics page
load pe raw events se live compute karne ki jagah.

## Step 6: Deep Dive

### 6.1 Short code generation strategies, compare kiye hue

**Strategy A — ek auto-incrementing counter ka Base62 encoding**
- Ek single global counter (ya ek distributed counter service) sequential
  integers deta hai: 1, 2, 3, .... Har integer ko base62 (0-9, a-z, A-Z)
  mein encode kiya jaata hai ek compact string banane ke liye — jaise,
  integer 125 chand characters mein encode hota hai.
- **Pros**: trivially collision-free hai (counter kabhi ek value repeat
  nahi karta); codes shuru mein choti ho sakti hain jab counter chhota
  hota hai.
- **Cons**: counter khud ek centralized, coordinated resource hai — har
  code-generation request ko next value obtain karni padti hai, jiska
  matlab ya toh ek single database sequence hai (scale pe ek bottleneck
  aur contention ka single point) ya ek distributed counter service
  (complexity add karta hai, aur ab tumhe Snowflake-style partitioning
  jaisa kuch chahiye, dekho `01_distributed_id_generator.md`, bottleneck
  ko wapas recentralize hone se rokne ke liye). Sequential codes bhi
  **predictable/guessable** hain (code `N+1` obviously "next link jo
  kisi ne create ki" hai), jo information leak kar sakta hai (jaise, ek
  competitor guess kar sakta hai ki ek company ne kitni links create ki
  hain) jab tak deliberately obfuscate na kiya jaaye.

**Strategy B — long URL ko hash karo (jaise, MD5) aur pehle N base62 characters lo**
- `MD5(long_url)` compute karo, hash ko base62-encode karo, aur pehle 6-7
  characters short code ki tarah lo.
- **Pros**: koi centralized counter nahi chahiye — koi bhi server
  independently aur deterministically input URL se ek code compute kar
  sakta hai, bina kisi coordination ke.
- **Cons**: ek hash ko chand characters tak truncate karna
  **collisions** ko likely bana deta hai (birthday-paradox math: ek
  7-character base62 truncation ke saath, effective space ~3.5 trillion
  hai, lekin 100M+ codes/month pe collision probability years ke saath
  meaningfully climb karti hai — aur zyada important, do different users
  jo *same* long URL shorten karte hain unko deterministically *same*
  short code milta hai, jo desired behavior ho bhi sakta hai aur nahi
  bhi). Isko ek collision-handling path chahiye: collision pe, ek
  salt/counter append karo aur rehash karo, retry karo, aur phir se
  check-then-insert karo — extra round trips exactly write path pe, aur
  ek aisi case ke liye added implementation complexity jo sahi honi hi
  chahiye warna tum silently kisi aur ki link overwrite kar dete ho.

**Strategy C — random codes ka ek keyspace pre-generate karo, har server
ko ranges hand out karo (aksar best real-world answer)**
- Ek background job pehle se hi ek large batch of random, unique
  7-character base62 strings generate karke unhe ek "available codes"
  pool (ek table ya queue) mein store kar deta hai. Har application
  server, startup pe ya jab woh low run kare, is pool se ek **contiguous
  range ya batch** of unused codes claim karta hai (jaise, "server A, yeh
  10,000 codes sirf tumhare liye reserved hain").
- Jab ek user ek short URL create karta hai, server bas apne **locally
  held batch** se next available code pop kar leta hai — koi network
  round trip nahi, koi coordination nahi, kisi doosre server ke saath
  collision ka koi risk nahi, kyunki construction se hi har server ka
  batch har doosre server se disjoint hai.
- **Pros**: yeh sweet spot hai — codes genuinely random hote hain
  (non-guessable, Strategy A ke unlike), zero per-request coordination
  hota hai (Strategy A ke shared counter ke unlike), aur zero collision
  risk ya retry logic ki zaroorat hoti hai (Strategy B ke hash truncation
  ke unlike), kyunki uniqueness pehle se hi guarantee ho chuki thi jab
  pool generate hua tha (ek baar centrally check kiya gaya, generation
  time pe, har request pe nahi).
- **Cons**: isko ek background process chahiye jo pool ko replenish karta
  rahe servers ke apne batches exhaust hone se pehle (pool depletion rate
  monitor karo aur proactively regenerate karo); ek server jo ek unused
  batch ke saath crash ho jaaye woh un codes ko "waste" kar deta hai jab
  tak koi mechanism unused ranges reclaim karne ka na ho (usually iska
  Step 2 ke enormous total keyspace ko dekhte hue ek acceptable loss ki
  tarah accept kar liya jaata hai).
- Yeh range-handout approach directly analogous hai ki kaise kuch sharded
  database setups mein distributed primary-key allocation kaam karti hai,
  aur generally woh answer hai jo ek interview mein sabse deep
  understanding demonstrate karta hai, kyunki yeh explicitly ek chhoti si
  operational complexity (pool manage karna) ko trade karta hai
  coordination ko hot path se poori tarah eliminate karne ke liye.

**Custom aliases**: code generation ko poori tarah bypass karte hain —
user directly code supply karta hai, aur system ko bas usko atomically
check-and-reserve karna hota hai (`INSERT ... ON CONFLICT DO NOTHING` ya
equivalent atomic "insert if absent", taaki ek race avoid ho jahan do
users simultaneously same alias grab kar lein) primary mapping table ke
against.

### 6.2 HTTP 301 vs. 302 — ek genuine product trade-off

Yeh frequently gloss over kiya jaata hai, lekin yeh poore system ke sabse
concrete, decision-worthy details mein se ek hai.

- **301 Moved Permanently**: browser (aur kisi bhi intermediate
  caches/CDNs) ko batata hai ki yeh redirect permanent hai. Browsers
  **redirect ko locally cache kar lete hain** — same short link ke ek
  repeat visit pe, browser shayad tumhare server ko contact hi na kare
  aur directly long URL pe apni khud ki cache se navigate kar jaaye.
  - *Benefit*: same link ke repeat visits ke liye tumhari redirect
    service pe load dramatically kam ho jaata hai — exactly wahi savings
    jo Step 2 ke 100:1+ read skew ko dekhte hue matter karti hai.
  - *Cost*: tum un cached repeat visits ki **visibility kho dete ho** —
    agar browser tumhare server ko kabhi hit nahi karta, tum us click ko
    log nahi kar sakte, jo directly Step 1 ke click-analytics functional
    requirement ko undermine karta hai. Tum yeh ability bhi kho dete ho
    ki us short code ko kahin aur point karne ke liye kabhi change kar
    sako (agar baad mein destination update karna pade, cached 301 waale
    browsers re-check nahi karenge).
- **302 Found (temporary redirect)**: browser ko batata hai ki yeh
  redirect change ho sakta hai, toh **har single click tumhare server ko
  hit karta hai** — browser-side koi caching nahi hoti redirect target
  ki.
  - *Benefit*: complete click visibility (har click log hota hai), aur
    destination kabhi bhi change ho sakta hai aur turant saari future
    clicks ke liye effective ho jaata hai.
  - *Cost*: redirect service pe significantly zyada load, kyunki 301 ka
    "free" caching benefit chala jaata hai — peak pe ~11,574
    redirects/sec mein se har ek actually tumhari infrastructure tak
    pahunchta hai.
- **Practically trade-off**: zyadatar production URL shorteners
  (bit.ly included) **302** use karte hain, explicitly click analytics
  ko prioritize karte hue — ek link shortener product ki poori business
  value aksar analytics hi hoti hai, sirf redirect nahi — aur uske badle
  resulting load ko aggressive server-side caching (Step 6.4) se handle
  karte hain, browser pe cache karne ke liye rely karne ki jagah. Ek
  system jisko koi analytics requirement bilkul na ho, ya jo explicitly
  apni khud ki infrastructure load ko sabse zyada minimize karna chahta
  ho, reasonably 301 choose karega. Isko explicitly surface kiya jaana
  chahiye ek deliberate choice ki tarah, silently default nahi kiya
  jaana chahiye.

### 6.3 Custom alias support

- Custom aliases generated codes ke saath hi same underlying
  `short_code` column aur lookup path share karte hain — distinction
  (`is_custom_alias`) metadata hai, ek structurally different code path
  nahi.
- **Availability check** atomic honi chahiye taaki do users simultaneously
  same alias request karein toh race na ho — yeh ek conditional insert
  ki tarah implement hota hai (`INSERT ... ON CONFLICT DO NOTHING`, phir
  check karo ki jo row tumne insert karni chahi thi wahi actually present
  hai) na ki ek separate "check if exists" read ke baad ek "insert"
  write, jo phir se ek check-then-act race reintroduce kar dega.
- **Generated codes ke saath namespace collision**: kyunki generated
  codes Strategy C ke pre-generated random pool se aate hain, ek custom
  alias coincidentally pool mein pehle se reserved ek code se match kar
  sakta hai (unlikely, lekin possible) — reservation pool ko ek code ko
  "consumed" mark kar dena chahiye jis moment ek custom alias usko claim
  kare, taaki pool distribution job us code ko baad mein kisi server ko
  na de.
- **Validation**: custom aliases ko character-set aur length validation
  chahiye (reserved paths jaise `/api`, `/admin` avoid karna; aise
  characters avoid karna jinko URL-encoding chahiye) jo generated codes,
  ek known-safe base62 alphabet se draw hui, ko nahi chahiye.

### 6.4 Heavy read:write skew ke liye caching strategy

Step 2 mein quantify kiye gaye ~100:1+ (real products mein aksar isse
kaafi zyada, kyunki popular links disproportionately click hoti hain)
read:write ratio ko dekhte hue, poora redirect path **hot short codes ko
aggressively cache karne** ke around design kiya gaya hai,
`01_Concepts/05_caching.md` mein describe kiye gaye cache-aside pattern
ko follow karte hue:
- Ek redirect request pe, redirect service pehle Redis check karti hai
  (`redirect:{short_code}`). Ek cache hit primary datastore ko kabhi touch
  kiye bina redirect resolve kar deta hai — yeh wahi path hai jise peak
  ke ~11,574 redirects/sec ka bulk handle karna hota hai.
- Ek cache miss pe, service primary datastore se read karti hai, redirect
  return karti hai, aur subsequent requests ke liye cache populate kar
  deti hai (standard cache-aside).
- **Popularity skew (links ka ek chhota fraction zyadatar clicks account
  karta hai)** ka matlab hai ek relatively chhota, hot working set — chahe
  total links hundreds of millions hi kyun na hon, jo links *abhi* traffic
  receive kar rahi hain kisi bhi given moment pe, woh ek much smaller set
  hoti hain, jo ek Redis cluster ki memory mein comfortably fit ho jaati
  hai (yaad karo Step 2 ka storage estimate: poori mapping table bhi 5
  saal baad sirf ~1.2 TB hai; actively-hot subset kisi bhi moment pe uska
  ek chhota fraction hi hota hai).
- **Negative caching**: "yeh code exist nahi karta / expired hai / is
  deactivated" results ko bhi cache karo (ek shorter TTL ke saath), sirf
  successful lookups ko nahi — warna ek dead ya mistyped link ke liye
  requests ka burst (jo practically hamesha hota hai — typos, expired
  campaign links jo abhi bhi click ho rahi hain) baar baar primary
  datastore tak fall through ho jaayega.
- **CDN/edge caching** ko redirect service ke saamne further offload ke
  liye layer kiya ja sakta hai, halaanki yeh 301/302 choice ke saath
  interact karta hai: agar 302 use kar rahe ho, ek CDN phir bhi redirect
  response ko server-side cache kar sakta hai (browser-side ek 301 cache
  karne se distinct) ek short TTL ke saath, jisse 301 ke *kuch* server-load
  benefits mil jaate hain while phir bhi CDN edge pe clicks log karte hue
  origin ko forward karne se pehle, aur ek browser ke indefinite 301
  cache se shorter, zyada analytics-friendly effective cache window ke
  liye periodically invalidate kiya ja sakta hai.

## Step 7: Bottlenecks & Trade-offs

- **Sabse pehle kya break hota hai**: redirect service ki cache layer,
  agar actively-hot key set ke relative under-provisioned ho — ek
  cache-miss storm (jaise, ek cache cluster restart ke baad cold cache
  ke saath, ya ek pehle se cold link pe sudden viral spike ke dauran)
  traffic ka ek burst directly primary datastore tak bhej deta hai, jo
  steady-state cache offload ke liye sized hai, full redirect QPS ko
  directly absorb karne ke liye nahi. Isko mitigate karo deploy pe cache
  warming se aur request coalescing se (ek given short_code ke liye ek
  single in-flight DB read us same code ke saare concurrent requests ko
  service karta hai, har ek independently DB hit karne ki jagah — yeh
  thundering herd problem hai, jo `01_Concepts/05_caching.md` mein cover
  kiya gaya hai).
- **Hot-link concentration**: ek single link viral ho jaana effectively
  unbounded QPS ek cache key pe direct kar sakta hai — isko cache layer ki
  apni horizontal scaling se mitigate kiya jaata hai aur, genuinely
  extreme cases ke liye, har redirect service instance pe single hottest
  keys ke liye ek short-lived local (in-process) cache se, un keys ke
  liye slightly staler data accept karte hue badle mein system ke sabse
  popular link ke har request ke liye Redis ko round-trip na karna pade.
- **Trade-off — 301 vs 302**: pehle hi Step 6.2 mein depth mein cover ho
  chuka hai; poore design ke headline trade-off ki tarah restate karte
  hain — analytics completeness vs. infrastructure load, zyadatar
  production systems mein 302 + aggressive server-side caching choose
  karke resolve hota hai, 301 + browser caching ke upar.
- **Trade-off — short code generation strategy**: Strategy C
  (pre-generated range handout) ek chhoti si background-job complexity
  trade karta hai Strategy A ke coordination bottleneck aur Strategy B ke
  collision-handling complexity dono ko eliminate karne ke liye — is
  scale ke zyadatar systems ke liye sahi choice hai, halaanki Strategy A
  ek much smaller-scale system ke liye reason karna simpler rehta hai
  jahan ek single counter ka throughput genuinely sufficient ho.
- **Write path relatively unconstrained hai**: ~200 creations/sec average
  pe (Step 2), write path ke paas enormous headroom hai — yehi wajah hai
  ki design correctly apna almost saara complexity budget read path mein
  invest karta hai, write path mein nahi; ek design jo link creation ko
  optimize karne mein equal effort spend kare, woh galat problem solve
  kar raha hoga.

## Follow-up Questions an Interviewer Might Ask

- **"Ek link jo achanak viral ho jaaye — minutes mein normal traffic ka
  100x — usko kaise handle karoge?"** Cache layer ki horizontal
  scalability aur request coalescing pe rely karo taaki spike ko primary
  datastore tak kabhi pahunchne diye bina absorb kiya ja sake; agar 302
  use kar rahe ho, us specific key ki effective staleness tolerance ko
  dynamically shorten karna unnecessary hai kyunki mapping khud change
  nahi hoti — concern purely read throughput ka hai, jise caching pehle
  se hi address kar deta hai.
- **"Kisi ko ek phishing ya malware site pe URL shorten karne se kaise
  roko ge?"** Creation time pe synchronously ya near-synchronously ek
  URL-safety check add karo (jaise, Google Safe Browsing ya similar
  reputation API ke against), plus existing links ka asynchronous
  periodic re-scanning, kyunki ek destination site short link create
  hone ke baad bhi malicious ban sakti hai.
- **"Bina poori table scan kiye expired rows ke liye ek background job ke,
  link expiration ko efficiently kaise support karoge?"** Read time pe
  lazily `expires_at` check karo (redirect service ek expired link ko
  404/410 treat karti hai jis moment usko access kiya jaaye uski expiry
  ke baad, chahe cleanup job chala ho ya nahi) aur ek background job ko
  sirf eventual physical deletion/archival ke liye use karo, expiry
  behavior enforce karne ke liye nahi.
- **"Agar keyspace exhaustion ke kareeb pahunch jaao toh longer short
  codes pe kaise migrate karoge?"** Kyunki codes opaque strings hain,
  fixed-width integers nahi, tum bas 8-character codes generate karna
  shuru kar sakte ho jab 7-character pool low ho jaaye, jabki saare
  existing 7-character codes normally resolve karte rehte hain — koi
  existing data migration ki zaroorat nahi, kyunki lookup exact string
  match se hota hai length se independent.
- **"Agar ek bug ki wajah se do servers pool se overlapping code ranges
  claim kar lein toh kya hoga?"** Creation time pe atomic "insert if
  absent" write (Step 6.3) hi actual safety net hai — chahe range
  allocation mein bug ho bhi, final uniqueness guarantee database ke
  conditional-insert constraint se aati hai, is trust se nahi ki ranges
  kabhi overlap nahi karengi — defense in depth, ek single mechanism pe
  rely karne ki jagah.
- **"Primary datastore ko grow karte hue kaise shard karoge?"** `short_code`
  ke ek hash se shard karo (Step 5 mein pehle hi note kiya gaya) `user_id`
  ya `created_at` se nahi, kyunki redirect access pattern hamesha
  short_code se ek point lookup hota hai — usi pe hashing storage aur
  redirect read load dono ko shards ke across evenly distribute kar deta
  hai, jabki creation time se sharding poora current click traffic jis
  bhi shard mein recently-created (typically zyada actively clicked)
  links hon usi pe concentrate kar degi.

# What Is System Design

## Definition

System design ek practice hai jisme hum define karte hain **architecture** (components kaise split hote hain aur deploy hote hain), **components** (services, databases, caches, queues, load balancers), **data model** (information kaise structure hoti hai aur kahan store hoti hai), aur pieces ke beech ka **APIs/contracts** — yeh sab is liye taaki ek set of **functional requirements** (system ko kya karna hai) aur **non-functional requirements** (usse kitna achha karna hai) real-world constraints ke andar meet ho: limited budget, limited engineering headcount, deadlines, aur ek codebase jo launch ke baad bhi evolve karta rehna hai.

Yeh fundamentally ek **decision-making discipline** hai. Aap rarely hi koi naya algorithm invent kar rahe hote hain; aap known building blocks ke beech choose kar rahe hote hain (relational DB vs NoSQL, synchronous vs async, monolith vs microservices, cache-aside vs write-through) aur har choice ko diye gaye specific constraints ke against justify kar rahe hain. Do engineers ko agar same problem diya jaaye but different constraints (jaise, "10 users" vs "10 million users"), toh unhe different, dono hi correct designs produce karne chahiye.

## Yeh important kyun hai

Deliberate system design ke bina, systems predictable tareekon se degrade hote hain:

- **Ek single database load ke neeche melt ho jaata hai** kyunki kisi ne read replicas, caching, ya sharding ke liye plan nahi kiya — schema aur access patterns sirf correctness ke liye design kiye gaye the, us write/read volume ke liye nahi jo product actually dekhega.
- **Ek "quick fix" permanent bottleneck ban jaata hai**: jaise, ek slow third-party API ko synchronous call karna checkout flow ke request path mein directly baith jaata hai, toh jab woh API slow ho, aapka pura checkout uske saath hi down ho jaata hai — na koi queue, na timeout, na circuit breaker.
- **Outages cascade hote hain**: ek overloaded service har us service ko down kar deti hai jo usse synchronously call karti hai, kyunki kisi ne backpressure, jitter ke saath retries, ya bulkheading ke baare mein socha hi nahi.
- **Team month 3 ke baad fast move nahi kar paati**: agar design mein clear service boundaries ya API contracts nahi hain, toh har change ke liye paanch teams ko coordinate karna padta hai, kyunki kuch bhi decoupled nahi hai.

System design wahi cheez hai jo "demo mein kaam karta hai" aur "raat ke 2 baje traffic spike ke dauraan kaam karta hai, teen saal baad, un engineers ke through maintain hokar jinhone ise likha bhi nahi tha" — in dono ke beech khada hota hai.

## System Design vs DSA: ek alag tarah ka problem

Aapko already pata hai DSA (Data Structures & Algorithms) problems kaise solve karte hain: ek precise, unambiguous problem statement diya jaata hai, us mein optimal time/space complexity wala algorithm dhundna hota hai, aur generally **ek hi correct/optimal answer** hota hai jo test cases ke against verify kiya ja sakta hai.

System design in properties mein se lagbhag har ek ko invert kar deta hai:

| Dimension | DSA | System Design |
|---|---|---|
| Problem statement | Fully specified upfront | Ambiguous, incomplete — aapko questions poochh kar ise pin down karna hota hai |
| "Correct" answer | Usually ek optimal solution | Kayi valid designs; correctness = diye gaye constraints ke liye fit |
| Evaluation | Test cases ke against pass/fail | Trade-off reasoning par judge hota hai, ek single right answer par nahi |
| Time horizon | Ek baar solve karo | Months/years mein scale/requirements change hone ke saath evolve karna zaroori |
| Scope | Self-contained function/algorithm | Components, teams, failure modes, operational cost tak spread hota hai |
| Skills tested | Algorithmic reasoning | Architecture, communication, ambiguity ke under prioritization |
| Changing requirements | Problem ka part nahi | Problem ka core part — interviewer mid-discussion mein constraints add karta hai |

Kyunki requirements ambiguous aur evolving hote hain, system design mein ek heavy **organizational** dimension bhi hota hai jo DSA mein bilkul nahi hota: kaunsi service kaun own karta hai, do teams bina ek dusre ko block kiye API contract par kaise agree karti hain, baad mein kya cheap hai change karna vs kya cheez lock-in kar deti hai (ek chuna hua database engine swap karna mushkil hai jab millions rows already likhi ja chuki hon; ek internal API ki parameter list change karna aasan hai jab tak koi aur team us par depend na kare).

## Functional vs Non-Functional Requirements

**Functional requirements (FRs)** describe karte hain ki system *kya* karta hai — features, user-visible behavior. Yeh usually easily state ho jaate hain aur sab jaldi agree kar lete hain.

Examples:
- Users ek tweet post kar sakte hain (text + optional image).
- Ek user doosre user ko follow kar sakta hai aur unke posts apni feed mein dekh sakta hai.
- Ek rider trip request kar sakta hai aur nearby driver se match ho sakta hai.

**Non-functional requirements (NFRs)** describe karte hain ki system *kitna achha* perform karna chahiye — woh qualities aur constraints jo ek single feature ki tarah nahi dikhtin lekin har architectural decision ko shape karte hain. Yehi woh jagah hai jahan real design work hota hai, kyunki FRs akele toh ek single Rails app aur Postgres instance se satisfy ho jaate hain; NFRs hi hain jo aapko caching, replication, queues, sharding, etc. ki taraf force karte hain.

Examples:
- 99.9% availability (system reachable aur functioning honi chahiye us fraction of time).
- p99 read latency 200ms se kam (99% read requests ko 200ms se fast complete hona chahiye).
- Peak par 10,000 writes/second support karna.
- Durability: ek baar write acknowledge ho gaya, toh woh kabhi lose nahi hona chahiye, chahe node turant hi mar jaaye.
- Data regions ke across 5 seconds ke andar eventually consistent hona chahiye (ya: financial balances ke liye strongly consistent hona chahiye).

System design mein achha karne ka ek bahut bada part hai — interviews mein bhi aur real work mein bhi — design se pehle **NFRs ko explicitly surface karna**, kyunki interviewer (ya aapka PM) usually sirf FRs bataata hai aur expect karta hai ki scale, latency, aur consistency needs ke baare mein aap khud poochhein.

## Companies interviews mein yeh kyun test karti hain

Ek system design interview asal mein ek senior/staff engineer ke actual job ka proxy hota hai: ek vague ask diya jaaye ("URL shortener banao," "hume ek notification system chahiye"), toh kya aap

1. **clarifying questions poochh sakte ho** taaki ambiguity ko concrete requirements (functional aur non-functional) mein convert kiya ja sake,
2. **trade-offs bana aur justify kar sakte ho** zor se bolkar, taaki team follow aur challenge kar sake aapki reasoning,
3. **scale estimate kar sakte ho** taaki design bilkul over- ya under-engineered na ho,
4. **failure modes identify kar sakte ho** aur unke liye design kar sakte ho, sirf happy path assume karne ke bajaye,
5. **architecture clearly communicate kar sakte ho** itna ki koi doosra engineer aapke description se implement kar sake.

Iska koi bhi part chat app ke liye "the" design memorize karne ke baare mein nahi hai. Interviewers actively yeh dekhna chahte hain ki aap design ko adapt karo jab woh mid-interview mein koi constraint change karein ("ab assume karo 100x users hain lekin reads real-time honi chahiye") — woh adaptability hi actual signal hai, initial diagram se zyada.

## Core mindset: koi perfect design nahi hota, sirf diye gaye constraints ke liye right trade-offs hote hain

Har design decision ek property ko doosri ke liye trade karta hai: consistency ko availability ke liye, latency ko throughput ke liye, cost ko redundancy ke liye, simplicity ko flexibility ke liye. "Best" tabhi sense banata hai jab ek stated set of constraints ke relative dekha jaaye. Neeche same requirement diya hai jo constraints change hone par differently solve hui hai.

System design mein "best architecture" naam ki koi universal cheez nahi hoti. Tum jis cheez ko prioritize karte ho, uske according kuch doosri cheez sacrifice karni pad sakti hai.

**Example 1 — "user ki profile photo store aur serve karna"**
- *Small scale (hazaaron users, internal tool)*: image ko user ke same Postgres row mein BLOB ki tarah store karo. Simple, ek hi system operate karna, fully consistent, is scale par bilkul theek.
- *Large scale (sau-crore users)*: image ko object storage mein store karo (jaise, S3), sirf URL/key ko Postgres mein store karo, aur image ko CDN ke through serve karo. Reason: DB storage aur I/O expensive hain aur large binary blobs ke liye nahi bane hain; ek CDN bytes ko user ke close le aata hai aur origin ko poori tarah offload kar deta hai.

**Example 2 — "users ko unka notification count dikhana"**
- *Read-heavy, small scale*: har page load par `COUNT(*) WHERE read = false` directly notifications table ke against query karo. Simple, hamesha accurate, theek hai agar traffic kam ho.
- *Read-heavy, huge scale*: ek denormalized counter maintain karo (Redis mein, write par increment/decrement kiya jaaye) instead of har read par ek `COUNT` query karne ke, kyunki har page load par ek live aggregate query millions concurrent reads tak scale nahi karti. Trade-off: counter thoda sa out of sync ho sakta hai aur usse periodic reconciliation chahiye hoti hai — aapne perfect accuracy ko speed aur DB load reduction ke liye trade kiya hai.

**Example 3 — "e-commerce checkout ke liye order writes handle karna"**
- *Write-light (ek boutique store)*: request ke andar directly ek single relational database mein likho; synchronous, simple, strongly consistent, aur user ko success/failure turant dikh jaata hai.
- *Write-heavy (flash sale, huge spike)*: order request accept karo, use queue par push karo, turant "order received" return karo, aur workers ke saath asynchronously process/persist karo jo independently scale ho sakte hain aur failure par retry ho sakte hain. Trade-off: aap bursts absorb karne aur downstream slowness se survive karne ki ability gain karte ho, lekin us immediate strong guarantee ko give up karte ho ki order response dene tak fully process ho chuka hai — ab aapko "pending" state user ko communicate karni padegi.

Har example mein, "less scalable" option galat nahi hai — woh apne constraints ke liye correct answer hai, aur zyada complex option ko premature reach karna khud ek design mistake hai (bina real benefit ke unnecessary operational cost aur complexity).

## Aapke paas already intuition hai — yeh sirf usko vocabulary deta hai

Agar aapne kabhi ek database scale kiya hai (read replicas, indexes, connection pooling, sharding) ya load ki wajah se hui production incident debug ki hai, toh aap already real system design trade-offs bana chuke ho — bas aapne unhe alag naam se, us moment mein, bina kisi formal framework ke banaya tha. Yeh material aapko zero se koi naya way of thinking nahi sikha raha. Yeh aapke existing instincts ko de raha hai:

- **Vocabulary** — taaki "woh cheez jisme aap nearest server par route karte ho" ban jaaye "GSLB" ya "L7 load balancing," aur aap doosre engineers aur interviewers ke saath precisely communicate kar sako.
- **Ek repeatable framework** — requirements clarify karo → scale estimate karo → API/data model define karo → high-level architecture design karo → 1-2 hard parts par deep jao → trade-offs aur failure modes discuss karo — taaki aap har baar discussion ki structure ko scratch se improvise na karo.
- **Missing pieces** — patterns jo shayad aapko apne khud ke kaam mein abhi tak nahi chahiye the (jaise, consistent hashing, CDNs, scale par message queues) lekin jo system design contexts mein hamesha aate hain.

Global Server Load Balancing(GSLB):
GSLB decide karta hai ki duniya ke different locations mein available servers / data centers / CDN PoPs mein se user ki request ko kahan bhejna chahiye.

                  GSLB
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
      India      Singapore    USA
       PoP          PoP        PoP
     S1 S2 S3     S1 S2       S1 S2 S3

## Is folder ka roadmap

`01_Concepts` ka baaki hissa woh shared vocabulary aur mental models banata hai jo har system design discussion mein use hote hain:

- **02_scalability_and_estimation.md** — vertical vs horizontal scaling, latency vs throughput, availability aur "the nines," SLA/SLO/SLI, aur back-of-envelope capacity estimation kaise karein.
- **03_networking_and_apis.md** — DNS, TCP vs UDP, HTTP evolution, real-time communication options (WebSockets/SSE/polling), REST vs GraphQL vs gRPC, aur API gateways.
- **04_load_balancing.md** — load balancers kya karte hain, L4 vs L7, load balancing algorithms, health checks, aur session affinity.

Baad ke folders (`01_Concepts` se bahar) is foundation par build karke caching, database scaling, message queues, aur full worked system designs cover karte hain — yeh sab yahan introduce kiye gaye terms aur trade-off framing par lean karte hain.

## Quick Recall — Self-Test

**Q1: Requirements ki woh do categories kya hain jo aapko system design karne se pehle gather karni chahiye, aur unme kya difference hai?**
Functional requirements describe karte hain ki system *kya* karta hai (features/behaviors, jaise, "users tweet post kar sakte hain"). Non-functional requirements describe karte hain ki usse *kitna achha* karna chahiye (jaise, 99.9% availability, p99 latency 200ms se kam). NFRs usually hard architectural decisions drive karte hain.

**Q2: Ek diye gaye problem ke liye koi single "correct" system design kyun nahi hota?**
Kyunki right design constraints par depend karta hai — scale, read/write ratio, consistency needs, budget, team size — jo situation ke hisaab se vary karte hain. Ek design jo ek set of constraints ke liye optimal hai (jaise, low traffic, strong consistency chahiye) woh different constraints ke under galat choice ho sakta hai (jaise, massive scale, eventual consistency acceptable).

**Q3: Ek concrete tareeka batao jisse ek system bina deliberate design ke production mein fail hone lagta hai.**
Ek synchronous call kisi slow downstream dependency ko (jaise, ek third-party API) jo directly ek user-facing request path mein baithi ho — jab woh dependency slow ho jaaye, calling service bhi slow ya fail ho jaati hai, bina kisi timeout, queue, ya circuit breaker ke jo damage ko contain kare.

First establish a strict timeout so the downstream cannot hold resources indefinitely. If the operation doesn't need to complete synchronously, move it behind a queue and process it asynchronously. For synchronous calls that remain necessary, add a circuit breaker, bounded concurrency, and controlled retries with exponential backoff and jitter. Where possible provide a fallback or cached response. The key is to contain the failure so a slow third-party dependency doesn't consume all service's resources and cause a cascading failure.

**Q4: Companies sirf zyada DSA questions poochhne ke bajaye system design interviews kyun use karti hain?**
Kyunki ek senior engineer ka job largely ambiguous requirements handle karna, trade-offs banana aur communicate karna, scale estimate karna, aur failure modes anticipate karna hota hai — yeh skills DSA problems (jo fully specified hote hain ek right answer ke saath) bilkul test nahi karte.

**Q5: Ek requirement kehta hai "app fast feel hona chahiye." Us statement mein kya galat hai, aur interview mein aapko iske saath kya karna chahiye?**
Yeh measurable nahi hai — yeh ek vague NFR hai. Aapko clarifying questions poochh kar ise ek concrete, testable target mein convert karna chahiye, jaise, "read path ke liye p99 latency 200ms se kam," taaki design ko actually usse evaluate kiya ja sake.

**Q6: Ek example do jahan same functional requirement se do different, dono valid designs bante hain.**
"User ka notification count dikhana": small scale par, ek direct `COUNT(*)` query per page load theek hai; huge scale par, ek fast store mein (jaise, Redis) maintain kiya gaya denormalized counter database ko har read par aggregate queries se hammer karne se bachata hai, thodi si drift ke cost par jisse reconciliation chahiye hoti hai.

**Q7: Iska kya matlab hai ki system design mein ek "organizational" dimension hai jo DSA mein nahi hai?**
Real systems teams banate aur operate karte hain, isolation mein solve nahi hote. Service boundaries aur API contracts jaise decisions decide karte hain ki changes ship karne ke liye teams ko kitna coordinate karna padega, aur kuch choices (jaise, ek database engine) baad mein reverse karna expensive hota hai — isliye design mein yeh account karna zaroori hai ki kaun kya owns karta hai aur kya cheap vs costly hai change karne ke liye.

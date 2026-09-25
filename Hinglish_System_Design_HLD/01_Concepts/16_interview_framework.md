# The Interview Framework

Ye file `01_Concepts` ka capstone hai — ye pichli 15 files jaisi koi nayi technical vocabulary introduce nahi karti. Iske bajaye, ye tumhe poore system design interview chalane ke liye ek repeatable *process* deti hai, jisme ab tak jo tumne seekha hai wo sab (scalability and estimation, networking, load balancing, caching, databases, CAP/consistency, distributed systems, queues, microservices, storage, search, security, observability) sahi moment pe slot ho jaata hai. `02_Interview_Questions/` ki har file is exact framework ka ek specific system pe apply kiya gaya worked example hai — isliye is file ko internalize karna hi ek pile of separate concepts ko ek single, confident approach mein badal deta hai jo tum *kisi bhi* prompt pe chala sakte ho, including wo jo tumne kabhi dekhe hi nahi.

## The Framework

Ek realistic system design interview 45-60 minutes ka hota hai. Sabse common failure mode us clock ko mismanage karna hai — 20 minutes boxes draw karne mein spend karna aur deep dive ke liye koi time na bachna, jo actually candidates ko differentiate karta hai. Neeche wale time budgets ko defaults maano jinki taraf consciously steer karna hai, ek rigid script nahi.

### 1. Requirements clarify karo (~5 min)

Kuch bhi design karne se pehle, ambiguous prompt ("design Twitter") ko ek concrete, scoped problem mein convert karo. Ye poocho:

- **Functional requirements (FRs)** — system ko actually kya karna chahiye? "Design Twitter" jaisa prompt posting + following + feed ka matlab ho sakta hai, ya search, trending topics, DMs, ads bhi ho sakte hain. Explicitly scope narrow karo: "Main posting, following, aur home timeline pe focus karunga — kya mujhe search ya DMs include karne chahiye, ya unhe out of scope treat karun?"
- **Non-functional requirements (NFRs)** — ye kitna achha perform karna chahiye? Scale (kitne users, peak pe kitne requests/sec), latency targets, consistency needs (kya feed kuch seconds stale ho sakta hai, ya immediate hona chahiye), availability expectations. Yahaan ki full vocabulary (SLA/SLO/SLI, "the nines") ke liye `02_scalability_and_estimation.md` dekho.

Inme se kuch bhi silently assume mat karo — apni assumptions loudly state karo aur ek nod le lo, ya directly poocho. Ye step exist hi isliye karta hai taaki tum agle 40 minutes galat system design karne mein spend na karo.

### 2. Scale estimate karo (~5 min)

Back-of-envelope math karo rough numbers pin down karne ke liye: daily active users, peak pe requests/sec (aksar ~2-5x daily average estimate kiya jaata hai non-uniform traffic account karne ke liye), read/write ratio, storage growth per day/year, average payload size. Ye directly baad ke real design decisions drive karta hai — e.g., "200K writes/sec" ek single unsharded relational database ko outright rule out kar deta hai, jabki "50 writes/sec" ka matlab hai probably abhi tumhe shard karne ki zaroorat hi nahi. Full technique aur worked examples `02_scalability_and_estimation.md` mein hain — ye step hai jahaan tum us technique ko is interview ne diye gaye specific numbers pe apply karte ho.

Numbers ko rough aur round rakho (powers of 10, false precision nahi) — goal order-of-magnitude judgment hai ("isse shard karna padega," "ye comfortably ek Redis instance pe fit ho jaata hai"), ek spreadsheet nahi.

### 3. High-level design (~15 min)

Core components aur unke beech data flow ka sketch banao — client, API/load balancer, application services, databases, caches, queues — ek aise level pe jo comfortably ek diagram mein fit ho jaaye. Pehla pass deliberately simple rakho: ek chhoti number of boxes jo step 1 mein scope kiye FRs ke main read aur write paths cover karte hon. Jo bhi component tumhe pata hai use add karne ki urge resist karo (ek cache, ek queue, ek CDN, ek search index) jab tak requirements actually har ek ko justify na karein — ek unjustified component interviewer ke liye ek red flag hai, koi bonus point nahi.

```text
  client ──► load balancer ──► app servers ──► primary DB
                                    │
                                    ├──► cache (hot reads)
                                    └──► queue ──► async workers
```

Har box draw karte waqt uske liye *reasoning* state karo, sirf box nahi — "writes yahaan ek queue se guzarte hain kyunki is system ko bursty traffic absorb karna hai bina user-facing request ko block kiye," na ki bina kisi justification ke bas "queue."

### 4. API design (~5 min, aksar high-level design mein fold ho jaata hai)

Key endpoints/contracts define karo jo client-facing (ya service-facing) API expose karti hai — method, path, key parameters, aur response shape, ek level of detail pe jo contract pin down kare bina har field belabor kiye. E.g., ek URL shortener ke liye: `POST /urls {long_url} -> {short_url}`, `GET /:short_code -> 302 redirect to long_url`. Ye tumhe force karta hai confirm karne ke liye ki tumhe actually pata hai system ko kya expose karna hai, storage design karne se pehle jo uske neeche hoga, aur ye interviewer ke liye scope questions probe karne ki ek natural jagah hai.

### 5. Data model (~5-10 min, aksar high-level design mein fold ho jaata hai)

Storage types choose karo (relational vs NoSQL, aur agar relevant ho to NoSQL ka kaunsa flavor — `06_databases_fundamentals.md` dekho) aur core schema/entities aur unke relationships ka sketch banao, directly step 4 ke API se implied access patterns se driven. State karo *kyun* har storage choice fit baithti hai — e.g., "user profile data relational hai aur joins/transactions chahiye, isliye Postgres; feed khud ek single key (user ID) se bahut high read volume pe access hoti hai bina joins ki zaroorat ke, isliye ek key-value/wide-column store waha better fit hai." Ek storage engine ko trendy hone ki wajah se mat pick karo — ise is liye pick karo kyunki access pattern use demand karta hai.

### 6. Deep dive (~15-20 min — sabse important part)

Is specific system ke 1-2 sabse hard parts pe genuinely deep jao — sab kuch nahi, aur generically "isse aur scale karo" nahi. Yahaan strong candidates weak candidates se separate hote hain, kyunki yahaan tum demonstrate karte ho ki tum actually ek hard problem ke through reason kar sakte ho, sirf component names recite karne ke bajaye. Deep-dive target identify karne ke liye ye poocho: is system ka wo ek part kaunsa hai jo genuinely hard, non-obvious hai, ya jahaan ek naive approach clearly break ho jaata hai?

Har system ke liye deep dive kaisa dikhta hai iske examples:
- **URL shortener**: unique short codes ko scale pe collisions ke bina aur ek single bottlenecked counter ke bina kaise generate karein? (distributed ID generator ka base62 encoding, vs ek hash + collision check, vs pre-generated key ranges jo app servers ko de diye jaayein.)
- **News feed**: fan-out-on-write (post banate hi har follower ka feed precompute karo — fast reads, celebrities ke liye millions of followers ke saath expensive/wasteful) vs fan-out-on-read (read time pe followed users ke recent posts merge karke feed compute karo — cheap writes, expensive reads) vs ek hybrid.
- **Rate limiter**: kaunsa algorithm (`14_security_basics.md` dekho), aur bahut saari distributed rate-limiter instances ke across counters ko consistent aur fast kaise rakhein bina counter store khud bottleneck bane.
- **Chat application**: real time mein messages kaise deliver karein (WebSockets ke liye `03_networking_and_apis.md` dekho), ordering aur at-least-once delivery guarantee kaise karein, aur ek user jo sender se alag server se connected hai use kaise handle karein.

Interviewer ke tumhe yahaan steer karne ka dhyan rakho — agar wo poochein "kya hoga jab X fail ho jaaye" ya "is ek part pe 100x load kaise handle karoge," ye ek direct signal hai ki wo deep dive kahaan chahte hain. Follow karo.

### 7. Bottlenecks aur trade-offs identify karo (~5 min)

Explicitly state karo ki load badhne pe kya sabse pehle break hoga, aur use kaise address karoge — e.g., "primary database N writes/sec ke baad write bottleneck ban jaata hai; main ise user ID se sharding karke address karunga" (`07_database_scaling.md` dekho), ya "load balancer pe ek single point of failure; main ise active-passive ya active-active pair mein chalaunga." Apne design ne already kiye hue trade-offs bhi revisit aur naam lo (consistency vs availability, latency vs throughput, cost vs redundancy) implicit chhodne ke bajaye — vocabulary ke liye `08_cap_theorem_and_consistency.md` dekho.

### 8. Wrap up (~5 min)

Design ko kuch sentences mein summarize karo, aur proactively mention karo ki agar zyada time hota to tum kya karte — cheezein jo tumne knowingly defer kiye (e.g., "main full-text post search ke liye ek dedicated search index add karta, aur notification path ke liye exactly-once delivery guarantees mein aur deep jaana chahta"). Ye design ke current gaps ke baare mein self-awareness dikhata hai, ise finished aur perfect present karne ke bajaye.

```text
 5 min      5 min        15 min          20 min           5 min    5 min
┌───────┬───────────┬──────────────┬────────────────┬───────────┬───────┐
│Clarify│ Estimate  │ High-level   │   Deep dive     │Bottlenecks│ Wrap  │
│  reqs │  scale    │ design + API │  (1-2 hard      │ & trade-  │  up   │
│       │           │ + data model │   parts)        │   offs    │       │
└───────┴───────────┴──────────────┴────────────────┴───────────┴───────┘
                                          ▲
                              strong vs weak candidates
                              separate here, most of all
```

## Ek Compressed Worked Example

Framework ko concrete banane ke liye, yahaan hai ki "design a URL shortener" ke liye 8 steps practice mein kaise sound karenge, har step ke liye kuch lines mein compressed (is exact system ki full version `02_Interview_Questions/03_url_shortener.md` hai):

1. **Clarify**: "Kya short codes user-chosen (custom aliases) honge ya system-generated? Kya links expire hote hain? Kya click analytics scope mein hai?" → agree hua: system-generated codes, optional expiry, basic click count only.
2. **Estimate**: 100M new URLs/month ≈ ~40 writes/sec average; reads (redirects) typically ~100x writes ≈ ~4K reads/sec; har mapping tiny hai (kuch sau bytes), isliye storage count se dominate hota hai, size se nahi.
3. **High-level design**: client → load balancer → app service → mapping ke liye DB, hot redirects ke liye DB ke saamne cache (redirects extremely read-heavy aur highly cacheable hote hain).
4. **API**: `POST /urls {long_url, expiry?} -> {short_url}`, `GET /:code -> 302 to long_url`.
5. **Data model**: ek simple key-value mapping (`short_code -> long_url, expiry, created_at`) — koi relational joins ki zaroorat nahi, isliye ek key-value store ya ek simple relational table dono kaam karte hain; expected scale ke basis pe pick karo.
6. **Deep dive**: is write rate pe collisions ke bina short codes kaise generate karein bina ek single bottlenecked counter ke — e.g., ek distributed unique ID ko base62-encode karna (`02_Interview_Questions/01_distributed_id_generator.md` dekho) ek single DB pe naive auto-increment column ke bajaye.
7. **Bottlenecks**: cache almost saara redirect traffic absorb kar leta hai, isliye DB khud rarely reads ke liye bottleneck hota hai; write path itna low-volume hai ki ek single primary with replicas likely sufficient hai — explicitly ye bolo, reflexively ek system ko shard karne ke bajaye jise abhi zaroorat hi nahi.
8. **Wrap-up**: design ko do sentences mein summarize karo; mention karo ki zyada time hota to analytics aggregation aur custom alias collision handling cover karte.

Notice karo ki deep dive (step 6) hi wo ek jagah hai jahaan real problem-solving hota hai — usse pehle sab kuch shared context establish kar raha hai, aur uske baad sab kuch jo bana wo stress-test kar raha hai.

## Common Mistakes

- **High-level design establish karne se pehle low-level details mein diving.** Interview ke pehle 10 minutes exact schema field types ya ek specific caching library pe spend karna interviewer ko poori architecture pata chalne se pehle — wo aisi reasoning follow ya challenge nahi kar sakte jo unhone dekhi hi nahi, aur tum ek foundation pe fine detail banane ka risk lete ho jise baad mein rip up karna padega.
- **Clarifying questions na poochna aur silently requirements assume karna.** Sabse damaging early mistake — tum poori interview galat scale, galat consistency needs, ya galat feature set ke liye system design karne mein spend kar sakte ho, aur late discover hone ke baad recover karne ka time na bache.
- **Infinite scale ke liye over-engineer karna jab interviewer ne ek modest system describe kiya ho.** Sharding, multi-region replication, aur ek message queue ke liye reach karna ek aise system ke liye jise interviewer ne "kuch thousand users" scope kiya ho, signal deta hai ki tum complexity ko actual requirements se calibrate nahi kar sakte — jo khud hi core skill hai jise test kiya ja raha hai (`01_what_is_system_design.md` ka core mindset section dekho).
- **Under-engineer karna aur scale ko completely ignore karna.** Opposite failure — design aise karna jaise ek single server aur ek single database step 2 mein establish kiye gaye chahe jo bhi numbers ho unhe handle kar lenge, ye acknowledge kiye bina ki wo kahaan break hoga. Dono directions same underlying gap signal karti hain: design ko stated constraints se connect na karna.
- **Trade-offs kabhi loudly state na karna — bas silently ek option pick karna.** Eventual consistency, ya ek NoSQL store, ya async processing choose karna, bina *kyun* bataye, interviewer se tumhari reasoning dekhne ka chance chheen leta hai (jo evaluate hone wali most cheez hai) aur aisa lagta hai jaise tumhe pata hi nahi tha ki koi choice banani thi.
- **Sochte hue lambe stretches ke liye quiet ho jaana, narrate karne ke bajaye.** Ek interview ek silent exam nahi hai — lambi silences interviewer ko tumhari reasoning follow karne ya tumhe jaldi course-correct karne ke able nahi chhodti, aur ye uncertainty jaisa lagta hai chahe tum internally actually achha progress kar rahe ho.
- **Time manage na karna, aur deep dive se pehle time khatam kar dena.** Kyunki deep dive interview ka highest-signal part hai, initial architecture draw karne mein bahut zyada time spend karna (ya ek diagram ko over-polish karna) uske expense pe sabse costly mistakes mein se ek hai jo tum kar sakte ho — actively clock dekho aur khud ko aage move karo.
- **Ise ek whiteboard art exercise ki tarah treat karna, ek technical conversation ke bajaye.** Substantive reasoning se zyada ek tidy diagram pe focus karna, ya interviewer ke questions/pushback ko real signal ki tarah engage na karna, ye miss kar deta hai ki interview evaluate kar raha hai ki tum ambiguity ke neeche kaise sochte aur communicate karte ho — tumhari box-and-arrow drawing skill nahi.

## Design Karte Waqt Communicate Kaise Karein

- **Continuously loudly socho.** Apni reasoning state karo jaise-jaise aage badho, including wo options jo tum weigh kar rahe ho aur kyun ek pick kar rahe ho — interviewer reasoning process grade kar raha hai, sirf final diagram nahi, aur wo grade nahi kar sakte jo wo sun hi nahi sakte.
- **Interviewer ko ek collaborator ki tarah treat karo, ek examiner ki tarah nahi jisse defend karna hai.** Wo ek stakeholder hain jinke saath tum shared understanding aur alignment ki taraf drive kar rahe ho — koi jo tumhare saath ye build kar raha hai, jinke questions tumhe ek better design pe land karne mein help karne ke liye hain, "gotchas" survive karne ke liye nahi.
- **Periodically check in karo.** Natural boundaries pe explicitly pause karo aur pooch lo jaise "kya ye direction sense banata hai, ya aap chahenge main X pe deeper jaun?" — ye tumhe correctly calibrated rakhta hai limited time kahaan spend karna hai, guess karne aur potentially 15 minutes galat cheez pe deep jaane ke bajaye.
- **Choices banate waqt explicitly trade-offs naam lo.** E.g., "Main yahaan eventual consistency choose kar raha hun kyunki is system ko har reader ke absolute latest write dekhne se zyada availability aur low latency prioritize karni chahiye" — trade-off ko us moment loudly bolo jab tum choice banate ho, sirf baad mein poochne pe nahi. Ye ek single habit poori interview mein sabse highest-leverage cheezon mein se ek hai jo tum kar sakte ho, kyunki ye directly wo trade-off reasoning demonstrate karta hai jise test karne ke liye system design interviews exist karte hain.

## Ye `02_Interview_Questions` Folder Se Kaise Map Hota Hai

`02_Interview_Questions/` ki har file exact yahi step structure follow karti hai: clarify → estimate → high-level design → API → data model → deep dive → bottlenecks → follow-ups. Ye coincidence nahi hai — ye is file ka same framework hai, ek specific system pe end-to-end apply kiya gaya (ek URL shortener, ek rate limiter, ek news feed, ek chat app, aur so on).

Iska matlab hai ki un files ke through kaam karna sirf "ye specific systems kaise banaye jaate hain seekhna" nahi hai — ye directly is framework ki repeated practice hai, varied problems ke against, bilkul waise hi jaise `dsa.rb` mein problems solve karna ek small set of techniques (two pointers, sliding window, BFS/DFS, DP) ko bahut saari different problems ke across repeatedly apply karke algorithmic problem types ke liye pattern recognition build karta hai. Yahaan, "techniques" 8 framework steps aur `01_Concepts/01` se `15` tak ki vocabulary hain, aur "problems" `02_Interview_Questions/` ke systems hain.

Practically: un files ko sirf passively mat padho. Ek given file ka design padhne se pehle, khud us system ke prompt pe framework chalane ki koshish karo (clarify, estimate, ek high-level design sketch karo, ek deep-dive target pick karo) — phir worked version se compare karo. Tumhare attempt aur worked design ke beech ka gap exactly wahaan hai jahaan tumhari practice focus karni chahiye.

## Quick Recall — Self-Test

**Q1: Pehle 5 minutes mein candidates ki sabse badi interview mistake kya hai?**
Clarifying questions na poochna aur iske bajaye silently requirements assume karna — ye galat scale ya galat feature scope ke liye galat system design karne mein result ho sakta hai, aur mismatch surface hone ke baad recover karne ka time na bache.

**Q2: Deep-dive step 45-60 minute interview ka sabse important part kyun hai, aur uske liye ek realistic time budget kya hai?**
Yahaan strong aur weak candidates separate hote hain, kyunki isme component names recite karne ke bajaye ek hard, specific problem ke through genuine reasoning chahiye hoti hai — ek realistic budget roughly 15-20 minutes hai, interview ka sabse bada single block.

**Q3: Is context mein over-engineering aur under-engineering mein kya difference hai, aur dono mistakes kyun hain?**
Over-engineering heavy-scale patterns (sharding, multi-region, queues) ek aise system pe apply karta hai jise interviewer ne small scope kiya ho; under-engineering stated scale ko completely ignore karta hai aur design aise karta hai jaise ek single server sufficient ho chahe estimation step mein establish kiye gaye numbers kuch bhi hon. Dono same failure signal karte hain: design ko actual stated constraints se calibrate na karna.

**Q4: Trade-offs ko loudly state kyun karna chahiye, silently ek option pick karne ke bajaye?**
Interview tumhari reasoning process evaluate kar raha hai, sirf tumhare final architecture ko nahi — ek silently banaya gaya choice (e.g., eventual consistency pick karna) interviewer ko koi visibility nahi deta ki tumhe pata bhi tha ki koi choice hai, jabki ise explicitly naam lena wo trade-off reasoning demonstrate karta hai jise test karne ke liye interview exist karta hai.

**Q5: Deep-dive step mein kya focus karna hai ye kaise decide karein?**
System ka wo part identify karo jo genuinely hard ya non-obvious hai, jahaan ek naive approach clearly break ho jaata hai (e.g., scale pe unique ID generation, feed fan-out strategy), aur interviewer se koi direct signal follow karo (ek specific "X fail ho jaaye to kya hoga" ya "yahaan 100x load handle karo" question) jahaan wo chahte hain tum deep jao.

**Q6: Design ke dauraan natural checkpoints pe kya karna chahiye, aur kyun?**
Interviewer ke saath periodically check in karo — e.g., "kya ye direction sense banata hai, ya mujhe X pe deeper jaana chahiye?" — kyunki ye tumhe calibrated rakhta hai ki limited interview time actually kahaan spend hona chahiye, guess karne aur galat part pe ek lambe detour ka risk lene ke bajaye.

**Q7: Ye framework `02_Interview_Questions/` ki files se kaise related hai?**
Waha ki har file exact same 8-step structure follow karti hai (clarify, estimate, high-level design, API, data model, deep dive, bottlenecks, follow-ups) ek specific system pe apply kiya gaya, isliye unke through kaam karna is framework ki direct, repeated practice hai — analogous to how `dsa.rb` mein problems solve karna ek small set of core techniques ke repeated application se pattern recognition build karta hai.

**Q8: Interviewer ko ek collaborator ki tarah kyun treat karein, ek examiner ki tarah nahi?**
Kyunki interview ek technical conversation ki tarah structured hai, ek silent exam nahi — interviewer ke questions aur pushback tumhe ek better design ki taraf steer karne ke liye hain aur genuine signal hain jo incorporate karna chahiye, obstacles nahi jinse defend karna hai; unhe ek collaborator ki tarah engage karna tumhe talking aur narrating rakhta hai bhi, silence mistake avoid karte hue.

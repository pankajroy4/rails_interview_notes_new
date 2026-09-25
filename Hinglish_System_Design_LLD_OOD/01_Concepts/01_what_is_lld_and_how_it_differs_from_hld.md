# What Is LLD/OOD, and How It Differs from HLD

## Definition

**Low-Level Design (LLD)**, jise **Object-Oriented Design (OOD)** bhi kehte
hain, ek single application ya process banane wale classes, interfaces,
methods, aur relationships ko design karne ki practice hai, taaki resulting
code correct, readable, aur bina rewrite kiye extend karna easy ho. Design
ka unit **class** hai (aur runtime pe woh jo object produce karta hai). LLD
jo core question answer karta hai woh hai: *"Given this problem, kaunse
objects exist karte hain, har ek ko kya pata hai, har ek kya karta hai, aur
woh ek dusre ke saath kaise collaborate karte hain?"*

**High-Level Design (HLD)**, jo is repo ke sibling `System_Design/` folder
ka subject hai, ek system ko **many machines/services** ke across kaise
distribute kiya jaaye taaki woh scale, availability, aur failure handle kar
sake, iski practice hai. Design ka unit **service** hai (ya component:
database, cache, queue, load balancer). HLD jo core question answer karta
hai woh hai: *"Given this load and these failure modes, hum work ko machines
ke across kaise split karein, aur jab ek machine die ho jaaye tab kya
karein?"*

Dono hi "design" hain is sense mein ki "code karne se pehle socho," lekin
dono bilkul different altitude pe operate karte hain. LLD ek process ke
andar code ke shape ke baare mein hai. HLD ek network ke across system ke
shape ke baare mein hai. HLD diagram mein ek single service — jaise, "Booking
Service" — khud aisi cheez hai jispe aap internally LLD apply karoge: Booking
Service ke andar kaunse classes hain, `Booking`, `Slot`, aur `Payment` objects
kaise relate karte hain? Dono disciplines compose hote hain; woh compete
nahi karte.

## Why it matters

Bina is clear mental model ke ki koi question kis discipline se belong
karta hai, do failure modes constantly interviews mein (aur real design docs
mein bhi) dikhte hain:

1. **Ek LLD question ko HLD answer mil jaata hai.** "Design a parking lot
   using OOP" poochne pe, jo candidate default systems thinking pe jaata hai,
   woh baat karna shuru kar deta hai "hum spot availability Redis mein
   fast reads ke liye daalenge, database ko region ke hisaab se shard
   karenge, aur API ke saamne ek load balancer laga denge." Real production
   system mein isme se kuch bhi galat nahi hai, lekin yeh actual ask ko
   completely dodge kar deta hai: classes, inheritance, polymorphism, ek van
   3 bike spots kaise consume karta hai. Interviewer object modeling dekhna
   chahta tha aur usko "DB" aur "Cache" labeled boxes se bhara whiteboard
   mil gaya.

2. **Ek HLD question ko LLD answer mil jaata hai.** "Design a URL shortener
   that handles 10 million requests a day" poochne pe, jo candidate default
   class modeling pe jaata hai, woh ek `UrlShortener` class likhna shuru kar
   deta hai `encode(long_url)` method ke saath aur storage ke liye ek
   `Hash`, aur 20 minute base-62 encoding algorithm perfect karne mein
   spend kar deta hai. Meanwhile interviewer read/write ratio, caching
   layers, database choice aur indexing strategy, aur horizontal scaling ke
   baare mein sunna chahta tha — inme se kuch bhi nahi aaya kyunki candidate
   ek single class ke method body mein heads-down tha.

Dono hi "wrong question ko well answer karna" hain. Interviewer yeh grade
nahi kar raha ki aapka code aapke head mein compile hota hai ya nahi — woh
grade kar raha hai ki aapne correctly identify kiya ki yeh kis type ka
problem hai aur usme right toolkit laaya ya nahi. Pehle 60 seconds mein yeh
triage sahi karna, wrong kind ke answer pe kisi bhi amount ke polish se zyada
worth hai.

Yahi confusion real production work mein bhi real time cost karta hai: ek
team jo ek class-modeling problem ("humara `Order` object ek 1500-line god
class ban gaya hai") ko infrastructure changes (usko microservices mein
split karke) se solve karne ki koshish karti hai, instead of ek LLD
refactor (collaborator classes extract karke, Single Responsibility apply
karke), unhe ek distributed version milta hai usi tangled object graph ka,
ab beech mein network calls ke saath.

## LLD vs HLD: Comparison Table

| Dimension | LLD / OOD | HLD |
|---|---|---|
| Unit of design | Classes, objects, interfaces | Services, components, machines |
| Primary concern | Code ki correctness, readability, extensibility | Machines ke across scalability, availability, fault tolerance |
| Core skill tested | OOP modeling, design patterns, SOLID | Distributed systems trade-offs (CAP, sharding, caching, queues) |
| Typical question framing | "Design the classes for X. Now extend it to support Y." | "Design X to handle N million users/requests." |
| Artifact produced | Class diagram, method signatures, working code | Architecture diagram (boxes: services, DBs, caches, queues) |
| Failure looks like | God classes, `case type` chains, fragile inheritance | Single points of failure, unbounded growth, partition pe data loss |
| Where it runs | Ek process/application ke andar | Processes ke ek network ke across |
| Example deep dive in this repo | `LLD_OOD/02_Interview_Questions/01_parking_lot.md` | `System_Design/01_Concepts/16_interview_framework.md` |

## The diagnostic skill: recognizing which kind of question you're being asked

Yeh is file ki sabse directly useful cheez hai. Interviewers rarely bol ke
kehte hain "this is an LLD question" — aapko phrasing se infer karna padta
hai, aur kabhi kabhi mid-interview pivot se (isper neeche zyada baat hogi).
Signal ko kaise padhein, yeh raha:

**Signals that point to LLD:**
- Prompt ek bounded, single-application domain naam leta hai: ek parking
  lot, ek chess game, ek elevator system, ek library management system, ek
  tic-tac-toe game, ek vending machine, ek movie ticket booking *flow*
  (poore platform ka nahi).
- Prompt "design the classes for," "model," "design the system using OOP,"
  bolta hai, ya aapko ek naya variant "extend it to support" karne ko kehta
  hai.
- Request volume, users ki number, latency budgets, ya "at scale" ka koi
  mention nahi hai.
- Interesting complexity **entities ke beech rules aur relationships**
  mein hai (ek van 3 bike spots leta hai; ek bishop diagonally move karta
  hai; ek elevator apni travel direction mein nearest request pick karta
  hai), na ki **data volume ya network topology** mein.

**Signals that point to HLD:**
- Prompt ek platform ya product ka naam leta hai jo bahut saare log use
  karte hain: "design Twitter," "design WhatsApp," "design Uber," "design a
  URL shortener," "design Netflix."
- Prompt aapko ek number deta hai: "handles 10 million requests/day," "100M
  daily active users," "must respond within 200ms at p99."
- Interesting complexity **data volume, availability, aur distribution**
  mein hai (yeh table shard kaise karein, agar yeh region down ho jaaye to
  kya hoga, yeh hot read kaise cache karein).

**Worked examples, classified explicitly:**

| Prompt | Classification | Why |
|---|---|---|
| "Design a parking lot" | LLD | Single-facility domain, koi user-count/scale language nahi, complexity vehicle/spot rules mein hai. |
| "Design a URL shortener that handles 10M requests/day" | HLD | Explicit scale number; interesting problem storage, caching, aur volume pe encoding uniqueness hai. |
| "Design a chess game" | LLD | Bounded rules engine, ek time pe ek game, complexity pieces/moves/board state modeling mein hai. |
| "Design WhatsApp" | HLD (usually) | Named platform, millions of concurrent users imply karta hai, message delivery guarantees, presence — ek systems problem. |
| "Design the message class hierarchy for a chat app" | LLD | WhatsApp jaisa hi domain, lekin explicitly "class hierarchy" tak scoped — koi scale language nahi, pure object modeling. |
| "Design a vending machine" | LLD | Single machine, state-machine jaisa behavior (idle, has-money, dispensing), classic OOD interview staple. |
| "Design an elevator system for a 40-floor building" | LLD | Ek building tak bounded; hard part scheduling algorithm aur elevator/request object modeling hai, distributed scale nahi. |
| "Design a ride-sharing service like Uber" | HLD | Platform-scale, millions of drivers/riders ke across geospatial matching involve karta hai — ek distributed systems problem. |
| "Design a rate limiter" | Default se ambiguous — often HLD (agar "for our API gateway handling X requests/sec" jaise frame hua ho) lekin LLD bhi ho sakta hai ("implement a `RateLimiter` class using the token bucket algorithm") | Scale language ya ek specific data-structure/algorithm ask check karein. |

Pattern yeh hai: **named platforms jo bahut saare concurrent external users
serve karte hain, woh HLD hote hain; bounded single-instance domains, ya ek
prompt jo explicitly "classes"/"model"/"hierarchy" tak narrow karta hai, woh
LLD hote hain.** Jab genuinely ambiguous ho (rate limiter case), interviewer
se directly poochna completely fair hai — aur ek strong signal bhi: "Should
I focus on the class design and algorithm here, or do you want me to also
cover how this scales across multiple servers?" Yeh question akela hi
demonstrate karta hai ki aapko pata hai yeh distinction exist karta hai, jo
half hai us cheez ka jo evaluate ho raha hai.

## The blended question: recognizing a mid-interview pivot

Kuch interviews deliberately dono ko blend karte hain. Ek common shape:
"Design a movie ticket booking system" ek HLD conversation ki tarah shuru
hota hai (services, database choice, concurrent seat-booking requests
handle karna), aur 15-20 minutes ke baad interviewer kehta hai "okay, ab
seat-selection aur booking logic mein zoom karte hain — mujhe core classes
dikhao ki aap kaise prevent karoge ki do log same seat book kar dein." Yeh
mid-interview HLD se LLD mein ek pivot hai, aur yeh deliberate hai:
interviewer yeh dekhna chahta hai ki aap dono altitude pe operate kar sakte
ho ki nahi, aur — critically — kya aap **pivot notice karte ho** aur mode
switch karte ho, instead of database replication ke baare mein baat karte
rehna jab aapko `Seat`/`Booking`/`Show` class diagram sketch karna chahiye
ek explicit locking ya state-transition mechanism ke saath (jaise, ek `Seat`
`available` se `locked` phir `booked` mein move karta hai, aur sirf ek
thread/request hi woh transition jeet sakta hai — yahin aap `Seat#status`
pe ek atomic compare-and-swap laa sakte ho, wahi race-condition concern
echo karte hue jo parking lot example concurrent `park` calls ke liye
raise karta hai).

Pivot ho rahe hone ka tell: interviewer specific business rules, edge
cases, ya "show me the code for X" poochna shuru kar deta hai, instead of
"how would this scale" ya "what happens if this server goes down." Jab aap
yeh shift sunein, use out loud kahiye — "got it, let's move from the
architecture level into the actual class design for this piece" — aur jo
aap draw kar rahe hain use change kariye. Pivot ko naam dena khud us signal
ka part hai jo aap bhej rahe hain; silently wrong mode mein continue karna
woh mistake hai jise prevent karne ke liye yeh poori file exist karti hai.

**A worked mini-dialogue, to make the pivot concrete:**

```
Interviewer: "Design a movie ticket booking system."
Candidate:   "Let's start with the high-level shape: a Booking Service
             behind an API, a Postgres database for shows/seats/bookings,
             and probably a cache in front of show listings since those
             are read-heavy. For booking itself, the tricky part is two
             users hitting 'book' on the same seat at once — I'd handle
             that with a short-lived lock or a DB-level unique constraint
             on (show_id, seat_id) for confirmed bookings."
Interviewer: "Okay — walk me through the actual classes and how you'd
             implement that seat-locking logic."
Candidate:   "Got it, switching from architecture to the class design for
             this piece specifically." [draws Show / Seat / Booking, and
             a Seat#status state machine: available -> locked -> booked,
             with the transition guarded by a single atomic update]
```

Notice kariye candidate ne pivot pe kya kiya: ek short sentence mein out
loud bola, phir turant change kar diya jo woh produce kar raha tha (service
boxes se ek class diagram aur ek state machine mein) instead of caching ya
database choice pe elaborate karte rehna. Yeh explicit acknowledgment plus
output mein visible change hi poora skill hai — ek interviewer jo isko watch
kar raha hai, use confirmation milta hai ki aapne shift track kiya, sirf
luck nahi ki aap koincidentally kuch relevant baat karte rahe.

## What a Strong Opening Sounds Like, by Mode

Pehle 60 seconds baaki interview ka frame set karte hain, aur aap kya bolte
hain woh meaningfully differ karta hai depending on kis type ka question
aapne identify kiya hai:

**Opening an LLD question** (e.g., "design a parking lot"):
- Scope confirm kariye: "This is about the class design for a single
  parking facility, not multiple locations or concurrent access at scale —
  should I assume single-process, or do you want me to note concurrency
  concerns too?"
- Turant requirements aur nouns pe move kariye: "Let me list the entities
  I'm seeing: Vehicle, ParkingSpot, ParkingLot, and probably a Ticket to
  track an active parking session."
- Storage choice, caching, ya load balancing se **mat** kholiye — un
  answers ka is altitude pe abhi wajood hi nahi hai, aur unke liye reach
  karna signal karta hai ki aap habit se HLD pattern-match kar rahe hain.

**Opening an HLD question** (e.g., "design a URL shortener for 10M
requests/day"):
- Pehle scale aur constraints confirm kariye: "What's the read/write
  ratio, and do shortened URLs need to be globally unique immediately, or
  is eventual consistency acceptable?"
- Kisi bhi class talk se pehle back-of-envelope estimation pe move kariye:
  requests/sec, storage growth per year, cache hit rate assumptions.
- Ek `UrlShortener` class ko `encode` method ke saath sketch karke mat
  khuliye — yeh us system-level constraints ko establish karne se pehle LLD
  sub-problem answer kar dena hai jo unhe shape karne chahiye the.

**Opening a blended or ambiguous question** (e.g., "design a rate
limiter"):
- Committing se pehle poochiye kaunsi altitude chahiye — yeh single
  question kai baar ek poore LLD ya poore HLD answer se zyada worth hoti
  hai jo wrong expectation ko deliver ho.
- Agar bola jaaye "both," to use explicitly sequence kariye: "I'll cover
  the algorithm and class design first, then talk about how this holds up
  distributed across multiple servers" — aur actually us structure ko
  follow kariye instead of dono answers ko mid-stream blend karne ke.

## Common Misconceptions

**"LLD is just easier/smaller HLD."** Nahi — woh completely different
skills test karte hain, same skill ko different sizes pe nahi. Ek
excellent HLD candidate SOLID, design patterns, ya polymorphism model karna
na jaan ke bhi LLD interview mein fail ho sakta hai, aur vice versa. Inhe
do separate skill sets ki tarah treat kariye jinki prepare karni hai, ek
scaled-down skill ki tarah nahi.

**"Agar ek question scale mention nahi karta, tab bhi infrastructure
discussion briefly mention karna safe hai."** Ek one-sentence
acknowledgment ("this would sit behind an API in a real deployment") fine
hai aur often expected bhi. Uspe real time spend karna — services sketch
karna, ek database schema discuss karna, ek cache mention karna — safe
nahi hai; yeh directly us time ko kha jaata hai jo class design ke liye
budgeted tha jo question actually chahta hai, aur yeh signal deta hai ki
aapne question ko correctly triage nahi kiya.

**"Design patterns sirf LLD ke belong karte hain, distributed systems
concepts sirf HLD ke belong karte hain, to main unhe independently prepare
kar sakta hoon."** Ek study split ke roop mein mostly true hai, lekin
boundary case jaanne layak hai: Strategy pattern (parking lot follow-ups
mein `PricingStrategy` ke liye use hota hai) ek LLD/OOD concept hai, jabki
ek distributed lock (agar wahi parking lot multiple servers ke across chale
to zaroori) ek HLD concept hai — same feature (pricing, ya concurrent
booking) dono require kar sakta hai, depending on aap currently problem ke
kis layer ke baare mein pooche ja rahe ho.

**"Ek baar main correctly LLD vs. HLD identify kar loon, main triaging mein
done hoon."** Bilkul nahi — kuch interviews mid-way pivot karte hain (upar
dekhiye), to identification ek one-time decision nahi hai jo minute one
mein liya jaata hai; yeh kuch aisa hai jo conversation evolve hote hue
re-check karte rehna hai, especially design ke "first pass" khatam karne ke
turant baad.

## Interview Tips

- Pehle minute mein, explicitly state kariye ki aapko lagta hai yeh kis
  type ka question hai: "This sounds like an LLD/OOD question — you want me
  to focus on class design and relationships rather than infrastructure
  scaling, is that right?" Yeh 10 seconds costs karta hai aur 10 minutes ka
  misaligned work prevent karta hai; interviewers consistently isper
  achha react karte hain kyunki yeh discipline ke baare mein self-awareness
  dikhata hai jo test ho rahi hai.
- Agar ek "design X" prompt ambiguous hai, directly poochiye. Silently
  guess mat kariye aur wrong mode mein 15 minutes burn mat kariye —
  interviewer ek 5-second clarifying question ka answer dena kahin zyada
  pasand karega, instead of aapko wrong cheez banate hue dekhna.
- Agar aap mid-interview pivot notice karein (systems talk "show me the
  classes for..." mein badalna), switch ko narrate kariye. Yeh signal karta
  hai ki aap interviewer ke intent ko track kar rahe hain, sirf ek
  memorized script execute nahi kar rahe.
- Rigidity mein over-correct mat kariye: kuch questions genuinely ek brief
  HLD framing chahte hain ("this would sit behind an API, but let's focus
  on...") LLD mein dive karne se pehle. Ek single sentence ki HLD context
  fine hai aur often expected bhi; mistake real time wahan spend karna hai
  jab ask LLD hai.
- Ek LLD question ko actually step-by-step work karne ke process ke liye
  (ek baar aapne identify kar liya ki yeh ek hai) — requirements clarify
  karna, objects identify karna, relationships identify karna, design
  karna, code karna, edge cases/extensibility discuss karna — is same
  folder mein `08_lld_interview_framework.md` dekhiye — yeh LLD ke liye
  wahi role play karta hai jo `System_Design/01_Concepts/16_interview_framework.md`
  HLD ke liye karta hai.

## Quick Recall — Self-Test

1. **LLD mein design ka unit kya hai, aur HLD mein kya hai?**
   LLD ka design unit class hai (aur woh objects jo yeh ek single
   application ya process ke andar runtime pe produce karta hai). HLD ka
   design unit service ya component hai (database, cache, queue, load
   balancer) jo machines ke ek network ke across distributed hai.

2. **Ek prompt kehta hai "design Instagram." Kya yeh LLD hai ya HLD, aur
   kya cheez aapko reconsider karwaayegi?**
   Default classification HLD hai — yeh ek named platform hai jo millions
   of concurrent users, feed generation, media storage at scale imply
   karta hai. Yeh LLD ban jaayega agar narrow ho ke kuch aisa ho jaaye
   "design the class hierarchy for Instagram's post/story/reel content
   types," jo scale framing drop kar deta hai aur instead object modeling
   maangta hai.

3. **Ek prompt ki wording mein do concrete signals bataiye jo LLD ki
   jagah HLD point karte hain.**
   Ek specific scale number (jaise, "10 million requests/day," "100M
   DAU"), aur named platforms/products ke around framing jo bahut saare
   external users use karte hain, instead of ek single bounded instance
   (ek parking lot, ek chess game, ek elevator bank).

4. **"Wrong question well" failure mode kya hai, aur yeh right question
   ke partially wrong answer se worse kyun hai?**
   Yeh ek technically correct, polished answer dena hai us problem se ek
   different problem ka — e.g., database sharding discuss karna jab ek
   parking lot ke classes design karne ko pucha gaya ho. Yeh right-question
   ke partial answer se worse hai kyunki yeh signal karta hai ki aap
   problems correctly triage nahi kar sakte, jo khud us cheez ka part hai
   jo evaluate ho raha hai, aapki technical depth se independent.

5. **Ek mid-interview HLD-to-LLD pivot kaisa dikhta hai describe kariye,
   aur jab aap ek notice karein tab aapko kya karna chahiye.**
   Interviewer specific business rules, edge cases poochna shuru kar deta
   hai, ya "show me the classes/code for X" kehta hai architecture-level
   discussion ke ek period ke baad. Aapko yeh explicitly bolna chahiye
   ("let's move from architecture into the class design for this piece")
   aur class boxes aur relationships sketch karne pe switch karna chahiye,
   instead of infrastructure discuss karte rehna.

6. **Interviewer se directly poochna kyun acceptable hai, aur ek good sign
   bhi, ki ek question LLD hai ya HLD?**
   Kuch prompts (jaise "design a rate limiter") bina zyada context ke
   genuinely ambiguous hote hain. Poochna seconds costs karta hai aur
   demonstrate karta hai ki aapko pata hai dono disciplines distinct hain
   aur different approaches require karte hain — silently wrong guess karna
   interview ka most part cost kar sakta hai.

7. **In do disciplines ko confuse karne ka ek real-world (non-interview)
   cost ka example dijiye.**
   Ek team jo ek class-modeling problem face kar rahi hai — e.g., ek
   `Order` class jo ek unmaintainable god object ban gaya hai — ek
   infrastructure fix (microservices mein split karke) ke liye reach karti
   hai instead of ek LLD refactor (Single Responsibility ke hisaab se
   collaborator classes extract karna), aur end mein wahi tangled object
   graph milta hai ab ek network ke across spread hua, added latency aur
   operational complexity ke saath.

8. **Konsi HLD counterpart file wahi role play karti hai jo
   `08_lld_interview_framework.md` is folder ke liye karegi?**
   `System_Design/01_Concepts/16_interview_framework.md` — yeh ek HLD
   question ko work through karne ke liye step-by-step approach deta hai,
   waise hi jaise `08_lld_interview_framework.md` LLD questions ke liye
   karegi.

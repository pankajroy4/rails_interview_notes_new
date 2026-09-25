# Microservices and Patterns

## Monolith vs microservices

Ek **monolith** ek single deployable unit hai jisme application ki saari
functionality hoti hai — ek codebase, ek build, ek deploy, typically ek
database. Ek **microservices architecture** application ko kai chote,
independently deployable services mein split karta hai, har ek apni
functionality ka piece own karta hai (aur usually apna khud ka data store),
network ke through communicate karte hue (HTTP/gRPC/messaging).

| Dimension | Monolith | Microservices |
|---|---|---|
| Deployment | Single unit — one deploy ships everything | Independent — each service deploys on its own schedule |
| Team scaling | Coordination overhead grows as more teams touch the same codebase | Team autonomy — teams own and ship their service without blocking on others |
| Failure isolation | A bug/crash in one part can take the whole app down | Blast radius contained to the failing service (if calls are resilient — see below) |
| Operational complexity | Simple — one thing to deploy, monitor, log | High — requires service discovery, distributed tracing, container orchestration, per-service monitoring |
| Data consistency | Easy — local ACID transactions across tables in one DB | Hard — distributed transactions/sagas needed across service boundaries (see `09_distributed_systems_core.md`) |
| Local development | Simple — run one app | Harder — may need many services running (or mocked) to test one flow |
| Performance (in-process calls) | Fast — function calls, no network hop | Slower — every cross-service call is a network round trip |

**Microservices free nahi hain, aur often prematurely adopt ki jaati hain.**
Real justification "yeh better scale karti hai" nahi hai — ek monolith bhi
horizontally scale ho sakti hai (N copies ek load balancer ke peeche run
karo, exactly jaise aap ek service ko scale karte ho). Actual justification
organizational hai: **Conway's Law** — yeh observation ki ek system ki
architecture end mein us organization ki communication structure ko mirror
karti hai jisne use banaya. Agar aapke paas kai independent teams hain jinhe
apne schedule par ship karna hai bina ek doosre ke code review, release
train, ya test suite ka wait kiye, to ek monolith bottleneck ban jaata hai
chahe uski technical scalability kuch bhi ho — har team ko same deploy,
same on-call, "kisi aur ke change ne mera app ka part tod diya" ke same risk
se couple hona padta hai. Microservices teams ko **independently deployable**
banati hain, jo ek organizational/velocity property hai, raw-throughput
property nahi. Ek 5-person startup ek team ke saath is benefit ka essentially
kuch bhi nahi paata aur poora operational tax bharta hai — yeh classic
premature-microservices mistake hai.

### Database-per-service

Upar wali data-consistency row ka apna khud ka explanation deserve karti hai,
kyunki yeh microservices adopt karne ki sabse badi hidden cost hai. Ek
monolith mein, har table typically ek database mein rehti hai, isliye ek
single ACID transaction "order," "payment," aur "inventory" concepts ke
across rows ko ek saath atomically update kar sakta hai — database engine
all-or-nothing guarantee karta hai.

Microservices se expect kiya jaata hai ki har ek apna **khud** ka database
(ya kam se kam apna khud ka schema/tables jinhe koi doosri service directly
touch na kare) own kare — yahi cheez actually unhe independently deployable
banati hai: agar service B directly service A ke tables tak reach kar sakti
ho, to B break ho jaayegi jaise hi A apna schema change kare, exactly wahi
tight coupling recreate karte hue jise microservices remove karne ke liye
bane the. Lekin iska matlab hai ki atomic-multi-table-transaction tool gayab
ho jaata hai jaise hi ek operation ek se zyada service ke data ko span kare
— ab ek single database nahi bacha jispe ek transaction run kiya jaa sake.
Yahi exactly wahi gap hai jise Saga pattern (dekho
`09_distributed_systems_core.md`) fill karne ke liye exist karta hai. **Shared
database anti-pattern** — jahan multiple services directly same database
ko read/write karte hain isse dodge karne ke liye — generally avoid kiya
jaata hai kyunki yeh silently un services ko dobara couple kar deta hai jo
independent hone chahiye the, unhe split karne ka main point defeat karte
hue.

## Service discovery

**Problem**: ek system mein jahan service instances dynamically scale up
aur down hote hain (autoscaling, deploys, crashes), ek caller bas "payment
service ko 10.0.0.5:8080 par call karo" hardcode nahi kar sakta — woh IP
paanch minute baad exist hi nahi karegi shayad. Kisi ko track karna hoga ki
ek service ke konse instances currently alive aur reachable hain, aur
callers ko us list ko find karne ka ek tareeka chahiye.

- **Client-side discovery**: calling service ek **service registry**
  (jaise, Consul, Eureka) ko directly query karti hai current healthy
  instances ki list paane ke liye, aur phir khud unke across apni khud ki
  load balancing karti hai (jaise, round-robin).
- **Server-side discovery**: calling service bas ek fixed address ko call
  karti hai — ek **load balancer/router** — jo khud registry ko query karta
  hai aur request ko ek healthy instance tak forward karta hai. Caller kabhi
  directly registry se baat nahi karta.

| | Client-side discovery | Server-side discovery |
|---|---|---|
| Who queries the registry | The calling service itself | A load balancer/router in front of the target service |
| Extra network hop | No — client calls the instance directly after lookup | Yes — client calls the LB, which forwards to the instance |
| Client complexity | Higher — every client needs registry-aware load-balancing logic | Lower — client just calls a stable address |
| Coupling to registry | Every client is coupled to the registry's API/client library | Only the load balancer is coupled to the registry |
| Common in | Netflix-style stacks (Eureka + Ribbon), some service meshes | Most cloud setups — DNS + a load balancer, Kubernetes Services |

```text
Client-side discovery                    Server-side discovery

Client --> Registry (get instance list)   Client --> Load Balancer --> Registry
Client --> Instance B  (picks one, calls)                          --> Instance B
                                                                     (LB forwards)
```

Zyada tar modern cloud-native setups default se server-side discovery use
karte hain (ek Kubernetes `Service` + uska internal load balancer ek
server-side discovery mechanism hai) kyunki yeh client code simple rakhta
hai — client-side discovery zyada older/legacy stacks mein dikhta hai ya
jahan ek service mesh sidecar client ki taraf se discovery ka kaam kar raha
ho.

## API Gateway recap and the Backend-for-Frontend pattern

Ek **API Gateway** ek system ki services ke saamne ek single entry point ki
tarah baithta hai external clients ke liye, cross-cutting concerns jaise
authentication, rate limiting, request routing, aur TLS termination ko ek
jagah handle karte hue instead of har service mein unhe duplicate karne ke
(dekho `03_networking_and_apis.md` full treatment ke liye).

**Backend-for-Frontend (BFF)** pattern isse aage le jaata hai: ek generic
gateway se har tarah ke client (web, iOS, Android, third-party API
consumers) ko same shape ke responses se serve karwane ke bajaye, aap
**har client type ke liye ek dedicated gateway** run karte ho, har ek us
specific client ki actual zaroorat ke hisaab se tailored — jaise, ek mobile
BFF jo responses ko aggregate aur trim karta hai payload size aur round
trips ko mobile network par minimize karne ke liye, versus ek web BFF jo
richer, zyada detailed responses afford kar sakta hai. Yeh generic gateway
ko ek bloated compromise banne se bachata hai jo mobile ke liye over-fetch
aur web ke liye under-fetch kare, iski cost hai multiple gateway codebases
maintain karna.

## Service mesh

**Yeh jo problem solve karta hai**: resilience aur observability concerns —
retries, timeouts, mutual TLS (mTLS) encryption services ke beech, load
balancing, aur request tracing/metrics — agar har team independently
implement kare to har single service ke code mein duplicate ho jaate hain,
jisse inconsistent behavior hota hai (ek service 3 baar retry karti hai,
doosri 0 baar) aur languages/teams ke across bahut sara repeated
boilerplate.

Ek **service mesh** in concerns ko application code se nikal kar ek
infrastructure layer mein le jaata hai: ek lightweight **sidecar proxy** jo
har service instance ke saath deploy hota hai uska sara network traffic
(incoming aur outgoing dono) intercept karta hai aur retries, timeouts,
mTLS, load balancing, aur telemetry uniformly handle karta hai — application
code bas apne sidecar ko ek plain local call karta hai aur network-level
machinery se unaware rehta hai.

- **Istio**: ek widely used service mesh jo Envoy proxy par built hai, fine-
  grained traffic control offer karta hai (canary routing, fault injection)
  aur strong mTLS/security policy support ke saath.
- **Linkerd**: ek lighter-weight, simpler-to-operate service mesh jo Istio
  se smaller resource footprint ke saath easy adopt hone par focus karta
  hai.

Dono apne aap mein deep topics hain — interview-relevant takeaway hai *kyun*
ek mesh exist karta hai (cross-cutting network concerns ko application code
se centralize karna) unke internals nahi.

## Resilience patterns

Yeh patterns isliye exist karte hain kyunki microservices architecture mein,
services ke beech network calls constantly fail hote hain (timeouts, slow
responses, crashes) — aur deliberate handling ke bina, ek struggling
service ki failure har us service tak spread ho jaati hai jo use call karti
hai.

### Circuit breaker

**Kya trigger karta hai isse**: ek downstream dependency ek configured
threshold se zyada fail ya timeout hona shuru karti hai (jaise, ek rolling
window mein 50% se zyada calls fail hon).

**Yeh kya prevent karta hai**: ek aisi dependency ko requests bhejte rehna
jo already struggling hai sirf cheezein aur bura banata hai — callers
timeouts ka wait karte hue pile up ho jaate hain, threads/connections
consume karte hue, aur failing service ko still-incoming load ke under
recover hone ka koi chance nahi milta. Ek circuit breaker ek baar threshold
trip hone ke baad dependency ko call karna poori tarah band kar deta hai,
**fail fast** karte hue (immediate error/fallback, koi wasted wait nahi),
aur periodically ek trial request through jaane deta hai check karne ke
liye ki kya dependency recover ho gayi hai.

Teen states:
- **Closed**: normal operation, requests through flow karte hain, failures
  count ho rahe hote hain.
- **Open**: threshold trip ho gaya — sab requests turant fail ho jaate hain
  call attempt kiye bina bhi.
- **Half-open**: ek cooldown period ke baad, limited number of trial
  requests through jaane diye jaate hain; agar woh succeed karein, to
  breaker phir se close ho jaata hai (normal traffic resume); agar woh fail
  hon, to yeh phir se open ho jaata hai.

```text
   failures exceed threshold
CLOSED ------------------------> OPEN
   ^                                |
   | trial requests succeed        | cooldown timer expires
   |                                v
   +---------------------------- HALF-OPEN
              trial requests fail --> back to OPEN
```

### Bulkhead

**Kya trigger karta hai isse**: yeh ek failure ka reaction nahi hai — yeh
ek proactive resource-isolation design hai. Ship bulkheads (compartments jo
ek flooded section ko poore ship ko doobne se rokte hain) ke naam par.

**Yeh kya prevent karta hai**: isolation ke bina, threads/connections ka ek
shared pool jo *har* downstream dependency ko call karne ke liye use hota
hai, matlab ek slow dependency poora pool exhaust kar sakti hai uska wait
karte hue — completely unrelated, healthy dependencies ko calls ke liye
resources se starve karte hue. Ek bulkhead **har dependency ke liye alag
resource pools** allocate karta hai (jaise, ek fixed-size connection pool ya
thread pool service B ko calls ke liye dedicated, service C ke liye use
hone wale pool se independent), taaki ek slow/stuck service B kabhi bhi
sirf apna khud ka chota pool exhaust kare, service C ke calls ko kabhi
starve na kare.

### Retry with exponential backoff + jitter

**Kya trigger karta hai isse**: ek call fail ya timeout hoti hai aur use
safe/worth retrying consider kiya jaata hai (ideally sirf idempotent
operations ke liye — dekho `09_distributed_systems_core.md`).

**Yeh kya prevent karta hai / naive retries cheezein kyun aur bura banate
hain**: agar har failed caller turant retry kare, aur failure ki wajah
downstream service ka overloaded hona ho, to ek immediate retry storm ek
already-struggling service par aur zyada load daal deta hai — actively
uski recovery delay karte hue. **Exponential backoff** retries ke beech
progressively zyada wait karta hai (jaise, 100ms, 200ms, 400ms, 800ms)
dependency ko recover hone ke liye room dene ke liye, use continuously
hammer karne ke bajaye. **Jitter** (har backoff delay mein ek chota random
amount add karna) thundering-herd effect ko prevent karta hai jahan kai
clients jo same moment par fail hue (jaise, kyunki dependency abhi abhi
down hui) sab exactly same synchronized intervals par retry karte hain,
same load ka spike baar baar recreate karte hue instead of use spread out
karne ke.

### Timeouts

**Har network call ko ek kyun chahiye**: ek explicit timeout ke bina, ek
caller ek slow ya hung dependency se response ka indefinitely wait kar
sakta hai, apne khud ke resources (threads, connections) ko poore time ke
liye tie up karte hue. **Ek na hone ka danger**: ek single slow dependency,
time ke saath, purely uska wait karte hue pile up hui requests se caller ke
apne resource pools exhaust kar sakti hai — ek slow downstream service ko
calling service ka bhi ek outage bana dete hue, chahe calling service ke
apne code mein koi bug na ho. Baaki sab resilience patterns assume karte
hain ki timeouts already jagah par hain — ek circuit breaker un "failures"
ko count nahi kar sakta jo kabhi resolve hi nahi hote, aur ek bulkhead ka
pool permanently fill ho jaata hai bina ek timeout ke jo eventually uske
slots ko free kare.

## Strangler fig pattern

**Strangler fig pattern** (us vine ke naam par jo ek tree ke around badhti
hai, gradually use replace karte hue, jab tak original tree gayab na ho
jaaye) woh tareeka hai jisse teams ek monolith ko incrementally
microservices mein migrate karti hain bina ek risky big-bang rewrite ke.
Feature work rokh kar sab kuch scratch se rebuild karne ke bajaye (ek
project jo routinely estimate se kaafi zyada time leta hai aur uss beech
purane system ki improvement ko freeze kar deta hai), aap:

1. Ek routing layer (often API gateway) monolith aur naye services dono ke
   saamne rakhte ho.
2. Ek time par ek piece of functionality naye service mein extract karte ho.
3. Us functionality ke liye traffic ka badhta hua slice naye service ko
   route karte ho, jabki baaki sab abhi bhi monolith ko jaata hai.
4. Piece by piece repeat karte ho, jab tak monolith kuch bhi handle na kare
   (ya sirf woh jo deliberately wahan chhoda gaya ho).

```text
Before:                          During migration:                   After:
Client --> Monolith              Client --> Gateway --+-> Monolith    Client --> Gateway --> New Service A
           (everything)                               +-> New Svc A              +-> New Service B
                                                                                   +-> Monolith (remainder)
```

Benefit yeh hai ki har extracted piece independently low-risk aur reversible
hai (aap traffic wapas monolith par route kar sakte ho agar naye service
mein problems hon), aur system migration ke poore samay fully functional
aur shippable rehta hai, midway rewrite mein frozen hone ke bajaye.

## Trade-offs / When to use what

| Situation | Lean toward | Why |
|---|---|---|
| Small team, early-stage product | Monolith | No org-scaling problem yet; avoid the operational tax of microservices for no benefit |
| Multiple independent teams needing to ship on their own schedule | Microservices | Conway's Law — independent deployability matches independent teams |
| Need raw horizontal scalability only | Either — scale out monolith replicas, or split into services | Horizontal scaling doesn't by itself require microservices |
| Different client types with very different data needs | BFF per client type | Avoids a bloated one-size-fits-all gateway |
| Many services duplicating retry/mTLS/observability code | Service mesh | Centralizes cross-cutting concerns instead of duplicating per-service |
| Migrating an existing monolith | Strangler fig | Incremental, reversible, avoids a risky big-bang rewrite |

## Interview Tips

- Agar aap microservices propose karte ho, interviewer often poochega
  "monolith ko horizontally scale kyun nahi kiya?" — Conway's Law /
  team-autonomy wala answer ready rakho; "yeh better scale karti hai" akela
  ek weak answer hai kyunki monoliths bhi scale karti hain.
- Circuit breaker, bulkhead, retry+backoff+jitter, aur timeouts frequently
  ek group ki tarah poochhe jaate hain ("aap is service ko ek failing
  dependency ke against resilient kaise banaoge?") — chaaron ko saath naam
  lena, aur har ek specifically kya prevent karta hai, practical production
  experience ka ek strong signal hai.
- Agar interviewer kahe "socho yeh aaj ek monolith hai aur microservices
  banna hai," to strangler fig expected answer hai "isse rewrite karo" ki
  jagah — ek full rewrite propose karna real-world judgment ke liye ek red
  flag ki tarah padha jaata hai.
- Service discovery questions ("service A service B ke healthy instances
  kaise dhoondti hai?") kisi bhi dynamic scaling wale design mein common
  hain — client-side aur server-side discovery dono jaano aur bata sako ki
  Kubernetes-based stack mein konsa zyada common hai (server-side, ek
  Service/load balancer ke through).
- Ek service mesh ko default answer ki tarah reach mat karo "retries/mTLS
  kaise handle karte ho" jaise sawaal ke liye services ki kam number ke
  liye — yeh tab justified hai jab kai services ke across duplication/
  inconsistency problem real ho, day one se nahi.

## Quick Recall — Self-Test

**Q1: Monolith se microservices choose karne ki actual justification kya hai, aur "better scalability" akela ek sufficient answer kyun nahi hai?**
Real justification organizational hai: Conway's Law kehta hai ki ek system ki architecture org ki communication structure ko mirror karti hai, isliye independent teams ko independently deployable services chahiye ek doosre par block hue bina ship karne ke liye. "Better scalability" akela insufficient hai kyunki ek monolith bhi horizontally scale ho sakti hai kai replicas ek load balancer ke peeche run karke.

**Q2: Client-side aur server-side service discovery mein kya difference hai?**
Client-side discovery mein, calling service khud registry ko query karti hai aur instances ke across khud load-balance karti hai. Server-side discovery mein, client ek fixed load balancer/router address ko call karta hai, jo registry ko query karta hai aur request forward karta hai — client kabhi directly registry se baat nahi karta.

**Q3: Ek circuit breaker specifically kya prevent karta hai, aur uski teen states kya hain?**
Yeh ek already-failing dependency ko requests se hammer karte rehna prevent karta hai jo timeouts ka wait karte hue pile up ho jaate hain, caller ke resources consume karte hue jabki dependency ko recover hone ka koi room nahi milta. Iski states hain closed (normal traffic flow karta hai), open (turant fail fast, koi calls attempt nahi hoti), aur half-open (recovery check karne ke liye ek cooldown ke baad limited trial requests).

**Q4: Ek bulkhead ek circuit breaker se kaise different hai isme ki woh kya protect karta hai?**
Ek circuit breaker ek specific dependency ke already fail hone par react karta hai aur use call karna band kar deta hai. Ek bulkhead proactive resource isolation hai — har dependency ke liye alag pools (threads/connections) — taaki ek slow dependency sirf apna khud ka pool exhaust kare, kabhi unrelated healthy dependencies ke calls ko starve na kare jo same caller share karte hon.

**Q5: Naive immediate retrying outages ko kyun aur bura banata hai, aur do techniques isse kaise fix karti hain?**
Agar failure ek overloaded dependency ki wajah se hai, to har failed caller se immediate retries aur zyada load daal dete hain exactly tab jab dependency ko kam chahiye, recovery ko delay karte hue. Exponential backoff badhte delay ke saath retries ko space out karta hai dependency ko recover hone ke liye room dene ke liye, aur jitter un delays ko randomize karta hai taaki simultaneously fail hue kai clients synchronized spikes mein retry na karein.

**Q6: Baaki sab resilience patterns kyun assume karte hain ki timeouts already jagah par hain?**
Ek circuit breaker un failures ko count nahi kar sakta jo kabhi resolve hi nahi hote bina ek timeout ke jo define kare ki ek call kab fail count hoti hai, aur ek bulkhead ka dedicated pool permanently fill ho jaata hai aur exhausted rehta hai bina ek timeout ke jo eventually uske slots free kare — timeouts basic mechanism hain jo bound karte hain ki koi bhi call kitni der resources hold kar sakti hai.

**Q7: Strangler fig pattern kya problem solve karta hai, aur high level par yeh kaise kaam karta hai?**
Yeh ek big-bang monolith rewrite ke risk se bachata hai (lambi timelines, frozen improvements, high failure risk) traffic ka badhta hua slice incrementally naye services ko route karke jo ek time par ek piece extract kiye jaate hain, jabki monolith woh sab abhi bhi handle karta hai jo migrate nahi hua — system ko poore samay fully functional rakhte hue.

**Q8: Backend-for-Frontend pattern kya hai, aur yeh kya problem solve karta hai jo ek single generic API Gateway nahi karta?**
BFF har client type (web, mobile, etc.) ke liye ek dedicated gateway run karta hai, har ek us client ki specific data aur payload needs ke hisaab se tailored. Yeh us problem ko solve karta hai jahan ek single generic gateway ek bloated compromise ban jaata hai — constrained clients jaise mobile ke liye over-fetching, ya richer clients jaise web ke liye under-serving.

**Q9: "Database-per-service" ek operation ke liye ek single atomic transaction run karne ki ability kyun tod deta hai jo multiple services ko span karta hai, aur us gap ko kya fill karta hai?**
Har service apna khud ka database own karti hai matlab ab koi ek shared database engine nahi bacha jo, jaise, order aur payment aur inventory data ke across ek all-or-nothing transaction enforce kar sake — yeh ab separate databases mein alag services ke saamne rehte hain. Saga pattern us gap ko fill karta hai local transactions ko compensating actions ke saath sequence karke instead of ek single cross-service atomic transaction par rely karne ke.

**Q10: "Shared database" anti-pattern microservices architecture mein kyun harmful maana jaata hai?**
Yeh multiple services ko same database ko directly read/write karne deta hai, jo silently unhe dobara couple kar deta hai — ek service ka schema change doosri service ko break kar sakta hai jo same tables mein reach karti ho — independent-deployability benefit ko defeat karte hue jo actually microservices adopt karne ki wajah thi.

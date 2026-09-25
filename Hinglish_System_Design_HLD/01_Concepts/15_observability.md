# Observability

## Why it matters

Tum duniya ka sabse elegant architecture design kar sakte ho aur wo phir bhi production mein break hoga — ek deploy ek regression introduce kar deta hai, ek downstream dependency slow ho jaati hai, ek specific shard hot ho jaata hai. Ek 5-minute incident aur ek 5-hour incident ke beech difference almost poori tarah is baat pe hai ki tum quickly "kya broken hai, kahaan, aur kyun" answer kar sakte ho apne system ke already produce kiye hue data se, kisi box mein SSH karke guess karne ke bajaye. **Observability** ek system ki general property hai jo tumhe wo question outside se answer karne deti hai, uske outputs (logs, metrics, traces) use karke, bina abhi tumhare saamne wale specific incident ko debug karne ke liye baad mein naya instrumentation add kiye. Interview mein, observability mention karna signal deta hai ki tum ek system ki poori lifecycle ke baare mein soch rahe ho — build karo, operate karo, 2am pe debug karo — sirf uski happy-path architecture diagram nahi.

## Teen pillars

| Pillar | Answer karta hai | Granularity |
|---|---|---|
| Logging | Exactly kya hua, ek specific event/request ke liye | Bahut fine — ek single occurrence ka full detail |
| Metrics | Kya system abhi healthy hai, aggregate mein | Coarse — time ke over numeric signal, koi per-event detail nahi |
| Tracing | Ek request ka time multiple services ke across kaise spend hua | Medium — ek request, but uske poore path ke across |

**Logging**: ek specific event ka record jaise wo hua — "user 4821 ne 14:32:07 pe login attempt kiya aur fail hua: invalid password," "order 9931 charge karne mein fail hua: gateway timeout." Logs tumhare liye ek single occurrence ka detailed truth ka source hain — indispensable jab tumhe already roughly pata ho ki *kya* hua aur tumhe exactly *kyun* jaanna ho, ek request ya ek user ke liye.

**Metrics**: aggregate numeric signals jo time ke over sample/collect kiye jaate hain — requests per second, error rate, CPU utilization, queue depth. Metrics ek glance mein poori fleet ke across "kya system abhi healthy hai" answer karte hain, kisi bhi individual event ko dekhe bina. Ye wo cheez hai jispe dashboards aur zyaadatar alerts bane hote hain, kyunki ye huge volume pe bhi cheap hain store/query karne ke liye (ek counter ek single number hai, har event ka ek growing log nahi).

**Tracing**: ek single request ka journey follow karta hai jaise wo multiple services ke through flow karta hai, dikhaate hue ki har hop mein kitna time spend hua. Ek baar jab ek request ek se zyada service touch karta hai, har service se isolation mein logging aur metrics tumhe nahi bata sakte *kaunse* hop ne slowdown cause kiya — tracing poore path ko ek timeline mein stitch kar deta hai.

```text
Logging:  "exactly what happened, for this one event"      -> one line, full detail
Metrics:  "is everything healthy right now"                -> one number, over time
Tracing:  "where did this one request's time actually go"  -> one timeline, across services
```

Ye teen complementary hain, substitutes nahi: ek metric tumhe batata hai ki error rate abhi spike hua; ek trace tumhe batata hai ki specifically payment service ke fraud-check service ko calls slow ho gaye; ek log tumhe batata hai ki fraud-check service ek specific malformed request payload ki wajah se timeout kar raha hai.

## Structured logging vs plain-text logging

**Plain-text logs** free-form human-readable strings hain: `"2024-01-15 14:32:07 ERROR User 4821 login failed: invalid password"`. Terminal mein directly padhna easy hai, but scale pe query karna hard hai — "pichle ek ghante mein, 200 servers ke across, user 4821 ke saare failed logins dhoondo" ka matlab hai unstructured strings ke upar grep-jaisi text searching, jo slow aur brittle hai (thoda different message format tumhari search break kar deta hai).

**Structured logging** logs ko machine-parseable key-value data ke roop mein emit karta hai, typically JSON: `{"timestamp": "2024-01-15T14:32:07Z", "level": "error", "event": "login_failed", "user_id": 4821, "reason": "invalid_password"}`. Har field directly queryable hai — "wo saare `login_failed` events jahan `user_id = 4821`" ek precise, fast query hai ek log aggregation system ke against (e.g., Elasticsearch-backed tooling — `13_search_and_indexing.md` dekho), text search nahi.

Ek baar jab tumhare paas meaningful log volume generate karne wali handful se zyada services ho jaayein, structured logging decisively win karta hai: ye tumhe logs ko filter, aggregate, aur correlate karne deta hai services ke across (e.g., "har service ke across har wo log line dikhao jo is ek `request_id` se tagged hai") ek aise tarike se jo plain text fundamentally scale pe support nahi kar sakta. Cost ye hai ki structured logs ko raw file mein directly eyeball karna kam pleasant hai — but scale pe, koi bhi raw log files eyeball nahi kar raha hota anyway; wo ek aggregation system query kar rahe hote hain.

| | Plain-text | Structured (JSON/key-value) |
|---|---|---|
| Human readability | High, directly | Directly kam, but tools use nicely render karte hain |
| Scale pe queryability | Poor — sirf text search | Strong — precise field-based queries |
| Cross-service correlation | Hard | Easy (shared fields jaise `request_id`) |
| Best fit | Local dev, single small app | Ek se zyada services/meaningful volume wala koi bhi system |

## Metrics types

**Counters**: ek value jo sirf increase hi hota hai (jab tak reset na ho, e.g., process restart pe) — total requests served, total errors, total orders placed. Tum typically ek counter ke raw cumulative value se zyada uski *rate of change* (requests/sec) ki parwaah karte ho.

**Gauges**: ek value jo up ya down ja sakta hai, ek current state represent karte hue — current active connections, current queue depth, current memory usage. Ek counter ke unlike, ek gauge ki current value apne aap mein meaningful hai (ek counter akela tumhe bas ye batata hai "start se bahut kuch hua hai," current state nahi).

**Histograms**: values ke ek set ki *distribution* capture karte hain, sirf ek single number nahi — bucketed counts ki kitne observations har range mein aaye. Canonical use request latency hai: ek number ke bajaye, tumhe percentiles jaise p50 (median), p95, p99 (99th percentile) compute karne layak enough data mil jaata hai.

**Latency ke liye percentiles averages se zyada kyun matter karte hain**: ek average perfectly healthy dikh sakta hai jabki real user pain hide kar raha ho. Agar 99 requests 10ms lete hain aur 1 request 10 seconds leta hai, average roughly 109ms hai — theek dikhta hai — but wo ek request ek real user represent karta hai jiska experience terrible tha, aur scale pe "1 in 100" rare nahi hai, ye tumhare total traffic ka ek meaningful fraction hai. p99 latency (wo value jiske neeche 99% requests aate hain) directly answer karta hai "mere users ka ek non-trivial chunk actually kitna worst experience jhel raha hai," jo generally tumhe optimize aur alert karna chahiye — ek system ka average great ho sakta hai aur p99 simultaneously terrible ho sakta hai, aur averages ye kabhi surface nahi karenge.

```text
Latencies (ms): 8, 9, 9, 10, 10, 11, 10, 9, 8, 10000

Average ≈ 1009ms   <- dominated/skewed, but also misleadingly "not that bad" looking
                       for the 9 fast requests hidden inside it
p50 (median) = 9-10ms   <- "typical" request, accurate
p99 = ~10000ms          <- the tail user's actual (bad) experience, visible
```

| Metric type | Example | Kaunsa question answer karta hai |
|---|---|---|
| Counter | Total requests served | Cumulatively kitna hua hai? |
| Gauge | Current active DB connections | Abhi state kya hai? |
| Histogram | Request latency distribution | Outcomes ka poora spread kaisa dikhta hai (p50/p95/p99)? |

## Distributed tracing

Ek baar jab ek system handful services ka ho jaata hai jo ek dusre ko call karte hain, ek single user-facing request unme se bahut saari ke across fan out ho sakta hai — ek API call ek gateway, ek auth service, ek order service, ek payment service, aur ek inventory service ko respond karne se pehle hit kar sakta hai. Agar wo request slow hai, isolation mein per-service logs aur metrics tumhe nahi batate ki un paanch hops mein se *kaunsa* culprit hai — har service khud ko healthy report kar sakta hai, kyunki slowness network hop, ek queue, ya ek downstream call mein ho sakti hai jise unme se koi bhi individually end-to-end nahi dekhta.

Distributed tracing ise solve karta hai request ke har hop ke across shared identifiers propagate karke:

- **Trace ID**: poori request ko end-to-end identify karta hai, har service ke across jo wo touch karti hai. Is ek logical request ka har span same trace ID share karta hai.
- **Span ID**: us trace ke andar work ki ek unit identify karta hai — typically ek service ka request handle karna, ya usme koi significant operation (e.g., ek DB query). Har span apna start time, duration, aur wo kis span ka child hai record karta hai, taaki full trace ek timeline/tree reconstruct kare "kisne kisko call kiya, aur har hop mein kitna time laga."

Ye context (trace ID, current span ID, plus parent span ID) request ke as it moves from service to service **request headers ke through propagate** hota hai — har service incoming trace context padhta hai, uska child ke roop mein apna span banata hai, aur (possibly updated) context aage jo bhi call kare use pass kar deta hai. Ek trace ID share karne wale saare spans ko collect karke unhe visualize karna (commonly nested time ranges ke ek waterfall/flame graph ke roop mein) exactly dikhata hai ki request ka total time kahaan gaya.

```text
trace_id: abc123
┌─────────────────────────────── Gateway (span 1, 220ms) ───────────────────────────────┐
   ┌──── Auth svc (span 2, 15ms) ────┐
                                       ┌────────── Order svc (span 3, 190ms) ───────────┐
                                          ┌── Payment svc (span 4, 160ms) ──┐  <- the culprit
                                          ┌ Inventory svc (span 5, 10ms) ┐
```
Tracing ke bina, har service individually shayad log kare "maine 190ms liye" ya "maine 160ms liye" bina koi shared context ke jo unhe ek request ki story mein tie kare — tracing wo cheez hai jo isolated per-service numbers ko ek single, attributable timeline mein badal deti hai.

## Log levels

Structured ho ya na ho, logs typically ek **severity level** se tag hote hain taaki consumers (humans aur alerting systems dono) message content parse kiye bina importance se filter kar sakein:

| Level | Meaning | Example |
|---|---|---|
| `DEBUG` | Fine-grained detail, sirf active debugging ke waqt useful | "Cache lookup for key X missed, falling through to DB" |
| `INFO` | Normal operational events, expected | "User 4821 logged in" |
| `WARN` | Kuch unexpected but (abhi tak) broken nahi | "Retrying payment gateway call, attempt 2 of 3" |
| `ERROR` | Ek operation fail hui | "Failed to charge order 9931: gateway timeout" |
| `FATAL/CRITICAL` | Process khud continue nahi kar sakta | "Unable to connect to primary DB at startup, exiting" |

Production mein, `DEBUG` usually disabled hota hai ya heavily sampled (full fidelity pe store/query karne ke liye bahut zyada high-volume), aur alerting generally raw log volume ke bajaye `ERROR`/`FATAL` rates pe build hoti hai, neeche wale symptom-based alerting mein feed karte hue.

## Sampling: scale pe tracing ko affordable banana

High request volume pe har single request ke liye full trace capture karna expensive hai — spans generate karne ka overhead aur unhe retain karne ka storage cost dono. Production tracing systems commonly **sampling** use karte hain: sirf ek percentage requests (e.g., saare traffic ka 1%, ya un requests ka 100% jo error karte hain/ek latency threshold exceed karte hain, jise "tail-based" ya "error-biased" sampling kehte hain) fully trace aur retain kiye jaate hain. Ye ek trade-off hai jo naam lena worthwhile hai agar scale pe tracing ke baare mein poocha jaaye: har request pe full-fidelity tracing complete visibility deta hai but cheaply scale nahi karta; sampling cost ko bounded rakhta hai jabki abhi bhi wo traces catch karta hai jo sabse zyada matter karte hain (slow aur failing wale), is cost pe ki agar tumhe baad mein ek dhoondhna ho to har single request ka trace nahi hoga.

## Alerting

**Symptom-based alerting**: alert karo un cheezon pe jo users actually experience karte hain — elevated error rate, elevated p99 latency, failed checkouts per minute. Ye primary alerts hain, kyunki ye directly user impact reflect karte hain — agar symptomatically kuch bhi wrong nahi hai, to arguably kisi ko jagane layak abhi kuch bhi wrong nahi hai, chahe internal metrics kuch bhi kahein.

**Cause-based alerting**: alert karo ek specific internal condition pe — high CPU, high memory, disk fill hona, queue depth badhna. Ye *supporting diagnostic signals* ke roop mein valuable hain ek baar jab ek symptom-based alert already fire ho chuka ho (high CPU probably iski wajah hai ki latency up hai), but akele primary alerts ke roop mein ye noisy hote hain aur aksar actual user impact se disconnected hote hain — CPU briefly spike kar sakta hai zero user-visible effect ke saath (e.g., ek GC pause ke dauraan jo tolerance ke well andar hai), aur har aise blip pe alert karna logon ko alerts ignore karna sikha deta hai.

**Symptom-based primary kyun hona chahiye**: ye zyada honest question hai. "Kya CPU high hai" jaruri nahi ki iska matlab ho ki users suffer kar rahe hain; "kya error rate/latency elevated hai" ka matlab hai wo directly suffer kar rahe hain, internal cause chahe kuch bhi ho. Cause-based signals ko best treat kiya jaata hai un dashboards/diagnostics ki tarah jo tum ek symptom-based alert fire hone ke *baad* check karte ho, root cause dhoondhne ke liye — akele kisi ko page karne wali cheezon ki tarah nahi.

**Alert fatigue**: bahut saare low-value, low-signal alerts hone ka danger (har minor CPU blip, har transient retry) ye hai ki log alerts ko wholesale ignore karna shuru kar dete hain, real waale bhi — alerting system apne hi operators ko use tune out karna sikha deta hai. Ek chhoti number of high-signal, symptom-based alerts jo reliably real user impact indicate karte hain bahut zyada effective hain ek large number of noisy alerts se, chahe wo noisy waale individually well-intentioned hi kyun na hon.

## Health checks: liveness vs readiness

**Liveness probe**: "kya ye process abhi bhi running hai / bilkul function kar raha hai, ya ise kill karke restart karna chahiye?" Ek failing liveness check ka matlab hai process ek broken, unrecoverable-without-restart state mein hai (e.g., deadlocked, hung) — orchestrator ka response typically ise kill karke restart karna hota hai.

**Readiness probe**: "kya ye process abhi *right now* traffic receive karne ke liye ready hai?" Ek process alive ho sakta hai (crash nahi hua, liveness check pass kar jaayega) but abhi ready na ho — e.g., ye abhi bhi warm up ho raha hai, ek large in-memory cache load kar raha hai, ya ek dependency ke available hone ka wait kar raha hai. Ek failing readiness check ka matlab hai "yahaan abhi traffic route mat karo," "ise kill karo" nahi — orchestrator ka response ise temporarily load balancer ke pool se remove karna hai jab tak wo dobara ready report na kare.

**Dono ko conflate karna real outages kyun cause karta hai**: agar ek slow-starting ya temporarily-busy process ko liveness probe se check kiya jaaye readiness probe ke bajaye, orchestrator conclude kar leta hai ki ye dead hai aur ise kill kar deta hai — chahe wo bas warm up ho raha tha ya briefly overloaded tha, aur khud recover ho jaata. Ek process ko baar-baar kill karna jo healthy hone hi wala tha (kyunki use kabhi startup finish karne ka chance hi nahi milta) ek classic self-inflicted outage hai: fix application code mein nahi hai, ye infrastructure/health-check configuration level pe correctly "isse restart karna chahiye" (liveness) ko "isse traffic milna chahiye" (readiness) se distinguish karne mein hai.

| | Liveness | Readiness |
|---|---|---|
| Question | Kya ye process restart hona chahiye? | Kya ye process abhi traffic receive karna chahiye? |
| Kab fail hota hai | Process hung/deadlocked/broken hai | Process alive hai but abhi ready nahi hai (warming up, dependency down) |
| Failure pe orchestrator response | Kill aur restart karo | Load balancer pool se remove karo, kill mat karo |
| Inhe conflate karna cause karta hai | N/A | Healthy-but-busy/starting processes ko kill karna, outages worsen karna |

## Trade-offs

| Decision | Ye choose karo jab... | Cost |
|---|---|---|
| Structured logging | Ek couple se zyada services, cross-service queries/correlation chahiye | Raw log files directly padhne mein human ke liye thoda kam pleasant |
| Har request pe fine-grained tracing | Ek specific microservices latency problem debug karna, ya ek complex system mein always-on | Trace data ka storage/overhead cost; usually high volume pe sampling se mitigate hota hai (sirf ek percentage requests trace karo) |
| Symptom-based alerts primary ke roop mein | Almost always — ye safer default hai | User-facing metrics (error rate, latency) mein achhi visibility chahiye taaki meaningful ho |
| Cause-based alerts primary ke roop mein | Rarely — sirf un conditions ke liye jo reliably, directly imminent user impact predict karte hain (e.g., disk poora fill hone wala hai) | Broadly use karne pe noise/alert fatigue ka high risk |

## Interview Tips

- Agar ek design multiple services ke across span karta hai, proactively distributed tracing mention karo — ye ek strong signal hai ki tum operability ke baare mein soch rahe ho, sirf happy-path architecture nahi.
- Latency requirements discuss karte waqt, "average" ke bajaye "p99" bolo — interviewers notice karte hain jab ek candidate default average latency pe jaata hai, kyunki ye ek well-known tarika hai jisse real tail-latency problems ek metric se chhup jaate hain.
- "Ise kaise monitor karoge" poochne pe symptom-based alerts ko primary aur cause-based ko diagnostic support ke roop mein distinguish karo — ek common weak answer bas "hum CPU aur memory pe alert karenge" list kar deta hai, jo miss kar jaata hai ki actually kisi ko page kya karna chahiye.
- Liveness vs readiness specifically mention karo agar design containerized/orchestrated services involve kare (e.g., Kubernetes) autoscaling ya rolling deploys ke saath — inhe conflate karna ek realistic, concrete failure mode hai jo practical operational awareness dikhata hai.

## Quick Recall — Self-Test

**Q1: Teen observability pillars mein se har ek kaunsa distinct question answer karta hai?**
Logging answer karta hai exactly kya hua ek specific event ke liye. Metrics answer karte hain kya system abhi healthy hai, aggregate mein. Tracing answer karta hai ek single request ka time multiple services ke across kaise flow hua.

**Q2: Structured logging kai services hone ke baad plain-text logging se better kyun perform karta hai?**
Structured (JSON/key-value) logs machine-parseable hote hain, isliye tum specific fields pe precisely query kar sakte ho (e.g., ek given `user_id` ya `request_id` wale saare events) aur services ke across ek common field share karne wale logs ko correlate kar sakte ho. Plain text logs sirf brittle text search support karte hain aur scale pe reliably aggregate ya filter nahi ho sakte.

**Q3: Ek counter, ek gauge, aur ek histogram ka example do, aur har ek kis liye hai.**
Counter: total requests served (monotonically increasing, iski rate ki parwaah hoti hai). Gauge: current active connections (up ya down jaata hai, current-state snapshot). Histogram: request latency distribution (bucketed values jo percentile calculations jaise p95/p99 enable karte hain).

**Q4: Ek average latency healthy kyun dikh sakti hai jabki real users suffer kar rahe hon?**
Ek average fast aur slow requests ko ek number mein blend kar deta hai, isliye bahut slow requests ka ek small fraction majority ke fast requests se mask ho sakta hai. p99 jaise percentiles directly tail isolate karte hain, worst-affected (but abhi bhi numerically significant) fraction of users ka experience dikhate hue, jo ek average hide kar deta hai.

**Q5: Trace ID aur span ID har ek kya identify karte hain, aur wo context services ke beech kaise pass hota hai?**
Ek trace ID poori end-to-end request ko identify karta hai har service ke across jo wo touch karti hai; ek span ID us trace ke andar work ki ek unit identify karta hai (typically ek service ka handling, ya ek sub-operation). Ye context request headers ke through propagate hota hai jaise request ek service se dusri mein move karti hai, har hop ko apna span same overall trace se attach karne deta hai.

**Q6: Symptom-based alerting generally cause-based alerting se primary alert ke roop mein preferred kyun hai?**
Symptom-based alerts (elevated error rate, elevated latency) directly actual user impact reflect karte hain, jabki cause-based signals (high CPU, high memory) bina kisi user-visible effect ke spike ho sakte hain, noisy, low-value alerts cause karte hue. Cause-based signals abhi bhi diagnostic support ke roop mein useful hain ek baar jab ek symptom-based alert already fire ho chuka ho.

**Q7: Alert fatigue kya hai, aur ye dangerous kyun hai?**
Ye bahut saare low-signal alerts hone ka effect hai, jo unhe receive karne walon ko generally alerts ignore karna sikha deta hai — real, important waale bhi. Ek chhota set of high-signal alerts ek large set of noisy alerts se zyada effective hai, chahe har noisy alert individually well-intentioned hi kyun na ho.

**Q8: Liveness probe aur readiness probe mein kya difference hai, aur inhe conflate karna kaunsa real outage cause karta hai?**
Ek liveness probe poochta hai "kya ye process restart hona chahiye" (sirf tab fail hota hai jab wo genuinely broken/hung ho); ek readiness probe poochta hai "kya ye process abhi traffic receive karna chahiye" (fail hota hai jab wo alive hai but temporarily ready nahi hai, e.g., abhi bhi warm up ho raha hai). Inhe conflate karna orchestrator ko un processes ko kill karwa deta hai jo bas briefly busy the ya start ho rahe the, ek transient, self-recovering condition ko ek unnecessary restart loop aur outage mein badalte hue.

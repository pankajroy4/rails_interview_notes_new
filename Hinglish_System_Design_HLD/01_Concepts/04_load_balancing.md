# Load Balancing

## Ek load balancer kya karta hai aur yeh kyun zaroori hai

Ek **load balancer (LB)** servers ke ek pool ke saamne baithta hai aur incoming requests ko unke beech distribute karta hai. Yeh clients ko ek single, stable entry point deta hai (ek IP/domain) jabki actual work uske peeche kayi machines mein spread hota hai.

Iske bina: clients ko har server ke baare mein individually pata hona chahiye hota (fragile — kya hoga jab ek server add, remove, ya die ho jaaye?), aur koi bhi single server usse zyada traffic se overwhelm ho sakta hai jitna woh handle kar sakta hai jabki doosre idle baithe hon. Ek load balancer dono problems solve karta hai: yeh pool ki internal topology ko clients se hide kar deta hai, aur yeh actively load spread karta hai taaki koi single server bottleneck na bane (ya gir na jaaye) jabki pool mein kahin aur capacity available ho.

**Important nuance**: server pool se single point of failure hataane ke liye ek load balancer introduce karna bas single point of failure ko load balancer par hi move kar deta hai — agar LB die ho jaaye, toh uske peeche ke sabhi servers unreachable ho jaate hain chahe woh sab healthy hi kyun na ho. Isliye LB ko khud highly available banana zaroori hai, typically in tareekon se:

- **Active-passive LB pairs**: ek standby LB primary ko monitor karta hai aur agar primary fail ho jaaye toh (ek floating/virtual IP ke through) takeover kar leta hai.
- **DNS round-robin across multiple LBs**: kayi independent load balancer instances sab same DNS name ke under publish kiye jaate hain, isliye ek client ko in mein se ek diya jaata hai, aur ek ke lose hone se entry point poori tarah down nahi hota.

## Yeh important kyun hai

Real systems proper load balancing ke bina specific, visible tareekon se fail hote hain:

- **Hot-spotting**: balancing ke bina, requests sab ek hi server par land kar sakte hain (jaise, DNS cache ke over naive round-robin ki wajah se, ya ek sticky client ki wajah se) jabki doosre idle baithe rehte hain — woh ek server us load ke under timeout ya crash ho jaata hai jise pool as a whole easily absorb kar sakta tha.
- **Server failure ka graceful handling na hona**: agar ek app server crash ho jaaye aur uske saamne koi health-check-aware LB na ho, toh incoming requests ka ek fraction dead server par hi route hota rehta hai aur fail hota rehta hai, instead of automatically sirf healthy servers par route hone ke.
- **LB khud ek unplanned single point of failure ban jaata hai**: teams availability fix karne ke liye ek load balancer add kar dete hain, phir bhool jaate hain ki LB ko khud bhi redundancy chahiye — aur ek single LB outage uske peeche ki poori perfectly healthy fleet ko down kar deta hai.

## L4 vs L7 Load Balancing

Load balancers network stack ke different layers par operate karte hain, aur layer decide karti hai ki unke paas routing ke liye kya information available hai.

| | L4 (Transport Layer) | L7 (Application Layer) |
|---|---|---|
| Operate karta hai | IP address aur port par | Full HTTP request content par — path, headers, cookies, method, body |
| Awareness | Protocol-agnostic — payload parse nahi karta, bas packets/connections forward karta hai | Protocol-aware — HTTP (ya gRPC, WebSocket, etc.) samajhta hai |
| Speed / CPU cost | Faster, kam CPU overhead (payload inspection nahi) | Slower, zyada CPU cost (request terminate/parse karna padta hai) |
| Routing intelligence | Basic — sirf IP/port se route karta hai | Smart — `/api/orders` ko ek service par aur `/api/users` ko doosri service par route kar sakta hai, cookie ke basis par route kar sakta hai, header se A/B testing kar sakta hai |
| Typical use | High-throughput, protocol-agnostic traffic (jaise, raw TCP services, database traffic) | Web/API traffic jahan routing decisions request content par depend karte hain |

Concrete implication: ek L4 LB URL path ke basis par route nahi kar sakta (yeh kabhi HTTP request ko dekhta hi nahi, sirf IP/port ko), toh agar aapko same public endpoint se `/checkout` aur `/search` ko different backend services par bhejna hai, toh aapko ek L7 LB chahiye hoga (ya ek L7 layer, jaise ek API Gateway, ek L4 LB ke downstream).

## Load Balancing Algorithms

| Algorithm | Kaise kaam karta hai | Kab appropriate hai |
|---|---|---|
| Round robin | Requests servers ko fixed rotating order mein distribute hote hain | Servers capacity mein roughly equal hain aur requests cost mein roughly equal hain |
| Weighted round robin | Round robin jaisa hi, lekin zyada capacity wale servers ko proportionally zyada requests milte hain | Server pool heterogeneous hai (kuch bade/faster machines doosron se) |
| Least connections | Naya request us server par jaata hai jiske paas fewest active connections hain | Request durations bahut vary karte hain — isse already-busy server par zyada kaam pile hone se bachta hai |
| Least response time | Naya request us server par jaata hai jiske paas lowest recent response time ho (aur/ya fewest active connections) | Aap actively un servers ko favor karna chahte ho jo abhi sabse better perform kar rahe hain, sirf least loaded nahi |
| IP hash | Client ka IP hash kiya jaata hai taaki consistently same server par map ho | Bina external session storage ke ek given client ko same server par rakhne ka simple tareeka chahiye |
| Consistent hashing | Requests/keys ek hash ring par map hote hain taaki jab ek server add/remove ho, sirf ek small fraction of mappings change ho (instead of almost sab, jaisa plain modulo hashing mein hota hai) | Nodes ka ek changing set ke across requests ya data distribute karna minimal reshuffling ke saath — yeh `database_scaling.md` aur `caching.md` mein depth mein cover kiya gaya hai, kyunki yeh consistent-hash-based sharding aur cache node distribution ka backbone hai; yahan sirf ek routing option ki tarah introduce kiya gaya hai |

## Health Checks

Ek load balancer failure ke around tabhi route kar sakta hai jab use pata ho ki kaunse servers actually healthy hain.

- **Active health checks**: LB proactively har server ko periodic requests bhejta hai (jaise, `GET /health`) aur agar woh correctly respond karna band kar de ya timeout ho jaaye toh use unhealthy mark kar deta hai. Yeh failures ko tab bhi catch karta hai jab uss server par abhi koi real traffic hit nahi ho raha.
- **Passive health checks**: LB real production traffic observe karta hai aur agar us par jaane wale actual requests fail ya timeout hone lagte hain toh server ko unhealthy mark kar deta hai. Real-world behavior ko directly reflect karta hai, lekin definition se sirf real requests suffer hone ke baad hi failure detect karta hai.

Dono saath mein matter karte hain: active checks ek dead server ko customer requests fail hone se pehle hi catch kar lete hain; passive checks subtler failures catch karte hain (jaise, ek server jo ek trivial `/health` endpoint par theek respond karta hai lekin actually heavier real requests par fail ho raha hai) jise ek shallow active check miss kar deta.

## Sticky Sessions (Session Affinity)

**Sticky sessions**: load balancer ek given client ki sabhi requests ko unke session ki duration ke liye same backend server par route karta hai (commonly ek cookie ya IP hash ke through).

**Yeh kabhi-kabhi kyun zaroori hoti hai**: agar ek server session state ko apni khud ki local memory mein rakhta hai (jaise, ek shopping cart shared store ke bajaye in-process hold ki gayi ho), toh us client ko *zaroor* usi server ko hit karte rehna padega, warna unka session data gayab ho jaata dikhega jab koi doosra server unki agli request handle kare.

**Yeh modern design mein generally kyun avoid ki jaati hai**: sticky sessions horizontal scaling aur load balancing ke core benefit ko undermine kar deti hain — agar bahut saare "stuck" clients wala ek server overloaded ho ya die ho jaaye, aap freely uska load redistribute nahi kar sakte (ya unke users apna session state poori tarah lose kar dete hain). Preferred alternative hai services ko **stateless** design karna: session state ko ek shared, fast store jaise Redis mein externalize kar dena jise koi bhi server instance read kar sake, taaki koi bhi request kisi bhi server par ja sake aur identical behavior mile. Isse LB purely load/health ke basis par balance karne ke liye free rehta hai, bina "kaunse server ke paas already is user ka state hai" se constrained hue.

## Load Balancers Kahan Baithte Hain

```text
        clients
           |
           v
          DNS  (resolve hota hai kayi LB IPs mein se ek par / ek GSLB decision)
           |
           v
   +----------------+
   |  Load Balancer  |  (active-passive pair, ya DNS round-robin ke peeche multiple)
   +--------+--------+
            |
   +--------+---------+---------+
   |        |         |         |
   v        v         v         v
 +-----+  +-----+   +-----+   +-----+
 | App |  | App |   | App |   | App |
 | Srv |  | Srv |   | Srv |   | Srv |
 +-----+  +-----+   +-----+   +-----+
```

Load balancers sirf public edge par nahi hote. Yeh commonly yahan bhi baithte hain:

- **Database read replicas ke saamne** — read queries ko kayi replicas mein spread karna taaki koi single replica poora read traffic na le.
- **Internal microservices ke beech** — service A ka service B ko call karna often ek load balancer (ya same kaam karne wala service-mesh sidecar) se guzarta hai taaki B ko A ke liye transparently kayi instances mein scale kiya ja sake.

## Trade-offs / Kab kya use karein

| Choice | Trade-off |
|---|---|
| L4 LB | Fast, protocol-agnostic, cheap — lekin content-aware routing decisions nahi le sakta |
| L7 LB | Smart, content-aware routing — lekin per request zyada CPU cost aur thodi latency add karta hai |
| Round robin | Simple, koi state track nahi karna — lekin actual server load ignore karta hai, isliye uneven request costs se imbalance hota hai |
| Least connections | Real load ke hisaab se adapt karta hai — lekin LB ko har server ka connection state track karna padta hai, thoda zyada overhead |
| Sticky sessions | In-memory state ko chalu rakhne ka simple tareeka — lekin "server as single point of failure for its users" problem wapas laata hai jise load balancing hataane ke liye bani thi |
| Externalized session state (jaise, Redis) | Servers ko stateless aur freely interchangeable rakhta hai — lekin ek extra network hop aur shared store ki apni availability par dependency add karta hai |

## Interview Tips

Load balancing questions test karte hain ki aapko pata hai ki ek LB koi magic box nahi hai jo aap ek baar draw kar do aur phir kabhi mention na karo — interviewers sunna chahte hain ki aap reason karo ki *kis basis par* woh route kar raha hai (L4 vs L7) aur *kaise* (kaunsa algorithm, aur woh us traffic pattern ke liye kyun fit hai jo aapne describe kiya). Ek common trap hai bina trade-off acknowledge kiye sticky sessions propose karna — ek strong answer ya toh ise explicitly justify karta hai (jaise, "hum abhi ke liye session state in-memory rakh rahe hain, isliye humein affinity chahiye") ya state ko externalize karke proactively avoid karta hai. Yeh bhi expect karo ki aapse poocha jaaye "agar load balancer khud down ho jaaye toh?" — active-passive / DNS ke peeche multiple-LBs wala answer ready rakhna yeh dikhata hai ki aap LB ko inherently infallible nahi maan rahe. Aakhir mein, yeh mention karna ki load balancers DB replicas ke saamne aur internal services ke beech bhi appear hote hain (sirf public edge par nahi) yeh signal karta hai ki aap poori architecture ke baare mein soch rahe ho, sirf entry point ke baare mein nahi.

## Quick Recall — Self-Test

**Q1: Apne server pool ke saamne ek single load balancer add karna aapki availability problem ko fully solve kyun nahi karta?**
Yeh server pool ko single point of failure hone se toh hata deta hai lekin load balancer ko khud ek naya single point of failure bana deta hai — agar woh ek LB down ho jaaye, uske peeche ka har healthy server unreachable ho jaata hai. LB ko actually is gap ko close karne ke liye apni khud ki redundancy chahiye (active-passive pair, ya DNS ke peeche multiple LBs).

**Q2: Ek L7 load balancer kya kar sakta hai jo ek L4 load balancer fundamentally nahi kar sakta, aur kyun?**
Ek L7 LB actual HTTP request content ke basis par route kar sakta hai — path, headers, cookies (jaise, `/api/orders` ko ek service par aur `/api/search` ko doosri par bhejna). Ek L4 LB sirf IP/port par operate karta hai aur payload ko kabhi inspect nahi karta, isliye use HTTP-level information ki koi visibility hi nahi hoti route karne ke liye.

**Q3: "Least connections" plain round robin se kab better choice hoga?**
Jab request costs significantly vary karte hain — round robin regardless rotate karta hai chahe request "expensive" ho ya nahi, isliye ek server ke paas kayi long-running requests ho sakte hain jabki doosra idle baitha ho. Least connections naye requests ko actively us server par route karta hai jiske paas currently sabse kam in-flight connections hain, real load ke hisaab se adapt karta hai.

**Q4: Active aur passive health checks mein kya difference hai, aur production systems typically dono kyun use karte hain?**
Active checks proactive pings/polls hain jo LB ek schedule par server health test karne ke liye bhejta hai, real traffic ke bina bhi. Passive checks actual production traffic observe karte hain aur server ko unhealthy flag karte hain jab real requests fail hone lagein. Dono matter karte hain kyunki active checks ek fully dead server ko fast catch kar lete hain, jabki passive checks aise failures catch karte hain jo sirf real request patterns ke under dikhte hain jo ek shallow health endpoint reveal nahi karega.

**Q5: Sticky sessions modern service design mein generally discourage kyun ki jaati hain, aur standard alternative kya hai?**
Yeh ek client ko ek specific server se tie kar deti hain, jo load balancing ki freely load redistribute karne ki ability ko undermine kar deta hai aur iska matlab hai us server ke marne se us client ka session lose ya strand ho sakta hai. Standard alternative hai services ko stateless banana session state ko ek shared store jaise Redis mein externalize karke, taaki koi bhi server kisi bhi client ki request serve kar sake.

**Q6: Public-facing edge ke alawa, do aur jagahein batao jahan architecture mein load balancers commonly appear hote hain.**
Ek database ke read replicas ke saamne (unke beech read queries spread karna), aur internal microservices ke beech (taaki ek calling service transparently kisi scaled-out pool of instances of the service se baat kar sake jispar woh depend karti hai).

**Q7: Consistent hashing kaunsa problem solve karta hai jo plain round robin ya simple modulo hashing nahi karte, high level par?**
Jab backend nodes ka set change hota hai (ek node add ya remove hota hai), consistent hashing sirf ek small fraction of keys/requests ko different nodes par remap karta hai, jabki simple modulo-based hashing lagbhag sab kuch remap kar deta hai — consistent hashing pool ko scale up ya down karne se hone wali disruption ko minimize karta hai.

**Q8: Redundancy ke liye do LBs deploy kiye gaye hain, DNS round-robin use karte hue unke beech. Iska failover trade-off ek floating IP wale active-passive pair ke against kya hai?**
DNS round-robin failover DNS TTL se bound hota hai — jin clients ke paas ab-dead LB ka cached record hai woh TTL expire hone tak use hi try karte rehte hain, isliye failover instant nahi hota. Ek floating IP wala active-passive pair faster fail over kar sakta hai kyunki IP khud DNS cache expiry ka wait kiye bina standby ko move ho jaata hai, halaanki isme active-passive mechanism ka reliable aur failure detect karne mein fast hona zaroori hai.

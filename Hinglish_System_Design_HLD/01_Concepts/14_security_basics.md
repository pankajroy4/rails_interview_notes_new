# Security Basics

## Why it matters

Har system design interview eventually "tumhe kaise pata chalega ki is API ko kaun call kar raha hai, aur tum use abuse hone se kaise roken ge" ko touch karta hai. Yahaan achha karne ke liye tumhe security engineer banne ki zaroorat nahi hai — tumhe recurring concepts ke ek chhote se set ka correct mental model chahiye (authentication vs authorization, session vs token auth, rate limiting, encryption) taaki jab interviewer pooche "is endpoint ko hammer hone se kaise roken ge" ya "client apni pehchaan kaise prove karta hai," to tumhare paas ek precise, confident answer ho, "kuch security add kardo" ki taraf ek vague gesture nahi. Ye same concepts directly un production Rails apps mein bhi matter karte hain jo tum already operate karte ho — ye file un instincts ke upar vocabulary layer deti hai jo tumhare paas already honge (e.g., tumne `devise` ya JWTs use kiya hoga, tumne ek API rate-limit ki hogi, tum already sab kuch HTTPS pe serve karte ho).

## Authentication vs Authorization

**Authentication (AuthN)** answer karta hai "tum kaun ho?" — identity prove karna. Ek username aur password (ya ek passkey, ya ek OAuth flow) se login karna authentication hai: iske end mein, system ko pata hota hai ki *kaunsa* user requests kar raha hai.

**Authorization (AuthZ)** answer karta hai "tumhe kya karne ki permission hai?" — permission, ek known identity ke given. Ek regular user ke roop mein logged in hote hue `/admin/users` hit karne pe `403 Forbidden` milna authorization hai: system ko exactly pata hai tum kaun ho, usne bas decide kiya hai ki tumhare paas us action ke rights nahi hain.

Ye separate concerns aur separate failure modes hain: ek system flawless authentication (rock-solid login) rakh sakta hai aur phir bhi data leak kar sakta hai agar authorization checks missing hon (koi bhi logged-in user ek ID guess karke dusre user ke private endpoint ko hit kar sakta hai) — us class ke bug ko **broken access control** kehte hain, aur ye sabse common real-world security failures mein se ek hai. Inhe hamesha ek design mein do distinct checks ki tarah model karo, ek blended "kya ye request OK hai" step ki tarah nahi.

| | Authentication | Authorization |
|---|---|---|
| Question | Tum kaun ho? | Tumhe kya karne ki permission hai? |
| Example | Password se login karna | Logged in hote hue `/admin` se block hona |
| Failure mode | Koi dusre user ko impersonate kar leta hai | Ek legitimate user aisa data/actions access kar leta hai jo use nahi karna chahiye |
| Typically happens | Ek baar per session/token issuance | Har request pe, per resource/action |

## Session-based auth vs Token-based auth (JWT)

Dono ye answer karte hain "ek baar user login ho jaaye, to har subsequent request kaise prove kare ki wo kaun hai bina har baar password dobara bheje?" — ye is baat mein differ karte hain ki "ye user logged in hai" state kahaan rehti hai.

**Session-based auth**: login ke baad, server ek session record banata hai (server-side state — typically ek DB mein ya Redis jaisi fast store mein) jo ek random session ID se keyed hota hai, aur wo ID client ko ek cookie ke roop mein bhejta hai. Har request pe, client cookie wapas bhejta hai, aur server session ID lookup karke jaan leta hai ki kaun logged in hai.

- Revocation trivial hai: session record ko server-side delete kardo, aur user instantly everywhere se logged out ho jaata hai.
- Ya to **sticky sessions** chahiye (load balancer hamesha ek given user ko us hi server pe route kare jo unki session memory mein hold karta hai — `04_load_balancing.md` dekho) ya ek **shared session store** (Redis/DB jo har server se reachable ho) taaki koi bhi server kisi bhi session ko validate kar sake. Sticky sessions server-affinity ka ek form reintroduce karti hain jo horizontal scaling aur failover ko complicate karti hai; ek shared store isse avoid karti hai but chalane ke liye ek aur piece of infrastructure hai aur har request pe ek lookup add karti hai.

**Token-based auth (JWT — JSON Web Token)**: login ke baad, server ek signed token issue karta hai jisme user ki identity aur claims (e.g., user ID, roles, expiry) directly token ke andar contained hote hain. Client har request pe token bhejta hai (commonly ek `Authorization` header mein), aur koi bhi server signing key/secret use karke ise verify kar sakta hai — koi database lookup nahi, koi shared session store nahi, kyunki token **self-contained aur stateless** hai.

JWT structure, us level pe jo interview ke liye chahiye: `header.payload.signature`, teen base64url-encoded segments dots se separated.
- **Header**: metadata, e.g. kaunsa signing algorithm use hua.
- **Payload**: claims — arbitrary data jaise user ID, roles, expiry time. Jiske paas bhi token hai wo padh sakta hai (ye encoded hai, encrypted nahi), isliye isme kabhi secrets mat daalo.
- **Signature**: server ne ek secret (ya private key) use karke cryptographically sign kiya hota hai, isliye corresponding secret/public key hold karne wala koi bhi server verify kar sakta hai ki token tamper nahi hua, bina session ke baare mein kuch bhi store kiye.

Core trade-off: JWTs shared-state requirement remove kar dete hain (stateless, horizontally scaled services ke liye great, aur cross-service/cross-domain auth ke liye), but ek token **expire hone se pehle revoke nahi ho sakta** — kyunki verification kisi central store ko consult nahi karta, ek live token "delete" karne ki koi single jagah nahi hai. Mitigations, interview mein explicitly naam lene layak:
- Expiry short rakho (minutes) aur ek longer-lived **refresh token** issue karo naye short-lived tokens silently obtain karne ke liye — ek leaked token ke damage window ko limit karta hai.
- Rare "abhi hi revoke karna hai" case ke liye (e.g., ek compromised account) revoked token IDs ki ek server-side **blocklist** maintain karo — ye us ek check ke liye ek shared store reintroduce karta hai, JWT ki statelessness ka kuch hissa revoke karne ki ability ke against trade karte hue.

| | Session-based | Token-based (JWT) |
|---|---|---|
| State kahaan hai? | Server-side (session store) | Client-side (token ke andar) |
| Revocation | Instant — record delete karo | Hard — expiry ka wait karna padta hai, ya ek blocklist maintain karni padti hai |
| Servers ke across scaling | Sticky sessions ya shared store chahiye | Koi bhi server independently verify kar sakta hai (stateless) |
| Per-request cost | Session store ke against ek lookup | Sirf signature verification (koi I/O nahi) |
| Good fit | Single service/app, instant revocation chahiye | Multiple services/APIs, cross-domain, mobile clients |

### Ek JWT structurally kaisa dikhta hai

```text
  header              payload                       signature
 (algorithm)      (claims: user id, role, exp)   (proves it wasn't tampered with)
┌──────────┐    ┌──────────────────────────┐    ┌─────────────────────┐
│eyJhbGciOi│ .  │eyJ1c2VyX2lkIjo0ODIxLCJyb│ .  │SflKxwRJSMeKKF2QT4fwp│
│Mi5In0    │    │xlIjoiYWRtaW4ifQ         │    │MeJf36POk6yJV_adQssw5c│
└──────────┘    └──────────────────────────┘    └─────────────────────┘
     base64url            base64url                  HMAC/RSA signature
   (not encrypted — decodable by anyone; never put secrets in the payload)
```

Shared secret hold karne wala (HMAC-style signing) ya public key hold karne wala (RSA/ECDSA-style signing) koi bhi server independently header+payload ke upar signature recompute/verify kar sakta hai, ye confirm karte hue ki token ek trusted authority ne issue kiya tha aur alter nahi hua — bina kabhi us server se contact kiye jisne originally ise issue kiya tha.

### Passwords ke specifically baare mein ek note

Password se authentication ke liye kuch store karna padta hai jiske against password check kiya jaaye — aur wo cheez kabhi plaintext password khud nahi honi chahiye. Passwords **hashed** store hote hain (ek one-way function jaise bcrypt ya Argon2 se pass karke, jisme ek per-user random **salt** mix kiya jaata hai taaki same password wale do users same stored hash produce na karein, aur taaki precomputed "rainbow table" lookups kaam na karein). Login phir submitted password ko stored salt se dobara hash karta hai aur hashes compare karta hai, plaintext kabhi compare nahi karta. Ye ek detail hai jo ready rakhna worthwhile hai agar interviewer pooche "credentials kaise store karte ho," halaanki ye rarely ek system design interview ka focus hota hai (ye architecture-level detail se zyada ek security-review-level detail hai).

## OAuth2, mental-model level pe

**OAuth2** ek protocol hai **delegated authorization** ke liye: ye ek user ko ek third-party application ko unka password diye bina, dusri service pe unke data tak limited access grant karne deta hai.

Canonical example hai "Login with Google" ya "Is app ko apne Google Calendar tak access karne do": tumhe Google pe redirect kiya jaata hai, tum directly Google mein login karte ho (third-party app tumhara Google password kabhi nahi dekhti), tum access ka ek specific scope approve karte ho ("tumhare calendar events padhne do"), aur Google ka **authorization server** third-party app ko wapas ek **access token** issue karta hai. App phir us access token ka use tumhari taraf se Google ke APIs call karne ke liye karta hai, jitna scope tumne approve kiya utna limited, aur typically ek limited time ke liye.

Key actors, conceptually:
- **Resource owner**: tum, wo user jinka data hai.
- **Client**: third-party app jo access request kar rahi hai.
- **Authorization server**: tumhare access approve karne ke baad tokens issue karta hai (e.g., Google ka login/consent screen).
- **Resource server**: wo API jo actually data hold karti hai aur access token accept karti hai (e.g., Google Calendar ki API).

System design interview ke liye tumhe har OAuth2 grant type enumerate karne ki zaroorat nahi hai — mental model jo matter karta hai ye hai: **authentication authorization server ko identity prove karta hai (tum Google mein login karte ho), aur OAuth2 ka kaam authorization hai — ek app ko tumhari taraf se ek scoped, revocable token ke saath act karne dena, kabhi bhi underlying service ke liye tumhare credentials dekhe bina.**

### OAuth2 flow, ek diagram ke shape mein

```text
   user            third-party app          Google (auth server)      Google API (resource server)
    │                     │                         │                          │
    │  "log in with       │                         │                          │
    │   Google" click     │                         │                          │
    │────────────────────►│                         │                          │
    │                     │  redirect to Google      │                          │
    │◄──────────────────────────────────────────────│                          │
    │  logs in + approves scope, directly on Google's page (app never sees the password)
    │────────────────────────────────────────────────►                          │
    │                     │   authorization code / access token issued         │
    │                     │◄────────────────────────│                          │
    │                     │   calls API using the access token                 │
    │                     │─────────────────────────────────────────────────────►
    │                     │◄─────────────────────────────────────────────────────
    │                     │   scoped data returned                              │
```

Interview mein explicitly state karne layak critical detail: password sirf Google ke apne page pe enter hota hai, third-party app pe kabhi nahi — app ko sirf ek scoped, revocable token milta hai, credentials nahi.

## Rate limiting algorithms

Rate limiting cap karta hai ki ek client ek given time window mein kitne requests kar sakta hai, ek system ko abuse, runaway clients, aur traffic spikes se protect karte hue. Full worked design (ise enforce kahaan karein — client, edge, ya per-service; kis pe key karein — IP, user, API key; ek throttled client ko kya return karein) **`02_Interview_Questions/02_rate_limiter.md`** mein hai. Yahaan wo algorithm-level vocabulary hai jo isme jaane se pehle chahiye.

**Fixed window counter**: time ko fixed windows mein divide karo (e.g., 1-minute buckets), har window ke liye ek counter rakho, limit hit hote hi requests reject karo, window boundary pe zero reset karo. Simple, cheap (per client per window ek counter), but isme ek real **boundary-burst problem** hai: ek client ek window ke last instant mein full limit ke requests bhej sakta hai, phir immediately agle window ke first instant mein full limit dobara bhej sakta hai — e.g., ek 100 req/min limit 0:59 pe 100 requests hone deti hai aur 1:00 pe aur 100, yaani 2 second se kam mein 200 requests, intended rate se kaafi zyada.

```text
window 1 [0:00 - 1:00]         window 2 [1:00 - 2:00]
...............|████████|      |████████|...............
            100 reqs at 0:59    100 reqs at 1:00
            = 200 reqs in ~1 second, limit "respected" per window
```

**Sliding window log**: har client ke har request ka exact timestamp store karo; ek naye request ko check karne ke liye, count karo kitne stored timestamps last window (e.g., last 60 seconds) ke andar aate hain, purane discard karte hue. Perfectly accurate — koi boundary artifact nahi — but memory-heavy hai, kyunki ye per client ek single counter ke bajaye har individual request ka timestamp store karta hai.

**Sliding window counter**: ek practical approximation jo har timestamp store karne se bachta hai. Fixed-window counters rakho (naive approach jaise) but, ek request check karte waqt, *previous* window ke count ko weight karo is hisaab se ki wo kitna trailing window se overlap karta hai abhi bhi — e.g., agar tum current window mein 25% andar ho, to previous window ke requests ka 75% count karo plus current window ka 100%. Ye boundary-burst problem ko ek full log se kaafi kam memory ke saath smooth kar deta hai — real systems ke liye ek achha default.

**Token bucket**: ek bucket `N` tokens tak hold karta hai aur ek steady rate pe refill hota hai (e.g., 10 tokens/second); har request ek token consume karta hai, aur bucket empty hone pe requests reject hote hain. Kyunki bucket `N` tokens tak hold kar sakta hai, ek client jo idle raha ho instantly `N` requests tak burst kar sakta hai, phir steady refill rate pe throttle ho jaata hai — ek perfectly flat rate ke bajaye controlled burstiness allow karta hai, jo ek hard cap se real traffic patterns ke saath better fit hota hai.

```text
   refill: +1 token/100ms
        ┌─────────────┐
        │ ● ● ● ● ●   │  bucket (capacity 5)
        └─────────────┘
  request arrives → consume 1 token → allowed
  bucket empty → request rejected until next refill
```

**Leaky bucket**: incoming requests queue hote hain aur ek constant, fixed rate pe process (leak out) hote hain, incoming traffic kitna bhi bursty kyun na ho — ek bucket jaisa jisme neeche ek chhota hole ho: paani (requests) fast pour ho sakta hai, but ye sirf ek fixed rate pe drain hota hai, aur agar wo drain hone se fast pour ho, bucket overflow ho jaata hai (requests drop ho jaate hain). Ye bursty traffic ko ek steady outflow mein smooth karta hai, kisi bhi burst allow karne se zyada ek constant processing rate ko priority deta hai — token bucket ke opposite emphasis, jo explicitly bucket size tak bursts allow karta hai.

| Algorithm | Accuracy | Memory cost | Bursts allow karta hai? |
|---|---|---|---|
| Fixed window counter | Low (boundary burst) | Bahut kam (1 counter) | Haan, unintentionally, boundaries pe |
| Sliding window log | Exact | High (har timestamp) | Nahi |
| Sliding window counter | Achha approximation | Kam | Thoda, smoothed |
| Token bucket | Design se approximate | Kam | Haan, intentionally, bucket size tak |
| Leaky bucket | Design se approximate | Kam | Nahi — constant outflow enforce karta hai |

## Encryption basics

**Encryption at rest** disk pe stored data ko protect karta hai (ek database, ek backup, ek object storage bucket) — agar kisi ko storage medium tak physical ya filesystem access mil jaaye, decryption key ke bina data unreadable hai. **Encryption in transit** network ke over move hote hue data ko protect karta hai (client se server, service se service) — primarily **TLS** (Transport Layer Security, wo protocol jo HTTPS ke peeche hai) ke through. Ye alag threats ke against protect karte hain aur tumhe dono chahiye: at-rest encryption help nahi karta agar koi attacker unencrypted network traffic sniff kar le, aur in-transit encryption help nahi karta agar koi ek unencrypted database backup churaa le.

**Symmetric encryption**: ek hi key encrypt aur decrypt dono karti hai. Fast hai, isliye ye bulk data ke liye use hota hai (ek request ka actual payload, ek encrypted database column). Hard problem key distribution hai — dono parties ko same secret key chahiye, aur us key ko dono sides tak ek insecure channel ke over safely pahunchana non-trivial hai.

**Asymmetric encryption**: ek key *pair* — ek public key (kisi ke saath bhi share ho sakti hai) aur ek private key (secret rakhi jaati hai). Public key se encrypt kiya gaya data sirf matching private key se decrypt ho sakta hai. Symmetric encryption se slower hai (zyada computationally expensive), isliye ye bulk data directly encrypt karne ke liye use nahi hota — ye ek symmetric key ko securely establish/exchange karne ke liye use hota hai, jo phir actual bulk encryption karti hai.

**TLS handshake, high level pe**: client aur server asymmetric cryptography use karke ek shared symmetric session key pe agree karte hain (ye symmetric encryption ki key-distribution problem solve karta hai — symmetric key khud ek asymmetric crypto se secured channel ke over exchange hoti hai), aur server ek trusted certificate authority se signed certificate ke through apni identity prove karta hai. Ek baar wo session key establish ho jaaye, baaki actual traffic speed ke liye symmetrically encrypt hota hai. Interview ke liye tumhe poora multi-step protocol nahi chahiye — bas: **asymmetric crypto ek shared secret bootstrap karta hai; symmetric crypto uske baad heavy lifting karta hai**, tumhe asymmetric key exchange ki security aur symmetric bulk encryption ki speed dono dete hue.

| | Symmetric | Asymmetric |
|---|---|---|
| Keys | Ek shared key | Public/private key pair |
| Speed | Fast | Slow (per byte kaafi zyada compute) |
| Use hota hai | Bulk data encryption | Key exchange, digital signatures, identity verification |
| Hard problem | Key ko safely distribute karna | Secretly distribute karne ko kuch nahi (public key public hai), but scale pe slower |

## DDoS mitigation basics

Ek **DDoS (Distributed Denial of Service) attack** ek system ko ek saath bahut saare sources se traffic se flood karta hai, uski capacity exhaust karne ki koshish mein taaki legitimate users through na aa sakein. Ye ek brief overview hai — deep dive nahi — defense ke standard layers ka:

- **Edge pe rate limiting**: request path mein jitni jaldi ho sake rate limits apply karo (upar dekho) — ideally traffic tumhare application servers tak pahunchne se pehle hi — taaki abusive volume perimeter pe drop ho jaaye backend capacity consume karne ke bajaye.
- **CDN traffic ko absorb/cache kare**: ek CDN (Content Delivery Network) tumhare origin servers ke saamne baithta hai, geographically distributed, aur traffic ka bada volume absorb aur cache kar sakta hai (especially static/cacheable content ke liye) taaki wo tumhare origin tak kabhi pahunche hi na — origin servers sirf wo residual traffic dekhte hain jo CDN cache se serve nahi kar sakta.
- **Web Application Firewall (WAF)**: ek layer jo incoming requests ko known malicious patterns ke liye inspect karti hai (SQL injection attempts, known bad IP ranges, suspicious request shapes) aur unhe application tak pahunchne se pehle block karti hai — ek pattern-matching filter jo tumhare app ke saamne baithta hai, rate limiting se alag (jo volume-based hai, pattern-based nahi).

## Trade-offs

| Decision | Ye choose karo jab... | Isse dhyan rakho |
|---|---|---|
| Session-based auth | Single app/service, instant revocation chahiye (e.g., banking, admin tools) | Horizontally scale karne ke liye sticky sessions ya shared store chahiye |
| JWT | Multiple services/APIs, mobile clients, cross-domain auth | Expiry se pehle revocation hard hai — short expiry + refresh tokens se mitigate karo |
| Token bucket rate limiting | Legitimate bursty usage allow karna chahte ho (e.g., ek user ek page load karta hai jo ek saath kai API calls fire kare) | Bucket capacity carefully size karni padegi — bahut bada limiting purpose ko defeat kar deta hai |
| Leaky bucket rate limiting | Ek strictly smoothed, constant outbound rate chahiye chahe input kitna bhi bursty ho (e.g., ek hard throughput ceiling wale downstream system ko protect karna) | Bursty-but-legitimate traffic queue/drop hota hai bilkul abuse jaisa |

## Interview Tips

- Jab poocha jaaye "is API ko kaise secure karoge," sirf "authentication add karo" mat bolo — explicitly authentication (kaun call kar raha hai) ko authorization (wo kya kar sakte hain) se separate karo, kyunki interviewers us distinction ko sunte hain.
- Agar design mein multiple services involve hon, default JWT/stateless tokens ki taraf jao aur explicitly revocation trade-off aur uska mitigation naam lo (short expiry + refresh tokens) — ye dikhaata hai ki tumhe real cost samajh aati hai, sirf buzzword nahi.
- Rate limiting questions ke liye, sirf ek algorithm naam mat lo — fixed windows ke saath boundary-burst problem ko concretely explain karo, kyunki ye wo detail hai jo genuine understanding dikhaata hai, memorized vocabulary nahi.
- "Data kaise protected hai" poochne pe at-rest aur in-transit dono encryption mention karo — candidates aksar sirf TLS (in-transit) mention karte hain aur at-rest bhool jaate hain, ya vice versa.
- OAuth2 aur DDoS mitigation answers ko conceptual rakho aur jaldi aage badho jab tak interviewer explicitly deeper jaane ko na kahe — ye rarely ek system design interview ka deep-dive focus hote hain.

## Quick Recall — Self-Test

**Q1: Authentication aur authorization ke beech one-sentence distinction kya hai?**
Authentication prove karta hai tum kaun ho (identity); authorization decide karta hai tumhari identity known hone ke baad tumhe kya karne ki permission hai (permissions). Login karna authentication hai; logged in hote hue ek admin endpoint tak access deny hona authorization hai.

**Q2: JWT-based auth session-based auth se revoke karna harder kyun hai?**
Session-based auth session state server-side store karta hai, isliye access revoke karna bas us record ko delete karna hai. Ek JWT self-contained hai aur sirf signature se verify hota hai, koi central lookup nahi — isliye delete karne ko koi single record nahi hai, aur token naturally expire hone tak valid rehta hai jab tak tum extra infrastructure jaise ek blocklist add na karo.

**Q3: OAuth2 kaunsi problem solve karta hai, koi specific grant type naam liye bina describe karo?**
Ye ek user ko ek third-party app ko dusri service pe unke data tak limited, scoped access grant karne deta hai, us service ke liye apna password third-party app ke saath kabhi share kiye bina — authorization server directly user ko authenticate karta hai aur app ko ek scoped access token issue karta hai.

**Q4: Fixed window counter ki boundary-burst problem ko concretely explain karo.**
Kyunki counter fixed time boundaries pe reset hota hai, ek client ek window ke end pe full allowed limit bhej sakta hai aur agle window ke start pe dobara full limit — do back-to-back bursts jo alag windows mein aate hain per-window check pass kar jaate hain, chahe wo almost simultaneously hue hon, intended rate se kaafi zyada.

**Q5: Token bucket leaky bucket se kis cheez ko optimize karne mein alag hai?**
Token bucket bucket ki capacity tak controlled bursts allow karta hai, kyunki idle rehte hue unused tokens accumulate hote hain. Leaky bucket ek constant outflow rate enforce karta hai chahe input kitna bhi bursty ho, sab kuch ek fixed processing rate mein smooth karte hue bursts allow karne ke bajaye.

**Q6: At-rest aur in-transit encryption dono kyun chahiye — kya ek kaafi nahi?**
Ye alag threats ke against protect karte hain: in-transit (TLS) network ke over move hote hue data ko interception se protect karta hai; at-rest stored data ko protect karta hai agar storage medium khud compromise ho jaaye (churaaya hua backup, unauthorized filesystem access). Sirf ek hone se dusra attack surface open reh jaata hai.

**Q7: TLS handshake mein, sirf ek use karne ke bajaye asymmetric aur symmetric encryption dono kyun use karte hain?**
Asymmetric encryption key-distribution problem solve karta hai (bina kisi prior shared secret ke safely ek secret pe agree karna) but bulk data ke liye bahut slow hai. Isliye ye sirf ek shared symmetric session key establish karne ke liye use hota hai, jiske baad actual traffic speed ke liye symmetrically encrypt hota hai — asymmetric ke secure key exchange ko symmetric ki performance ke saath combine karte hue.

**Q8: Yahaan mention kiye gaye DDoS mitigation ke teen standard layers naam lo aur har ek kya karta hai.**
Edge pe rate limiting (app tak pahunchne se pehle excess volume drop karo), ek CDN (traffic ko geographically distributed absorb/cache karta hai taaki wo kabhi origin servers ko hit na kare), aur ek WAF (known malicious patterns match karne wale requests ko inspect aur block karta hai).

# The LLD Interview Framework

Ek repeatable step-by-step approach jo kisi bhi "design X using OOP"
prompt mein use kar sakte ho — Parking Lot, Vending Machine, ATM,
Elevator, Tic-Tac-Toe, jo bhi specific object ho — bina yeh freeze kiye
ki kaha se start karein ya seedha code par rush kiye. Yeh LLD ka woh
equivalent hai jo `System_Design/01_Concepts/16_interview_framework.md`
HLD questions ke liye karta hai; process ka shape similar hai, lekin
substance alag hai: HLD framework steps servers/databases/scaling
trade-offs par khatam hote hain, LLD framework steps classes/interfaces/
methods par khatam hote hain.

## The Framework

Ek realistic 45-minute LLD interview ke liye budget kiya gaya hai. Times
sirf guidance hain, koi rulebook nahi — agar koi step clearly zyada time
lene wala lage toh apne interviewer se scope ke baare mein baat karo.

**1. Functional requirements AUR scope clarify karo (~5 minutes).**
Bas yeh mat list karo ki system kya karta hai — explicitly yeh bhi bolo
ki kya *out of scope* hai. LLD prompts intentionally underspecified hote
hain aur agar aap sab kuch ek saath design karne ki koshish karo toh 45
minutes se kaafi zyada cover karne lag sakte hain. Aise cheeze bolo jaise
"main abhi single-threaded assume kar raha hoon aur agar time raha toh
concurrency ko follow-up ki tarah mention karunga" ya "main ek single
parking lot ke liye design karunga, multi-location chain ke liye nahi,
jab tak aap na chaho." Isse do cheeze hoti hain: yeh aapke design ko
achievably sized rakhta hai, aur yeh interviewer ko dikhata hai ki
aapko pata hai problem ko kaise scope karna hai — ek skill jo woh
explicitly evaluate kar rahe hain, sirf time-saving trick nahi.

**2. Core objects/entities identify karo (~5 minutes).**
Requirements ko wapas padho aur nouns nikal lo — yeh almost hamesha
aapki first-pass class list hoti hai. "Ek parking lot mein spots hote
hain, aur vehicles spots mein park karte hain, aur ticket lete hain" se
directly `ParkingLot`, `ParkingSpot`, `Vehicle`, `ParkingTicket` surface
ho jaate hain. Yeh zor se bolo — "let me pull the nouns out of the
problem statement" ek legible, teachable step hai jise interviewer follow
kar sake, silently kahin se ek class list produce karne ke bajaye.

**3. Inke beech relationships identify karo (~5 minutes).**
Ek class diagram sketch karo — chahe ek rough text/ASCII wala hi ho —
jisme inheritance (is-a), composition (owns, dies with owner), aggregation
(owns, but survives independently), aur association (references, but no
ownership implied) dikhaye. Yeh vocabulary sahi lena khud ek signal hai;
dekho `04_uml_and_class_diagrams.md` iski notation aur in relationship
types ka poora worked breakdown ke liye.

**4. Har class par key behaviors/methods identify karo (~5-8 minutes).**
Har class ke liye, yeh kya *karti* hai, sirf kaunsa data hold karti hai
yeh nahi? Yehi woh jagah hai jaha aap decide karte ho ki kaunsi class
kaunsi responsibility own karti hai — yaha sabse common failure yeh hai
ki poora behavior ek "manager" class par daal diya jaaye (jaise,
vehicle-specific rules ko `ParkingLot` mein cram karna) instead of har
object ko apna behavior own karne dena.

**5. Jaha koi design pattern genuinely help karta ho waha spot karo (~5
minutes).**
Yeh step tab aata hai *jab* aap already objects, relationships, aur
behaviors sketch kar chuke ho — pehle nahi. Jo bhi draw kiya hai use
dekho aur poocho "kya yaha koi `case`/`if` chain hai jise polymorphism
remove kar dega? Kya koi object hai jiska behavior ek internal status
field par depend karta hai? Kya mujhe specific instances mein behavior
add karna hai bina poori class touch kiye?" Pattern ke liye isliye jao
kyunki jo shape aapke paas already hai use uski zaroorat hai, na ki
isliye ki aap dikhana chahte ho ki aapko pattern ka naam pata hai. Poore
catalog ke liye `05_design_patterns_creational.md`,
`06_design_patterns_structural.md`, aur `07_design_patterns_behavioral.md`
cross-reference karo.

**6. Core classes ke liye working code likho (~10-12 minutes).**
Sab kuch nahi — un 2-3 classes ko chuno jo problem ke central challenge
ke liye sabse zyada matter karti hain (Parking Lot mein, yeh `Vehicle`
ki hierarchy aur `ParkingLot#park`/`#unpark` hai; surrounding classes
jaise `ParkingSpot` thinner rakhi ja sakti hain). Zor se bolo ki aap
kaunsi classes ko prioritize kar rahe ho aur kyun, taaki interviewer yeh
sochta na reh jaaye ki aap baaki bhool gaye.

**7. Main use case ko apne code ke against end-to-end walk through karo
(~3-5 minutes).**
Literally ek call trace karo (jaise, "ek Van aata hai, `park` call hota
hai, yeh pehle `:van_spot` try karta hai...") apne actual method bodies
ke through. Yeh step real bugs pakad leta hai (ek off-by-one, ek spot
type mismatch) interviewer se pehle, aur yeh dikhata hai ki aap apne
design ko khud test karte ho, sirf mind mein code compile hote hi victory
declare nahi karte.

**8. Edge cases aur extensibility discuss karo (~5 minutes, often
interviewer-driven).**
"Naya vehicle type kaise add karoge?" "Agar do log exact same time par
park karein toh?" "Multi-floor support kaise add karoge?" Yaha aksar
zyada code likhne ki zaroorat nahi hoti — precisely describe karna ki
kaunsi classes change hongi (ideally: sirf naye, existing mein zero
edits) hi answer hai, aur yeh steps 2-5 achhe se karne ka direct payoff
hai.

```text
 1. Scope        2. Objects       3. Relationships     4. Behaviors
 (5 min)   -->    (5 min)   -->    (5 min)       -->    (5-8 min)
    |                                                        |
    v                                                        v
 8. Edge cases  <--  7. Walk through  <--  6. Write code  <--  5. Patterns
 (5 min)             (3-5 min)             (10-12 min)         (5 min)

 Total: ~45 min. Steps 1-5 are "design," 6-8 are "prove the design works."
 Spending the whole 45 minutes in step 6 (jumping to code early) is the
 single most common way this framework gets skipped under pressure.
```

## Common Mistakes

- **Kisi bhi class structure sketch kiye bina seedha code par jump karna.**
  Productive lagta hai kyunki aap type kar rahe ho, lekin typically aap
  mid-way mein redesign karte hue end up hoge jab koi relationship jo
  aapne socha nahi tha (jaise, "wait, van ko un-park karne se saare 3
  spots kaise free hote hain?") ek diagram par nahi balki ek method body
  ke andar surface hoti hai, jo isse discover karne ki ek bahut zyada
  expensive jagah hai.
- **Ek deep inheritance hierarchy banana jaha composition zyada flexible
  hota.** Ek `Vehicle -> LandVehicle -> WheeledVehicle -> Car` chain jo
  preemptively "shayad zaroorat pade isliye" bana di gayi, woh bina kisi
  payoff ke rigidity add karti hai — har layer ek coupling point hai.
  Shallowest hierarchy prefer karo jo actual requirements satisfy kare,
  aur composition (ek object *ke paas* ek capability hai, ek chote
  collaborator object ke through) ki taraf jao jab behavior ko mix aur
  match karna ho, strictly specialize karne ke bajaye.
- **Kisi design pattern ke liye isliye jaana kyunki aapko woh pata hai,
  na ki isliye ki problem use maang rahi hai.** Pattern-first thinking
  interviewers ke liye ek bahut recognizable failure mode hai — jaise,
  ek Observer ko ek aise design mein force karna jisme koi actual
  notification requirement nahi hai, sirf yeh dikhane ke liye ki aapko
  Observer aata hai. Patterns ko ek specific pain point ka answer hona
  chahiye jo aapne apne hi design mein already identify kiya ho (upar
  step 5), kabhi bhi starting point nahi.
- **Interviewer ke "agar humein X bhi support karna ho toh?" follow-ups
  ko ignore karna instead of design ko live adapt karne ke.** Yeh
  follow-ups hi actual test hain — ek design jo bina rewrite ke ek
  reasonable extension absorb nahi kar sakta, usually iska matlab hai ki
  pehle koi responsibility galat class par daal di gayi thi. Har
  follow-up ko Open/Closed action mein demonstrate karne ka chance treat
  karo, na ki route around karne wali nuisance.
- **Isse HLD question ke saath confuse karna aur databases/servers ke
  baare mein baat karna shuru kar dena jab interviewer classes chahta
  tha.** LLD interviews object design ke baare mein hote hain ek single
  process/codebase ke andar — horizontal scaling ya database sharding ke
  baare mein baat karna jab parking lot ki classes design karne ko kaha
  gaya ho, galat question ka answer dena hai. Dekho
  `01_what_is_lld_and_how_it_differs_from_hld.md` yeh exactly dekhne ke
  liye ki woh boundary kaha hai, aur usse *briefly* kaise bridge karein
  sirf tab jab interviewer explicitly aapko waha lekar jaaye (jaise
  parking lot file ke concurrency/multi-location follow-ups karte hain).
- **Assumptions/scope ko zor se na bolna, jisse over-building ho jaaye.**
  Silently decide kar lena "main multi-floor aur concurrent access aur
  pricing aur reservations sab support karunga" bina pehle scope check
  kiye, yehi wajah hai jisse 45 minutes ek unfinished `ParkingLot` class
  mein gayab ho jaate hain. Scope ko explicitly step 1 mein state karo —
  aur agar interviewer pushback kare toh usse zor se revise karo.

## Design Karte Waqt Kaise Communicate Karein

- **Hamesha zor se socho** — narrate karo ki aap composition ko
  inheritance se zyada *kyun* choose kar rahe ho, ya ek specific pattern
  ke liye kyun ja rahe ho, sirf yeh fact nahi ki aap yeh kar rahe ho. "Main
  `Vehicle` ko ek abstract class bana raha hoon jisme `spots_required` ek
  aisa method hai jo subclasses ko implement karna hi hai, taaki
  `ParkingLot` ko kabhi bhi vehicle type par branch na karna pade" ek
  complete, gradeable sentence hai; chup-chaap same code likhna nahi hai.
- **SOLID principles ka naam explicitly lo jab woh kisi decision ko
  justify karte ho.** "Isse `ParkingLot` closed to modification rehta hai
  jab koi naya vehicle type add hota hai — Open/Closed" "yeh zyada
  extensible hai" se zyada strong, zyada specific statement hai. Poora
  set aur har ek code mein kaise dikhta hai (sirf naam mein nahi) yeh
  janne ke liye dekho `03_solid_principles.md`.
- **Kisi ek area mein deep jaane se pehle interviewer se scope ke baare
  mein check-in karo.** Pricing logic ko poori tarah flesh out karne mein
  10 minutes spend karne se pehle, poocho "kya aap chahte ho main pricing
  par deep jaaun, ya usse ek stub rehne dun aur un-parking par move karun?"
  — isse aap design ke us corner mein over-invest karne se bachte ho jiski
  interviewer ko actually parwaah nahi hai.

## Yeh Interview Questions Folder Se Kaise Map Hota Hai

`02_Interview_Questions/` ki har file isi exact shape ko follow karti
hai: requirements aur scope, phir core objects, phir relationships (ek
class diagram), phir design decisions aur kaunse patterns apply hote hain
aur kyun, phir un classes ke liye code jo sabse zyada matter karti hain,
phir edge cases aur extensibility, phir likely follow-up questions. Yeh
coincidence nahi hai — yehi framework hai, applied. Un files ko work
through karna sirf "worked examples padhna" nahi hai — yeh har baar isi
exact framework ko end-to-end rehearse karna hai, isliye har ek ko ek
timed practice run ki tarah treat karo: sirf problem statement padho,
steps 1-8 khud pehle work through karo, phir file se compare karo.

## Quick Recall — Self-Test

1. **Jab aapko ek LLD prompt diya jaaye, koi bhi code likhne se pehle
   pehla concrete kaam kya karna chahiye?**
   Functional scope clarify karo aur explicitly bolo ki kya out of scope
   hai, phir core nouns ko candidate classes ki tarah extract karo —
   seedha code par jump karna usually iska matlab hai ki baad mein
   redesign karna padega jab requirements mid-implementation surface
   hongi.

2. **Scope ko zor se bolna, actually ek scoped design hone jitna hi
   matter kyun karta hai?**
   Kyunki interviewer yeh evaluate kar raha hai ki aap ek problem ko scope
   down kar *sakte* ho ya nahi, sirf yeh nahi ki aapka final design
   reasonably sized hua ya nahi — ek candidate jo silently scope limit
   karta hai, interviewer ki seat se, uske jaisa hi dikhta hai jo bade
   version ke baare mein kabhi socha hi nahi.

3. **Framework mein kis point par aapko design pattern dhundna chahiye,
   aur usse pehle kyun nahi?**
   Jab objects, relationships, aur behaviors sketch ho chuke hon (step 5,
   step 1 nahi) — kyunki patterns ko ek concrete pain point solve karna
   chahiye jo aapne apne design mein already identify kiya ho, problem par
   force nahi kiya jaana chahiye usse pehle ki aapko pata ho ki uska
   shape actually kya hai.

4. **Ek concrete tell batao jo dikhata ho ki ek design ne bahut zyada
   responsibility ek "manager" class par daal di hai.**
   Woh class doosre object ke type ya status par `if`/`case` branches
   contain karti hai (jaise, `ParkingLot` ka `vehicle.type` par branch
   karna) — woh logic us object par honi chahiye jiska type/status check
   ho raha hai, orchestrate karne wali class par nahi.

5. **"Interviewer ke follow-up questions ko ignore karna" ko sirf ek
   omission ke bajaye mistake kyun treat kiya jaata hai?**
   Follow-ups hi extensibility ka test HAIN, uska distraction nahi — ek
   design jo bina rewrite ke "agar humein X bhi chahiye ho toh?" absorb
   nahi kar sakta, usually iska matlab hai ki pehle koi responsibility
   galat class ko assign hui thi, aur follow-up ko dodge karna exactly
   wahi cheez chhupata hai jo evaluate ki ja rahi hai.

6. **Agar ek LLD interviewer database schemas ya server scaling ke baare
   mein poochna shuru kar de toh aapko kaise respond karna chahiye?**
   Yeh recognize karo ki yeh HLD territory mein ek bridge hai aur us
   transition ko explicitly naam do ("yeh is problem ke distributed-
   systems version mein move kar raha hai") instead of silently ek HLD
   question ko LLD framing use karke answer karne ki koshish karne ke, ya
   uska ulta — dekho `01_what_is_lld_and_how_it_differs_from_hld.md`.

7. **"Main yaha composition use kar raha hoon" aur "main yaha composition
   use kar raha hoon kyunki X" narrate karne mein kya difference hai?**
   Pehla ek fact state karta hai jo interviewer already aapke code mein
   dekh sakta hai; doosra judgment demonstrate karta hai — jo actually
   evaluate ki jaa rahi cheez hai. Hamesha "kyunki" include karo.

8. **`02_Interview_Questions/` ko sirf reference material ke bajaye is
   framework ko practice karne ki tarah kyun describe kiya gaya hai?**
   Kyunki usme har file same requirements-objects-relationships-
   decisions-code-extensibility shape follow karti hai jo yeh framework
   prescribe karta hai — ek ko passively padhna us approach se kam
   sikhata hai jaha aap problem statement ko ek timed prompt ki tarah
   treat karo aur 8 steps khud work through karo file ke answer se
   compare karne se pehle.

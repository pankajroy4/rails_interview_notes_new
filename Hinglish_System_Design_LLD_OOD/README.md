# Low-Level Design / Object-Oriented Design — Zero se Interview-Ready tak

Yeh folder aapki interview prep ka teesra pillar hai, `dsa.rb` aur
`System_Design/` ke saath. Yeh un dono se genuinely alag discipline cover karta hai.

## Yeh `System_Design/` se kaise alag hai

| | DSA (`dsa.rb`) | System Design (`System_Design/`) | LLD / OOD (yeh folder) |
|---|---|---|---|
| Question ka shape | "Algorithm dhoondo" | "WhatsApp ko scale pe design karo" | "Parking Lot ko classes ke roop mein design karo" |
| Design ki unit | Ek function | Services, databases, machines | Classes, interfaces, objects |
| Scale ki concern | Time/space complexity | Millions of users, multiple machines | Single process, correctness & extensibility |
| Test hone wali core skill | Algorithmic reasoning | Distributed-systems trade-offs | OOP principles, real-world entities ko model karna |
| "Good" kaisa dikhta hai | Optimal complexity | Diye gaye constraints ke liye sahi trade-offs | Clean class boundaries, SOLID, design patterns |

Agar koi system design interview poochta hai "10 million users ko kaise handle
karoge," toh wo HLD hai. Agar wo poochta hai "X ke liye classes design karo aur
dikhao ki kal isko kaise extend karoge," toh wo LLD hai — aur yahan load
balancer ya database schema ki taraf jaana bilkul galat instinct hai. Yehi
mistake ek real interview mein bhaari padi thi: ek plain Ruby class jisme kuch
methods the, na koi class hierarchy, na SOLID reasoning, na koi design pattern
— kyunki HLD aur LLD ko kabhi separate skills ke roop mein distinguish hi
nahi kiya gaya tha.

Small aur mid-size product companies (aur FAANG bhi, ek separate round ke
roop mein) LLD hamesha poochti hain, kyunki yeh ek direct proxy hai is baat
ka ki "yeh insaan maintainable code likhega ya nahi," jo day-to-day mein
distributed-systems trivia se zyada matter karta hai.

## 01_Concepts/ — building blocks

| # | File | Kya cover karta hai |
|---|------|-----------------|
| 01 | what_is_lld_and_how_it_differs_from_hld.md | HLD/LLD distinction depth mein, interviewers yeh kyun poochte hain, kaise pehchane ki aapse kaunsa poocha ja raha hai |
| 02 | oop_fundamentals_for_interviews.md | Encapsulation, abstraction, inheritance, polymorphism — jaise yeh actually interviews mein test hote hain, textbook definitions nahi |
| 03 | solid_principles.md | Saare paanch SOLID principles, har ek ke saath ek concrete before/after code example |
| 04 | uml_and_class_diagrams.md | UML class diagrams kaise padhein aur banayein — association vs aggregation vs composition vs inheritance |
| 05 | design_patterns_creational.md | Singleton, Factory Method, Abstract Factory, Builder, Prototype |
| 06 | design_patterns_structural.md | Adapter, Decorator, Facade, Proxy, Composite |
| 07 | design_patterns_behavioral.md | Strategy, Observer, State, Command, Chain of Responsibility, Template Method, Visitor |
| 08 | lld_interview_framework.md | Kisi bhi LLD interview question ke liye step-by-step approach, common mistakes |

## 02_Interview_Questions/ — worked problems

Har file: requirements clarify karna → core objects/entities identify karna →
relationships identify karna (class diagram) → design decisions & use kiye
gaye patterns → working code → edge cases & extensibility → follow-up
questions. Code examples Ruby mein hain taaki aap actually jaise kaam karte
ho waise match ho.

| # | File | Problem |
|---|------|---------|
| 01 | parking_lot.md | Parking lot (multi-spot vehicles, spot types) — flagship, real-interview-tested problem |
| 02 | elevator_system.md | Elevator system (multiple cars, request scheduling) |
| 03 | library_management_system.md | Library management (books, members, holds, fines) |
| 04 | vending_machine.md | Vending machine (purchase flow ke liye state machine) |
| 05 | atm_machine.md | ATM machine (transactions, card/PIN validation) |
| 06 | tic_tac_toe.md | Tic-Tac-Toe (board games, win-condition strategy) |
| 07 | chess_game.md | Chess (piece hierarchy, move validation) |
| 08 | splitwise_expense_sharing.md | Splitwise-style expense splitting (balances, settlement) |
| 09 | movie_ticket_booking_bookmyshow.md | Movie ticket booking, LLD version (classes, infra nahi — contrast `System_Design/02_Interview_Questions/16_ticket_booking_system.md` ke saath) |
| 10 | lru_cache_oop_design.md | LRU Cache ek OOD problem ke roop mein (contrast `dsa.rb` wali DSA version ke saath) |
| 11 | logging_framework.md | Logging framework (log levels, multiple output strategies) |
| 12 | car_rental_system.md | Car rental system (inventory, reservations, pricing strategy) |

## Is folder ko kaise use karein

`01_Concepts` ko ek baar order mein padho. Phir `02_Interview_Questions` ki
har file ke liye, **pehle khud paper pe design karo** — actual classes,
actual method signatures — worked version padhne se pehle. Wahi struggle
hai jo reflex banata hai; kisi aur ka answer pehle padh lena aapko kuch nahi
sikhata jo aap live interview mein reproduce kar sako.

## Status

Stages mein generate ho raha hai. Agar koi file abhi wahan nahi hai, toh
iska matlab hai wo abhi likhi ja rahi hai.

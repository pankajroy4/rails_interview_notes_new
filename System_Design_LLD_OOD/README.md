# Low-Level Design / Object-Oriented Design — From Zero to Interview-Ready

This folder is the third leg of your interview prep, alongside `dsa.rb` and
`System_Design/`. It covers a genuinely different discipline than both of those.

## How this is different from `System_Design/`

| | DSA (`dsa.rb`) | System Design (`System_Design/`) | LLD / OOD (this folder) |
|---|---|---|---|
| Question shape | "Find the algorithm" | "Design WhatsApp at scale" | "Design a Parking Lot as classes" |
| Unit of design | A function | Services, databases, machines | Classes, interfaces, objects |
| Scale concern | Time/space complexity | Millions of users, multiple machines | Single process, correctness & extensibility |
| Core skill tested | Algorithmic reasoning | Distributed-systems trade-offs | OOP principles, modeling real-world entities |
| What "good" looks like | Optimal complexity | Right trade-offs for given constraints | Clean class boundaries, SOLID, design patterns |

If a system design interview asks "how do you handle 10 million users," it's
HLD. If it asks "design the classes for X and show me how you'd extend it
tomorrow," it's LLD — and reaching for a load balancer or a database schema
is the wrong instinct entirely. This is the mistake that cost a real
interview: a plain Ruby class with a few methods, no class hierarchy, no
SOLID reasoning, no design pattern — because HLD and LLD were never
distinguished as separate skills to begin with.

Small and mid-size product companies (and even FAANG, as a separate round)
ask LLD constantly, because it's a direct proxy for "will this person write
maintainable code," which matters more day-to-day than distributed-systems
trivia.

## 01_Concepts/ — the building blocks

| # | File | What it covers |
|---|------|-----------------|
| 01 | what_is_lld_and_how_it_differs_from_hld.md | The HLD/LLD distinction in depth, why interviewers ask it, how to recognize which one you're being asked |
| 02 | oop_fundamentals_for_interviews.md | Encapsulation, abstraction, inheritance, polymorphism — as actually tested in interviews, not textbook definitions |
| 03 | solid_principles.md | All five SOLID principles, each with a concrete before/after code example |
| 04 | uml_and_class_diagrams.md | How to read and draw UML class diagrams — association vs aggregation vs composition vs inheritance |
| 05 | design_patterns_creational.md | Singleton, Factory Method, Abstract Factory, Builder, Prototype |
| 06 | design_patterns_structural.md | Adapter, Decorator, Facade, Proxy, Composite |
| 07 | design_patterns_behavioral.md | Strategy, Observer, State, Command, Chain of Responsibility, Template Method, Visitor |
| 08 | lld_interview_framework.md | The step-by-step approach for ANY LLD interview question, common mistakes |

## 02_Interview_Questions/ — worked problems

Each file: clarify requirements → identify core objects/entities → identify
relationships (class diagram) → design decisions & patterns used → working
code → edge cases & extensibility → follow-up questions. Code examples are
in Ruby to match how you actually work.

| # | File | Problem |
|---|------|---------|
| 01 | parking_lot.md | Parking lot (multi-spot vehicles, spot types) — the flagship, real-interview-tested problem |
| 02 | elevator_system.md | Elevator system (multiple cars, request scheduling) |
| 03 | library_management_system.md | Library management (books, members, holds, fines) |
| 04 | vending_machine.md | Vending machine (state machine for the purchase flow) |
| 05 | atm_machine.md | ATM machine (transactions, card/PIN validation) |
| 06 | tic_tac_toe.md | Tic-Tac-Toe (board games, win-condition strategy) |
| 07 | chess_game.md | Chess (piece hierarchy, move validation) |
| 08 | splitwise_expense_sharing.md | Splitwise-style expense splitting (balances, settlement) |
| 09 | movie_ticket_booking_bookmyshow.md | Movie ticket booking, LLD version (classes, not infra — contrast with `System_Design/02_Interview_Questions/16_ticket_booking_system.md`) |
| 10 | lru_cache_oop_design.md | LRU Cache as an OOD problem (contrast with the DSA version in `dsa.rb`) |
| 11 | logging_framework.md | Logging framework (log levels, multiple output strategies) |
| 12 | car_rental_system.md | Car rental system (inventory, reservations, pricing strategy) |

## How to use this folder

Read `01_Concepts` in order once. Then for every file in
`02_Interview_Questions`, **design it yourself on paper first** — actual
classes, actual method signatures — before reading the worked version. That
struggle is what builds the reflex; reading someone else's answer first
teaches you nothing you can reproduce live in an interview.

## Status

Being generated in stages. If a file isn't there yet, it's still being written.

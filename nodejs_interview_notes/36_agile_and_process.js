/*
===============================================================================================
                       AGILE / SCRUM & ENGINEERING PROCESS
===============================================================================================
(Mirrors my agile_methodology.rb. This is 100% language-agnostic — my Scrum experience transfers
unchanged from Rails to Node. Kept here so the Node folder is self-contained for behavioral rounds.
My resume already says I worked in Agile sprints with Jira + Slack, delivering 10+ features.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: What is Agile, and why over Waterfall?
-----------------------------------------------------------------------------------------------
Answer -> Agile is an iterative, incremental approach: build the product in small chunks, get
feedback frequently, and adapt to change quickly — delivering working software continuously rather
than following a rigid long-term plan. It's preferred over Waterfall because requirements change;
Agile gives continuous feedback, faster delivery, and early issue detection, which lowers risk and
improves customer satisfaction.

  Core values: individuals & interactions over processes; working software over documentation;
  customer collaboration over contract negotiation; responding to change over following a plan.
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Scrum — roles, ceremonies, artifacts
-----------------------------------------------------------------------------------------------
Answer -> Scrum manages work in iterations called SPRINTS (usually 1-2 weeks).
  ROLES:
   - Product Owner: owns + prioritizes the product backlog by business value.
   - Scrum Master: facilitates the process, removes blockers, drives improvement (not a manager).
   - Development Team: builds the increment.
  CEREMONIES:
   - Sprint Planning: pick + estimate backlog items for the sprint.
   - Daily Standup: quick sync — what I did / will do / blockers.
   - Sprint Review: demo the working increment to stakeholders.
   - Retrospective: what went well / what to improve next sprint.
  ARTIFACTS: Product Backlog, Sprint Backlog, the Increment.

  "I've mostly worked in Scrum (Jira + Slack), with Kanban understood conceptually. Day to day:
   plan the sprint, standups, build features with PRs + reviews, demo at review, improve at retro."
*/

/*
-----------------------------------------------------------------------------------------------
Q3: Estimation, stories, and definition of done
-----------------------------------------------------------------------------------------------
Answer ->
  - USER STORIES: "As a <user>, I want <goal> so that <benefit>." Small, vertical slices of value.
  - STORY POINTS: relative effort (often Fibonacci 1,2,3,5,8) capturing complexity + uncertainty,
    not hours. Velocity = points completed per sprint, used for forecasting.
  - DEFINITION OF DONE: agreed checklist before a story is "done" — code reviewed, tests written +
    passing, CI green, docs updated, deployed to staging. This is where my testing/CI discipline
    plugs in (files 20, 32).
  - ACCEPTANCE CRITERIA: concrete pass/fail conditions per story.
*/

/*
-----------------------------------------------------------------------------------------------
Q4: How engineering practices fit Agile (tie it to my technical answers)
-----------------------------------------------------------------------------------------------
Answer -> Agile relies on solid engineering hygiene to actually ship continuously:
  - Small PRs + code review (the automated-review answer, file 32 / my Rails notes).
  - CI on every PR (lint, type-check, tests) as a merge gate (file 32).
  - Trunk-based / short-lived feature branches; feature flags for risky/incomplete work.
  - CD with rolling, zero-downtime deploys (file 26 Q9).
  - Automated tests so you can refactor + release confidently (file 20).
  "Agile cadence works only if the technical foundation — tests, CI/CD, small reviewable PRs — is
   there; that's the discipline I brought to my Rails sprints and carry into Node."
*/

module.exports = {};

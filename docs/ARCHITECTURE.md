Design Goals

Measure structural alignment, not correctness.

No accounts — UUID-only sessions.

Low operational overhead — simple infra, minimal services.

Community-extensible corpus with moderation.

Explicit separation of concerns:

Flutter UI

Django REST API

Structural scoring engine

PostgreSQL (persistent state)

Redis (optional caching / transient state)




---

System Overview

Flutter (Web / Mobile)
        |
        v
Django REST API
        |
        +-- Structural Scoring Engine
        |
        +-- PostgreSQL
        |
        +-- Redis (optional)


---

Core Concepts

1. Run (Session)

Identified by run_uuid

No user accounts

Tracks:

question set filter

answers submitted

scoring results



Runs are lightweight and ephemeral.


---

2. TestCase

Represents a question in the corpus.

Fields include:

title

prompt

expected (optional guidance)

test_set (FK to TestSet)

is_active

tags


Inactive by default when user-submitted.


---

3. TestSet

Logical grouping of test cases.

Used for:

Benchmark sets

Curated philosophical sets

Community sets

Calibration sets


Mobile UI dropdown loads questions filtered by set.


---

4. Result

Represents an answer submission.

Stores:

run_uuid

testcase

provider (human / Claude / GPT / etc.)

output_text

score

score_details

rubric_version



---

Mobile Flow (Current)

1. POST /api/mobile/run/

Returns run_uuid

Accepts optional test_set



2. GET /api/mobile/question

Params:

run_uuid

test_set or test_set_id


Returns next unanswered question in that set



3. POST /api/mobile/preview/

Evaluates structural alignment

Returns:

score (0–100)

band (Eikasia → Noesis)

diagnostics




4. POST /api/mobile/answer/

Persists answer + final score



5. GET /api/mobile/question_sets

Returns available sets + counts

Used to populate dropdown



6. POST /api/mobile/testcase/

Creates new inactive question





---

Structural Scoring Engine

The scoring engine measures structural alignment between question and answer.

It evaluates:

Domain correspondence

Mode alignment (define, explain, argue, evaluate)

Conceptual grounding

Coherence

Lexical diversity

Repetition penalties


Not measured:

Factual correctness

Citations

External truth


Anti-Gaming Measures

Lexical diversity penalty

N-gram repetition penalty

Domain mismatch cap

Default marker cap


All scoring includes rubric_version for future reproducibility.


---

Validation Policy

Default constraints:

Minimum words

Minimum sentences


Validation gates submission, not scoring.

Preview scoring is always available.


---

Moderation

New testcases are inactive by default.

Activated via Django Admin.

Question sets allow curated benchmarking.



---

Infrastructure

Django REST API

PostgreSQL

Redis (optional)

Stateless frontend (Flutter web / mobile)


Deployment is containerized and designed for minimal maintenance.


---

Philosophical Position

Sophistry does not attempt to determine whether an answer is correct.

It attempts to determine whether an answer is structurally aligned with the question.

The system treats reasoning as form, not truth.



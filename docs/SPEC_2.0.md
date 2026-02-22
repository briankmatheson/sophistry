# Sophistry 2.0 – Structural Alignment & Human Calibration

## Status
Draft for internal review and architectural comment.

---

# 1. Purpose

Sophistry 2.0 extends the 1.x structural scoring engine by introducing:

1. Cross-model structural comparison
2. Blind architectural scoring (GPT)
3. Human qualitative evaluation
4. Rubric calibration against both structural and human judgment

The goal is to move from a static scoring rubric to a calibrated structural alignment system.

---

# 2. Core Thesis

LLM answers can be evaluated at three distinct layers:

1. Structural fidelity (ontology preservation)
2. Architectural judgment (expert structural intuition)
3. Human perceived quality

Sophistry 2.0 measures all three and analyzes their divergence.

---

# 3. Evaluation Phases

## Phase 0 – Model Generation

For each test case:

- Generate Claude answer (baseline batch run)
- Generate GPT answer (parallel comparator)

No scoring at this stage.

---

## Phase A – Blind Architectural Scoring (GPT)

For each `(question, answer)` pair:

- GPT produces:
  - Structural alignment estimate (0.0–1.0)
  - Commentary on:
    - Constraint loss
    - Quantifier fidelity
    - Scope shifts
    - Edge-case handling

No rubric exposure.

This becomes:

`S_gpt` – Architectural structural score.

---

## Phase B – Formal Rubric Scoring

Sophistry structural engine computes:

- Structural signature
- Graph distance
- Constraint retention
- Scope integrity
- Edge-case recognition

Produces:

`S_rubric`

This score is deterministic and weight-based.

---

## Phase C – Human Judgment

Human annotators label answers:

- Good
- Meh
- Bad

Mapped to ordinal scale:

- Good = 1.0
- Meh  = 0.5
- Bad  = 0.0

Produces:

`S_human`

Optional:
- Annotator confidence
- Free-text commentary

---

# 4. Divergence Analysis

For each answer, compute:

Δ₁ = S_gpt − S_human  
Δ₂ = S_rubric − S_human  
Δ₃ = S_gpt − S_rubric  

These deltas allow analysis of:

- Structural vs perceived quality
- Rubric vs expert intuition
- Model-specific bias patterns

---

# 5. Calibration Objectives

Possible optimization targets:

1. Align rubric to human perception  
   maximize corr(S_rubric, S_human)

2. Align rubric to architectural judgment  
   maximize corr(S_rubric, S_gpt)

3. Hybrid objective  
   minimize:
   α|S_rubric − S_human| + β|S_rubric − S_gpt|

Weighting (α, β) TBD.

---

# 6. Data Model Additions

## human_label

- testcase_id
- model
- label (good/meh/bad)
- annotator_id
- confidence
- created_at

## architectural_score

- testcase_id
- model
- structural_alignment_estimate
- commentary
- created_at

---

# 7. Success Criteria for 2.0

- ≥ 25 benchmark test cases
- Claude + GPT batch generation complete
- Blind architectural scoring implemented
- Human labeling UI live
- Divergence metrics computed
- Rubric weight tuning mechanism defined

---

# 8. Open Questions

- Should structural correctness override human perception?
- Should edge-case detection be weighted higher?
- Should verbosity penalties exist?
- Should we normalize scores per question difficulty?
- Is the dial representing structure, perception, or hybrid?

---

# 9. Non-Goals (for 2.0)

- Reinforcement learning of the rubric
- Fine-tuning models
- Large-scale crowdsourcing
- Full academic study design

2.0 is instrumentation, not publication.

---

# 10. Design Principle

Sophistry 2.0 does not assume:

“Human judgment == correctness”

It measures:

Structural alignment  
Expert structural intuition  
Human perceived quality  

And makes their differences explicit.

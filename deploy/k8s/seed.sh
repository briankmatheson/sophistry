#!/bin/bash
# Seed test cases for Sophistry

BASE=https://app.sophistry.online/api/testcases/
H="Content-Type: application/json"

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "capital-of-france",
  "title": "Capital of France",
  "prompt": "What is the capital of France?",
  "expected": {"answer": "Paris"},
  "tags": ["geography", "easy"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "phlogiston",
  "title": "Phlogiston",
  "prompt": "What is phlogiston?",
  "expected": {"answer": "an old theory of heat transfer"},
  "tags": ["science", "medium", "disproven"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "quark",
  "title": "Quark",
  "prompt": "What is a quark?",
  "expected": {"answer": "subatomic constituent of stuff"},
  "tags": ["science", "easy"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "trolley-problem",
  "title": "Trolley Problem",
  "prompt": "Describe the trolley problem and its implications for ethics.",
  "expected": {"answer": "a thought experiment about utilitarian vs deontological ethics"},
  "tags": ["philosophy", "medium", "ethics"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "halting-problem",
  "title": "Halting Problem",
  "prompt": "What is the halting problem and why is it important?",
  "expected": {"answer": "it is undecidable whether an arbitrary program will halt"},
  "tags": ["cs", "hard", "computability"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "luminiferous-aether",
  "title": "Luminiferous Aether",
  "prompt": "What was the luminiferous aether and why was it abandoned?",
  "expected": {"answer": "a hypothetical medium for light propagation, disproven by Michelson-Morley"},
  "tags": ["science", "medium", "disproven"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "p-vs-np",
  "title": "P vs NP",
  "prompt": "Explain the P vs NP problem in simple terms.",
  "expected": {"answer": "whether problems easy to verify are also easy to solve"},
  "tags": ["cs", "hard", "open-problems"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "ship-of-theseus",
  "title": "Ship of Theseus",
  "prompt": "What is the Ship of Theseus paradox?",
  "expected": {"answer": "if all parts are replaced, is it the same ship"},
  "tags": ["philosophy", "easy", "identity"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "spontaneous-generation",
  "title": "Spontaneous Generation",
  "prompt": "What was the theory of spontaneous generation?",
  "expected": {"answer": "the idea that living organisms arise from non-living matter, disproven by Pasteur"},
  "tags": ["science", "easy", "disproven"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "monty-hall",
  "title": "Monty Hall Problem",
  "prompt": "Explain the Monty Hall problem. Should you switch doors?",
  "expected": {"answer": "yes, switching gives 2/3 probability of winning"},
  "tags": ["math", "medium", "probability"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "chinese-room",
  "title": "Chinese Room",
  "prompt": "What is Searles Chinese Room argument?",
  "expected": {"answer": "manipulating symbols does not constitute understanding"},
  "tags": ["philosophy", "hard", "ai", "consciousness"],
  "is_active": true
}'

curl -X POST "$BASE" -H "$H" -d '{
  "slug": "fermi-paradox",
  "title": "Fermi Paradox",
  "prompt": "What is the Fermi paradox?",
  "expected": {"answer": "the contradiction between the high probability of alien civilizations and the lack of evidence"},
  "tags": ["science", "medium", "space"],
  "is_active": true
}'

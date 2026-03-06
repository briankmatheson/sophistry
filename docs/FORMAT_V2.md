# Sophistry Testcase Format v2: Braintrust-Compatible Superset

## Design Rationale

Braintrust datasets use three top-level fields per record:
- `input` — what gets sent to the task function
- `expected` — ground truth for scoring comparison
- `metadata` — additional context for filtering/grouping

Sophistry extends this with fields Braintrust ignores but our platform uses.
A Braintrust-compatible tool can consume the `input`/`expected`/`metadata` fields
and skip the rest. Sophistry's seeder and scorer can use the full record.

## Field Mapping

| Sophistry v1         | Braintrust        | Sophistry v2                          |
|---------------------|-------------------|---------------------------------------|
| `prompt`            | `input`           | `input.prompt`                        |
| `expected.answer`   | `expected`        | `expected.answer`                     |
| `expected.key_terms`| (custom)          | `expected.key_terms`                  |
| `expected.prompt_type`| (custom)        | `expected.prompt_type`                |
| `expected.validation`| (custom)         | `expected.validation`                 |
| `tags`              | `metadata.tags`   | `metadata.tags`                       |
| `slug`              | (custom)          | `metadata.slug`                       |
| `title`             | (custom)          | `metadata.title`                      |
| `is_active`         | (custom)          | `metadata.is_active`                  |
| (new)               | `metadata`        | `metadata.category`, `.difficulty`    |

## v2 Record Schema

```json
{
  "input": {
    "prompt": "The full question text with embedded context..."
  },
  "expected": {
    "answer": "structural reference answer for scoring",
    "prompt_type": "EXPLANATION",
    "key_terms": ["term1", "term2"],
    "validation": {
      "min_words": 42,
      "min_sentences": 3
    }
  },
  "metadata": {
    "slug": "wave-particle-duality",
    "title": "Wave-Particle Duality",
    "tags": ["physics", "quantum-mechanics", "medium"],
    "category": "physics",
    "difficulty": "medium",
    "is_active": true
  }
}
```

## Compatibility

- **Braintrust import**: records can be loaded directly via `initDataset()` / CSV upload.
  Braintrust uses `input`, `expected`, `metadata` — all present.
- **Braintrust scorers**: custom scorers receive `(input, output, expected)` — works.
- **Sophistry seeder**: reads `metadata.slug`, `metadata.is_active`, `input.prompt`,
  full `expected`, and `metadata.tags` to populate Django models.
- **Sophistry structural scorer**: reads `input.prompt` + `expected.*` as before.

## Migration Notes

- `tags` array is preserved in `metadata.tags`
- `category` is inferred from first tag (or explicitly set)
- `difficulty` is inferred from last tag if it matches easy/medium/hard
- `slug` and `title` move into `metadata`
- `prompt` moves into `input.prompt`
- `expected` stays as-is (already a dict), just ensure `answer` is always present

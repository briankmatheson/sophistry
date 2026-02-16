# Architecture

## Goals
- No accounts; UUID-only sessions
- Cheap to run; low maintenance
- Community contributed test cases (inactive by default)
- Clean separation: Flutter UI, Django API, Postgres, Redis

## Mobile flow
1) `POST /api/mobile/run/` -> run_uuid
2) `GET /api/mobile/question?run_uuid=...`
3) `POST /api/mobile/answer/` -> stores answer
4) `POST /api/mobile/testcase/` -> creates inactive testcase

## Moderation
Activate testcases in Django admin (`/admin/`) by setting `is_active=true`.

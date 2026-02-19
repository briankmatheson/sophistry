# Sophistry

A lightweight, privacy-respecting, mostly-one-screen mobile app + backend that asks users questions, shows their results,
and lets them contribute new test cases. Each result set is associated with a UUID. No ads. No user accounts.

- Flutter frontend: `flutter_app/`
- Django backend (DRF + Celery): `backend/`
- Kubernetes deploy (CloudNativePG + Redis): `deploy/k8s/`

## Quick start (local dev)

### Backend
```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python manage.py migrate
python manage.py migrate django_celery_results
ROLE=web python manage.py runserver 0.0.0.0:8000
```

In another shell:
```bash
cd backend
source .venv/bin/activate
ROLE=worker celery -A sophistry worker -l INFO --concurrency=4
```

### Flutter
    ```bash
cd flutter_app
flutter pub get
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8000
```

## API (mobile)
- `POST /api/mobile/run/` -> `{ run_uuid }`
- `GET  /api/mobile/question?run_uuid=...` -> `{ testcase_id, slug, prompt }`
- `POST /api/mobile/answer/` -> stores user's answer linked to `run_uuid`
- `POST /api/mobile/testcase/` -> create a new testcase (inactive by default)

## License
GPL-3.0-or-later (see LICENSE.md)

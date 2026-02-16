#!/usr/bin/env bash
set -euo pipefail

ROLE="${ROLE:-web}"

if [[ "${ROLE}" == "migrate" ]]; then
  python manage.py migrate
  python manage.py migrate django_celery_results
  exit 0
fi

if [[ "${ROLE}" == "worker" ]]; then
  celery -A sophistry worker -l INFO -Q default --concurrency="${CELERY_CONCURRENCY:-4}"
  exit 0
fi

gunicorn sophistry.wsgi:application --bind 0.0.0.0:8000 --workers "${WEB_WORKERS:-2}" --timeout 120

import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-supersecure")
DEBUG = os.getenv("DJANGO_DEBUG", "true").lower() in ("1","true","yes","y")
ALLOWED_HOSTS = [h.strip() for h in os.getenv("DJANGO_ALLOWED_HOSTS",  "*").split(",") if h.strip()]
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",

    "rest_framework",
    "django_filters",
    "django_celery_results",

    "evals",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "sophistry.middleware.SophistrySessionMiddleware",   # <-- add this
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "sophistry.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    }
]

WSGI_APPLICATION = "sophistry.wsgi.application"

PG_WRITER_HOST = os.getenv("PG_WRITER_HOST", "localhost")
PG_READER_HOST = os.getenv("PG_READER_HOST", PG_WRITER_HOST)
PG_PORT = os.getenv("PG_PORT", "5432")

POSTGRES_DB = os.getenv("POSTGRES_DB", "sophistry")
POSTGRES_USER = os.getenv("POSTGRES_USER", "sophistry")

POSTGRES_RO_USER = os.getenv("POSTGRES_RO_USER", "")
POSTGRES_RO_PASSWORD = os.getenv("POSTGRES_RO_PASSWORD", "")

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": POSTGRES_DB,
        "USER": POSTGRES_USER,
        "PASSWORD": POSTGRES_PASSWORD,
        "HOST": PG_WRITER_HOST,
        "PORT": PG_PORT,
        "CONN_MAX_AGE": 60,
    },
}

if POSTGRES_RO_USER and POSTGRES_RO_PASSWORD:
    for i in (1,2,3):
        DATABASES[f"replica{i}"] = {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": POSTGRES_DB,
            "USER": POSTGRES_RO_USER,
            "PASSWORD": POSTGRES_RO_PASSWORD,
            "HOST": PG_READER_HOST,
            "PORT": PG_PORT,
            "CONN_MAX_AGE": 60,
            "OPTIONS": {"options": "-c default_transaction_read_only=on"},
        }
    DATABASE_ROUTERS = ["sophistry.dbrouter.PrimaryReplicaRouter"]
else:
    DATABASE_ROUTERS = []

AUTH_PASSWORD_VALIDATORS = [
    {"NAME":"django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME":"django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME":"django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME":"django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_FILTER_BACKENDS": [
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.OrderingFilter",
    ]
}

# ─── Scoring defaults ─────────────────────────────────────
SOPHISTRY_MIN_WORDS = int(os.getenv("SCORING_MIN_WORDS", 42))
SOPHISTRY_MIN_SENTENCES = int(os.getenv("SCORING_MIN_SENTENCES", 3))

CELERY_BROKER_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
CELERY_RESULT_BACKEND = "django-db"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = "UTC"

REDIS_CACHE_URL = os.getenv("REDIS_CACHE_URL", "redis://localhost:6379/1")
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_CACHE_URL,
        "TIMEOUT": 30,
    }
}

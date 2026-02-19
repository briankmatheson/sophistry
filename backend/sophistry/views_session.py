import uuid
from django.http import JsonResponse
from django.views.decorators.http import require_POST
from evals.models import Participant

COOKIE_NAME = "sophistry_session"
COOKIE_MAX_AGE = 60 * 60 * 24 * 365


@require_POST
def reset_session(request):
    """Clear current session cookie and issue a fresh UUID."""
    new_session_id = str(uuid.uuid4())
    Participant.objects.get_or_create(session_id=new_session_id)

    response = JsonResponse({
        "status": "reset",
        "session_id": new_session_id,
    })
    response.set_cookie(
        COOKIE_NAME,
        new_session_id,
        max_age=COOKIE_MAX_AGE,
        httponly=False,
        samesite="Lax",
        secure=True,
    )
    return response

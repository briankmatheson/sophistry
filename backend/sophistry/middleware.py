import uuid
from django.conf import settings

COOKIE_NAME = "sophistry_session"
COOKIE_MAX_AGE = 60 * 60 * 24 * 365  # 1 year


class SophistrySessionMiddleware:
    """
    Assigns a UUID cookie to every visitor on first request.
    Creates a Participant record if one doesn't exist.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        session_id = request.COOKIES.get(COOKIE_NAME)
        new_session = False

        if not session_id:
            session_id = str(uuid.uuid4())
            new_session = True

        request.sophistry_session_id = session_id

        # Lazily create participant record
        from evals.models import Participant
        Participant.objects.get_or_create(session_id=session_id)

        response = self.get_response(request)

        if new_session:
            response.set_cookie(
                COOKIE_NAME,
                session_id,
                max_age=COOKIE_MAX_AGE,
                httponly=False,  # Flutter web needs to read it
                samesite="Lax",
                secure=True,
            )

        return response

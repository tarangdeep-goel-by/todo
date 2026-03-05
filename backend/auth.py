"""Firebase Authentication dependency for FastAPI."""
import logging

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import firebase_admin
from firebase_admin import auth as firebase_auth, credentials

from config import get_settings

logger = logging.getLogger(__name__)

_firebase_app = None


def _init_firebase():
    """Initialize Firebase Admin SDK (once)."""
    global _firebase_app
    if _firebase_app is not None:
        return
    settings = get_settings()
    if settings.google_application_credentials:
        cred = credentials.Certificate(settings.google_application_credentials)
        _firebase_app = firebase_admin.initialize_app(cred)
    else:
        # Use project ID only (for environments where ADC or emulator is available)
        _firebase_app = firebase_admin.initialize_app(options={
            "projectId": settings.firebase_project_id,
        })


_bearer = HTTPBearer()


async def get_current_user(
    cred: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    """Verify Firebase ID token and return the user's UID.

    Raises 401 if token is missing or invalid.
    """
    _init_firebase()
    try:
        decoded = firebase_auth.verify_id_token(cred.credentials)
        uid = decoded["uid"]
        logger.debug("Authenticated user: %s", uid)
        return uid
    except firebase_admin.auth.ExpiredIdTokenError:
        logger.warning("Auth failed: expired token")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )
    except firebase_admin.auth.RevokedIdTokenError:
        logger.warning("Auth failed: revoked token")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token revoked",
        )
    except firebase_admin.auth.InvalidIdTokenError as e:
        logger.warning("Auth failed: invalid token — %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
    except Exception as e:
        logger.warning("Auth failed: unexpected — %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed",
        )

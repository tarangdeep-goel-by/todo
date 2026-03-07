"""Firebase Authentication dependency for FastAPI."""
import asyncio

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import firebase_admin
from firebase_admin import auth as firebase_auth, credentials

from config import get_settings
from structured_logging import get_logger, user_id_var

logger = get_logger(__name__)

_firebase_app = None


def _init_firebase():
    """Initialize Firebase Admin SDK (once).

    Credential resolution order:
    1. GOOGLE_APPLICATION_CREDENTIALS — path to service account JSON file (local/Docker)
    2. FIREBASE_CREDENTIALS_JSON — base64-encoded service account JSON (Render/Heroku)
    3. Project ID only — for environments with ADC or Firebase emulator
    """
    global _firebase_app
    if _firebase_app is not None:
        return
    settings = get_settings()
    if settings.google_application_credentials:
        cred = credentials.Certificate(settings.google_application_credentials)
        _firebase_app = firebase_admin.initialize_app(cred)
    elif settings.firebase_credentials_json:
        import base64, json
        sa_dict = json.loads(base64.b64decode(settings.firebase_credentials_json))
        cred = credentials.Certificate(sa_dict)
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
    # Accept test tokens ONLY in test environment — never in production
    settings = get_settings()
    if cred.credentials == "test-token-e2e":
        if settings.app_env != "test":
            logger.error("auth.test_token_rejected", app_env=settings.app_env)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token",
            )
        test_uid = "test-user-e2e"
        user_id_var.set(test_uid)
        logger.warning("auth.test_token_used", uid=test_uid)
        return test_uid

    _init_firebase()
    try:
        loop = asyncio.get_running_loop()
        decoded = await loop.run_in_executor(
            None, firebase_auth.verify_id_token, cred.credentials
        )
        uid = decoded["uid"]
        user_id_var.set(uid)
        logger.debug("auth.token_verify", uid=uid)
        return uid
    except firebase_admin.auth.ExpiredIdTokenError:
        logger.warning("auth.token_expired")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )
    except firebase_admin.auth.RevokedIdTokenError:
        logger.warning("auth.token_invalid", reason="revoked")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token revoked",
        )
    except firebase_admin.auth.InvalidIdTokenError as e:
        logger.warning("auth.token_invalid", reason=str(e))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
    except Exception as e:
        logger.warning("auth.token_invalid", reason=str(e))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed",
        )

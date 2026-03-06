"""E2E test fixtures — logging HTTP client wrapper + multi-user support.

Uses header-based auth so multiple clients can coexist without
conflicting dependency overrides on the shared FastAPI app.
"""
import time
import json
import pytest
import pytest_asyncio
from fastapi import Request
from httpx import AsyncClient, ASGITransport

from database import get_db
from auth import get_current_user
from tests.conftest import TEST_USER_ID


SECOND_USER_ID = "test-user-2"


class E2EClient:
    """Wraps httpx AsyncClient with detailed step logging for E2E tests.

    Every request logs: step number, name, method, path, request body,
    response status, response body, and timing. On assertion failure,
    dumps the full audit trail of prior steps.
    """

    def __init__(self, client: AsyncClient, user_id: str):
        self.client = client
        self.user_id = user_id
        self.step_num = 0
        self.steps: list[dict] = []

    async def request(
        self,
        method: str,
        path: str,
        step_name: str,
        *,
        expected_status: int = 200,
        json_body: dict | list | None = None,
        params: dict | None = None,
    ) -> dict | list | str:
        self.step_num += 1
        step = {
            "num": self.step_num,
            "name": step_name,
            "method": method.upper(),
            "path": path,
            "request_body": json_body,
            "params": params,
        }

        # Log request
        print(f"\n[STEP {self.step_num}] \"{step_name}\" — {method.upper()} {path}")
        if json_body:
            print(f"  Request body: {json.dumps(json_body, indent=2, default=str)[:1000]}")
        if params:
            print(f"  Params: {params}")

        # Execute
        t0 = time.monotonic()
        resp = await self.client.request(
            method, path, json=json_body, params=params
        )
        duration_ms = round((time.monotonic() - t0) * 1000, 1)

        # Parse response
        try:
            body = resp.json()
        except Exception:
            body = resp.text

        step["status"] = resp.status_code
        step["response"] = body
        step["duration_ms"] = duration_ms
        step["passed"] = resp.status_code == expected_status
        self.steps.append(step)

        # Log response
        resp_str = json.dumps(body, indent=2, default=str) if isinstance(body, (dict, list)) else str(body)
        print(f"  Response: {resp.status_code} ({duration_ms}ms)")
        print(f"  Body: {resp_str[:2000]}")

        # Assert with rich context on failure
        if resp.status_code != expected_status:
            trail = self._format_trail()
            raise AssertionError(
                f"\n{'='*60}\n"
                f"STEP {self.step_num}/{self.step_num}: \"{step_name}\" FAILED\n"
                f"  {method.upper()} {path}\n"
                f"  Expected: {expected_status}  Got: {resp.status_code}\n"
                f"  Response: {resp_str[:2000]}\n"
                f"{'='*60}\n"
                f"AUDIT TRAIL:\n{trail}\n"
                f"{'='*60}"
            )

        print(f"  PASS (expected {expected_status})")
        return body

    def _format_trail(self) -> str:
        lines = []
        for s in self.steps:
            mark = "PASS" if s["passed"] else "FAIL"
            lines.append(
                f"  {s['num']}. [{mark}] {s['name']} — "
                f"{s['method']} {s['path']} -> {s['status']} ({s['duration_ms']}ms)"
            )
        return "\n".join(lines)

    # Convenience methods
    async def get(self, path, step_name, **kw):
        return await self.request("GET", path, step_name, **kw)

    async def post(self, path, step_name, **kw):
        return await self.request("POST", path, step_name, **kw)

    async def patch(self, path, step_name, **kw):
        return await self.request("PATCH", path, step_name, **kw)

    async def put(self, path, step_name, **kw):
        return await self.request("PUT", path, step_name, **kw)

    async def delete(self, path, step_name, **kw):
        return await self.request("DELETE", path, step_name, **kw)


# ──────────────── Header-based auth for multi-user E2E ────────────────
#
# Instead of a single global dependency override (which breaks when two
# clients need different user IDs), we override get_current_user to read
# the user ID from a custom request header. Each AsyncClient sends its
# own header value.

_TEST_USER_HEADER = "x-test-user"


@pytest_asyncio.fixture
async def _e2e_app(db_session):
    """Set up the FastAPI app with header-based auth for E2E tests."""
    from main import app

    async def _override_db():
        yield db_session

    def _user_from_header(request: Request):
        return request.headers.get(_TEST_USER_HEADER, TEST_USER_ID)

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = _user_from_header

    yield app

    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def e2e(_e2e_app) -> E2EClient:
    """E2EClient for the default test user (test-user)."""
    transport = ASGITransport(app=_e2e_app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test/api",
        headers={_TEST_USER_HEADER: TEST_USER_ID},
    ) as client:
        yield E2EClient(client, TEST_USER_ID)


@pytest_asyncio.fixture
async def e2e_user2(_e2e_app) -> E2EClient:
    """E2EClient for a second user (test-user-2), for isolation tests."""
    transport = ASGITransport(app=_e2e_app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test/api",
        headers={_TEST_USER_HEADER: SECOND_USER_ID},
    ) as client:
        yield E2EClient(client, SECOND_USER_ID)

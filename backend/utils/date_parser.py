from datetime import datetime, timezone, timedelta
from dateutil.parser import parse as dateutil_parse
from typing import Optional
import re

def parse_flexible_date(date_str: Optional[str]) -> Optional[datetime]:
    """Parse relative/ISO dates to UTC datetime."""
    if not date_str:
        return None

    try:
        date_lower = date_str.lower().strip()

        # Handle shortcuts
        if date_lower == "today":
            return datetime.now(timezone.utc).replace(hour=9, minute=0, second=0, microsecond=0)
        elif date_lower == "tomorrow":
            tomorrow = datetime.now(timezone.utc) + timedelta(days=1)
            return tomorrow.replace(hour=9, minute=0, second=0, microsecond=0)

        # Handle "next monday", "next friday"
        next_day_match = re.match(r'next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)', date_lower)
        if next_day_match:
            return _get_next_weekday(next_day_match.group(1))

        # Fallback to dateutil parser
        parsed = dateutil_parse(date_str)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed

    except (ValueError, OverflowError):
        return None

def _get_next_weekday(weekday_name: str) -> datetime:
    """Get next occurrence of weekday."""
    weekdays = {'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
                'friday': 4, 'saturday': 5, 'sunday': 6}
    target_day = weekdays[weekday_name]
    today = datetime.now(timezone.utc)
    days_ahead = target_day - today.weekday()
    if days_ahead <= 0:
        days_ahead += 7
    next_date = today + timedelta(days=days_ahead)
    return next_date.replace(hour=9, minute=0, second=0, microsecond=0)

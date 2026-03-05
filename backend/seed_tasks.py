"""Generate sample tasks for testing Amble frontend."""
import asyncio
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

import requests
import random

API_URL = "http://localhost:8001/api"
USER_ID = "default-user"

# Diverse task templates matching the 5 domains
TASK_TEMPLATES = {
    "Work": [
        "Review project proposal",
        "Update API documentation",
        "Fix authentication bug",
        "Deploy staging environment",
        "Code review for PR #123",
        "Prepare quarterly report",
        "Schedule team meeting",
        "Refactor user service",
        "Performance optimization",
        "Security audit",
    ],
    "Personal": [
        "Buy groceries",
        "Schedule dentist appointment",
        "Call mom",
        "Pay electricity bill",
        "Organize garage",
        "Book vacation tickets",
        "Return library books",
        "Get car serviced",
        "Plan weekend dinner",
        "Water the plants",
    ],
    "Health": [
        "Morning jog",
        "Meal prep for the week",
        "Take vitamins",
        "Schedule annual checkup",
        "Yoga session",
        "Track water intake",
        "Buy protein powder",
        "Sleep before 11pm",
        "Meditation practice",
        "Update fitness goals",
    ],
    "Learning": [
        "Complete React tutorial",
        "Read chapter 3 of design book",
        "Practice Spanish vocabulary",
        "Watch ML course lecture",
        "Solve 3 LeetCode problems",
        "Learn about OKLCH colors",
        "Study Flutter animations",
        "Research AI agents",
        "Take online course quiz",
        "Read research paper",
    ],
    "Projects": [
        "Design new landing page",
        "Build portfolio website",
        "Write blog post about AI",
        "Create side project roadmap",
        "Sketch app wireframes",
        "Record podcast episode",
        "Edit YouTube video",
        "Plan content calendar",
        "Brainstorm product ideas",
        "Update GitHub README",
    ],
}


def create_task(title: str, category: str, description: str = None):
    """Create a task via API."""
    payload = {
        "user_id": USER_ID,
        "title": title,
        "category": category,
        "transcription": title,
        "status": "active",
    }

    if description:
        payload["description"] = description

    response = requests.post(f"{API_URL}/tasks", json=payload)

    if response.status_code == 200:
        task = response.json()
        print(f"✓ Created [{category}]: {title}")
        return task
    else:
        print(f"✗ Failed [{category}]: {title}")
        print(f"  Error: {response.text[:200]}")
        return None


def main():
    """Generate diverse sample tasks across all 5 domains."""
    print("🌱 Seeding tasks for Amble frontend testing...\n")

    created = 0
    failed = 0

    # Create 5-10 tasks per domain
    for domain, templates in TASK_TEMPLATES.items():
        num_tasks = random.randint(5, 10)
        selected = random.sample(templates, min(num_tasks, len(templates)))

        for title in selected:
            # Add some variety with descriptions
            desc = None
            if random.random() > 0.6:
                desc = f"This is a {domain.lower()} task that needs attention"

            task = create_task(title, domain, desc)

            if task:
                created += 1
            else:
                failed += 1

    print(f"\n✅ Done! Created {created} tasks across 5 domains")
    if failed > 0:
        print(f"⚠️  {failed} tasks failed to create")

    print(f"\n📱 Refresh your app to see the tasks!")


if __name__ == "__main__":
    main()

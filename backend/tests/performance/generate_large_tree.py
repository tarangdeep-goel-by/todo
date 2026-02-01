"""Generate large task trees for performance testing."""
import asyncio
import random
from typing import Dict, List
from sqlalchemy.ext.asyncio import AsyncSession
from database import AsyncSessionLocal
from services.task_service import TaskService


TASK_TEMPLATES = {
    "work": [
        "Project Alpha", "Backend API", "Frontend UI", "Database optimization",
        "Code review", "Testing", "Documentation", "Deployment",
        "Bug fix", "Feature request", "Refactoring", "Performance tuning",
        "Security audit", "Integration", "Migration", "Setup",
        "Meeting", "Planning", "Research", "Analysis"
    ],
    "personal": [
        "Groceries", "Errands", "Home maintenance", "Doctor appointment",
        "Gym", "Reading", "Cooking", "Cleaning", "Shopping",
        "Family time", "Hobby", "Travel planning", "Bills",
        "Car maintenance", "Pet care", "Garden", "Organizing"
    ]
}


async def generate_tree(
    user_id: str,
    num_tasks: int,
    max_depth: int = 5,
    branching_factor: int = 4
) -> Dict:
    """
    Generate task tree with specified size/depth.

    Args:
        user_id: User ID for tasks
        num_tasks: Total number of tasks to create
        max_depth: Maximum tree depth
        branching_factor: Average children per parent

    Returns:
        Dictionary with tree metadata
    """
    async with AsyncSessionLocal() as db:
        task_service = TaskService(db)

        # Create root categories
        root_work = await task_service.create_task(
            user_id=user_id,
            title="Work",
            category="work",
            transcription="Work root",
            parent_id=None
        )

        root_personal = await task_service.create_task(
            user_id=user_id,
            title="Personal",
            category="personal",
            transcription="Personal root",
            parent_id=None
        )

        tasks_by_level = {0: [root_work, root_personal]}
        created = 2
        current_depth = 1

        # Breadth-first creation
        while created < num_tasks and current_depth <= max_depth:
            tasks_by_level[current_depth] = []

            for parent in tasks_by_level[current_depth - 1]:
                if created >= num_tasks:
                    break

                # Random number of children
                num_children = min(
                    random.randint(2, branching_factor * 2),
                    num_tasks - created
                )

                category = parent.category
                templates = TASK_TEMPLATES[category]

                for i in range(num_children):
                    if created >= num_tasks:
                        break

                    # Generate task title
                    base_title = random.choice(templates)
                    title = f"{base_title} {created}"

                    # Random priority
                    priority = random.choice([None, "low", "medium", "high"])

                    # Random tags
                    tags = None
                    if random.random() > 0.7:
                        tags = [f"tag{random.randint(1, 10)}"]

                    child = await task_service.create_task(
                        user_id=user_id,
                        title=title,
                        category=category,
                        transcription=title,
                        parent_id=parent.id,
                        priority=priority,
                        tags=tags,
                        description=f"Generated task at depth {current_depth}"
                    )

                    tasks_by_level[current_depth].append(child)
                    created += 1

            current_depth += 1

        return {
            "total_tasks": created,
            "max_depth": current_depth - 1,
            "user_id": user_id
        }


async def main():
    """Generate sample trees."""
    sizes = [50, 100, 200, 500]

    for size in sizes:
        user_id = f"perf-test-{size}"
        print(f"\nGenerating {size}-task tree for user {user_id}...")

        result = await generate_tree(user_id, size, max_depth=5)

        print(f"  Created {result['total_tasks']} tasks")
        print(f"  Max depth: {result['max_depth']}")


if __name__ == "__main__":
    asyncio.run(main())

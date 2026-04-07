"""Seed showcase data for 3 new features: due_soon, calendar view, breakdown."""
import asyncio
import os
import sys
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(__file__))

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import text
from database import Base
from models.task import Task
from models.category import Category as CategoryModel
from services.task_service import TaskService

DB_URL = os.environ.get("DATABASE_URL", "postgresql+asyncpg://todo:changeme@localhost:5433/todo_db")
USER = "default-user"


async def main():
    engine = create_async_engine(DB_URL)
    sf = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with sf() as db:
        ts = TaskService(db)
        now = datetime.now(timezone.utc)

        # Categories
        for name in ["work", "personal", "health", "learning", "projects"]:
            await ts.create_category(USER, name)
        print("Categories created")

        # === WORK ===
        # Overdue
        w1 = await ts.create_task(user_id=USER, title="Prepare quarterly report", category="work",
            transcription="quarterly report", priority="high",
            due_date=now - timedelta(days=5), ai_placement={"confidence":0.9,"reasoning":"work"})
        w2 = await ts.create_task(user_id=USER, title="Submit expense reports", category="work",
            transcription="expense reports", priority="medium",
            due_date=now - timedelta(days=3), ai_placement={"confidence":0.9,"reasoning":"work"})

        # Due soon (within 48h)
        w3 = await ts.create_task(user_id=USER, title="Code review for PR #247", category="work",
            transcription="code review", priority="high",
            due_date=now + timedelta(hours=12), ai_placement={"confidence":0.9,"reasoning":"work"})
        w4 = await ts.create_task(user_id=USER, title="Deploy staging environment", category="work",
            transcription="deploy staging", priority="medium",
            due_date=now + timedelta(hours=36), ai_placement={"confidence":0.9,"reasoning":"work"})

        # Future
        w5 = await ts.create_task(user_id=USER, title="Refactor auth service", category="work",
            transcription="refactor auth", priority="high",
            due_date=now + timedelta(days=8), ai_placement={"confidence":0.9,"reasoning":"work"})
        # Children of w5
        await ts.create_task(user_id=USER, title="Write migration script", category="work",
            transcription="migration", priority="medium", parent_id=w5.id,
            due_date=now + timedelta(days=6), ai_placement={"confidence":0.9,"reasoning":"subtask"})
        await ts.create_task(user_id=USER, title="Update API endpoints", category="work",
            transcription="api endpoints", priority="medium", parent_id=w5.id,
            due_date=now + timedelta(days=7), ai_placement={"confidence":0.9,"reasoning":"subtask"})
        await ts.create_task(user_id=USER, title="Add integration tests", category="work",
            transcription="tests", priority="low", parent_id=w5.id,
            due_date=now + timedelta(days=8), ai_placement={"confidence":0.9,"reasoning":"subtask"})

        w6 = await ts.create_task(user_id=USER, title="Design system documentation", category="work",
            transcription="design docs", priority="low",
            due_date=now + timedelta(days=14), ai_placement={"confidence":0.9,"reasoning":"work"})
        w7 = await ts.create_task(user_id=USER, title="Team standup notes", category="work",
            transcription="standup", priority="low",
            ai_placement={"confidence":0.9,"reasoning":"work"})
        w8 = await ts.create_task(user_id=USER, title="Update CI/CD pipeline", category="work",
            transcription="cicd", priority="medium",
            due_date=now + timedelta(days=3), ai_placement={"confidence":0.9,"reasoning":"work"})

        # Completed
        await ts.create_task(user_id=USER, title="Fix login bug", category="work",
            transcription="login bug", priority="high",
            due_date=now - timedelta(days=7), ai_placement={"confidence":0.9,"reasoning":"work"})
        # Complete it
        tasks = await ts.get_tasks(USER, category="work")
        for t in tasks:
            if t.title == "Fix login bug":
                await ts.complete_task(t.id)
                break

        # === PERSONAL ===
        await ts.create_task(user_id=USER, title="Buy groceries", category="personal",
            transcription="groceries", priority="medium",
            due_date=now + timedelta(hours=10), ai_placement={"confidence":0.9,"reasoning":"personal"})
        await ts.create_task(user_id=USER, title="Call mom", category="personal",
            transcription="call mom", priority="high",
            due_date=now - timedelta(days=2), ai_placement={"confidence":0.9,"reasoning":"personal"})
        await ts.create_task(user_id=USER, title="Pay electricity bill", category="personal",
            transcription="electricity", priority="high",
            due_date=now + timedelta(hours=40), ai_placement={"confidence":0.9,"reasoning":"personal"})
        await ts.create_task(user_id=USER, title="Schedule dentist appointment", category="personal",
            transcription="dentist", priority="low",
            due_date=now + timedelta(days=5), ai_placement={"confidence":0.9,"reasoning":"personal"})
        await ts.create_task(user_id=USER, title="Book vacation flights", category="personal",
            transcription="vacation", priority="medium",
            due_date=now + timedelta(days=20), ai_placement={"confidence":0.9,"reasoning":"personal"})
        await ts.create_task(user_id=USER, title="Return library books", category="personal",
            transcription="library", priority="low",
            due_date=now + timedelta(days=3), ai_placement={"confidence":0.9,"reasoning":"personal"})
        await ts.create_task(user_id=USER, title="Organize garage", category="personal",
            transcription="garage", priority="low",
            ai_placement={"confidence":0.9,"reasoning":"personal"})

        # === HEALTH ===
        h1 = await ts.create_task(user_id=USER, title="Marathon training plan", category="health",
            transcription="marathon", priority="high",
            due_date=now + timedelta(days=50), ai_placement={"confidence":0.9,"reasoning":"health"})
        await ts.create_task(user_id=USER, title="Base building phase", category="health",
            transcription="base building", priority="medium", parent_id=h1.id,
            due_date=now + timedelta(days=5), ai_placement={"confidence":0.9,"reasoning":"subtask"})
        await ts.create_task(user_id=USER, title="Speed work sessions", category="health",
            transcription="speed work", priority="medium", parent_id=h1.id,
            due_date=now + timedelta(days=20), ai_placement={"confidence":0.9,"reasoning":"subtask"})
        await ts.create_task(user_id=USER, title="Long run progression", category="health",
            transcription="long run", priority="high", parent_id=h1.id,
            due_date=now + timedelta(days=35), ai_placement={"confidence":0.9,"reasoning":"subtask"})

        await ts.create_task(user_id=USER, title="Morning yoga routine", category="health",
            transcription="yoga", priority="low",
            due_date=now + timedelta(hours=14), ai_placement={"confidence":0.9,"reasoning":"health"})
        await ts.create_task(user_id=USER, title="Meal prep for the week", category="health",
            transcription="meal prep", priority="medium",
            due_date=now - timedelta(days=4), ai_placement={"confidence":0.9,"reasoning":"health"})
        await ts.create_task(user_id=USER, title="Annual health checkup", category="health",
            transcription="checkup", priority="high",
            due_date=now + timedelta(days=14), ai_placement={"confidence":0.9,"reasoning":"health"})
        await ts.create_task(user_id=USER, title="Track water intake", category="health",
            transcription="water", priority="low",
            ai_placement={"confidence":0.9,"reasoning":"health"})

        # === LEARNING ===
        await ts.create_task(user_id=USER, title="Complete Flutter animations course", category="learning",
            transcription="flutter animations", priority="medium",
            due_date=now + timedelta(days=5), ai_placement={"confidence":0.9,"reasoning":"learning"})
        await ts.create_task(user_id=USER, title="Read Design Patterns book", category="learning",
            transcription="design patterns", priority="low",
            due_date=now + timedelta(days=25), ai_placement={"confidence":0.9,"reasoning":"learning"})
        await ts.create_task(user_id=USER, title="Practice SQL queries", category="learning",
            transcription="sql", priority="medium",
            due_date=now + timedelta(hours=30), ai_placement={"confidence":0.9,"reasoning":"learning"})
        await ts.create_task(user_id=USER, title="Watch system design lecture", category="learning",
            transcription="system design", priority="low",
            due_date=now - timedelta(days=6), ai_placement={"confidence":0.9,"reasoning":"learning"})
        await ts.create_task(user_id=USER, title="Build side project MVP", category="learning",
            transcription="side project", priority="high",
            due_date=now + timedelta(days=35), ai_placement={"confidence":0.9,"reasoning":"learning"})

        # === PROJECTS ===
        pr1 = await ts.create_task(user_id=USER, title="Kitchen renovation planning", category="projects",
            transcription="kitchen renovation", priority="high",
            due_date=now + timedelta(days=20), ai_placement={"confidence":0.9,"reasoning":"projects"})
        await ts.create_task(user_id=USER, title="Get contractor quotes", category="projects",
            transcription="contractor quotes", priority="high", parent_id=pr1.id,
            due_date=now + timedelta(days=4), ai_placement={"confidence":0.9,"reasoning":"subtask"})
        await ts.create_task(user_id=USER, title="Choose cabinet materials", category="projects",
            transcription="cabinets", priority="medium", parent_id=pr1.id,
            due_date=now + timedelta(days=10), ai_placement={"confidence":0.9,"reasoning":"subtask"})
        await ts.create_task(user_id=USER, title="Design floor layout", category="projects",
            transcription="floor layout", priority="medium", parent_id=pr1.id,
            due_date=now + timedelta(days=15), ai_placement={"confidence":0.9,"reasoning":"subtask"})

        await ts.create_task(user_id=USER, title="Portfolio website redesign", category="projects",
            transcription="portfolio", priority="medium",
            due_date=now + timedelta(days=30), ai_placement={"confidence":0.9,"reasoning":"projects"})
        await ts.create_task(user_id=USER, title="Write blog post about AI", category="projects",
            transcription="blog post", priority="low",
            ai_placement={"confidence":0.9,"reasoning":"projects"})
        await ts.create_task(user_id=USER, title="Record podcast episode", category="projects",
            transcription="podcast", priority="low",
            due_date=now - timedelta(days=1), ai_placement={"confidence":0.9,"reasoning":"projects"})

    await engine.dispose()
    print("Done! Seeded tasks across 5 domains with overdue, due_soon, future, and no-date tasks")


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""
Seed realistic task tree for a senior PM / tech lead.

Key property: overlapping child names across different parents.
Multiple projects each have "spec", "design review", "standup", "retro", etc.
Personal life has overlapping patterns too (meal prep, groceries, appointments).

~80 tasks, 4 levels deep.
"""

import asyncio
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://todo:changeme@postgres:5432/todo_db")
os.environ.setdefault("GEMINI_API_KEY", "test-key")
os.environ.setdefault("SEARCH_ENGINE", "pg_native")

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from services.task_service import TaskService

USER_ID = "default-user"


def uid():
    return str(uuid.uuid4())


# ── Tree structure ──
# Format: (id, title, parent_id, category, status)

TREE = []


def add(title, category, parent_id=None, status="active"):
    task_id = uid()
    TREE.append((task_id, title, parent_id, category, status))
    return task_id


# ═══════════════════════════════════════
# CAREER — Senior PM managing 3 projects
# ═══════════════════════════════════════

# Project: Payments Rewrite
payments = add("payments rewrite", "career")
pay_spec = add("product spec", "career", payments)
pay_design = add("design review", "career", payments)
pay_api = add("api design", "career", payments)
pay_api_auth = add("auth endpoints", "career", pay_api)
pay_api_webhook = add("webhook handlers", "career", pay_api)
pay_testing = add("testing plan", "career", payments)
pay_unit = add("unit tests", "career", pay_testing)
pay_integration = add("integration tests", "career", pay_testing)
pay_load = add("load testing", "career", pay_testing)
pay_launch = add("launch checklist", "career", payments)
pay_retro = add("sprint retro", "career", payments, status="completed")

# Project: Mobile App v2
mobile = add("mobile app v2", "career")
mob_spec = add("product spec", "career", mobile)
mob_design = add("design review", "career", mobile)
mob_onboarding = add("onboarding flow", "career", mobile)
mob_onb_screens = add("screen wireframes", "career", mob_onboarding)
mob_onb_copy = add("ux copy", "career", mob_onboarding)
mob_push = add("push notifications", "career", mobile)
mob_push_backend = add("notification service", "career", mob_push)
mob_push_perms = add("permission flow", "career", mob_push)
mob_testing = add("testing plan", "career", mobile)
mob_unit = add("unit tests", "career", mob_testing)
mob_e2e = add("e2e tests", "career", mob_testing)
mob_retro = add("sprint retro", "career", mobile)
mob_standup = add("standup notes", "career", mobile)

# Project: Data Pipeline
pipeline = add("data pipeline migration", "career")
pipe_spec = add("product spec", "career", pipeline)
pipe_design = add("design review", "career", pipeline)
pipe_schema = add("schema migration", "career", pipeline)
pipe_etl = add("etl refactor", "career", pipeline)
pipe_monitoring = add("monitoring dashboard", "career", pipeline)
pipe_alerts = add("alert rules", "career", pipe_monitoring)
pipe_grafana = add("grafana setup", "career", pipe_monitoring)
pipe_testing = add("testing plan", "career", pipeline)
pipe_retro = add("sprint retro", "career", pipeline, status="completed")

# Cross-project work
hiring = add("hiring", "career")
hire_senior = add("senior engineer interviews", "career", hiring)
hire_jd = add("job description review", "career", hiring)
hire_onsite = add("onsite scheduling", "career", hiring)

team = add("team management", "career")
team_1on1 = add("1-on-1 prep", "career", team)
team_perf = add("performance reviews", "career", team)
team_standup = add("standup notes", "career", team)

# ═══════════════════════════════════════
# HOME — Busy adult life
# ═══════════════════════════════════════

# Home
home = add("apartment", "home")
home_lease = add("lease renewal", "home", home)
home_repair = add("fix kitchen faucet", "home", home)
home_clean = add("deep clean", "home", home)
home_declutter = add("declutter closet", "home", home)

# Family
family = add("family", "home")
fam_birthday = add("mom birthday gift", "home", family)
fam_dinner = add("family dinner sunday", "home", family)
fam_call = add("call sister", "home", family)

# Errands
errands = add("errands", "home")
err_groceries = add("grocery shopping", "home", errands)
err_groc_list = add("meal prep ingredients", "home", err_groceries)
err_groc_snacks = add("office snacks", "home", err_groceries)
err_dry = add("dry cleaning pickup", "home", errands)
err_pharmacy = add("pharmacy refill", "home", errands)
err_car = add("car service appointment", "home", errands)

# Finance
finance = add("finances", "home")
fin_tax = add("tax filing 2026", "home", finance)
fin_tax_docs = add("gather w2 documents", "home", fin_tax)
fin_tax_cpa = add("cpa appointment", "home", fin_tax)
fin_budget = add("monthly budget review", "home", finance)
fin_invest = add("rebalance portfolio", "home", finance)

# ═══════════════════════════════════════
# HEALTH
# ═══════════════════════════════════════

fitness = add("fitness", "health")
fit_run = add("marathon training", "health", fitness)
fit_run_tempo = add("tempo runs", "health", fit_run)
fit_run_long = add("long run saturday", "health", fit_run)
fit_gym = add("gym routine", "health", fitness)
fit_gym_upper = add("upper body day", "health", fit_gym)
fit_gym_lower = add("lower body day", "health", fit_gym)

nutrition = add("nutrition", "health")
nut_mealprep = add("meal prep sunday", "health", nutrition)
nut_mealprep_recipes = add("find new recipes", "health", nut_mealprep)
nut_mealprep_shop = add("meal prep ingredients", "health", nut_mealprep)
nut_water = add("track water intake", "health", nutrition)
nut_supplements = add("order supplements", "health", nutrition)

mental = add("mental health", "health")
ment_meditate = add("morning meditation", "health", mental)
ment_journal = add("evening journal", "health", mental)
ment_therapy = add("therapy appointment", "health", mental, status="completed")

# ═══════════════════════════════════════
# GROWTH
# ═══════════════════════════════════════

tech_learning = add("technical skills", "growth")
tech_rust = add("learn rust", "growth", tech_learning)
tech_rust_book = add("finish the rust book", "growth", tech_rust)
tech_rust_project = add("build cli tool", "growth", tech_rust)
tech_ml = add("machine learning", "growth", tech_learning)
tech_ml_course = add("fast.ai course", "growth", tech_ml)
tech_ml_paper = add("read attention paper", "growth", tech_ml)
tech_system = add("system design", "growth", tech_learning)
tech_system_book = add("design data intensive apps", "growth", tech_system)

leadership = add("leadership", "growth")
lead_book = add("read high output management", "growth", leadership)
lead_writing = add("practice technical writing", "growth", leadership)
lead_speaking = add("prep conference talk", "growth", leadership)

# ═══════════════════════════════════════
# RECREATION — Side projects
# ═══════════════════════════════════════

side_app = add("budget tracker app", "recreation")
side_app_spec = add("product spec", "recreation", side_app)
side_app_design = add("design review", "recreation", side_app)
side_app_mvp = add("build mvp", "recreation", side_app)
side_app_deploy = add("deploy to app store", "recreation", side_app)

blog = add("tech blog", "recreation")
blog_post1 = add("write rust async article", "recreation", blog)
blog_post2 = add("write system design post", "recreation", blog)
blog_seo = add("seo optimization", "recreation", blog)

podcast = add("podcast", "recreation")
pod_ep1 = add("record episode 1", "recreation", podcast)
pod_edit = add("edit and publish", "recreation", podcast)
pod_guests = add("reach out to guests", "recreation", podcast)


async def seed():
    engine = create_async_engine(os.environ["DATABASE_URL"], echo=False)
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with factory() as db:
        svc = TaskService(db)

        created = 0
        for task_id, title, parent_id, category, status in TREE:
            try:
                task = await svc.create_task(
                    user_id=USER_ID,
                    title=title,
                    category=category,
                    transcription=title,
                    parent_id=parent_id,
                    task_id=task_id,
                )
                if status == "completed":
                    await svc.complete_task(task.id)
                created += 1
            except Exception as e:
                print(f"  SKIP {title}: {e}")

        print(f"\nSeeded {created} tasks")

        # Summary
        from sqlalchemy import text
        r = await db.execute(text(
            "SELECT category, COUNT(*) FROM tasks WHERE user_id = :uid GROUP BY category ORDER BY category",
        ), {"uid": USER_ID})
        print("\nBy category:")
        for cat, count in r.all():
            print(f"  {cat}: {count}")

        r = await db.execute(text(
            "SELECT COUNT(*) FROM tasks WHERE user_id = :uid AND parent_id IS NOT NULL",
        ), {"uid": USER_ID})
        print(f"\nNested tasks: {r.scalar_one()}")

        # Show duplicated names
        r = await db.execute(text("""
            SELECT title, COUNT(*) as cnt
            FROM tasks WHERE user_id = :uid
            GROUP BY title HAVING COUNT(*) > 1
            ORDER BY cnt DESC
        """), {"uid": USER_ID})
        dupes = r.all()
        if dupes:
            print(f"\nDuplicated task names ({len(dupes)} titles):")
            for title, cnt in dupes:
                print(f"  '{title}' x{cnt}")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())

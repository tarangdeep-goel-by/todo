#!/usr/bin/env python3
"""Seed deep hierarchical tasks for VOKL frontend testing.

Creates ~160 tasks across 5 domains with 4-5 levels of nesting.
Includes priorities, due dates, tags, descriptions, and estimated hours.
"""

import urllib.request
import json
from datetime import datetime, timedelta

API_URL = "http://localhost:8001/api/tasks"
USER_ID = "default-user"

# Track counts
created = 0
failed = 0


def future(days):
    """Return ISO datetime string N days from now."""
    return (datetime.now() + timedelta(days=days)).isoformat()


def create_task(title, category, parent_id=None, **kwargs):
    """Create a task and return its ID."""
    global created, failed
    data = {
        "user_id": USER_ID,
        "title": title,
        "category": category,
        "transcription": title,
        "status": "active",
    }
    if parent_id:
        data["parent_id"] = parent_id
    for key in ("priority", "tags", "due_date", "description", "estimated_hours"):
        if key in kwargs and kwargs[key] is not None:
            data[key] = kwargs[key]

    try:
        req = urllib.request.Request(
            API_URL,
            data=json.dumps(data).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req) as response:
            task = json.loads(response.read().decode("utf-8"))
            created += 1
            return task["id"]
    except Exception as e:
        print(f"  FAIL: {title} - {e}")
        failed += 1
        return None


def seed_work():
    """Work domain - 4-5 levels deep, ~40 tasks."""
    print("Work...")

    # --- Product Launch ---
    launch = create_task("Q1 Product Launch", "Work", priority="high", due_date=future(30), tags=["launch", "q1"])
    if launch:
        planning = create_task("Planning & Strategy", "Work", launch, priority="high", due_date=future(7))
        if planning:
            market = create_task("Market research", "Work", planning, priority="high", estimated_hours=8)
            if market:
                create_task("Competitor analysis spreadsheet", "Work", market, priority="medium", estimated_hours=3)
                create_task("User survey design", "Work", market, priority="medium", estimated_hours=2)
                create_task("Analyze survey results", "Work", market, priority="medium", estimated_hours=3)
            create_task("Define launch timeline", "Work", planning, priority="high", due_date=future(5), estimated_hours=2)
            create_task("Set KPI targets", "Work", planning, priority="medium", estimated_hours=1)

        engineering = create_task("Engineering", "Work", launch, priority="high", due_date=future(21))
        if engineering:
            backend = create_task("Backend services", "Work", engineering, priority="high", tags=["backend"])
            if backend:
                create_task("Auth service refactor", "Work", backend, priority="high", estimated_hours=16, description="Migrate from session to JWT tokens")
                create_task("Payment integration v2", "Work", backend, priority="high", estimated_hours=24, due_date=future(14))
                create_task("Rate limiting middleware", "Work", backend, priority="medium", estimated_hours=8)
                create_task("Database migration scripts", "Work", backend, priority="high", estimated_hours=4)
            frontend = create_task("Frontend features", "Work", engineering, priority="high", tags=["frontend"])
            if frontend:
                create_task("Redesign onboarding flow", "Work", frontend, priority="high", estimated_hours=20)
                create_task("Dashboard analytics widgets", "Work", frontend, priority="medium", estimated_hours=12)
                create_task("Mobile responsive fixes", "Work", frontend, priority="medium", estimated_hours=8)
            infra = create_task("Infrastructure", "Work", engineering, priority="medium", tags=["devops"])
            if infra:
                create_task("Set up staging environment", "Work", infra, priority="high", estimated_hours=6)
                create_task("Configure CI/CD pipeline", "Work", infra, priority="medium", estimated_hours=8)
                create_task("Load testing setup", "Work", infra, priority="low", estimated_hours=4)

        marketing = create_task("Marketing", "Work", launch, priority="medium", due_date=future(25))
        if marketing:
            create_task("Write press release", "Work", marketing, priority="medium", estimated_hours=4)
            create_task("Prepare demo video", "Work", marketing, priority="high", estimated_hours=12)
            create_task("Social media campaign", "Work", marketing, priority="low", estimated_hours=6)
            create_task("Email blast to waitlist", "Work", marketing, priority="medium", due_date=future(28))

    # --- Team Management ---
    team = create_task("Team Management", "Work", priority="medium", tags=["team"])
    if team:
        hiring = create_task("Hiring pipeline", "Work", team, priority="high")
        if hiring:
            create_task("Review senior dev applications", "Work", hiring, priority="high", due_date=future(3))
            create_task("Schedule technical interviews", "Work", hiring, priority="high", due_date=future(5))
            create_task("Prepare onboarding docs", "Work", hiring, priority="low", estimated_hours=6)
        create_task("Q1 performance reviews", "Work", team, priority="medium", due_date=future(14), estimated_hours=10)
        create_task("Team offsite planning", "Work", team, priority="low", due_date=future(45))

    # --- Client Projects ---
    clients = create_task("Client Projects", "Work", priority="high", tags=["clients"])
    if clients:
        acme = create_task("ACME Corp - API rebuild", "Work", clients, priority="high", due_date=future(60))
        if acme:
            create_task("Audit existing endpoints", "Work", acme, priority="high", estimated_hours=8)
            create_task("Design new REST schema", "Work", acme, priority="high", estimated_hours=12)
            create_task("Migration plan document", "Work", acme, priority="medium", estimated_hours=4)
        globex = create_task("Globex - Dashboard MVP", "Work", clients, priority="medium", due_date=future(30))
        if globex:
            create_task("Wireframe review with client", "Work", globex, priority="high", due_date=future(4))
            create_task("Implement chart components", "Work", globex, priority="medium", estimated_hours=16)


def seed_personal():
    """Personal domain - 4-5 levels deep, ~35 tasks."""
    print("Personal...")

    # --- Home ---
    home = create_task("Home", "Personal", priority="medium")
    if home:
        reno = create_task("Kitchen renovation", "Personal", home, priority="high", tags=["renovation"], due_date=future(60))
        if reno:
            design = create_task("Design phase", "Personal", reno, priority="high")
            if design:
                create_task("Collect Pinterest inspo", "Personal", design, priority="low")
                create_task("Meet with interior designer", "Personal", design, priority="high", due_date=future(7))
                create_task("Finalize floor plan", "Personal", design, priority="high", due_date=future(14))
            procurement = create_task("Procurement", "Personal", reno, priority="medium", due_date=future(30))
            if procurement:
                create_task("Order quartz countertops", "Personal", procurement, priority="high", estimated_hours=2)
                create_task("Select cabinet hardware", "Personal", procurement, priority="medium")
                create_task("Choose backsplash tile", "Personal", procurement, priority="low")
                create_task("Buy new appliances", "Personal", procurement, priority="medium", description="Fridge, dishwasher, oven")
            create_task("Get 3 contractor quotes", "Personal", reno, priority="high", due_date=future(10))

        garden = create_task("Garden spring prep", "Personal", home, priority="low", due_date=future(45))
        if garden:
            create_task("Order seeds online", "Personal", garden, priority="low")
            create_task("Build raised beds", "Personal", garden, priority="low", estimated_hours=6)
            create_task("Set up drip irrigation", "Personal", garden, priority="low", estimated_hours=4)

    # --- Family ---
    family = create_task("Family", "Personal", priority="high")
    if family:
        vacation = create_task("Summer trip to Japan", "Personal", family, priority="medium", due_date=future(120), tags=["travel"])
        if vacation:
            create_task("Apply for rail pass", "Personal", vacation, priority="high", due_date=future(60))
            create_task("Book Tokyo hotel", "Personal", vacation, priority="high", due_date=future(75))
            create_task("Create daily itinerary", "Personal", vacation, priority="medium", estimated_hours=4)
            create_task("Get travel insurance", "Personal", vacation, priority="medium", due_date=future(90))
        create_task("Plan mom's birthday dinner", "Personal", family, priority="high", due_date=future(18))
        create_task("Schedule family photo session", "Personal", family, priority="low", due_date=future(30))

    # --- Finance ---
    finance = create_task("Finance", "Personal", priority="high", tags=["money"])
    if finance:
        taxes = create_task("Tax preparation 2026", "Personal", finance, priority="high", due_date=future(60))
        if taxes:
            create_task("Gather W-2 and 1099 forms", "Personal", taxes, priority="high", due_date=future(14))
            create_task("Organize receipts for deductions", "Personal", taxes, priority="medium", estimated_hours=3)
            create_task("Schedule CPA appointment", "Personal", taxes, priority="high", due_date=future(21))
        create_task("Review investment portfolio", "Personal", finance, priority="medium", due_date=future(7))
        create_task("Update household budget", "Personal", finance, priority="medium")


def seed_health():
    """Health domain - 4-5 levels deep, ~35 tasks."""
    print("Health...")

    # --- Fitness ---
    fitness = create_task("Fitness", "Health", priority="high", tags=["fitness"])
    if fitness:
        running = create_task("Marathon training", "Health", fitness, priority="high", due_date=future(90), description="Target: sub 4 hour marathon")
        if running:
            base = create_task("Base building phase", "Health", running, priority="high", due_date=future(30))
            if base:
                create_task("3x easy runs per week", "Health", base, priority="high")
                create_task("1x long run (increase 10% weekly)", "Health", base, priority="high")
                create_task("Track mileage in Strava", "Health", base, priority="low")
            speed = create_task("Speed work phase", "Health", running, priority="medium", due_date=future(60))
            if speed:
                create_task("Interval training Tuesdays", "Health", speed, priority="high")
                create_task("Tempo runs Thursdays", "Health", speed, priority="high")
                create_task("Hill repeats bi-weekly", "Health", speed, priority="medium")
            create_task("Buy new running shoes", "Health", running, priority="medium", due_date=future(7))

        strength = create_task("Strength training", "Health", fitness, priority="medium", tags=["gym"])
        if strength:
            upper = create_task("Upper body program", "Health", strength, priority="medium")
            if upper:
                create_task("Bench press progression", "Health", upper, priority="medium")
                create_task("Pull-up program (target: 15 reps)", "Health", upper, priority="medium")
                create_task("Shoulder mobility routine", "Health", upper, priority="low")
            create_task("Lower body 2x per week", "Health", strength, priority="medium")
            create_task("Core work daily (10 min)", "Health", strength, priority="low")

    # --- Nutrition ---
    nutrition = create_task("Nutrition", "Health", priority="medium", tags=["nutrition"])
    if nutrition:
        mealprep = create_task("Meal prep system", "Health", nutrition, priority="medium")
        if mealprep:
            create_task("Plan weekly menu template", "Health", mealprep, priority="medium", estimated_hours=1)
            create_task("Batch cook proteins Sundays", "Health", mealprep, priority="medium")
            create_task("Prep snack boxes", "Health", mealprep, priority="low")
        create_task("Track macros for 30 days", "Health", nutrition, priority="medium", due_date=future(30))
        create_task("Research creatine supplementation", "Health", nutrition, priority="low", estimated_hours=2)

    # --- Mental Health ---
    mental = create_task("Mental wellness", "Health", priority="high", tags=["mindfulness"])
    if mental:
        create_task("Morning meditation 10 min daily", "Health", mental, priority="high")
        create_task("Journal 3 gratitudes each night", "Health", mental, priority="medium")
        create_task("Digital detox Sundays", "Health", mental, priority="low")
        create_task("Schedule therapy check-in", "Health", mental, priority="high", due_date=future(10))


def seed_learning():
    """Learning domain - 4-5 levels deep, ~35 tasks."""
    print("Learning...")

    # --- Software Engineering ---
    swe = create_task("Software Engineering", "Learning", priority="high", tags=["coding"])
    if swe:
        systems = create_task("System design mastery", "Learning", swe, priority="high", estimated_hours=40)
        if systems:
            create_task("Read Designing Data-Intensive Applications", "Learning", systems, priority="high", estimated_hours=20)
            patterns = create_task("Practice design patterns", "Learning", systems, priority="medium")
            if patterns:
                create_task("URL shortener design", "Learning", patterns, priority="medium", estimated_hours=3)
                create_task("Chat system architecture", "Learning", patterns, priority="medium", estimated_hours=4)
                create_task("Rate limiter implementation", "Learning", patterns, priority="medium", estimated_hours=3)
                create_task("Distributed cache design", "Learning", patterns, priority="high", estimated_hours=5)
            create_task("Watch MIT distributed systems lectures", "Learning", systems, priority="medium", estimated_hours=12)

        flutter = create_task("Advanced Flutter", "Learning", swe, priority="high", tags=["flutter"])
        if flutter:
            create_task("Custom render objects deep dive", "Learning", flutter, priority="medium", estimated_hours=8)
            create_task("Riverpod advanced patterns", "Learning", flutter, priority="high", estimated_hours=6)
            create_task("Platform channels (iOS/Android native)", "Learning", flutter, priority="low", estimated_hours=10)
            create_task("Performance profiling with DevTools", "Learning", flutter, priority="medium", estimated_hours=4)

        rust = create_task("Learn Rust", "Learning", swe, priority="medium", tags=["rust"], description="Systems programming fundamentals")
        if rust:
            create_task("Complete The Rust Book", "Learning", rust, priority="high", estimated_hours=30)
            create_task("Build CLI tool in Rust", "Learning", rust, priority="medium", estimated_hours=12)
            create_task("Solve Advent of Code in Rust", "Learning", rust, priority="low", estimated_hours=20)

    # --- AI/ML ---
    ai = create_task("AI & Machine Learning", "Learning", priority="high", tags=["ai", "ml"])
    if ai:
        llms = create_task("LLM engineering", "Learning", ai, priority="high")
        if llms:
            create_task("Fine-tune a small model on custom data", "Learning", llms, priority="high", estimated_hours=12)
            create_task("Build RAG pipeline from scratch", "Learning", llms, priority="high", estimated_hours=16)
            create_task("Prompt engineering techniques", "Learning", llms, priority="medium", estimated_hours=6)
            create_task("Evaluate model outputs systematically", "Learning", llms, priority="medium", estimated_hours=4)
        create_task("Complete fast.ai course", "Learning", ai, priority="medium", estimated_hours=40, due_date=future(60))
        create_task("Read Attention Is All You Need paper", "Learning", ai, priority="low", estimated_hours=4)

    # --- Languages ---
    lang = create_task("Languages", "Learning", priority="low")
    if lang:
        japanese = create_task("Japanese N4 prep", "Learning", lang, priority="medium", due_date=future(180))
        if japanese:
            create_task("Genki II textbook chapters", "Learning", japanese, priority="medium")
            create_task("Anki kanji deck daily", "Learning", japanese, priority="high")
            create_task("Watch anime without subs 30 min/day", "Learning", japanese, priority="low")


def seed_projects():
    """Projects domain - 4-5 levels deep, ~35 tasks."""
    print("Projects...")

    # --- Open Source ---
    oss = create_task("Open Source", "Projects", priority="medium", tags=["oss", "github"])
    if oss:
        cli = create_task("CLI task manager (Rust)", "Projects", oss, priority="medium", description="Terminal-based task manager with TUI")
        if cli:
            design = create_task("Architecture", "Projects", cli, priority="high")
            if design:
                create_task("Define data model (tasks, tags, projects)", "Projects", design, priority="high", estimated_hours=2)
                create_task("Choose TUI framework (ratatui vs cursive)", "Projects", design, priority="medium", estimated_hours=1)
                create_task("Design command syntax", "Projects", design, priority="medium", estimated_hours=2)
            impl = create_task("Implementation", "Projects", cli, priority="medium")
            if impl:
                create_task("Task CRUD operations", "Projects", impl, priority="high", estimated_hours=8)
                create_task("SQLite storage backend", "Projects", impl, priority="high", estimated_hours=6)
                create_task("TUI rendering and keybindings", "Projects", impl, priority="medium", estimated_hours=12)
                create_task("Import/export (JSON, CSV)", "Projects", impl, priority="low", estimated_hours=4)
            create_task("Write README and docs", "Projects", cli, priority="low", estimated_hours=3)
            create_task("Set up GitHub Actions CI", "Projects", cli, priority="low", estimated_hours=2)

        contrib = create_task("Contribute to existing projects", "Projects", oss, priority="low")
        if contrib:
            create_task("Find good first issues on Flutter repos", "Projects", contrib, priority="low")
            create_task("Submit PR to Riverpod docs", "Projects", contrib, priority="low", estimated_hours=3)

    # --- Content ---
    content = create_task("Content Creation", "Projects", priority="medium", tags=["content"])
    if content:
        blog = create_task("Technical blog", "Projects", content, priority="medium")
        if blog:
            create_task("Write: Building a voice-first app with Flutter", "Projects", blog, priority="high", estimated_hours=6)
            create_task("Write: OKLCH color system in practice", "Projects", blog, priority="medium", estimated_hours=4)
            create_task("Write: Riverpod patterns for real apps", "Projects", blog, priority="medium", estimated_hours=5)
            create_task("Set up blog with Astro", "Projects", blog, priority="medium", estimated_hours=8)

        youtube = create_task("YouTube channel", "Projects", content, priority="low", tags=["video"])
        if youtube:
            create_task("Script: Flutter animation masterclass", "Projects", youtube, priority="low", estimated_hours=4)
            create_task("Record and edit first video", "Projects", youtube, priority="low", estimated_hours=8)
            create_task("Design channel branding", "Projects", youtube, priority="low", estimated_hours=3)

    # --- Startup Idea ---
    startup = create_task("Startup exploration", "Projects", priority="low", tags=["startup"])
    if startup:
        validate = create_task("Idea validation", "Projects", startup, priority="medium")
        if validate:
            create_task("Interview 10 potential users", "Projects", validate, priority="high", estimated_hours=10)
            create_task("Build landing page", "Projects", validate, priority="medium", estimated_hours=6)
            create_task("Run Google Ads experiment ($50 budget)", "Projects", validate, priority="low", estimated_hours=3)
        create_task("Research YC application process", "Projects", startup, priority="low", estimated_hours=2)
        create_task("Draft one-pager pitch", "Projects", startup, priority="low", estimated_hours=3)


def main():
    print("Seeding deep hierarchical tasks...\n")

    # Clear existing tasks
    print("Clearing existing tasks...")
    try:
        req = urllib.request.Request(f"{API_URL}?user_id={USER_ID}", method="DELETE")
        urllib.request.urlopen(req)
    except:
        pass
    print()

    seed_work()
    seed_personal()
    seed_health()
    seed_learning()
    seed_projects()

    print(f"\nDone! Created {created} tasks ({failed} failed)")
    print("Structure: up to 5 levels deep across 5 domains")


if __name__ == "__main__":
    main()

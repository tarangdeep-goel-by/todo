#!/usr/bin/env python3
"""Seed deep hierarchical tasks for VOKL frontend testing"""

import urllib.request
import urllib.parse
import json

API_URL = "http://localhost:8001/api/tasks"
USER_ID = "default-user"

def create_task(title, category, parent_id=None):
    """Create a task and return its ID"""
    data = {
        "user_id": USER_ID,
        "title": title,
        "category": category,
        "transcription": title,
        "status": "active"
    }

    if parent_id:
        data["parent_id"] = parent_id

    try:
        req = urllib.request.Request(
            API_URL,
            data=json.dumps(data).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req) as response:
            task = json.loads(response.read().decode('utf-8'))
            print(f"✓ Created: {title}")
            return task["id"]
    except Exception as e:
        print(f"✗ Failed: {title} - {str(e)}")
        return None

def main():
    print("🌱 Seeding deep hierarchical tasks...")
    print("")

    # Delete all existing tasks
    print("🗑️  Clearing existing tasks...")
    try:
        req = urllib.request.Request(
            f"{API_URL}?user_id={USER_ID}",
            method='DELETE'
        )
        urllib.request.urlopen(req)
    except:
        pass
    print("")

    # Work Domain - After Hours Project
    print("📁 Work Domain...")
    work_after_hours = create_task("After hours", "Work")
    if work_after_hours:
        work_ah_spec = create_task("Spec", "Work", work_after_hours)
        if work_ah_spec:
            create_task("Write API documentation", "Work", work_ah_spec)
            create_task("Design database schema", "Work", work_ah_spec)
            create_task("Document deployment process", "Work", work_ah_spec)

        work_ah_dev = create_task("Development", "Work", work_after_hours)
        if work_ah_dev:
            create_task("Build authentication system", "Work", work_ah_dev)
            create_task("Create user dashboard", "Work", work_ah_dev)
            create_task("Implement payment gateway", "Work", work_ah_dev)

        work_ah_test = create_task("Testing", "Work", work_after_hours)
        if work_ah_test:
            create_task("Write unit tests", "Work", work_ah_test)
            create_task("Run integration tests", "Work", work_ah_test)
            create_task("Perform load testing", "Work", work_ah_test)

    # Work Domain - Client Work
    work_client = create_task("Client work", "Work")
    if work_client:
        work_client_acme = create_task("ACME Corp project", "Work", work_client)
        if work_client_acme:
            create_task("Review requirements doc", "Work", work_client_acme)
            create_task("Design mockups", "Work", work_client_acme)
            create_task("Schedule kickoff meeting", "Work", work_client_acme)

        work_client_beta = create_task("Beta Inc redesign", "Work", work_client)
        if work_client_beta:
            create_task("Audit existing site", "Work", work_client_beta)
            create_task("Create style guide", "Work", work_client_beta)

    # Personal Domain - Home Projects
    print("📁 Personal Domain...")
    personal_home = create_task("Home projects", "Personal")
    if personal_home:
        personal_home_kitchen = create_task("Kitchen renovation", "Personal", personal_home)
        if personal_home_kitchen:
            create_task("Get contractor quotes", "Personal", personal_home_kitchen)
            create_task("Choose countertop material", "Personal", personal_home_kitchen)
            create_task("Order appliances", "Personal", personal_home_kitchen)

        personal_home_garage = create_task("Garage organization", "Personal", personal_home)
        if personal_home_garage:
            create_task("Buy storage shelves", "Personal", personal_home_garage)
            create_task("Sort tools", "Personal", personal_home_garage)
            create_task("Donate old items", "Personal", personal_home_garage)

    # Personal Domain - Family
    personal_family = create_task("Family", "Personal")
    if personal_family:
        personal_vacation = create_task("Summer vacation", "Personal", personal_family)
        if personal_vacation:
            create_task("Research destinations", "Personal", personal_vacation)
            create_task("Book flights", "Personal", personal_vacation)
            create_task("Reserve hotel", "Personal", personal_vacation)

    # Health Domain - Fitness
    print("📁 Health Domain...")
    health_fitness = create_task("Fitness routine", "Health")
    if health_fitness:
        health_cardio = create_task("Cardio training", "Health", health_fitness)
        if health_cardio:
            create_task("Morning run 5k", "Health", health_cardio)
            create_task("Cycling on weekends", "Health", health_cardio)
            create_task("Swimming sessions", "Health", health_cardio)

        health_strength = create_task("Strength training", "Health", health_fitness)
        if health_strength:
            create_task("Upper body workout", "Health", health_strength)
            create_task("Lower body workout", "Health", health_strength)
            create_task("Core exercises", "Health", health_strength)

    # Health Domain - Nutrition
    health_nutrition = create_task("Nutrition plan", "Health")
    if health_nutrition:
        health_meal = create_task("Meal prep", "Health", health_nutrition)
        if health_meal:
            create_task("Plan weekly menu", "Health", health_meal)
            create_task("Buy groceries", "Health", health_meal)
            create_task("Prep Sunday meals", "Health", health_meal)

    # Learning Domain - Programming
    print("📁 Learning Domain...")
    learning_prog = create_task("Programming skills", "Learning")
    if learning_prog:
        learning_flutter = create_task("Flutter mastery", "Learning", learning_prog)
        if learning_flutter:
            create_task("Complete animations course", "Learning", learning_flutter)
            create_task("Build sample app", "Learning", learning_flutter)
            create_task("Study state management", "Learning", learning_flutter)

        learning_ai = create_task("AI/ML fundamentals", "Learning", learning_prog)
        if learning_ai:
            create_task("Watch Stanford lectures", "Learning", learning_ai)
            create_task("Read ML papers", "Learning", learning_ai)
            create_task("Practice on Kaggle", "Learning", learning_ai)

    # Learning Domain - Languages
    learning_lang = create_task("Language learning", "Learning")
    if learning_lang:
        learning_spanish = create_task("Spanish fluency", "Learning", learning_lang)
        if learning_spanish:
            create_task("Daily Duolingo practice", "Learning", learning_spanish)
            create_task("Watch Spanish movies", "Learning", learning_spanish)
            create_task("Conversation practice", "Learning", learning_spanish)

    # Projects Domain - Side Projects
    print("📁 Projects Domain...")
    projects_side = create_task("Side projects", "Projects")
    if projects_side:
        projects_app = create_task("Mobile app idea", "Projects", projects_side)
        if projects_app:
            create_task("Sketch wireframes", "Projects", projects_app)
            create_task("Design UI mockups", "Projects", projects_app)
            create_task("Build MVP", "Projects", projects_app)
            create_task("Beta testing", "Projects", projects_app)

        projects_blog = create_task("Tech blog", "Projects", projects_side)
        if projects_blog:
            create_task("Write about VOKL design", "Projects", projects_blog)
            create_task("Post tutorial on Flutter", "Projects", projects_blog)
            create_task("Share on social media", "Projects", projects_blog)

    # Projects Domain - Content Creation
    projects_content = create_task("Content creation", "Projects")
    if projects_content:
        projects_youtube = create_task("YouTube channel", "Projects", projects_content)
        if projects_youtube:
            create_task("Plan video topics", "Projects", projects_youtube)
            create_task("Record coding tutorial", "Projects", projects_youtube)
            create_task("Edit and publish", "Projects", projects_youtube)

    print("")
    print("✅ Done! Created deep hierarchical tasks (3+ levels)")
    print("📊 Structure: Domain → Level 1 → Level 2 → Level 3")
    print("📱 Pull down to refresh your app to see the tasks!")

if __name__ == "__main__":
    main()

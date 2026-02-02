#!/bin/bash
# Seed deep hierarchical tasks for VOKL frontend testing
# Creates 3+ level task hierarchies

API_URL="http://localhost:8001/api/tasks"
USER_ID="default-user"

echo "🌱 Seeding deep hierarchical tasks..."
echo ""

# Function to create a task and return its ID
create_task() {
    local title="$1"
    local category="$2"
    local parent_id="$3"

    local data
    if [ -z "$parent_id" ]; then
        data="{\"user_id\":\"$USER_ID\",\"title\":\"$title\",\"category\":\"$category\",\"transcription\":\"$title\",\"status\":\"active\"}"
    else
        data="{\"user_id\":\"$USER_ID\",\"title\":\"$title\",\"category\":\"$category\",\"parent_id\":\"$parent_id\",\"transcription\":\"$title\",\"status\":\"active\"}"
    fi

    local response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$data")

    local task_id=$(echo "$response" | jq -r '.id')

    if [ "$task_id" != "null" ] && [ ! -z "$task_id" ]; then
        echo "✓ Created: $title"
        echo "$task_id"
    else
        echo "✗ Failed: $title"
        echo "$response" >&2
        echo ""
    fi
}

# Delete all existing tasks first
echo "🗑️  Clearing existing tasks..."
curl -s -X DELETE "$API_URL?user_id=$USER_ID" > /dev/null 2>&1
sleep 1
echo ""

# Work Domain - After Hours Project
echo "📁 Work Domain..."
work_after_hours=$(create_task "After hours" "Work")
work_ah_spec=$(create_task "Spec" "Work" "$work_after_hours")
create_task "Write API documentation" "Work" "$work_ah_spec"
create_task "Design database schema" "Work" "$work_ah_spec"
create_task "Document deployment process" "Work" "$work_ah_spec"

work_ah_development=$(create_task "Development" "Work" "$work_after_hours")
create_task "Build authentication system" "Work" "$work_ah_development"
create_task "Create user dashboard" "Work" "$work_ah_development"
create_task "Implement payment gateway" "Work" "$work_ah_development"

work_ah_testing=$(create_task "Testing" "Work" "$work_after_hours")
create_task "Write unit tests" "Work" "$work_ah_testing"
create_task "Run integration tests" "Work" "$work_ah_testing"
create_task "Perform load testing" "Work" "$work_ah_testing"

# Work Domain - Client Work
work_client=$(create_task "Client work" "Work")
work_client_acme=$(create_task "ACME Corp project" "Work" "$work_client")
create_task "Review requirements doc" "Work" "$work_client_acme"
create_task "Design mockups" "Work" "$work_client_acme"
create_task "Schedule kickoff meeting" "Work" "$work_client_acme"

work_client_beta=$(create_task "Beta Inc redesign" "Work" "$work_client")
create_task "Audit existing site" "Work" "$work_client_beta"
create_task "Create style guide" "Work" "$work_client_beta"

# Personal Domain - Home Projects
echo "📁 Personal Domain..."
personal_home=$(create_task "Home projects" "Personal")
personal_home_kitchen=$(create_task "Kitchen renovation" "Personal" "$personal_home")
create_task "Get contractor quotes" "Personal" "$personal_home_kitchen"
create_task "Choose countertop material" "Personal" "$personal_home_kitchen"
create_task "Order appliances" "Personal" "$personal_home_kitchen"

personal_home_garage=$(create_task "Garage organization" "Personal" "$personal_home")
create_task "Buy storage shelves" "Personal" "$personal_home_garage"
create_task "Sort tools" "Personal" "$personal_home_garage"
create_task "Donate old items" "Personal" "$personal_home_garage"

# Personal Domain - Family
personal_family=$(create_task "Family" "Personal")
personal_family_vacation=$(create_task "Summer vacation" "Personal" "$personal_family")
create_task "Research destinations" "Personal" "$personal_family_vacation"
create_task "Book flights" "Personal" "$personal_family_vacation"
create_task "Reserve hotel" "Personal" "$personal_family_vacation"

# Health Domain - Fitness
echo "📁 Health Domain..."
health_fitness=$(create_task "Fitness routine" "Health")
health_fitness_cardio=$(create_task "Cardio training" "Health" "$health_fitness")
create_task "Morning run 5k" "Health" "$health_fitness_cardio"
create_task "Cycling on weekends" "Health" "$health_fitness_cardio"
create_task "Swimming sessions" "Health" "$health_fitness_cardio"

health_fitness_strength=$(create_task "Strength training" "Health" "$health_fitness")
create_task "Upper body workout" "Health" "$health_fitness_strength"
create_task "Lower body workout" "Health" "$health_fitness_strength"
create_task "Core exercises" "Health" "$health_fitness_strength"

# Health Domain - Nutrition
health_nutrition=$(create_task "Nutrition plan" "Health")
health_nutrition_meal=$(create_task "Meal prep" "Health" "$health_nutrition")
create_task "Plan weekly menu" "Health" "$health_nutrition_meal"
create_task "Buy groceries" "Health" "$health_nutrition_meal"
create_task "Prep Sunday meals" "Health" "$health_nutrition_meal"

# Learning Domain - Programming
echo "📁 Learning Domain..."
learning_programming=$(create_task "Programming skills" "Learning")
learning_prog_flutter=$(create_task "Flutter mastery" "Learning" "$learning_programming")
create_task "Complete animations course" "Learning" "$learning_prog_flutter"
create_task "Build sample app" "Learning" "$learning_prog_flutter"
create_task "Study state management" "Learning" "$learning_prog_flutter"

learning_prog_ai=$(create_task "AI/ML fundamentals" "Learning" "$learning_programming")
create_task "Watch Stanford lectures" "Learning" "$learning_prog_ai"
create_task "Read ML papers" "Learning" "$learning_prog_ai"
create_task "Practice on Kaggle" "Learning" "$learning_prog_ai"

# Learning Domain - Languages
learning_languages=$(create_task "Language learning" "Learning")
learning_lang_spanish=$(create_task "Spanish fluency" "Learning" "$learning_languages")
create_task "Daily Duolingo practice" "Learning" "$learning_lang_spanish"
create_task "Watch Spanish movies" "Learning" "$learning_lang_spanish"
create_task "Conversation practice" "Learning" "$learning_lang_spanish"

# Projects Domain - Side Projects
echo "📁 Projects Domain..."
projects_side=$(create_task "Side projects" "Projects")
projects_side_app=$(create_task "Mobile app idea" "Projects" "$projects_side")
create_task "Sketch wireframes" "Projects" "$projects_side_app"
create_task "Design UI mockups" "Projects" "$projects_side_app"
create_task "Build MVP" "Projects" "$projects_side_app"
create_task "Beta testing" "Projects" "$projects_side_app"

projects_side_blog=$(create_task "Tech blog" "Projects" "$projects_side")
create_task "Write about VOKL design" "Projects" "$projects_side_blog"
create_task "Post tutorial on Flutter" "Projects" "$projects_side_blog"
create_task "Share on social media" "Projects" "$projects_side_blog"

# Projects Domain - Content Creation
projects_content=$(create_task "Content creation" "Projects")
projects_content_youtube=$(create_task "YouTube channel" "Projects" "$projects_content")
create_task "Plan video topics" "Projects" "$projects_content_youtube"
create_task "Record coding tutorial" "Projects" "$projects_content_youtube"
create_task "Edit and publish" "Projects" "$projects_content_youtube"

echo ""
echo "✅ Done! Created deep hierarchical tasks (3+ levels)"
echo "📊 Structure: Domain → Level 1 → Level 2 → Level 3"
echo "📱 Pull down to refresh your app to see the tasks!"

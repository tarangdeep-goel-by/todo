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

# Career Domain - After Hours Project
echo "📁 Career Domain..."
work_after_hours=$(create_task "After hours" "Career")
work_ah_spec=$(create_task "Spec" "Career" "$work_after_hours")
create_task "Write API documentation" "Career" "$work_ah_spec"
create_task "Design database schema" "Career" "$work_ah_spec"
create_task "Document deployment process" "Career" "$work_ah_spec"

work_ah_development=$(create_task "Development" "Career" "$work_after_hours")
create_task "Build authentication system" "Career" "$work_ah_development"
create_task "Create user dashboard" "Career" "$work_ah_development"
create_task "Implement payment gateway" "Career" "$work_ah_development"

work_ah_testing=$(create_task "Testing" "Career" "$work_after_hours")
create_task "Write unit tests" "Career" "$work_ah_testing"
create_task "Run integration tests" "Career" "$work_ah_testing"
create_task "Perform load testing" "Career" "$work_ah_testing"

# Career Domain - Client Work
work_client=$(create_task "Client work" "Career")
work_client_acme=$(create_task "ACME Corp project" "Career" "$work_client")
create_task "Review requirements doc" "Career" "$work_client_acme"
create_task "Design mockups" "Career" "$work_client_acme"
create_task "Schedule kickoff meeting" "Career" "$work_client_acme"

work_client_beta=$(create_task "Beta Inc redesign" "Career" "$work_client")
create_task "Audit existing site" "Career" "$work_client_beta"
create_task "Create style guide" "Career" "$work_client_beta"

# Home Domain - Home Projects
echo "📁 Home Domain..."
personal_home=$(create_task "Home projects" "Home")
personal_home_kitchen=$(create_task "Kitchen renovation" "Home" "$personal_home")
create_task "Get contractor quotes" "Home" "$personal_home_kitchen"
create_task "Choose countertop material" "Home" "$personal_home_kitchen"
create_task "Order appliances" "Home" "$personal_home_kitchen"

personal_home_garage=$(create_task "Garage organization" "Home" "$personal_home")
create_task "Buy storage shelves" "Home" "$personal_home_garage"
create_task "Sort tools" "Home" "$personal_home_garage"
create_task "Donate old items" "Home" "$personal_home_garage"

# Home Domain - Family
personal_family=$(create_task "Family" "Home")
personal_family_vacation=$(create_task "Summer vacation" "Home" "$personal_family")
create_task "Research destinations" "Home" "$personal_family_vacation"
create_task "Book flights" "Home" "$personal_family_vacation"
create_task "Reserve hotel" "Home" "$personal_family_vacation"

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

# Growth Domain - Programming
echo "📁 Growth Domain..."
learning_programming=$(create_task "Programming skills" "Growth")
learning_prog_flutter=$(create_task "Flutter mastery" "Growth" "$learning_programming")
create_task "Complete animations course" "Growth" "$learning_prog_flutter"
create_task "Build sample app" "Growth" "$learning_prog_flutter"
create_task "Study state management" "Growth" "$learning_prog_flutter"

learning_prog_ai=$(create_task "AI/ML fundamentals" "Growth" "$learning_programming")
create_task "Watch Stanford lectures" "Growth" "$learning_prog_ai"
create_task "Read ML papers" "Growth" "$learning_prog_ai"
create_task "Practice on Kaggle" "Growth" "$learning_prog_ai"

# Growth Domain - Languages
learning_languages=$(create_task "Language learning" "Growth")
learning_lang_spanish=$(create_task "Spanish fluency" "Growth" "$learning_languages")
create_task "Daily Duolingo practice" "Growth" "$learning_lang_spanish"
create_task "Watch Spanish movies" "Growth" "$learning_lang_spanish"
create_task "Conversation practice" "Growth" "$learning_lang_spanish"

# Recreation Domain - Side Projects
echo "📁 Recreation Domain..."
projects_side=$(create_task "Side projects" "Recreation")
projects_side_app=$(create_task "Mobile app idea" "Recreation" "$projects_side")
create_task "Sketch wireframes" "Recreation" "$projects_side_app"
create_task "Design UI mockups" "Recreation" "$projects_side_app"
create_task "Build MVP" "Recreation" "$projects_side_app"
create_task "Beta testing" "Recreation" "$projects_side_app"

projects_side_blog=$(create_task "Tech blog" "Recreation" "$projects_side")
create_task "Write about VOKL design" "Recreation" "$projects_side_blog"
create_task "Post tutorial on Flutter" "Recreation" "$projects_side_blog"
create_task "Share on social media" "Recreation" "$projects_side_blog"

# Recreation Domain - Content Creation
projects_content=$(create_task "Content creation" "Recreation")
projects_content_youtube=$(create_task "YouTube channel" "Recreation" "$projects_content")
create_task "Plan video topics" "Recreation" "$projects_content_youtube"
create_task "Record coding tutorial" "Recreation" "$projects_content_youtube"
create_task "Edit and publish" "Recreation" "$projects_content_youtube"

echo ""
echo "✅ Done! Created deep hierarchical tasks (3+ levels)"
echo "📊 Structure: Domain → Level 1 → Level 2 → Level 3"
echo "📱 Pull down to refresh your app to see the tasks!"

#!/bin/bash
# Seed sample tasks for VOKL frontend testing

API_URL="http://localhost:8001/api/tasks"
USER_ID="default-user"

echo "🌱 Seeding tasks for VOKL frontend testing..."
echo ""

# Function to create a task
create_task() {
    local title="$1"
    local category="$2"
    local description="$3"

    local json=$(cat <<EOF
{
    "user_id": "$USER_ID",
    "title": "$title",
    "category": "$category",
    "transcription": "$title",
    "status": "active"
}
EOF
)

    if curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$json" > /dev/null 2>&1; then
        echo "✓ Created [$category]: $title"
    else
        echo "✗ Failed [$category]: $title"
    fi
}

# Work tasks
create_task "Review project proposal" "Work"
create_task "Update API documentation" "Work"
create_task "Fix authentication bug" "Work"
create_task "Deploy staging environment" "Work"
create_task "Code review for PR #123" "Work"
create_task "Prepare quarterly report" "Work"
create_task "Schedule team meeting" "Work"
create_task "Refactor user service" "Work"

# Personal tasks
create_task "Buy groceries" "Personal"
create_task "Schedule dentist appointment" "Personal"
create_task "Call mom" "Personal"
create_task "Pay electricity bill" "Personal"
create_task "Organize garage" "Personal"
create_task "Book vacation tickets" "Personal"
create_task "Return library books" "Personal"

# Health tasks
create_task "Morning jog" "Health"
create_task "Meal prep for the week" "Health"
create_task "Take vitamins" "Health"
create_task "Schedule annual checkup" "Health"
create_task "Yoga session" "Health"
create_task "Track water intake" "Health"
create_task "Sleep before 11pm" "Health"

# Learning tasks
create_task "Complete React tutorial" "Learning"
create_task "Read chapter 3 of design book" "Learning"
create_task "Practice Spanish vocabulary" "Learning"
create_task "Watch ML course lecture" "Learning"
create_task "Solve 3 LeetCode problems" "Learning"
create_task "Learn about OKLCH colors" "Learning"
create_task "Study Flutter animations" "Learning"

# Projects tasks
create_task "Design new landing page" "Projects"
create_task "Build portfolio website" "Projects"
create_task "Write blog post about AI" "Projects"
create_task "Create side project roadmap" "Projects"
create_task "Sketch app wireframes" "Projects"
create_task "Record podcast episode" "Projects"
create_task "Edit YouTube video" "Projects"

echo ""
echo "✅ Done! Created tasks across all 5 domains"
echo "📱 Pull down to refresh your app to see the tasks!"

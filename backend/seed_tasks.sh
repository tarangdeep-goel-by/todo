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

# Career tasks
create_task "Review project proposal" "Career"
create_task "Update API documentation" "Career"
create_task "Fix authentication bug" "Career"
create_task "Deploy staging environment" "Career"
create_task "Code review for PR #123" "Career"
create_task "Prepare quarterly report" "Career"
create_task "Schedule team meeting" "Career"
create_task "Refactor user service" "Career"

# Home tasks
create_task "Buy groceries" "Home"
create_task "Schedule dentist appointment" "Home"
create_task "Call mom" "Home"
create_task "Pay electricity bill" "Home"
create_task "Organize garage" "Home"
create_task "Book vacation tickets" "Home"
create_task "Return library books" "Home"

# Health tasks
create_task "Morning jog" "Health"
create_task "Meal prep for the week" "Health"
create_task "Take vitamins" "Health"
create_task "Schedule annual checkup" "Health"
create_task "Yoga session" "Health"
create_task "Track water intake" "Health"
create_task "Sleep before 11pm" "Health"

# Growth tasks
create_task "Complete React tutorial" "Growth"
create_task "Read chapter 3 of design book" "Growth"
create_task "Practice Spanish vocabulary" "Growth"
create_task "Watch ML course lecture" "Growth"
create_task "Solve 3 LeetCode problems" "Growth"
create_task "Learn about OKLCH colors" "Growth"
create_task "Study Flutter animations" "Growth"

# Recreation tasks
create_task "Design new landing page" "Recreation"
create_task "Build portfolio website" "Recreation"
create_task "Write blog post about AI" "Recreation"
create_task "Create side project roadmap" "Recreation"
create_task "Sketch app wireframes" "Recreation"
create_task "Record podcast episode" "Recreation"
create_task "Edit YouTube video" "Recreation"

echo ""
echo "✅ Done! Created tasks across all 8 domains"
echo "📱 Pull down to refresh your app to see the tasks!"

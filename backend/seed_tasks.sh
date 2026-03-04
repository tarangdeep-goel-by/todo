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
create_task "Prepare quarterly report" "Career"
create_task "Schedule team meeting" "Career"
create_task "Update resume" "Career"

# Finance tasks
create_task "Review monthly budget" "Finance"
create_task "File tax documents" "Finance"
create_task "Set up automatic savings transfer" "Finance"
create_task "Cancel unused subscriptions" "Finance"

# Health tasks
create_task "Morning jog" "Health"
create_task "Meal prep for the week" "Health"
create_task "Schedule annual checkup" "Health"
create_task "Track water intake" "Health"

# Relationships tasks
create_task "Call mom" "Relationships"
create_task "Plan date night" "Relationships"
create_task "Write thank you note to mentor" "Relationships"
create_task "Catch up with college friends" "Relationships"

# Growth tasks
create_task "Read chapter 3 of design book" "Growth"
create_task "Practice Spanish vocabulary" "Growth"
create_task "Watch ML course lecture" "Growth"
create_task "Complete online certification module" "Growth"

# Recreation tasks
create_task "Plan weekend hiking trip" "Recreation"
create_task "Try new restaurant downtown" "Recreation"
create_task "Finish reading novel" "Recreation"
create_task "Book movie tickets" "Recreation"

# Home tasks
create_task "Buy groceries" "Home"
create_task "Organize garage" "Home"
create_task "Fix leaky kitchen faucet" "Home"
create_task "Deep clean bathroom" "Home"

# Community tasks
create_task "Sign up for neighborhood cleanup" "Community"
create_task "Volunteer at food bank Saturday" "Community"
create_task "Attend town hall meeting" "Community"
create_task "Donate old clothes" "Community"

echo ""
echo "✅ Done! Created tasks across all 8 domains"
echo "📱 Pull down to refresh your app to see the tasks!"

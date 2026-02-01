#!/bin/bash

# Script to create a complex task tree for testing
# Creates 50+ tasks across 4 levels

USER_ID="complex-test-user"
API_URL="http://localhost:8001/api/agent/process"

# Helper function to send prompts
send_prompt() {
    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"transcription\": \"$1\", \"user_id\": \"$USER_ID\"}" | jq -r '.message'
}

echo "🌳 Building complex task tree with 50+ tasks across 4 levels..."
echo ""

# LEVEL 1 - Top level categories
echo "📁 Level 1: Top-level categories"
send_prompt "Add Project Alpha to work"
send_prompt "Add Project Beta to work"
send_prompt "Add Team Management to work"
send_prompt "Add Home Projects to personal"
send_prompt "Add Health and Fitness to personal"
send_prompt "Add Learning to personal"
send_prompt "Add Errands to personal"
echo ""

# LEVEL 2 - Main project areas
echo "📁 Level 2: Main areas"
send_prompt "Add Backend Development under Project Alpha"
send_prompt "Add Frontend Development under Project Alpha"
send_prompt "Add DevOps under Project Alpha"
send_prompt "Add iOS Development under Project Beta"
send_prompt "Add Android Development under Project Beta"
send_prompt "Add Backend API under Project Beta"
send_prompt "Add weekly one on ones under Team Management"
send_prompt "Add Sprint Planning under Team Management"
send_prompt "Add Code Reviews under Team Management"

send_prompt "Add Kitchen Renovation under Home Projects"
send_prompt "Add Garden Work under Home Projects"
send_prompt "Add Gym Routine under Health and Fitness"
send_prompt "Add Meal Preparation under Health and Fitness"
send_prompt "Add Rust Programming under Learning"
send_prompt "Add Piano Practice under Learning"
send_prompt "Add Grocery Shopping under Errands"
send_prompt "Add Bank Tasks under Errands"
send_prompt "Add Car Maintenance under Errands"
echo ""

# LEVEL 3 - Specific task groups
echo "📁 Level 3: Specific task groups"
send_prompt "Add API Endpoints under Backend Development"
send_prompt "Add Database Migrations under Backend Development"
send_prompt "Add Authentication System under Backend Development"
send_prompt "Add Component Library under Frontend Development"
send_prompt "Add State Management under Frontend Development"
send_prompt "Add CI/CD Pipeline under DevOps"
send_prompt "Add Monitoring Setup under DevOps"

send_prompt "Add UI Components under iOS Development"
send_prompt "Add API Integration under iOS Development"
send_prompt "Add Material Design under Android Development"
send_prompt "Add Navigation Flow under Android Development"

send_prompt "Add Get Contractor Quotes under Kitchen Renovation"
send_prompt "Add Choose Materials under Kitchen Renovation"
send_prompt "Add Plant Vegetables under Garden Work"
send_prompt "Add Build Raised Beds under Garden Work"

send_prompt "Add Upper Body Workout under Gym Routine"
send_prompt "Add Lower Body Workout under Gym Routine"
send_prompt "Add Cardio Sessions under Gym Routine"
send_prompt "Add Weekly Meal Prep under Meal Preparation"
send_prompt "Add Healthy Recipes under Meal Preparation"
echo ""

# LEVEL 4 - Individual tasks
echo "📁 Level 4: Individual tasks (deepest level)"
send_prompt "Add implement user login endpoint under API Endpoints"
send_prompt "Add add JWT token validation under API Endpoints"
send_prompt "Add create tasks CRUD endpoints under API Endpoints"
send_prompt "Add add pagination support under API Endpoints"

send_prompt "Add create initial schema under Database Migrations"
send_prompt "Add add user preferences table under Database Migrations"
send_prompt "Add optimize task queries with indexes under Database Migrations"

send_prompt "Add research OAuth providers under Authentication System"
send_prompt "Add implement password hashing under Authentication System"
send_prompt "Add add two factor authentication under Authentication System"

send_prompt "Add build reusable button components under Component Library"
send_prompt "Add create modal dialog system under Component Library"
send_prompt "Add design form input components under Component Library"

send_prompt "Add setup Redux store under State Management"
send_prompt "Add implement task actions and reducers under State Management"

send_prompt "Add configure GitHub Actions workflow under CI/CD Pipeline"
send_prompt "Add add automated testing step under CI/CD Pipeline"
send_prompt "Add setup production deployment under CI/CD Pipeline"

send_prompt "Add get quotes from three contractors under Get Contractor Quotes"
send_prompt "Add schedule contractor consultations under Get Contractor Quotes"

send_prompt "Add bench press routine under Upper Body Workout"
send_prompt "Add pull up progression under Upper Body Workout"
send_prompt "Add squats and deadlifts under Lower Body Workout"
send_prompt "Add leg press routine under Lower Body Workout"

echo ""
echo "✅ Task tree created! Fetching summary..."
curl -s "http://localhost:8001/api/tasks?user_id=$USER_ID&status=active" | jq '[.[] | {title, category, parent_id}] | length as $count | "Total tasks created: \($count)"'

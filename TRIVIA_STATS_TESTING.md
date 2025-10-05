# Trivia Statistics Feature - Testing Guide

## What Was Implemented

### 1. Database Schema
- Created `trivia_game_stats` table to track:
  - `user_id` - which user played
  - `room_id` - which game room
  - `correct_answers` - number of correct answers
  - `incorrect_answers` - number of incorrect answers
  - `total_score` - points earned in that game

### 2. Backend Changes
- **GameServer** (`lib/amenity/trivia/game_server.ex`):
  - Added `player_stats` tracking to state
  - Modified `calculate_scores_and_stats/5` to track correct/incorrect per player
  - Added `save_game_stats/3` to persist stats when game ends
  - Stats are saved in `:end_game` handler

- **Trivia Context** (`lib/amenity/trivia.ex`):
  - Added `create_game_stats/1` to save individual game stats
  - Added `get_user_stats/1` to aggregate all stats for a user

### 3. Frontend Changes
- **Profile Page** (`lib/amenity_web/live/user_live/profile.ex`):
  - Fetches trivia stats on mount
  - Displays:
    - Games played count
    - Total correct answers
    - Total incorrect answers
    - Total score
    - Accuracy percentage
    - Interactive pie chart

- **Chart.js Integration** (`assets/js/app.js`):
  - Added Chart.js library via npm
  - Created `AccuracyPieChart` hook
  - Pie chart shows correct vs incorrect with hover tooltips
  - Shows percentages on hover

## How to Test

### Step 1: Start the Server
```bash
bash ./start.sh
```

### Step 2: Play a Trivia Game
1. Navigate to `/study/trivia`
2. Create a new trivia room
3. Start the game
4. Answer some questions (mix correct and incorrect answers)
5. Complete the game

### Step 3: Check Your Profile
1. Navigate to `/users/profile`
2. Scroll down to "Trivia Battle Stats" section
3. You should see:
   - Your game count
   - Correct/incorrect answer counts
   - Total score
   - Accuracy percentage
   - **Pie chart** showing the distribution

### Step 4: Verify Stats Update
1. Play another game
2. Refresh your profile page
3. Stats should update with cumulative totals
4. Pie chart should reflect new data

## Debugging

### Check if stats are being saved:
```bash
mix run -e "IO.inspect(Amenity.Repo.all(Amenity.Trivia.GameStats))"
```

### Check logs for a specific user:
The application now logs:
- When stats are saved (in GameServer)
- When stats are loaded (in Profile page)
- Any errors during save

### Check database directly:
```bash
mix ecto.psql
SELECT * FROM trivia_game_stats;
```

## Known Issues to Watch For

1. **Stats not saving**: Check server logs for errors when game ends
2. **Pie chart not rendering**: Check browser console for JavaScript errors
3. **Stats showing 0**: Ensure you completed a full game (not just joined)
4. **Chart.js not loaded**: Run `npm install --prefix assets` if needed

## File Changes Summary

- ✅ Migration: `priv/repo/migrations/*_create_trivia_game_stats.exs`
- ✅ Schema: `lib/amenity/trivia/game_stats.ex`
- ✅ Context: `lib/amenity/trivia.ex` (added stats functions)
- ✅ GameServer: `lib/amenity/trivia/game_server.ex` (tracking & saving)
- ✅ Profile LiveView: `lib/amenity_web/live/user_live/profile.ex`
- ✅ JavaScript: `assets/js/app.js` (Chart.js hook)
- ✅ Dependencies: `assets/package.json` (Chart.js added)

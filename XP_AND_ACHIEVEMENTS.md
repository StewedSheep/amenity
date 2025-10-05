# XP and Achievements System

## Overview
A complete gamification system has been added to track user progress through XP (Experience Points), Levels, and Achievements based on trivia game performance.

## Database Changes

### Users Table
Added three new fields:
- `xp` (integer, default: 0) - Total experience points earned
- `level` (integer, default: 1) - Current level based on XP
- `achievements` (array of strings, default: []) - List of unlocked achievement IDs

## XP System

### How XP is Awarded
When a trivia game ends, each player receives XP based on:
- **10 XP per correct answer**
- **Bonus XP from score** (score ÷ 100)

Example: 
- 5 correct answers = 50 XP
- Score of 3500 = 35 bonus XP
- **Total: 85 XP**

### Level Progression
- **Formula**: `level = floor(sqrt(xp / 100)) + 1`
- Level 1: 0 XP
- Level 2: 100 XP
- Level 3: 400 XP
- Level 4: 900 XP
- Level 5: 1600 XP
- And so on...

### XP Display
The profile page shows:
- Current level badge
- Total XP badge
- Progress bar to next level
- XP remaining to next level

## Achievements System

### Available Achievements

1. **🎉 First Victory**
   - Description: Complete your first trivia game
   - Requirement: Play 1 game

2. **💯 Perfect Game**
   - Description: Get all answers correct in a game
   - Requirement: 5+ correct answers with 0 incorrect

3. **🎓 Trivia Master**
   - Description: Play 10 trivia games
   - Requirement: Complete 10 games

4. **📚 Scholar**
   - Description: Get 50 correct answers
   - Requirement: 50+ total correct answers

5. **⭐ High Scorer**
   - Description: Reach 5000 total score
   - Requirement: 5000+ total score

### Achievement Display
- Achievements section on profile page
- Shows unlocked achievements with icons and descriptions
- Empty state encourages playing trivia games

## Technical Implementation

### Backend Functions

#### Accounts Context (`lib/amenity/accounts.ex`)
- `award_xp(user, xp_amount)` - Awards XP and auto-levels up
- `calculate_level(xp)` - Calculates level from XP
- `unlock_achievement(user, achievement_id)` - Unlocks an achievement
- `check_trivia_achievements(user, trivia_stats)` - Checks and unlocks eligible achievements

#### GameServer (`lib/amenity/trivia/game_server.ex`)
- `save_game_stats/3` - Saves stats and triggers XP/achievement awards
- `award_xp_and_achievements/3` - Awards XP and checks achievements after each game

### Frontend Display

#### Profile Page (`lib/amenity_web/live/user_live/profile.ex`)
Shows:
1. **Profile Header**
   - Level badge
   - XP badge
   - XP progress bar
   - XP to next level

2. **Achievements Section**
   - Grid of unlocked achievements
   - Achievement icons, names, and descriptions
   - Empty state for no achievements

3. **Trivia Statistics**
   - Games played
   - Correct/incorrect answers
   - Total score
   - Accuracy rate
   - Interactive pie chart

## Workflow

### When a Trivia Game Ends:

1. **Stats are saved** to `trivia_game_stats` table
2. **XP is calculated** based on correct answers and score
3. **XP is awarded** to the user
4. **Level is recalculated** automatically
5. **Achievements are checked** against current stats
6. **New achievements are unlocked** if requirements are met
7. **Logs are generated** for debugging

### Server Logs Show:
```
[info] Saving game stats for room 123: %{1 => %{correct: 5, incorrect: 2}}
[info] Successfully saved stats for user 1
[info] Awarding 85 XP to user 1
[info] User 1 now has 285 XP (Level 2)
[info] User 1 achievements: ["first_victory"]
```

## Testing

### Test XP Award:
1. Play a trivia game
2. Answer questions (mix correct/incorrect)
3. Complete the game
4. Check profile page for updated XP and level

### Test Achievements:
1. **First Victory**: Complete any game
2. **Perfect Game**: Answer all questions correctly
3. **Trivia Master**: Play 10 games
4. **Scholar**: Get 50+ correct answers total
5. **High Scorer**: Accumulate 5000+ points

### Verify in Database:
```bash
# Check user XP and achievements
mix run -e "user = Amenity.Accounts.get_user(1); IO.inspect(%{xp: user.xp, level: user.level, achievements: user.achievements})"

# Check game stats
mix run -e "IO.inspect(Amenity.Repo.all(Amenity.Trivia.GameStats))"
```

## Future Enhancement Ideas

### More Achievements:
- Speed Demon (Answer 10 questions in under 5 seconds each)
- Bible Expert (Play games from 20 different books)
- Streak Master (Win 5 games in a row)
- Social Butterfly (Play with 10 different players)

### Leaderboards:
- Top XP earners
- Highest level players
- Most achievements unlocked
- Best accuracy rate

### Rewards:
- Profile badges
- Custom profile themes
- Special icons
- Title system

### XP Sources:
- Daily login bonus
- Reading Bible chapters
- Creating flashcards
- Helping friends

## Files Modified

1. **Migration**: `priv/repo/migrations/*_add_xp_and_achievements_to_users.exs`
2. **User Schema**: `lib/amenity/accounts/user.ex`
3. **Accounts Context**: `lib/amenity/accounts.ex`
4. **GameServer**: `lib/amenity/trivia/game_server.ex`
5. **Profile LiveView**: `lib/amenity_web/live/user_live/profile.ex`

## Summary

The gamification system is now fully integrated! Users will:
- ✅ Earn XP for playing trivia games
- ✅ Level up automatically
- ✅ Unlock achievements based on performance
- ✅ See their progress on their profile page
- ✅ Get motivated to play more and improve

All XP and achievement awards happen automatically when a trivia game ends. No manual intervention needed!

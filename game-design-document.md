# Lost Little Ghost — Game Design Document

## 1. Game Overview

**Title:** Lost Little Ghost  
**Genre:** 2D side-scrolling platformer  
**Tone:** Cute, whimsical, cozy-spooky gothic  
**Estimated playtime:** 5–8 minutes  
**Development scope:** Mini-project, approximately 2.5 days  
**Technology / engine:** TBD — keep the design implementation-agnostic until the stack is chosen.

### High Concept

A little ghost is lost outside at night and must cross a graveyard and haunted woods to reach its haunted home before sunrise — without becoming corrupted into an evil ghost.

### One-Sentence Pitch

> A little ghost must cross a sleeping world, avoid ghost hunters and corrupted spirits, and reach its haunted home before sunrise without losing its good soul.

---

## 2. Assignment Requirements

### Must Have

- Player avatar
- Jump
- Background
- Enemy
- End portal

### Extra Features Used

This game includes at least three optional assignment features:

- Double jump
- Items / Powerup
- Dangerous objects

### Nice-to-Have

- Parallax scrolling background
- Dynamic sunrise progression
- Particles
- Fog
- Extra animation
- Music and sound effects

---

## 3. Player Goal

The player must travel through three connected areas:

1. Graveyard
2. Haunted Woods
3. Haunted House Grounds

The final goal is to enter the open window of the haunted house before sunrise.

The sunrise is primarily a **visual narrative progression**, not a strict countdown timer.

---

# 4. Core Gameplay Loop

**Move → Jump → Avoid danger → Collect Good Spirit Orbs → Manage SOUL → Reach the next area**

Occasionally:

**Collect Soul Orb → Activate Shadow Mode → Pass dangerous light / corrupted areas**

---

# 5. Player Character

## Little Ghost

A small, friendly ghost who is trying to return home before dawn.

### Movement

- Move left
- Move right
- Jump
- Double jump

### Movement Feel

The ghost should feel slightly floaty.

Recommended starting feel:

- Responsive horizontal movement
- Medium jump height
- Slightly slower falling than a normal platform character
- Double jump gives enough height to reach clearly higher platforms

### Optional Movement Feature

**Hold Jump → Slow Fall**

Only add this if the core game is already working.

---

# 6. SOUL System

The player does not use a normal health bar.

Instead, the player has:

## SOUL

Three **Spirit Hearts** represent how much of Little Ghost's good soul remains.

### Starting State

`GOOD | 👻 👻 👻`

All three Spirit Hearts begin pure.

### Corruption

The following cause **1 Spirit Heart to become corrupted**:

- Touching a Bad Spirit Orb
- Touching Ghost Hunter light
- Touching a Ghost Hunter

Example:

`SOUL | 😈 👻 👻`

Then:

`SOUL | 😈 😈 👻`

### Evil Ghost State

If all three Spirit Hearts become corrupted:

`SOUL | 😈 😈 😈`

Little Ghost becomes an **Evil Ghost**.

Then:

1. Play a short corruption effect or animation.
2. Fade / reset.
3. Respawn at the latest checkpoint.
4. Restore SOUL to three Good Spirit Hearts.

### Hit Feedback

Recommended:

- Brief flash or transparency effect
- Small knockback
- Approximately 1 second of temporary hit immunity

These values can be adjusted during playtesting.

---

# 7. Good Spirit Orbs

Good Spirit Orbs are friendly spirits that help Little Ghost stay good and find the way home.

### Function

When collected:

- If SOUL is corrupted, restore **1 corrupted Spirit Heart**
- If SOUL is already full, simply count the orb as collected
- Help visually guide the player through the level

### Visual Style

- Pale blue / white
- Soft glow
- Friendly, round shape
- Calm movement

### Optional Score

Display:

`Spirit Orbs: 0 / X`

This is optional and should not block completion of the game.

---

# 8. Bad Spirit Orbs

Bad Spirit Orbs are corrupted spirits.

### Function

Touching one:

- Corrupts 1 Spirit Heart
- Causes the same brief hit feedback as other hazards

### Visual Style

- Dark purple
- Uneven or sharp silhouette
- Faster or more unstable floating animation
- Evil eyes / expression if time allows

### Level Design Purpose

Bad Orbs should be placed where the player must carefully control jumps.

They are hazards, not enemies that chase the player.

---

# 9. Soul Orb / Shadow Power

A large, special orb gives Little Ghost temporary protection.

## Shadow Mode

### Activation

Shadow Mode activates automatically when the player collects a Soul Orb.

### Duration

Recommended starting value:

**5 seconds**

### During Shadow Mode

Little Ghost:

- Becomes semi-transparent
- Cannot be corrupted by Ghost Hunter light
- Cannot be corrupted by Bad Spirit Orbs

Optional:

- Ghost Hunters also cannot damage the player during Shadow Mode

### Purpose

Shadow Mode should appear only **1–2 times** in the whole game.

It is used to pass one clearly dangerous section rather than becoming a constantly managed ability.

### Visual Difference

Soul Orb must look clearly different from normal Good Spirit Orbs:

- Larger
- Stronger glow
- More magical animation

---

# 10. Enemy — Ghost Hunter

The game should initially use only **one enemy type**.

## Behaviour

Ghost Hunter patrols between two points.

Pattern:

`← patrol → turn around → patrol ←`

### Flashlight

The Ghost Hunter projects a visible cone of light in the direction they are facing.

When the hunter turns:

- The light cone turns with them.

### Damage

Touching:

- Ghost Hunter body → +1 corruption
- Flashlight cone → +1 corruption

### Design Goal

The player should mainly:

- Jump over the hunter
- Wait for the hunter to turn
- Take an alternate platform route
- Use Shadow Mode when available

### Do Not Add

For the first playable version, do not add:

- Shooting
- Complex vision AI
- Pathfinding
- Alert states
- Combat
- Multiple enemy types

---

# 11. Dangerous Objects

Keep hazards thematically connected to the world.

## Graveyard Hazards

Possible objects:

- Broken iron fence
- Sharp grave decorations
- Dangerous gaps

## Haunted Woods Hazards

Primary hazards:

- Bad Spirit Orbs
- Ghost Hunter light

Possible environmental objects:

- Sharp roots
- Dangerous gaps between platforms

## Haunted House Grounds

Combine:

- Bad Spirit Orbs
- Ghost Hunters
- Light
- Larger platform gaps

---

# 12. Checkpoints

Use simple checkpoints between major areas.

### Checkpoint Structure

**Start → Graveyard → Checkpoint → Haunted Woods → Checkpoint → Haunted House Grounds → End**

When the player becomes an Evil Ghost:

- Return to latest checkpoint
- Restore full SOUL

Checkpoint visuals can be extremely simple.

Possible visual:

- Small friendly ghost flame
- Glowing lantern
- Spirit marker

---

# 13. World Progression

The environment tells the story of time passing.

## Area 1

**Night**

- Deep blue / dark sky
- Bright moon
- Heavy fog
- Haunted house visible very far away

## Area 2

**Late Night / Early Dawn**

- Dark blue transitions toward purple
- Slightly more light in the background
- Haunted house appears closer

## Area 3

**Sunrise**

- Purple / pink / orange horizon
- The house dominates the background
- Player feels close to safety

There does not need to be a strict countdown timer.

---

# 14. Area 1 — Graveyard

## Purpose

Teach the player the basic controls and introduce the first danger.

### Environment

- Gravestones
- Broken stone walls
- Large grave monument
- Dead trees
- Cemetery gate
- Moon
- Fog
- Haunted house visible in the distance

### Gameplay Sequence

#### 1. Start

Little Ghost appears in a quiet graveyard.

Optional intro text:

> The sun will rise soon.  
> Find your way home.

#### 2. Movement

Give the player safe ground to learn:

- Left
- Right

#### 3. First Jump

A small gravestone blocks the route.

Player must jump over it.

#### 4. First Good Spirit Orb

Place a Good Spirit Orb along the obvious route.

This introduces collecting.

#### 5. Double Jump Tutorial

Place a large grave monument that cannot be crossed with a single jump.

Player must:

**Jump → Double Jump**

#### 6. First Ghost Hunter

Introduce one slow patrol Ghost Hunter.

Give the player enough space to understand the movement pattern.

#### 7. Exit

Player reaches the cemetery gate.

This leads into Haunted Woods.

### Area 1 Learning Goal

By the end of Area 1, the player understands:

- Movement
- Jump
- Double jump
- Good Spirit Orbs
- Ghost Hunter

---

# 15. Area 2 — Haunted Woods

## Purpose

Introduce the game's main danger system:

> Don't touch the light.  
> Don't touch corrupted spirits.

### Environment

Platform surfaces can include:

- Tree roots
- Fallen trees
- Tree stumps
- Rocks
- Low branches

Background:

- Twisted trees
- Fog
- Moon partially hidden
- Haunted house closer in the distance

### Gameplay Sequence

#### 1. Root Platforms

Simple jumps between tree roots and rocks.

#### 2. First Bad Spirit Orb

Place one Bad Spirit Orb in the player's path.

The player learns:

> Purple / corrupted spirits are dangerous.

#### 3. First Major Light Challenge

A Ghost Hunter patrols underneath or near platforms.

The player must avoid the flashlight cone.

#### 4. Good Spirit Orb

Place a Good Spirit Orb shortly after danger.

If the player was corrupted, it demonstrates that Good Orbs restore SOUL.

#### 5. Soul Orb

Introduce the large special Soul Orb.

Collecting it activates:

**SHADOW MODE**

#### 6. Shadow Mode Challenge

Immediately follow the powerup with a short section containing:

- Strong light
- Bad Spirit Orbs
- Or a Ghost Hunter

This teaches the player what Shadow Mode does without requiring long instructions.

#### 7. Exit

The trees begin to open.

The haunted house is now clearly visible.

### Area 2 Learning Goal

By the end of Area 2, the player understands:

- Bad Spirit Orbs
- SOUL corruption
- Good Spirit Orb healing
- Ghost Hunter light
- Shadow Mode

---

# 16. Area 3 — Haunted House Grounds

## Purpose

Combine all mechanics the player has learned.

Do not introduce major new systems here.

### Environment

- Old stone walls
- Trees
- Fence sections
- Rocks
- House exterior
- Porch / window
- Sunrise behind the trees

### Gameplay Sequence

#### 1. Harder Platforming

Use slightly larger gaps and more vertical movement.

#### 2. Combined Hazards

Combine:

- Platforms
- Bad Spirit Orbs
- Ghost Hunter patrol
- Flashlight cone

#### 3. Good Orb Opportunity

Provide one final opportunity to restore SOUL before the final challenge.

#### 4. Final Ghost Hunter

Use the same Ghost Hunter logic as before.

Make the encounter harder using:

- Longer patrol route
- Platform placement
- Larger light zone

Do not create a new enemy AI.

#### 5. Final Gap

Place a large gap between the player and the house.

The player must use a double jump.

#### 6. End Portal

The open window of the haunted house is the portal.

Player jumps through the window.

---

# 17. Ending

When Little Ghost enters the window:

1. Stop normal gameplay.
2. Fade to black.
3. Show a simple ending scene or end screen.

### Ending Text

> HOME AT LAST  
> Still a good ghost.

Optional:

`Spirit Orbs: X / X`

Button:

**Play Again**

---

# 18. Story Structure

## Beginning — Lost

Little Ghost wakes up alone in the graveyard.

The night is ending.

The haunted house can be seen far away.

Good spirits begin guiding Little Ghost home.

---

## Middle — Corruption

Little Ghost enters the Haunted Woods.

Ghost Hunters search through the darkness with flashlights.

Corrupted spirits appear.

The player discovers that Little Ghost can slowly become corrupted.

Good Spirit Orbs help Little Ghost remain good.

A Soul Orb temporarily grants Shadow Mode.

---

## End — Home

The sky becomes brighter.

Little Ghost reaches the grounds of the haunted house.

The final section combines:

- Platforming
- Bad Spirit Orbs
- Ghost Hunter
- Dangerous light
- Double jump

Little Ghost makes one final jump into the open window.

The ghost reaches home before sunrise without becoming evil.

---

# 19. UI

Keep the HUD minimal.

## Required HUD

### SOUL

Display three Spirit Hearts.

Example:

`SOUL  👻 👻 👻`

Corrupted example:

`SOUL  😈 👻 👻`

### Optional

Spirit Orb counter:

`ORB  6 / 15`

Avoid adding unnecessary UI.

No traditional health bar is needed.

---

# 20. Art Direction

## Style

- Cute gothic
- Cozy spooky
- Storybook-like
- Simple silhouettes
- Strong readable shapes
- Dark environments with soft glowing objects

## Little Ghost

Good state:

- White / pale blue
- Rounded shape
- Friendly expression
- Soft glow

Corrupted progression, if time allows:

- Slight purple tint after one corruption
- Stronger purple tint after two
- Evil transformation after three

## Visual Readability

Good elements:

- Pale
- Soft
- Blue / white

Danger:

- Purple
- Dark
- Sharp / unstable

Ghost Hunter light:

- Clearly visible against the environment

---

# 21. Audio

Audio is secondary to playable functionality.

## Recommended

- Soft spooky ambient music
- Jump sound
- Good Orb collect sound
- Bad Orb / corruption sound
- Shadow Mode sound
- Ghost Hunter light / alert ambience
- End portal sound

If time is limited, prioritize:

1. Jump
2. Collect
3. Damage
4. End portal

---

# 22. Camera

Recommended:

- 2D side-following camera
- Smooth horizontal follow
- Limited vertical movement
- Keep the player slightly left of center when moving right if easy to implement

Avoid complex cinematic camera systems.

---

# 23. Difficulty Curve

## Area 1

Easy.

Teach one mechanic at a time.

## Area 2

Medium.

Introduce danger and SOUL management.

## Area 3

Hardest.

Combine existing mechanics without introducing new systems.

The player should usually understand why they failed.

---

# 24. Balance — Starting Values

These are recommended starting values, not final values.

- Spirit Hearts: **3**
- Corruption per hazard hit: **1**
- Good Spirit Orb healing: **1**
- Shadow Mode duration: **5 seconds**
- Post-hit invulnerability: **1 second**
- Checkpoints: **2 main checkpoints**
- Ghost Hunter types: **1**
- Soul Orb powerups: **1–2**
- Total game length target: **5–8 minutes**

Tune after playtesting.

---

# 25. MVP — Must Be Playable First

Build in this order:

1. Player movement
2. Jump
3. Platforms / collisions
4. Double jump
5. Camera
6. One complete short test level
7. Ghost Hunter patrol
8. Ghost Hunter light hazard
9. SOUL system
10. Good Spirit Orb
11. Bad Spirit Orb
12. Checkpoint / respawn
13. End portal
14. Three area layout
15. Soul Orb / Shadow Mode
16. Final art pass
17. Audio / effects

Do not start with polish before the complete game can be played from start to finish.

---

# 26. Scope Priority

## MUST HAVE

- Little Ghost player avatar
- Left / right movement
- Jump
- Double jump
- Platforms
- Background
- Ghost Hunter
- Dangerous light
- SOUL system
- Good Spirit Orbs
- Bad Spirit Orbs
- 3 areas
- Checkpoints
- End portal
- Win screen

## SHOULD HAVE

- Soul Orb / Shadow Mode
- Visual sunrise progression
- Simple Ghost Hunter animations
- Basic sound effects

## NICE TO HAVE

- Parallax backgrounds
- Slow-fall
- Particle effects
- Fog animation
- Character corruption appearance
- Orb counter
- Music
- Extra environmental animation

## CUT FIRST IF TIME IS SHORT

- Real countdown timer
- Multiple enemy types
- Combat
- Dialogue system
- Inventory
- Boss fight
- Wall jump
- Complex possession
- Complex enemy AI
- Procedural levels

---

# 27. Core Design Rules for Implementation

When using AI / Codex to build the game:

1. Keep the game small and finishable.
2. Do not add mechanics that are not defined in this document without approval.
3. Reuse the same Ghost Hunter logic throughout the game.
4. Reuse existing platform and hazard systems between areas.
5. Prefer simple, reliable behaviour over technically impressive systems.
6. Every feature should support the core idea:
   **Get home before sunrise without becoming an Evil Ghost.**
7. Build and test one mechanic at a time.
8. Maintain a playable version after every major change.
9. If a feature threatens the deadline, simplify or cut it.
10. The final priority is a complete playable game, not feature quantity.

---

# 28. Final Experience

The intended player experience is:

**Curiosity → Learning → Tension → Risk → Relief**

The player begins as a small vulnerable ghost in a quiet graveyard.

As the journey continues, the world becomes brighter and more dangerous.

The SOUL system creates tension because every bad orb and beam of light brings Little Ghost closer to becoming evil.

Good spirits help the player recover and continue.

The final jump into the haunted house should feel like a small emotional reward:

> Little Ghost made it home — and stayed good.

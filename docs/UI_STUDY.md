# Base screen — UX study (v2.1 → v3.0)

## What was wrong
Looking at the v2.1 base screen on a 1280×720 phone screen in landscape:

1. **Everything at once.** The resource line, the drawing, the chatter box,
   four tabs and a scrolling panel of six building cards all compete for
   attention. Nothing says "this is what to do next".
2. **Resources as a sentence.** "People 6 (3 idle) · Beds 6 Scrap 60 Circuits 8…"
   is a run-on line of numbers. It's hard to find one value quickly.
3. **Tabs at the top.** On a phone held in landscape, thumbs live at the
   bottom corners. Top tabs mean a stretch for every switch.
4. **The drawing is decoration.** The picture of the Rock shows the
   buildings, but you can't touch them. You manage them in a separate list
   of six near-identical grey cards.
5. **Six cards, eight buttons each.** Crew steppers, upgrade, demolish and
   the ammo focus are repeated on every card. It reads as a wall of buttons.
6. **Mission cards are text blocks.** Type, zone, objective and fuel are
   squeezed into two lines of the same colour; the mission type, the most
   important thing, isn't visible at a glance.
7. **Primary action buried.** LAUNCH is at the bottom of a long briefing.
8. **No way out.** There's no menu: no settings, no saving to a slot,
   no quitting.

## Principles for the redesign
- **One focus per tab.** Each tab answers one question:
  *Missions:* where do I go next? *Base:* what do my people do?
  *Brigid:* is my mech ready? *Lab:* what do I improve?
- **Navigation at the thumbs.** A bottom tab bar with four big tabs.
- **Resources as chips.** Each resource gets its own chip: colour swatch,
  big number, small label. People show working/beds.
- **Direct manipulation.** In the Base tab you tap a building site on the
  drawing of the Rock; the side panel shows only that site. Empty sites
  show a short list of what you can build there.
- **Colour means something.** Each mission type has one colour, used on
  its badge everywhere. Gold = story. Green = go/primary. Red = danger.
- **Primary action always visible.** LAUNCH sits at the bottom of the
  briefing panel and never scrolls away. It says why it's disabled.
- **The crew still talks.** Chatter becomes a single radio strip above
  the tab bar: present, but not in the way.
- **A menu button** (top-left) opens Settings, Save & Quit to the main menu.

## New layout
```
┌──────────────────────── music bar ────────────────────────┐
│ ☰  ST. COLUMBA'S ROCK · DAY 7      [People][Scrap][Circ][Bio][Fuel][Ammo] │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                 content of the current tab                   │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ (face) Br. Anselm: The bees don't care about the end…    ›   │
├───────────┬───────────┬───────────┬──────────────────────────┤
│ MISSIONS  │   BASE    │  BRIGID   │   LAB                    │
└───────────┴───────────┴───────────┴──────────────────────────┘
```
- **Missions:** cards on the left (type badge, title, zone, fuel, threat),
  briefing on the right with LAUNCH pinned at the bottom.
- **Base:** the Rock drawing on the left with numbered site markers;
  the selected site's panel on the right.
- **Brigid:** armour with repair on the left, ammunition on the right.
- **Lab:** research cards in two columns.

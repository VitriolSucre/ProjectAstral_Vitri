# UI Changelog

UI and UX changes to ProjectAstral, final results only (no intermediate iterations).
Newest first. The general changelog is `.CHANGELOG.md`.

---

## 2026-10-07 — Talent Builds keep action bars

### Talent Builds (`TalentBuilds.lua`)
- Saving a build also saves the spells, items and macros on action slots 1-120; loading it (directly or through a Loadout) puts them back 1 s after the last talent, and loading an already active build puts them back too. Items need to be in your bags or equipped and macros are found by name; the ones that can't be placed are listed in chat
- Each row's info line shows "N bar actions", or "No action bars saved" in orange for builds saved before this; a new "Save bars" button (orange label when nothing is saved) stores the current layout in that build, only while that build is active
- Leveling build: each spell the character learns is placed in its saved slot when that slot is empty, with a chat line; spells learned in combat are placed when combat ends

## 2026-10-06 — Disenchant tab, hub micro button

### Hub micro button (`MinimapButton.lua`)
- New "Project Astral" button in the game's micro menu bar, between Dungeon Finder and the Game Menu: the Character button's frame and highlight, with the minimap button's Astral hub icon where the portrait goes (dims and shifts when pressed, like the portrait); stays pressed while the hub is open
- Clicking it opens a menu above the bar, in the hub's navy look (navy panel, 1px navy border, gold "PROJECT ASTRAL" title, navy hover wash, 3px gold bar on the open group). It lists the sidebar groups (Progression, Gems, Builds, Activities, Tools); hovering one opens its tabs with their icons in a submenu that grows upward, on the side with room. Picking a tab opens the hub straight on it
- The menu closes on Escape, on picking a tab, on clicking the button again, or shortly after the mouse leaves it

### Disenchant (`DisenchantTab.lua`, `AstralDisenchant.lua`, `MainMenu.lua`)
- New hub tab "Disenchant" in the GEMS group: a grid of every bag item the Astral Table accepts (green/blue/purple weapons and armor, not crafted), best quality and item level first
- Items saved in an equipment set are shown in their own "In your equipment sets" section, greyed out and not selectable
- Click an item to select or unselect it (gold outline, tint and check mark); "Select all" and "Clear" buttons; "Disenchant (n)" sends the selection 9 items per batch, one batch after the other, and the status bar shows the totals (gems, scrolls, lost, mailed)
- "Max price" with a gold box and a silver box (coin icons, remembered between sessions; both empty = no limit): items that sell to a vendor for more move to their own "To sell" line, which can't be selected for disenchanting
- "Sell (n)" button sells every item in the To sell line while a merchant window is open; without one, nothing is touched and the player is told to talk to a vendor first (status bar + red error text). After selling, the status bar shows the item count and the gold earned
- Items the server refuses to disenchant (crafted, wrong quality, not equippable) move to the To sell line on their own, and the rest of their batch is sent again; known crafted items start there. The final status adds "N refused, moved to To sell"
- Tooltips show the vendor price and why an item can't be selected (equipment set, refused by the table and why, or over the max price)
- Auto Import in the Astral Table and the new tab use the same eligibility check
## 2026-10-04 — Unified design: hub frame and Astral Tree

### Hub (`MainMenu.lua`)
- Window, sidebar, content area and section cards use the unified navy look: navy surfaces, 1px navy borders (no rounded tooltip borders), faint blue haze instead of the purple nebula. These colours are fixed and no longer follow the theme colour
- Sidebar: "PROJECT ASTRAL" in gold, group headings in dim blue-grey, tab labels in chat-style text (no outline, 12 px). Active tab = gold tint + 3px gold bar with a white label, hover = navy wash; idle tabs have light grey labels and greyed icons
- Section cards: gold title bar and gold header tint, white title, dim subtitle
- Scroll bar thumb and fullscreen button are navy with the light blue hover

### Astral Tree (`Skilltree.lua`, `Builds.lua`)
- Bottom dock and toolbar on navy; toolbar buttons use chat-style text
- Selected-node panel: navy card with gold tint and gold bar, icon in a navy frame, node name in gold, description in light grey. **Unlock** is a gold outline button
- Total Bonuses panel: navy, gold-barred title, gold group headings, green bonus lines
- Builds window: navy with a gold edge and gold-barred title, navy rows, gold **Load** and **Save Current** buttons; Import/Export dialogs match
- Fix: nodes can be selected again inside the hub (the node layer sat under the pan layer since the hub page was raised)

### Loadouts (`Loadouts.lua`, `Builds.lua`)
- New fourth part: **Astral Tree**, a dropdown with the builds saved in the tree's Builds window. Loading a loadout applies it after the talents and before the gems; the row shows it as "Tree <name>" and marks it active when your tree matches
- The load confirmation now says what will happen to the tree (nodes removed, nodes unlocked and their token cost) along with the talent reset
- If the tree hasn't been loaded from the server yet, the tab fetches it, and Load asks you to try again in a moment instead of skipping the tree
- The four part pickers are navy fields in the unified style instead of Blizzard dropdowns: the part name on the left ("Set", "Gems", "Talents", "Astral Tree"), the chosen build on the right ("None" when empty), a small arrow, a lighter navy on hover and a gold edge once a part is picked. A click opens the list under the field. They share the row width equally and line up in one row (two rows of two on a narrow window)
- What you have on right now is marked everywhere it's listed: the Loadouts pickers show the chosen set / gem / talent / tree build in gold with "active", and their lists mark the active entry; the Astral Tree Builds window gives the build matching your tree the gold tint, gold bar and "Active". (Gem Builds, Talent Builds, Set Builds, Loadouts and the Sets window already did.)
- Loading a loadout shows a **progress bar** in the status bar (Loadouts tab and the character window's Sets window): a gold fill that grows through the steps, the current step (e.g. "Gems: Raid build · Socketing <gem> into Head…") and a "2 / 4" counter. At the end it turns green, or amber if a part was skipped or didn't fully apply, keeps the result text and clears after a few seconds

### Unified look everywhere else
- Remaining hub tabs and windows use the unified navy palette (tinted by the Global UI color): Paragon, Store, Collections, Mount Journal, Raid lockouts, Leaderboards, Reagent Bank, Settings, Update Log, World Map and Player Guide tabs, and the Challenges, Prestige, Great Vault, Astral Table, Mythic (item upgrade, bag role picker), Mythic+ Warden / Upgrade, Personal Loot, Level Reward, Cube of Destiny, Starter Zone and Mount Viewer windows
- Their grey surfaces and borders became navy of the same depth; small text (16 px and under) is chat-style (no outline, black shadow); main action buttons are gold outline
- Window headers (`UI.MakeHeader`): gold title bar, white chat-style title, dim subtitle, navy divider. Blizzard-style buttons and close buttons skinned by the addon are navy
- Default window backgrounds (`UI.AstralBackdrop`, `UI.FlatBackdrop`) are the unified navy; hub tabs and these windows are marked so Theme.lua no longer greys their navy
- No feature or logic changed; layouts are the same
- Cube of Destiny and Token Tracker options windows: navy with a gold edge and glow, unified title, gold Re-roll button, chat-style labels
- Mythic item upgrade and reward role windows: navy with a gold edge instead of the purple dialog border, white title with a gold bar
- In-world overlays (chat window, gem tracker, Mythic+ HUD, token counter, Blizzard frame reskin) use the unified navy colours too; their text keeps its outline so it stays readable over the game world

### Daily Callboard (`DailyCallboard.lua`)
- Unified look: navy window with a gold edge, gold-barred title with the subtitle beside it, and the Astral close button
- Gold status bar under the title (replaces the footer): **Active quests 2 / 3** (amber when full), **Tokens today** against the soft cap with a gold fill showing how far you are, and **Resets in** with the time left; hover explains the active limit and the soft cap
- Category and sort buttons are filter chips (All, Slay, Gather, Craft, Quests, Dungeon · Sort: Tokens / Level)
- Quest list on the dark grey panel: each row has a category-coloured bar and tag (with the profession), white title, light-grey objective, the reward in gold and the level range on the right. Accepted quests get the gold tint and a gold bar, and say "In progress" or "Ready to turn in"
- **Accept** and **Get Reward** are gold buttons, **Abandon** is red; when all quest slots are used, Accept shows "Slots full" and explains why on hover
- "No callboard quests in this filter." when a filter has nothing

### Global UI color (`Core.lua`, `Settings.lua` and every redesigned tab)
- Settings > Global UI color now recolours the whole unified look: navy panels, borders, the hub background haze, hover and selection highlights, filter chips, the Astral Gems figure and the Astral Tree panels all take the chosen colour's hue (keeping their brightness). Gold accents, green/red values, item and tier colours, the Orbs blue and the dark grey list panels don't change
- New **Astral** swatch (the navy-blue look) is the default; a player who still had the old default (Cosmic) is moved to Astral once, so nothing changes until they pick a colour. Cosmic, Red, Blue, Green, Gold, Teal and Custom… tint everything
- Picking a colour saves it; **Reload UI** applies it everywhere
- Gem Stash and Gem Fusion lists use the same dark grey as the build tabs whatever the colour

### Build tabs (`GemBuilds.lua`, `TalentBuilds.lua`, `EquipmentSets.lua`, `Loadouts.lua`)
- Gem Builds, Talent Builds, Set Builds and Loadouts use Gem Stash's gold look: the list sits on the same dark grey panel, and every row has the warm gold gradient and 3px gold bar. The active build / equipped set / active loadout gets a stronger gold tint on top of its "Active" or "Equipped" label

### Astral Disenchant (`AstralDisenchant.lua`, `EquipmentSets.lua`)
- Items saved in an equipment set can't be put in the Disenchant table: shift-click, click or drop is refused with "this item is saved in your equipment set '<name>'", and Import skips them ("kept N items saved in your equipment sets"). Only the exact item the set uses is protected, not other copies of it in your bags

### Stats (`AstralStats.lua`)
- Bonuses flow through the three columns like a newspaper instead of one fixed column per group, so long groups (Quality of Life) no longer run off the page. Groups of up to 10 bonuses stay in one piece; longer ones continue in the next column under a "(continued)" header. Columns are as short as possible and all end at the same height; the area scrolls if it still doesn't fit
- Group headers get the gold title bar; bonuses not listed in any group appear under "Other"
- Summary tiles spread evenly over their rows (5 + 4 instead of 6 + 3)
- Gem Stash tile shows the gem count as its value and the number of types in its label, so it no longer gets cut off

---

## 2026-10-04 — Builds section, Astral Gems character sheet, Stats and hub layout

### Hub (`MainMenu.lua`)
- New **BUILDS** nav group: **Gem Builds** (moved out of GEMS), **Talent Builds**, **Set Builds** and **Loadouts** (formerly Boss Loadouts)
- **Home / Project Astral** and **Account Overview** tabs removed; their content lives in Stats. Old ids (`project_astral`, `home`, `account_overview`, `overview`) open Stats, so a saved start tab still works
- Sidebar search removed; the tab list starts right under "PROJECT ASTRAL" and runs to the bottom of the window. Its scroll bar only shows when the tabs don't fit
- Wallet (Tokens, Orbs, Prestiges, Lockouts) moved from the bottom of the sidebar to compact navy chips in the top bar, between the sidebar and the fullscreen / close buttons; they shrink on narrow windows and keep the count animation and gain pulse

### Talent Builds tab (`TalentBuilds.lua`) — the TalentBuildManager addon, integrated
- Same layout as Gem Builds (without Update): name field, **Save current**, **Import**, build count; gold action bar; rows with the main tree's icon, name, point split ("0/**51**/20 Protection") · saved by · date, and **Leveling**, **Load**, **Export**, **Delete** (two clicks)
- The build matching your current talents gets the gold tint and "Active"; hovering a row lists every talent and rank
- Load: validates class and tree layout; if talents are already spent, asks for confirmation and resets them for free with the server command (same as Reset Talents), then spends points one by one, each confirmed by the client; the action bar shows "Learning <talent> (rank N)…" with a progress bar and the result. Stops on combat, spec change, a refused talent or a timeout
- **Leveling** chip: one leveling build per character gets one point on every level-up (from level 10)
- Export / Import as `TBUILD:1:<CLASS>:<ranks>` (same class only)
- Builds are account-wide (`ProjectAstralTalentBuilds`); the list shows your class's builds
- The **Builds** button stays in the Blizzard talent window, styled like Reset Talents and centred next to it, and opens this tab; **Open Talent Menu** in the tab header opens the talent window and closes the hub
- Migration: each character imports its TalentBuildManager builds (and its leveling choice) on its first login with both addons; the old addon's button, panel and auto-leveling are switched off meanwhile

### Loadouts (`Loadouts.lua`) — Boss Loadouts moved to Builds and reworked
- **Boss Loadouts** (Tools) became **Loadouts** in the BUILDS section; old `boss_loadouts` links open it. Existing presets are kept and renamed "Boss · Name" with their gem build
- A loadout is a name plus any of: an equipment set, a gem build, a talent build (Set / Gems / Talents pickers in the header, **Save loadout**; saving an existing name updates it, **Edit** loads one back into the pickers)
- **Load** (or double-click) puts everything on in order — set, then talents, then gems — each step waiting for the previous one; one confirmation for the free talent reset when needed; the gold bar shows "Loading 'X' · Talents: Prot… (2/3)" and the result
- Rows show each part (gold when active, red with the reason when unusable here: set not on this character, talent build of another class, gem build deleted); a loadout with every part active gets the gold tint and "Active"
- The character window's Sets window has two tabs, **Equipment Sets** and **Loadouts**: the Loadouts view lists them with **Load** / double-click, its own status bar, and **Edit loadouts in the hub**

### Equipment sets (`EquipmentSets.lua`) — character window and Builds > Set Builds
- Built on the client's equipment manager: sets are saved by the server per character (10 max) and swapping takes items from your bags
- **Sets** button in the character window (top right, Reset Talents style) opens an Astral-style window next to it: name field + **Save as new**, status bar, list of sets (click to select, double-click to equip; the worn set gets the gold tint and "Equipped"), and a panel for the selected set with its item icons (faded when not worn), **Equip**, **Update** and **Delete** (two clicks). `/sets` opens it too; opening the Project Astral hub closes it
- **Set Builds** tab in the hub's BUILDS section: the same sets in the Talent Builds layout (name field, **Save current**, **Open Character**, count; rows with icon, name, "Equipped · N items", **Equip**, **Update**, **Delete**; hover lists every item and slot). Click a row to select it (double-click equips): the bottom panel shows every item of the set as an icon with its tooltip on hover, faded when not worn
- Slots saved empty are part of the set: equipping it takes off what you wear there (into free bag space), the set only counts as "Equipped" when those slots are empty, and the Set Builds item panel marks them with a red × ("left empty by this set")
- Blizzard's own equipment manager button and window are hidden; sets with a "?" icon show their weapon (or chest) icon
- When the game's Equipment Manager option is off, its red error is replaced by a popup: "Turn it on in Game Menu > Interface > Features", with an **Open Interface** button

### Gem Builds tab (`GemBuilds.lua`)
- Same design as the other gem tabs: navy layers, header with name field (search style), **Save current**, **Import**, build count; gold action bar; rows with build name, availability (green / amber / red) · saved by · date, and **Load**, **Update**, **Export**, **Delete**
- **Update** (two clicks) replaces a build's gems with the ones socketed now, keeping its name
- The build matching your socketed gems gets the gold tint, bar and "Equipped"
- Loading bar: "Loading 'X' · Socketing <gem> into <slot>…", a filling bar and a step counter, then "Build 'X' loaded: N socketed, N removed." (green, or amber with failures)
- **Higher tier gems available** popup before loading when you own a better tier of a build gem: one row per gem with a check box (icon, name, slot, "T2 » T4"), "Also save the higher tiers in this build", and **Cancel / Load as saved / Upgrade and load**

### Astral Gems tab (`AstralGems.lua`) — character sheet
- Left column Head, Neck, Chest; right column Weapon, Legs, Boots; each card shows its socket tiles (gem icon, coloured **+** when empty, padlock when locked; border = socket quality) and one line per socket
- Centre: a straight-line constellation figure (faceted helm, chest plate, pauldrons, limbs, knee diamonds, sword held point up) over a full-panel robe light, with sparkling joints and twinkling dust. The selected part's lines and stars turn gold and its name is shown
- Selecting a card, a socket tile or a part of the figure selects the same item
- Gold detail bar for the selected socket: gem with tier, trigger and full effect text, **Change gem** / **Remove**; empty socket with "N gems in your stash can go here" and **Add gem**; locked socket with the item quality it needs
- Clicks: a single click on an empty socket opens the gem picker; a single click on a filled socket selects it; a double click removes its gem. A plain click no longer removes a gem by accident
- Header: "N of 12 sockets filled · N empty · N locked", Export / Import / Refresh, and a legend for socket colours
- **Change gem** lists the other tiers of the current gem's family too, and swaps through the loadout queue (unsocket, server check, socket)

### Stats tab (`AstralStats.lua`) — Account Overview merged in
- Header: character, class and level, play time (asked once per session, without the chat line)
- Tile row: Nodes, Paragon, Unspent points, Bonuses, Tokens, Orbs, Prestige, Gem Stash ("619 · 320 types"), Gem Builds; Nodes, Paragon, Tokens, Gem Stash and Gem Builds open their tab
- Bonus columns in the navy style with alternating rows, dividers, green values, gold "Unlocked" and grey Paragon notes

### Buttons and shared UI (`Core.lua`)
- All gold action buttons (Fuse all, Save current, Upgrade and load, Load, Fuse, Deposit all, Builds) use the outline `gold` style; the filled `goldSolid` variant was removed
- Hub frames that must stay navy set `__paBackdrop`, because Theme.lua turns navy backdrops grey

### Gem loading speed and safety (`AstralGems.lua`)
- 0.1 s between server operations instead of 0.6 s; no per-gem "Loadout SOCKET / UNSOCKET" screen message during a build load
- Server verification kept: the loadout is re-read after every change, and after the unsockets the queue waits for a fresh loadout and stash (up to 3 s, no fixed 1.5 s pause) before planning the sockets

---

## 2026-10-04 — Gem tabs redesign and hub readability

### Gem Fusion tab (`GemFusion.lua`)
- New layout, top to bottom:
  - One-line header: Auto Fuse toggle, "up to" tier, live Auto Fuse state (Off / waiting / fusing / paused: no gold / paused: in combat), current gold, and a `?` button whose tooltip holds the T1 drop chance, every fusion cost and which tiers are locked
  - Tier chips (All, T1–T8) with gem count and ready stacks in gold (`+48`); locked tiers in red, tooltip with cost and unlock state
  - Trigger chips (Any trigger, Hit, Cast, Heal, Struck), "Ready only" chip, search
  - Gold action bar: "N fusions ready · total X" and a **Fuse all · X** button; status messages replace the summary for 4 s
  - List grouped as READY TO FUSE → IN PROGRESS → MAX TIER
- Rows: gem family as the title ("Blood Pact"), "T1 · Proc on Struck" below, 3 progress pips (blue in progress, gold when ready), result ("1× T2"), and a "Fuse · 50s" button only on ready rows ("1 more needed" otherwise). Red label when gold is short, "Locked" when the tier is locked
- Ready rows: warm gold gradient and 3 px gold left bar; faint dividers and alternating rows
- Hovering a row shows the item tooltip; Shift-click links it in chat
- **Fuse all** fuses every listed ready stack one at a time through the Auto Fuse loop (`GF.FuseAll`); it doesn't re-fuse its own results, stops on low gold or combat, and shows one summary popup. Row buttons are disabled while fusions run
- Removed: Gem Drop box, Fusion Cost cards, "Tiers:" row, Tier/Trigger dropdowns, Ready checkbox

### Gem Stash tab (`GemStash.lua`) — Gem Catalog merged in
- Gem Catalog tab removed; Gem Stash now shows both:
  - **Owned** chip on (default): your stash, with Withdraw 1 / 5 / All
  - **Owned** chip off: every gem in the game; owned ones show "×N", others "Not owned"
- Same chip bar as Gem Fusion: tier chips (All, T1–T8, Mythic, Scrolls, no counts), trigger chips, Owned, search
- Header: "N gem types in your stash" / "N gems in the catalog · N owned", and **Deposit all gems and scrolls** (moved from the bottom)
- Rows show the gem's effect text and flavor line directly (read once from the item tooltip and cached), up to 3 lines; "T1 · Proc on Hit" next to the name
- Owned rows get the same gold gradient and left bar as Gem Fusion's ready rows
- Only the visible rows exist (recycled while scrolling), so the full catalog stays smooth

### Look and readability
- Palette for both gem tabs: layered deep navy surfaces, brighter text codes (secondary `dcdff0`, dim `aab0d4`, gold `ffd970`, red `ff9a8f`, green `7fe0a0`), brighter next-tier colours, pure white descriptions
- The gem colour word ("Yellow", "Blue"…) is no longer shown
- Text in both gem tabs and the filter chips uses a chat-style look: no black outline, black drop shadow, +1 px size (Friz Quadrata kept)
- Hub: tab content was drawn **under** the content frame's 38 % dark backdrop, which greyed out every tab. Pages, cards and the scroll bar now sit above it — fixes text brightness on all hub tabs

### Shared UI (`Core.lua`)
- `UI.MakeButton` variant `gold` (gold outline) for gem actions
- `UI.MakeFilterChip(parent, w, label, onClick)` and `UI.StyleFilterSearch(box)`: the chip/search style used by both gem tabs
- `UI.SetTextFont(fs, size[, font])`: chat-style text (no outline, black shadow)
- `SetDisabledLook` no longer repaints when the state hasn't changed, so periodic refreshes don't wipe the hover highlight

### Fixes
- Gem Fusion list: rows scrolled out of view still caught the mouse (3.3.5 ScrollFrames clip drawing, not input), so hovering "All" showed Blood Pact's tooltip and "Ready only" couldn't be clicked. Only fully visible rows take the mouse now
- Gem Fusion: the item-info refresh called `RefreshGemList` without its panel and failed silently
- Gem Stash: icon preloading replaced the frame's OnUpdate, which permanently stopped the stash polling; it now runs on its own frame
- Gem catalog data: `isMythic` from the server is now kept (the Mythic filters relied on it)
- Hub home: Quick Access links are looked up by tab id instead of list position (removing a tab shifted them); Gem Catalog's slot now opens Gem Stash, and old `gem_catalog` / `catalog` ids redirect to Gem Stash

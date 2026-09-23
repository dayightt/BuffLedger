# BuffLedger — Design

**Target:** World of Warcraft: Forever (client 1.60.x, `## Interface: 16001`, Mainline 12.1.5 API surface with the Midnight addon restrictions).
**Status:** design as built, 2026-09-18 (bars rebuilt on the client's aura container the same day, after the probe showed every aura read is refused in combat).

## 1. What it is

BuffLedger is a player buff bar that organises your buffs instead of showing them in raw aura order. Buffs are grouped into colour-coded categories (one per class, plus Weapon, Consumable, World and Other), each group sits together as a visual cluster, and inside a cluster the buff closest to falling off comes first. Every category is data the player can edit: rename, recolour, reorder, delete, create new ones, and reassign any single buff to any category in two clicks. Crowded categories can collapse into one icon with a count badge and a hover popout. A separate debuff bar shows what is on you, ordered by time remaining and bordered by dispel type.

### Goals

- Categorisation that works with nothing configured: a built-in name table, plus the caster's class when the client tells us who cast a buff.
- Everything about categories is user-editable and persistent; nothing is hardcoded at render time.
- Native modern look: Blizzard templates, atlases and fonts only; options live in the Settings panel.
- Correct under the client's addon restrictions: every aura field is treated as possibly secret; a secret only loses information, never errors.
- Headless-testable core: classification, category management and layout math run under a plain Lua 5.1 interpreter.

### Non-goals

- Tracking auras on anyone but the player (the `/bl scan` helper reads group members out of combat only, to find unrecognised buffs).
- Cooldown tracking, aura alerts, or any trigger system.
- Libraries or bundled fonts/textures. The addon is self-contained.

## 2. Platform facts this design relies on

Carried over from the LootLedger probe on build 1.60.1.69893 (see that addon's spec §2): `WOW_PROJECT_ID == 1`; `C_*` namespaces, `Settings`, `AddonCompartmentFrame`, `ScrollUtil`/`MinimalScrollBar`/`WowScrollBoxList`, `BackdropTemplate`, `MenuUtil` all exist; legacy globals such as `IsAddOnLoaded` are nil; `COMBAT_LOG_EVENT*` must never be registered; secret values exist (`C_Secrets.HasSecretRestrictions()` is true) and every read is guarded with `issecretvalue`; creating an `EditBox` at load steals keyboard focus.

Verified 2026-09-18 with a throwaway probe addon plus the client's own `Blizzard_BuffFrame`/`AuraUtil` source for this build (raw notes in `docs/probe-2026-09-18.md`):

| Fact | Consequence |
|---|---|
| `C_UnitAuras.GetAuraDataByIndex("player", i, filter)` returns a plain table; every field (`name`, `spellId`, `icon`, `duration`, `expirationTime`, `sourceUnit`, `dispelName`, `applications`, `auraInstanceID`, …) was plain out of combat, and the client's own buff frame does `expirationTime - GetTime()` in plain Lua. Permanent auras have `duration == 0` and `expirationTime == 0`; `applications == 0` when unstacked; `sourceUnit == "player"` for self-casts; `dispelName` can be set on helpful buffs too. In-combat/instanced behaviour not yet captured. | Sorting and text timers use plain arithmetic; every read still goes through `BL.Plain` so a secret only degrades. |
| `UNIT_AURA` `updateInfo`: `isFullUpdate`, `addedAuras` (full aura tables), `updatedAuraInstanceIDs`, `removedAuraInstanceIDs`. | Structural change on full/added/removed; timer-only refresh on updated. |
| `BuffFrame`/`DebuffFrame` are not protected; `Hide()` works with no forbidden-action dialog. | Hide + re-hide on `OnShow`; never in combat. |
| `Cooldown:SetCooldownFromExpirationTime` exists. | Secret-safe swipe fallback. |
| Weapon enchants: `C_Item.GetWeaponEnchantInfo(slotID)` for `slotID` in `Enum.WeaponSlot` (0→16, 1→17, 2→18) returns a list of `{ hasEnchant, timeLeft (ms), charges, enchantType, enchantIconID }`; cancel via `C_Spell.CancelItemTempEnchantment(slotID, enchantType)`; tooltip `SetInventoryItem("player", invSlot)`. | Weapon category entries. |
| `UnitClass(unit)` → `"Hunter", "HUNTER", 3`. Group tokens not yet exercised. | Caster-class learning uses the second return. |
| `GameTooltip:SetUnitAuraByAuraInstanceID(unit, id)` (plus Buff/Debuff variants and `SetUnitAura(unit, index, filter)`). | Tooltips. |
| `SecureActionButtonTemplate` `type="cancelaura"` cancels on click; attributes are frozen in combat. | Right-click cancel with `spell=<name>` attributes and stable aura→button assignment (§6.1). |
| `DebuffTypeColor`, `RAID_CLASS_COLORS` present. `AuraUtil.GetAuraBorderColor(dispelType)`, `DEBUFF_DISPLAY_INFO` with atlases: border with corner dispel icon `ui-debuff-border-<magic|curse|disease|poison|bleed>-icon`, without `-noicon`, default `ui-debuff-border-default-noicon`; standalone icons `RaidFrame-Icon-Debuff<Type>`. | Debuff bar borders and the corner badge (§6.1). |
| Stock `AuraButtonTemplate` (30×40): `Icon` 30×30 TOP; `Duration` `GameFontNormalSmall` gold, white under the warning threshold, anchored TOP→Icon BOTTOM; `Count` `NumberFontNormal` at Icon BOTTOMRIGHT (-2, 2), shown when `applications > 1`; `DebuffBorder` 40×40 OVERLAY centred; `TempEnchantBorder` 32×32 `Interface\Buttons\UI-TempEnchant-Border`; icon alpha pulses under `BUFF_WARNING_TIME` (31 s). `SecondsToTimeAbbrev` must be `securecall`ed (taint). | Our button copies these fonts/anchors/thresholds; duration text is formatted by `BL.FormatTime`. |
| **In combat every aura read refuses for addon code**: `GetAuraDataByIndex`, `GetAuraDataBySlot`/`GetAuraSlots`, `GetUnitAuras`, `AuraUtil.ForEachAura` all raise "Auras cannot be accessed when secret while tainted", and the `UNIT_AURA` payload fields are secret. Out of combat everything is plain. | Nothing that draws the bar may depend on reading auras. |
| The client ships an intrinsic **`AuraContainer`** with `CustomAuraContainerTemplate` (`Blizzard_AuraContainer`): `AddAuraGroup(key, filterString, { candidateFilters = { includeSpellIDs | excludeSpellIDs | includeDispelTypes | … }, sortMethod, sortDirection, maxFrameCount, layout = { layoutIndex, elementWidth, elementHeight, elementSpacing, lineSpacing, groupSpacing, forceNewLine }, initializeFrame })`, `SetAuraGroupCandidateFilters/Layout/MaxFrameCount`, `AddItemEnchantment(slot, …)` + `SetItemEnchantmentLayout`, `SetFlowLayoutMaximumLineSize/AnchorPoint/GrowthDirection`. Buttons expose `SetIcon`, `SetDurationCooldown`, `SetDurationText`, `SetApplicationCount`, `AddDispelTypeTexture` (`Border`/`BorderWithIcon`/`CustomAsset` with colour maps), `SetCancelAuraButtons`, `SetTooltipAnchorPoint`; the client fills, sorts, lays out, tooltips and cancels them itself, in combat too. Spell-ID filters are explicitly permitted for helpful auras on the player. Verified live with a probe container in and out of combat. | The bars are containers (§6). |
| `Settings.RegisterVerticalLayoutCategory/Subcategory`, `RegisterCanvasLayoutSubcategory`, `RegisterProxySetting`, `CreateSlider`, `CreateCheckbox`, `CreateSliderOptions`, `CreateSettingsButtonInitializer`, `MenuUtil`, `ColorPickerFrame.SetupColorPickerAndShow`, `StaticPopup_Show` all present. | Settings panel as designed. |

## 3. Architecture

### 3.1 Files

All files share the addon-private namespace (`local ADDON_NAME, BL = ...`). Load order is the `.toc` order below.

| File | Responsibility |
|---|---|
| `BuffLedger.toc` | `## Interface: 16001`, `## SavedVariables: BuffLedgerDB`, `## AddonCompartmentFunc: BuffLedger_OnCompartmentClick` (+ OnEnter/OnLeave), `## IconTexture: Interface\Icons\Spell_Holy_WordFortitude` |
| `Core.lua` | namespace, `BL.Print`, `BL.Plain` / `BL.PlainTable` secret guards, event bus (`BL.On`/`BL.Fire`), client-event frame (`BL.RegisterEvent`), DB init + versioned migration + deep-default merge, `BL.GetSetting`/`BL.SetSetting` (buff and debuff scopes), clock indirection |
| `Categories.lua` | the editable category set (§4.2) |
| `Data.lua` | built-in buff-name → category seed table and substring heuristics (§4.3) |
| `Classify.lua` | the resolver (§5.1) and assignment history |
| `Auras.lua` | reads player auras and weapon enchants into plain entry tables when the client allows (§5.2) |
| `Spells.lua` | spell ID ↔ name bridge: learns ids whenever auras are readable, derives per-category id sets (§5.3) |
| `Layout.lua` | pure clustering/wrapping math, used by the preview renderer and by the consolidation gate (§5.4) |
| `Bar.lua` | the bar factory on the client's aura container: groups, flow layout, button decoration, popout, Blizzard frame hiding (§6) |
| `DebuffBar.lua` | the debuff bar instance (§6.4) |
| `UI_Preview.lua` | `/bl test` renderer: our own buttons laid out by `Layout.lua` (§6.5) |
| `Scan.lua` | `/bl scan` and `/bl auras` |
| `Preview.lua` | `/bl test` sample mode |
| `Widgets.lua` | helpers: icon button skeleton, colour swatch, list rows, popup dialogs |
| `UI_Settings.lua` | Settings panel: parent category + Buff Bar, Debuff Bar, Categories subcategories (§7) |
| `UI_Minimap.lua` | compartment entry + optional minimap button (§8) |
| `Commands.lua` | `/bl`, `/buffledger` (§9) |
| `tests/` | headless test suite (§10) |
| `README.md`, `CHANGELOG.md`, `LICENSE` (MIT) | docs |

`Core`, `Categories`, `Data`, `Classify`, `Auras`, `Spells`, `Layout`, `Scan`, `Preview` are UI-free.

### 3.2 Event bus

`BL.On(name, fn)` / `BL.Fire(name, ...)`. Events: `CATEGORIES_CHANGED`, `OVERRIDES_CHANGED`, `SPELLS_CHANGED`, `SETTINGS_CHANGED`, `AURAS_CHANGED` (preview toggled), `DB_READY`. Data code never references UI; UI subscribes and coalesces refreshes to the next frame (`C_Timer.After(0, …)` with a dirty flag).

### 3.3 Secret-value guard

`BL.Plain(v)` returns `v` unless `issecretvalue` reports it secret, in which case `nil`. Every field read from aura data, unit APIs or event payloads passes through it before comparison, string use or use as a table key. `BL.PlainTable(t)` does the same with `issecrettable`.

## 4. Data model

### 4.1 SavedVariables

`BuffLedgerDB` (account-wide):

```lua
{
  version = 1,
  settings = {
    locked = true, scale = 1, iconSize = 30, spacing = 4, categoryGap = 12, columns = 10,
    growLeft = true, showBackground = false, durationInside = false, borderThickness = 1,
    consolidateOnlyGroup = false, consolidateOnlyRaid = false,
    hideBlizzardFrames = true, minimapButton = false, minimapAngle = 220,
    point = nil,   -- absent = sit exactly on the client's BuffFrame (follows Edit Mode); set once dragged
    debuff = { locked = true, scale = 1, iconSize = 30, spacing = 4, columns = 10, growLeft = true,
               showBackground = false, durationInside = false, borderThickness = 1, point = nil },
  },
  categories    = { [id] = { name, color = { r, g, b }, icon, hidden = false, consolidate = false,
                             builtin = bool, deletable = bool } },
  categoryOrder = { id, … },
  overrides     = { [buffName] = categoryId },   -- manual reassignments; win over everything
  learned       = { [buffName] = categoryId },   -- caster-class discoveries; persist after the caster leaves
  spells        = { [spellId] = buffName },      -- every id seen while auras were readable; feeds the container filters
  history       = { { buffName, from, to, time }, … },  -- newest first, ≤ 200
  nextCustomId  = 1,
}
```

`Core.lua` runs forward migrations at `ADDON_LOADED` and fills defaults with a deep-default merge, so new fields never need per-site `or {}` guards. Both bars' positions are saved relative to `UIParent`.

### 4.2 Categories (`Categories.lua`)

- Default ids: `warrior`, `paladin`, `hunter`, `rogue`, `priest`, `shaman`, `mage`, `warlock`, `druid`, `weapon`, `consumable`, `world`, `other`. Class colours from `RAID_CLASS_COLORS`; Weapon/Consumable/World/Other get fixed colours. Icons are stock spell/item icons.
- Custom categories get id `custom-<nextCustomId>`.
- `Seed()` populates `categories`/`categoryOrder` only when `categories` is nil (first run).
- `Create(name, color)`, `Rename(id, name)`, `SetColor(id, rgb)`, `Move(id, delta)`, `SetHidden(id, bool)`, `SetConsolidate(id, bool)`.
- `Delete(id)`: refused for `other`; removes the record and its order entry; rewrites every `overrides`/`learned` entry pointing at it to `other`.
- `ResetToDefault()`: re-adds missing built-ins with shipped values, rebuilds order as shipped built-ins in shipped order followed by customs in their existing relative order; never touches overrides, learned or history.
- `Exists(id)`; `Resolve(id)` → `id` if it exists, else `other`.
- Every mutation fires `CATEGORIES_CHANGED`.

### 4.3 Built-in name table (`Data.lua`)

`BL.SEED_BUFFS = { [buffName] = categoryId }` covering class buffs (ranks share display names), world buffs, common consumables and weapon enchant names. `BL.SEED_PATTERNS = { { pattern, categoryId }, … }` for families too varied to list (`Elixir`, `Flask`, `Potion`, `Fortune`, `Well Fed`, `Sharpened`, `Oil` → consumable/weapon). Exact match runs before patterns. The table is seed data only: it is consulted by the classifier at runtime but never copied into the DB, so updates to it apply immediately while user overrides still win.

## 5. Engine

### 5.1 Classification (`Classify.lua`)

`Classify.Resolve(entry) → categoryId`, first hit wins:

1. `overrides[entry.name]`
2. `entry.kind == "weapon"` → `weapon`
3. `Data` exact name, then patterns
4. if `entry.sourceUnit` is a plain string that is not `player`/`vehicle` and `UnitClass(entry.sourceUnit)` yields a plain class token whose lowercase form is a category id: that id, and `learned[name]` is written (fires `OVERRIDES_CHANGED` only when it changed)
5. `learned[entry.name]`
6. `other`

The result passes through `Categories.Resolve` so a deleted category collapses to `other`. A secret or nil `name` skips 1, 3, 4, 5 and lands on `other`.

`Classify.Assign(name, categoryId, source)`: writes `overrides[name]`, unshifts `{ buffName, from = previous resolved id, to, time }` into `history` (trim to 200), fires `OVERRIDES_CHANGED`. `Classify.Unassign(name)` removes the override.

### 5.2 Aura reads (`Auras.lua`)

```lua
Auras.Collect("HELPFUL"|"HARMFUL") --> entries, restricted
entry = { kind = "aura", filter, index, auraInstanceID, name, icon, spellId, applications,
          duration, expirationTime, sourceUnit, dispelName, timed = bool }
Auras.CollectWeapons() --> { { kind = "weapon", slot = 16|17|18, weaponSlot, enchantType, name, icon, applications, expirationTime, timed = true }, … }
```

- Every `GetAuraDataByIndex` call is `pcall`ed; the first refusal sets `restricted = true` and stops. Every field goes through `BL.Plain`. Out of combat the list is complete and plain; in combat it is empty and restricted, and nothing that draws the bar depends on it.
- Weapon enchants from `C_Item.GetWeaponEnchantInfo(slotID)` over `Enum.WeaponSlot` (the container's `AddItemEnchantment` slots draw nothing on this client, so the live bar draws its own weapon buttons from this, refreshed every 0.2 s — it is not aura data and stays readable in combat; a refused read keeps the last known enchants). The weapon strip sits at the bar's start and the container is anchored to its far edge, so click mapping offsets by the strip's width.
- `Auras.Signature(entries)` → structural identity (used by tests).

### 5.3 Spell IDs (`Spells.lua`)

The container filters by spell ID; categories are decided by name. `Spells.Learn(entries)` records `spells[spellId] = name` for every readable aura (and runs `Classify.Resolve` so caster classes get learned), firing `SPELLS_CHANGED` when a new id appears. `Spells.CategoryOf(spellId)` = `Classify.Resolve` of the recorded name (`other` when unknown). `Spells.Sets()` → `{ byCategory = { [id] = { [spellId] = true } }, known = { [spellId] = true } }`, rebuilt from scratch each time so overrides, learned classes and deleted categories always apply. Learning runs at login, on every out-of-combat `UNIT_AURA`, and when combat ends; a buff first seen mid-fight shows under Other until then.

### 5.4 Layout (`Layout.lua`)

Pure functions kept for the preview renderer and the consolidation gate: `Layout.ClusterEntries`, `Layout.ConsolidateAllowed(category, settings, groupState)` (per-category flag × only-in-group × only-in-raid), `Layout.Build(entries, categories, order, settings, groupState)` → placements that mirror the container's flow layout (clusters in `categoryOrder`, soonest-first inside a cluster, `categoryGap` between clusters, a cluster moves whole to the next row when it doesn't fit, `growLeft` mirroring), and `Layout.BuildSingle` for one cluster.

## 6. Bars

Each bar **is** one of the client's aura containers (`CreateFrame("AuraContainer", name, UIParent, "CustomAuraContainerTemplate")`, `SetUnit("player")`). The addon never reads aura data to draw it, so it keeps working in combat where reads are refused, and right-click cancel is the client's own. The look stays ours: category-coloured edges, clustered groups with gaps, built from stock fonts and atlases. No bundled textures or fonts.

### 6.1 Groups and flow

- **One aura group per category**, key = category id, filter string `HELPFUL`, `candidateFilters = { includeSpellIDs = Spells.Sets().byCategory[id] }`; the `other` group uses `excludeSpellIDs = Spells.Sets().known` so anything unknown lands there. `sortMethod = ExpirationOnly` (soonest first, permanent last), `layout = { layoutIndex = position in categoryOrder, elementWidth/Height = iconSize, elementSpacing = spacing, lineSpacing = spacing + 12 (0 when durationInside), groupSpacing = categoryGap }`. Hidden category → `maxFrameCount 0`; consolidated (per-category flag and the group/raid gate) → `maxFrameCount 1`. Groups are registered once and then updated in place (`SetAuraGroupCandidateFilters/Layout/MaxFrameCount`) on `CATEGORIES_CHANGED`, `OVERRIDES_CHANGED`, `SPELLS_CHANGED`, `GROUP_ROSTER_UPDATE` and layout settings; a deleted category's group is set to 0 frames.
- **Weapon enchants** are the container's `AddItemEnchantment` for the three slots, placed after the aura groups with `SetItemEnchantmentLayout` at the Weapon category's `layoutIndex`; hiding Weapon zeroes their layout size and alpha.
- **Flow:** `SetFlowLayoutMaximumLineSize(columns × (iconSize + spacing))`, anchor `TOPRIGHT` + growth `Left, Down` when `growLeft`, else `TOPLEFT` + `Right, Down`.

### 6.2 Button decoration

`initializeFrame` runs once per button the client creates. We give it: an **edge** texture (`WHITE8X8`, one `borderThickness` larger than the icon, behind it, tinted with the category colour — static per group), the **icon** texture (`SetIcon`, tex coords 0.08–0.92), a **Cooldown** (`SetDurationCooldown`, swipe/edge/bling off), the **duration** text (`SetDurationText`, `GameFontNormalSmall`, below the icon or centred when `durationInside`; the client formats and colours it), the **stack count** (`SetApplicationCount`, `NumberFontNormal` bottom-right), our own **badge** fontstring (top-right) for consolidated member counts, `SetCancelAuraButtons("RightButtonUp")`, `SetTooltipAnchorPoint("ANCHOR_BOTTOMLEFT")`. On the **debuff bar** the edge is registered as a `CustomAsset` dispel-type texture with a colour map (the client tints it Magic/Curse/Disease/Poison/Bleed/None) and a second `BorderWithIcon` dispel texture draws the stock border with the corner badge. Weapon icons get only the category edge.

Buttons carry the client's "deny tainted access while auras are secret" restriction, so restyling (size, colour, anchors) happens out of combat and is deferred to `PLAYER_REGEN_ENABLED` otherwise.

### 6.3 Interaction

- **Right-click** cancels (client). **Shift-left-click** reassigns: out of combat the addon reads the group's members (readable data, ordered like the client's `ExpirationOnly`), ranks the group's visible buttons by position and picks the matching name, then shows the category menu → `Classify.Assign`. In combat it prints that categories can't be changed.
- **Consolidated groups** show their soonest member; the badge shows the member count from the last readable data (frozen during combat). Hovering opens a **popout**: a second container (`BuffLedgerPopout`) with one group carrying the same filters, unlimited frames, on a `TooltipBackdropTemplate` companion, hidden 0.3 s after the mouse leaves both.
- **Drag:** the container itself is movable when unlocked; a translucent overlay marks it. Saved point is absolute; *Reset Position* clears it so the bar sits on the client's `BuffFrame`/`DebuffFrame` again (they stay positioned by Edit Mode while hidden).

### 6.4 Debuff bar

Same factory with the `debuff` settings scope: one `HARMFUL` group sorted `ExpirationOnly`, no category gap, dispel-tinted edge plus the stock dispel border. Anchored to `DebuffFrame` by default.

### 6.5 Preview

`/bl test` renders a sample of the seed table with our own pooled buttons (`Widgets.CreateIconButton`) laid out by `Layout.Build`, over the live bar (which is hidden meanwhile). Fake auras can't be fed to a container, so this is the one place the addon draws icons itself.

## 7. Settings panel (`UI_Settings.lua`)

`Settings.RegisterVerticalLayoutCategory("BuffLedger")` parent registered under AddOns with: a one-line description, *Hide Blizzard buff and debuff frames*, *Minimap button*. Subcategories:

- **Buff Bar**: sliders *Icon size* 16–64, *Spacing* 0–16, *Category gap* 0–32, *Columns* 1–40, *Border thickness* 1–3, *Scale* 0.5–2.0; checkboxes *Lock*, *Grow left*, *Background*, *Duration inside icon*, *Consolidate only in a group*, *Consolidate only in a raid*; button *Reset Position*.
- **Debuff Bar**: the same minus category gap and consolidation.
- **Categories** (canvas layout): a `ScrollBox` list of categories in order; each row: colour swatch (opens `ColorPickerFrame` with live preview), name (click to rename via popup), *C* toggle (consolidate), eye toggle (hidden), ▲/▼ move, × delete (confirm; disabled for Other). Below the list: *New Category* (popup with name edit box, then the colour picker), *Reset to Default* (confirm). An *Assign a buff* row: edit box (created lazily, never auto-focused) + category dropdown (`MenuUtil`) + Assign button. A *History* `ScrollBox` of assignment entries (`name: from → to · when`), right-click → reassign menu; *Clear History*.

All controls write through `BL.SetSetting`/`Categories`/`Classify`, which fire the bus events; the bars refresh on the next frame.

## 8. Minimap (`UI_Minimap.lua`)

`BuffLedger_OnCompartmentClick` opens the Settings category (`Settings.OpenToCategory`); the tooltip shows `N buffs · M debuffs` and the lock state. Optional classic minimap button (off by default): drag around the ring, angle persisted, left-click opens settings, right-click toggles lock.

## 9. Commands (`Commands.lua`)

`/bl`, `/buffledger`:

| Command | Effect |
|---|---|
| (none), `help` | list commands |
| `options`, `opt`, `config` | open the Settings category |
| `lock` / `unlock` | lock or unlock the buff bar |
| `reset` | reset the buff bar position |
| `toggle <category name>` | show/hide one category (name match, case-insensitive) |
| `scan` | list unrecognised buffs on group members with the class the caster suggests |
| `auras` | raw dump of every player buff/debuff the API returns |
| `test [0–1 \| N% \| off]` | preview a sample of every seed buff on the bar |
| `debug` | toggle event tracing |

## 10. Testing

`tests/run.lua` (run with `luajit tests/run.lua` from the addon folder; interpreter at `C:\Users\dillo\AppData\Local\Programs\LuaJIT\bin\luajit.exe`) loads `tests/wow_stub.lua`, then the UI-free files in `.toc` order with a fake `...` vararg, then every `tests/test_*.lua`. Non-zero exit on failure.

`wow_stub.lua` provides: `CreateFrame` (records registrations, `stub.FireEvent`), `C_UnitAuras.GetAuraDataByIndex` from `stub.SetAuras(unit, filter, {...})`, `UnitClass` from a unit fixture, `GetWeaponEnchantInfo` from `stub.SetWeaponEnchants`, `IsInGroup`/`IsInRaid`, `RAID_CLASS_COLORS`, `DebuffTypeColor`, `issecretvalue`/`issecrettable` with `stub.MakeSecret(v)`, `C_Timer.After` (queued), `time`/`GetTime` under test control, `C_AddOns.GetAddOnMetadata`.

Test files:

- `test_core` — defaults merge, migration 0→1, settings get/set for both scopes.
- `test_categories` — seed once, create/rename/recolor/move/hidden/consolidate, delete redirects overrides and learned to `other`, Other undeletable, reset-to-default ordering with customs preserved.
- `test_data` — every seed entry and pattern maps to an existing default id; exact beats pattern.
- `test_classify` — priority chain end to end, learning from `sourceUnit`, secret name/source degrade to `other` without error, deleted-category collapse, history cap.
- `test_auras` — entry construction, secret fields dropped, refused reads reported as `restricted`, `timed` flag, weapon entries, signature stability.
- `test_spells` — learning ids and caster classes, `CategoryOf` through overrides/seeds/deletions, `Sets`, ranks sharing a name.
- `test_smoke` — loads every file, UI included, against a fake `AuraContainer` and drives login, learning → filters, combat (reads refused, restyle deferred), reassignment, hidden/consolidated groups, settings, preview and commands.
- `test_layout` — cluster order follows `categoryOrder`, time sort with untimed last, consolidation gate matrix (per-category × group/raid), a cluster never splits when it fits a row, oversize cluster splits, `categoryGap`, `growLeft` mirroring, hidden categories, `BuildSingle`.
- `test_scan` — unrecognised-buff report from a fixture group.

UI is verified in-game with `/bl debug` tracing and `/bl test`.

## 11. Repository and process

- Repository root is the addon folder. `.gitignore` excludes editor/OS noise. MIT `LICENSE`.
- No commits or pushes without an explicit request.
- The `BuffLedgerProbe` folder is deleted once the bars are verified in-game.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Aura reads refused in combat | The bar is a client container and never needs them; only learning, badges and reassignment wait for combat to end. |
| A buff first seen mid-combat | Shows under Other until combat ends, then moves to its category. |
| Hiding `BuffFrame` blocked or tainting | Setting defaults on but degrades to a no-op with a one-time chat notice; the user can leave Blizzard's frames visible. |
| `CustomAuraContainerTemplate` missing on a future build | `Create()` reports it in chat and shows nothing rather than erroring; the preview renderer still works. |
| `C_Item.GetWeaponEnchantInfo` shape differs from the probe | Legacy `GetWeaponEnchantInfo()` fallback; on both failing the Weapon category simply has no entries. |
| Corner badge / overlay atlases change between builds | The probe output (atlas names, sizes, anchors) is kept in `docs/` so the extras can be re-checked after a client patch; a missing atlas hides the badge rather than erroring. |
| Group members' auras unreadable | `/bl scan` reports "not available" rather than erroring. |

---
name: reactive-ui
description: >
  UrhoX UI reactive state management framework. Data-driven partial UI updates.
  MUST auto-trigger when: writing ANY UI code (require "urhox-libs/UI"),
  discussing UI architecture, adding/modifying UI panels/HUD/menus,
  or any conversation involving UrhoX UI components.
  When triggered, check if scripts/ReactiveUI.lua exists; if not,
  copy from assets/ReactiveUI.lua automatically.
---

# ReactiveUI - UrhoX UI Reactive State Management

Data-driven partial UI updates without full tree rebuilds.

## Auto-Setup Rule

**This skill auto-loads whenever UI code is being written or UI topics are discussed.**

On activation:

1. Check if `scripts/ReactiveUI.lua` exists
2. If **NOT** found, copy from `assets/ReactiveUI.lua` to `scripts/ReactiveUI.lua`, notify user
3. If found but **outdated** (line count differs from assets version), warn user and offer to update
4. If found and up-to-date, skip silently

```bash
# Auto-setup check (run on skill activation)
ASSET=".agent/skills/reactive-ui/assets/ReactiveUI.lua"
TARGET="scripts/ReactiveUI.lua"
if [ \! -f "$TARGET" ]; then
    cp "$ASSET" "$TARGET"
    echo "ReactiveUI auto-copied to scripts/"
elif [ "$(wc -l < "$ASSET")" \!= "$(wc -l < "$TARGET")" ]; then
    echo "WARNING: scripts/ReactiveUI.lua differs from skill assets version. Consider updating."
fi
```

## When to Use

| Scenario | Solution |
|----------|----------|
| Simple HUD (1-2 Labels) | Direct `widget:SetText()`, no ReactiveUI needed |
| Multi-panel UI / Tab / list sync | **Use ReactiveUI** |
| Decouple GameState from UI (MVC/MVVM) | **Use ReactiveUI as ViewModel** |

## Quick Start

```lua
local ReactiveUI = require "ReactiveUI"
local UI = require("urhox-libs/UI")

local store = ReactiveUI.new({ score = 0, hp = 100 })

local scoreLabel = UI.Label { text = "Score: 0" }
store:bind(scoreLabel, "text", "score", function(v) return "Score: " .. v end)

store.score = 999  -- scoreLabel auto-updates to "Score: 999"
```

## Architecture: GameState -> Store -> UI

```
GameState (raw data)  -->  Store (ReactiveUI)  -->  UI Widget (auto-update)
```

- **GameState**: Pure data, no UI awareness
- **Store**: Bridge layer, synced from GameState via `batch()`
- **UI**: Only binds Store, never reads GameState directly

> Full architecture example -> [references/example.lua](references/example.lua) Example 2

## API Quick Reference

| API | Purpose |
|-----|---------|
| `ReactiveUI.new(data?)` | Create Store |
| `store:bind(widget, prop, key, transform?)` | Bind key -> widget prop |
| `store:bind(widget, prop, {k1,k2}, fn)` | Multi-key bind |
| `store:watch(key, fn)` / `unwatch(id)` | Watch changes |
| `store:computed(name, deps, fn)` | Read-only derived value |
| `store:effect(fn)` -> dispose | Auto-track deps side effect |
| `store:batch(fn)` | Batch update, notify once |
| `store:bindList(container, key, opts)` | List CRUD binding |
| `store:listAppend/Insert/Remove/Update/Replace/Sort/Clear` | List operations |
| `store:listRemoveAll(key, predicate)` -> count | Batch remove all matches |
| `store:listUpdateAll(key, predicate, patch)` -> count | Batch update all matches |
| `store:unbind(id)` / `unbindWidget(w)` / `unbindAll()` | Cleanup |
| `store:silent(key, val)` / `refresh(key?)` | Silent write / force notify |
| `store:get(key)` / `set(key, val)` | Explicit read/write |
| `store:keys()` / `has(key)` | Key enumeration / existence check |
| `store:dump()` / `getBindingCount()` / `getWatcherCount(key?)` | Debug |

> Full API signatures and behavior -> [references/ReactiveUI-API.md](references/ReactiveUI-API.md)

## Key Rules (6 Rules)

### 1. batch for bulk updates

```lua
-- WRONG: 3 notifications
store.score = 100; store.hp = 50; store.stage = 2

-- CORRECT: 1 notification
store:batch(function()
    store.score = 100; store.hp = 50; store.stage = 2
end)
```

### 2. computed is read-only

```lua
store:computed("stageName", {"stage"}, function(s) return STAGES[s] end)
store.stageName = "x"  -- ERROR\! read-only
```

### 3. listReplace for bindList refresh

```lua
store.items = newList                    -- WRONG: skips bindList diff
store:listReplace("items", newList)      -- CORRECT: diff + reuse
```

### 4. Widget destroy auto-cleans bindings

bind auto-hooks Widget `Destroy`; page-level cleanup uses `unbindAll()`.

### 5. effect auto-tracks dependencies

```lua
local dispose = store:effect(function(s)
    print(s.score, s.hp)  -- auto-tracks score and hp
end)
dispose()  -- stop
```

### 6. transform parameters follow key order

- Single-key: `transform(value)`
- Multi-key: `transform(v1, v2, ...)` in keys array order
- computed: `fn(v1, v2, ...)` in deps order

## Common Mistakes (Anti-patterns)

### Mistake 1: Modify store inside effect -> infinite loop

```lua
-- WRONG: writing store.combo inside effect that tracks combo -> recursion
store:effect(function(s)
    if s.score > 100 then
        store.combo = s.combo + 1  -- triggers re-run\!
    end
end)

-- CORRECT: use watch for side effects that modify store
store:watch("score", function(newVal)
    if newVal > 100 then
        store.combo = store.combo + 1
    end
end)
```

### Mistake 2: Forget batch in Sync function

```lua
-- WRONG: 5 fields = 5 notification rounds per frame
function Sync()
    store.score = GameState.score
    store.hp = GameState.hp
    store.stage = GameState.stage
    store.matter = GameState.matter
    store.combo = GameState.combo
end

-- CORRECT: wrap in batch
function Sync()
    store:batch(function()
        store.score = GameState.score
        store.hp = GameState.hp
        store.stage = GameState.stage
        store.matter = GameState.matter
        store.combo = GameState.combo
    end)
end
```

### Mistake 3: Direct table assignment for list

```lua
-- WRONG: bindList never gets notified
store.inventory = { {id="a"}, {id="b"} }

-- CORRECT: use list operations
store:listReplace("inventory", { {id="a"}, {id="b"} })
store:listAppend("inventory", {id="c"})
```

### Mistake 4: Forget unbindAll on page destroy

```lua
-- WRONG: bindings leak, old watchers keep firing
function ClosePage()
    pageRoot:Destroy()  -- only destroys widgets
end

-- CORRECT: clean up store bindings
function ClosePage()
    store:unbindAll()   -- clean bindings + watchers + listBindings
    pageRoot:Destroy()
    store = nil
end
```

### Mistake 5: computed depends on another computed but order wrong

```lua
-- No worries: ReactiveUI uses topological sort internally
-- Order of computed() calls doesn't matter, deps resolve automatically
store:computed("total", {"base","bonus"}, function(b, x) return b + x end)
store:computed("display", {"total"}, function(t) return "Total: "..t end)
-- "display" correctly updates after "total" recalculates
```

## Project File Mapping

| File | Role | Key Patterns |
|------|------|-------------|
| `scripts/ReactiveUI.lua` | Framework source | `ReactiveUI.new()`, metatable proxy |
| `scripts/Game/GameStore.lua` | Bridge layer | `new()` + `batch()` + `computed()` + `Sync()` |
| `scripts/UI/HUD.lua` | Top HUD | `store:bind()` for labels/bars |
| `scripts/UI/BottomPanel.lua` | Bottom tabs | `store:bind()` + tab switching |
| `scripts/UI/GameUI.lua` | UI state manager | `store:unbindAll()` lifecycle |

## Lifecycle Pattern

```lua
-- Init
local store = ReactiveUI.new({ ... })

-- Sync (per-frame or on events)
store:batch(function() ... end)

-- Destroy
store:unbindAll()
store = nil
```

> Usage examples -> [references/example.lua](references/example.lua)
> Full API reference -> [references/ReactiveUI-API.md](references/ReactiveUI-API.md)

# ReactiveUI API Reference

## Table of Contents

1. [Constructor](#constructor)
2. [Data Read/Write](#data-readwrite)
3. [watch / unwatch](#watch--unwatch)
4. [bind / unbind](#bind--unbind)
5. [computed](#computed)
6. [effect](#effect)
7. [batch](#batch)
8. [silent / refresh / get / set / keys / has](#silent--refresh--get--set--keys--has)
9. [bindList](#bindlist)
10. [List Operations](#list-operations)
11. [Debug Tools](#debug-tools)

---

## Constructor

### `ReactiveUI.new(initialData?)`

Create a reactive Store instance.

```lua
local ReactiveUI = require "ReactiveUI"
local store = ReactiveUI.new({ score = 0, hp = 100, items = {} })
```

- **initialData** `table?` - Initial key-value pairs, shallow-copied into store
- **Returns** `table` - Store instance (proxy via metatable)

---

## Data Read/Write

Store uses metatable to proxy reads and writes:

```lua
-- Read
local v = store.score          -- __index -> returns data[key] or computed[key].value
                                -- If inside effect context, auto-records dependency

-- Write
store.score = 100              -- __newindex -> updates data[key] -> notifies watchers/bindings/computed
                                -- Skips notification if value unchanged (and not table)
                                -- Throws error if key is computed
```

---

## watch / unwatch

### `store:watch(key, fn)` -> `watcherId`
### `store:watch(keys, fn)` -> `watcherIds`

Watch one or more keys for changes.

```lua
-- Single key
local id = store:watch("score", function(newVal, oldVal, key)
    print(key, "changed from", oldVal, "to", newVal)
end)

-- Multiple keys (same callback, called on any key change)
local ids = store:watch({"score", "hp"}, function(newVal, oldVal, key)
    print(key, "changed")
end)
```

**Parameters**:
- **key/keys** `string | string[]` - Key(s) to watch
- **fn** `function(newVal, oldVal, key)` - Change callback

**Returns**: `integer | integer[]` - Watcher ID(s) for unwatch

### `store:unwatch(id)` / `store:unwatch(ids)`

Remove watcher(s).

```lua
store:unwatch(id)
store:unwatch(ids)  -- batch remove
```

---

## bind / unbind

### `store:bind(widget, prop, key, transform?)` -> `bindId`
### `store:bind(widget, prop, keys, transform?)` -> `bindId`

Bind Store key(s) to a Widget property. Auto-updates `widget[prop]` on data change.

```lua
-- Single-key binding
local id = store:bind(label, "text", "score", function(v)
    return "Score: " .. v
end)

-- Multi-key binding
local id = store:bind(label, "text", {"hp", "maxHp"}, function(hp, maxHp)
    return string.format("HP: %d/%d", hp, maxHp)
end)

-- No transform (direct assignment)
store:bind(progressBar, "value", "hp")
```

**Parameters**:
- **widget** `table` - UI Widget instance
- **prop** `string` - Widget property name (e.g. "text", "value", "visible")
- **key/keys** `string | string[]` - Data key(s)
- **transform** `function?` - Value transform. Single-key: `fn(value)` -> result; Multi-key: `fn(v1, v2, ...)` -> result

**Returns**: `integer` - Bind ID

**Behavior**:
1. Executes immediately once (initializes Widget state)
2. Auto-hooks Widget's `Destroy` method for auto-unbind on Widget destroy
3. On data change: `widget[prop] = transform(newVal)` or `widget[prop] = newVal`

### `store:unbind(bindId)`

Remove specific binding.

### `store:unbindWidget(widget)`

Remove all bindings on a widget.

### `store:unbindAll()`

Remove all bindings, watchers, and listBindings. **Must call on page/scene destroy**.

Also destroys all Widgets held by listBindings to prevent memory leaks.

---

## computed

### `store:computed(name, deps, fn)` -> `initialValue`

Define a read-only derived value. Auto-recalculates when any dep changes.

```lua
-- Basic
store:computed("stageName", { "stage" }, function(stage)
    return STAGES[stage] or "Unknown"
end)

-- Multi-dependency
store:computed("dps", { "clickPower", "autoProduction" }, function(click, auto)
    return click + auto
end)

-- Chained computed (topologically sorted)
store:computed("stageRemaining", { "totalMatter", "stage" }, function(total, stage)
    local nextReq = STAGE_REQS[stage + 1]
    return nextReq and math.max(0, nextReq - total) or -1
end)
```

**Parameters**:
- **name** `string` - Computed key name (readable and bindable like normal keys)
- **deps** `string[]` - Dependency keys (can include normal keys and other computed keys)
- **fn** `function(...)` - Compute function, params in deps order

**Notes**:
- Computed keys are **read-only**; assignment throws error
- Uses Kahn topological sort for correct chained computed update order

### `store:removeComputed(name)`

Remove a computed and its watchers.

---

## effect

### `store:effect(fn)` -> `dispose`

Create an auto-tracking side effect. Keys accessed during fn execution become dependencies.

```lua
local dispose = store:effect(function(s)
    -- accessing s.score and s.level auto-tracks them
    if s.score > 1000 and s.level < 10 then
        print("Achievement unlocked\!")
    end
end)

-- Stop responding
dispose()
```

**Parameters**:
- **fn** `function(store)` - Side effect function, receives store as argument

**Returns**: `function` - Dispose function; calling it stops the effect

**Behavior**:
1. Executes immediately once
2. Re-collects dependencies on each re-execution (dynamic deps)
3. Built-in infinite recursion guard (modifying dep key inside effect won't immediately re-trigger self)
4. Safe tracking stack cleanup on error

---

## batch

### `store:batch(fn)`

Batch update: all assignments inside fn only notify once at the end.

```lua
store:batch(function()
    store.score = store.score + 100
    store.hp = store.hp - 10
    store.stage = 3
end)
-- All watchers/bindings notified only once after batch ends
```

**Note**: batch is nestable (inner batch is part of outer batch).

---

## silent / refresh / get / set / keys / has

### `store:silent(key, value)`

Write data **without triggering** any notifications. Use for initialization or batch-prepare then manual refresh.

### `store:refresh(keyOrKeys?)`

Force trigger notification (even if value unchanged).

```lua
store:refresh("score")              -- Refresh single key
store:refresh({"score", "hp"})      -- Refresh multiple keys
store:refresh()                     -- Refresh all keys
```

### `store:get(key)` -> `value`

Equivalent to `store.key`, correctly triggers effect dependency tracking.

### `store:set(key, value)`

Equivalent to `store[key] = value`.

### `store:keys()` -> `string[]`

Returns an array of all data key names (excludes computed keys).

```lua
local store = ReactiveUI.new({ score = 0, hp = 100, name = "Player" })
local allKeys = store:keys()  -- { "score", "hp", "name" }
```

**Note**: Order is not guaranteed (Lua table iteration order).

### `store:has(key)` -> `boolean`

Check if a key exists in the store (checks both data keys and computed keys).

```lua
store:computed("dps", { "score" }, function(s) return s * 2 end)

store:has("score")    -- true  (data key)
store:has("dps")      -- true  (computed key)
store:has("unknown")  -- false
```

---

## bindList

### `store:bindList(container, key, opts)` -> `listBinding`

Bind a Store array key to a container Widget for auto CRUD list UI.

```lua
store:bindList(container, "items", {
    key = function(item) return item.id end,
    render = function(item, index) return UI.Label { text = item.name } end,
    update = function(widget, item, index) widget:SetText(item.name) end,  -- optional
    remove = function(widget) end,  -- optional
})
```

**opts fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | `fn(item) -> string` | YES | Returns unique identifier for diff |
| `render` | `fn(item, index) -> widget` | YES | Creates new Widget |
| `update` | `fn(widget, item, index)` | NO | In-place update existing Widget; improves perf by avoiding rebuild |
| `remove` | `fn(widget)` | NO | Pre-removal cleanup callback |

---

## List Operations

All list operations auto-sync UI (via bindList-bound containers).

### `store:listAppend(key, item)`

Append item to end of list.

### `store:listInsert(key, index, item)`

Insert item at specified position.

### `store:listRemove(key, predicateOrIndex)`

Remove an item. Parameter can be index (number) or predicate function.

```lua
store:listRemove("items", 3)                                          -- by index
store:listRemove("items", function(item) return item.id == "x" end)   -- by condition
```

### `store:listRemoveAll(key, predicate)` -> `number`

Remove **all** items matching predicate. Iterates from back to front for safe index handling.

```lua
-- Remove all consumed potions
local count = store:listRemoveAll("inventory",
    function(item) return item.count <= 0 end
)
print(count .. " items removed")
```

**Parameters**:
- **key** `string` - List key
- **predicate** `function(item) -> boolean` - Match condition

**Returns**: `number` - Count of removed items

**Note**: More efficient than calling `listRemove` in a loop — triggers only one notification.

### `store:listUpdate(key, predicate, patch)`

Update first matching item, merging patch fields onto item.

```lua
store:listUpdate("items",
    function(item) return item.id == "sword" end,
    { count = 5, enhanced = true }
)
```

### `store:listUpdateAll(key, predicate, patch)` -> `number`

Update **all** items matching predicate, merging patch fields onto each matched item.

```lua
-- Mark all common items as "reviewed"
local count = store:listUpdateAll("inventory",
    function(item) return item.rarity == "common" end,
    { reviewed = true }
)
print(count .. " items updated")
```

**Parameters**:
- **key** `string` - List key
- **predicate** `function(item) -> boolean` - Match condition
- **patch** `table` - Key-value pairs to merge onto matched items

**Returns**: `number` - Count of updated items

**Note**: Each matching item triggers its `updateFn` (if bindList has one). Only one change notification at the end.

### `store:listReplace(key, newItems)`

Full list replacement with auto-diff:
- **Fast path**: Key set and order unchanged + updateFn provided -> in-place update, no layout tree teardown
- **Slow path**: Additions/removals or order change -> `ClearChildren()` first, then destroy orphaned widgets and rebuild layout tree (optimized: no redundant per-widget `RemoveChild`)

### `store:listSort(key, comparator)`

In-place sort list and sync UI.

### `store:listClear(key)`

Clear list.

---

## Debug Tools

### `store:dump()` -> `table`

Returns snapshot of all data and computed values (shallow copy).

### `store:getBindingCount()` -> `number`

Returns number of active bindings.

### `store:getWatcherCount(key?)` -> `number`

Returns watcher count for specified key or globally.

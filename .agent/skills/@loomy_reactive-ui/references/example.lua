--[[
    ReactiveUI Usage Examples
    Demonstrates GameState -> Store -> UI architecture patterns
    
    Examples:
    1. Basic Binding - HUD Score/HP
    2. Bridge Pattern - GameState -> Store -> UI
    3. bindList - Inventory System
    4. effect - Auto Dependency Tracking
    5. Cleanup and Lifecycle
    6. Multi-key Watch
    7. listSort / listClear
    8. Anti-patterns (common mistakes)
    9. keys / has - Store Introspection
    10. listRemoveAll / listUpdateAll - Batch List Operations
]]

local ReactiveUI = require "ReactiveUI"
local UI = require("urhox-libs/UI")

-- ============================================================================
-- Example 1: Basic Binding - HUD Score/HP
-- ============================================================================

local function Example_BasicBinding()
    local store = ReactiveUI.new({
        score = 0,
        hp = 100,
        maxHp = 100,
    })

    -- computed: HP percentage
    store:computed("hpPct", { "hp", "maxHp" }, function(hp, maxHp)
        return math.floor(hp / maxHp * 100)
    end)

    -- Create UI
    local scoreLabel = UI.Label { text = "Score: 0", fontSize = 20 }
    local hpLabel = UI.Label { text = "HP: 100/100", fontSize = 16 }
    local hpBar = UI.ProgressBar { value = 100, width = 200 }

    -- Bind
    store:bind(scoreLabel, "text", "score", function(v)
        return "Score: " .. v
    end)

    store:bind(hpLabel, "text", { "hp", "maxHp" }, function(hp, maxHp)
        return string.format("HP: %d/%d", hp, maxHp)
    end)

    store:bind(hpBar, "value", "hpPct")

    -- watch: play SFX on HP change
    store:watch("hp", function(newVal, oldVal)
        if newVal < oldVal then
            -- PlaySound("hit.ogg")
        end
    end)

    -- Game logic modifies data -> UI auto-updates
    store:batch(function()
        store.score = store.score + 100
        store.hp = store.hp - 20
    end)
end

-- ============================================================================
-- Example 2: Bridge Pattern - GameState -> Store -> UI Decoupling
-- ============================================================================

local function Example_BridgePattern()
    -- GameState is pure data module
    local GameState = {
        matter = 0,
        stage = 1,
        clickUpgrades = {},
    }

    -- Store: bridge layer
    local store = ReactiveUI.new({
        matter = GameState.matter,
        stage = GameState.stage,
    })

    -- computed: stage name
    local STAGES = { "Singularity", "Big Bang", "Particle Formation" }
    store:computed("stageName", { "stage" }, function(stage)
        return STAGES[stage] or "Unknown"
    end)

    -- Sync function (call per-frame or on events)
    local function Sync()
        store:batch(function()
            store.matter = GameState.matter
            store.stage = GameState.stage
        end)
    end

    -- UI only binds store, doesn't care about GameState
    local stageLabel = UI.Label { text = "" }
    store:bind(stageLabel, "text", "stageName")

    -- Simulate game loop
    GameState.matter = 1000
    GameState.stage = 2
    Sync()
    -- stageLabel auto-updates to "Big Bang"
end

-- ============================================================================
-- Example 3: bindList - Inventory System
-- ============================================================================

local function Example_BindList()
    local store = ReactiveUI.new({
        inventory = {
            { id = "sword", name = "Iron Sword", count = 1, rarity = "common" },
            { id = "potion", name = "Health Potion", count = 5, rarity = "common" },
        },
    })

    local container = UI.ScrollView { width = "100%", height = 300 }

    store:bindList(container, "inventory", {
        key = function(item) return item.id end,

        render = function(item, index)
            local nameLabel = UI.Label { text = item.name, fontSize = 14 }
            local countLabel = UI.Label { text = "x" .. item.count, fontSize = 12 }

            return UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                width = "100%",
                padding = 8,
                children = { nameLabel, countLabel },
                _nameLabel = nameLabel,
                _countLabel = countLabel,
            }
        end,

        update = function(widget, item, index)
            widget._nameLabel:SetText(item.name)
            widget._countLabel:SetText("x" .. item.count)
        end,
    })

    -- Pick up item
    store:listAppend("inventory", {
        id = "shield", name = "Wooden Shield", count = 1, rarity = "common",
    })

    -- Use potion (update count)
    store:listUpdate("inventory",
        function(item) return item.id == "potion" end,
        { count = 4 }
    )

    -- Drop item
    store:listRemove("inventory",
        function(item) return item.id == "sword" end
    )

    -- Full refresh (e.g. from server sync)
    -- store:listReplace("inventory", newInventoryFromServer)
end

-- ============================================================================
-- Example 4: effect - Auto Dependency Tracking
-- ============================================================================

local function Example_Effect()
    local store = ReactiveUI.new({
        score = 0,
        level = 1,
        combo = 0,
    })

    -- effect auto-tracks accessed keys; re-runs on any dep change
    local dispose = store:effect(function(s)
        local msg = "Lv." .. s.level .. " Score:" .. s.score
        if s.combo > 5 then
            msg = msg .. " COMBO x" .. s.combo .. "\!"
        end
        print(msg)
    end)

    store.score = 500   -- effect auto re-runs
    store.combo = 8     -- effect auto re-runs (accessed s.combo)

    dispose()           -- stop responding
    store.score = 999   -- no longer triggers effect
end

-- ============================================================================
-- Example 5: Cleanup and Lifecycle
-- ============================================================================

local function Example_Lifecycle()
    local store = ReactiveUI.new({ score = 0 })
    local label = UI.Label { text = "0" }
    store:bind(label, "text", "score")

    -- Page destroy: one-call cleanup
    local function Destroy()
        store:unbindAll()  -- cleans bind + listBinding + watcher
        store = nil
    end

    -- Widget destroy auto-cleans its own bindings (no manual call needed)
    -- label:Destroy()  -- bind auto-unbinds for this widget only
end

-- ============================================================================
-- Example 6: Multi-key Watch
-- ============================================================================

local function Example_MultiKeyWatch()
    local store = ReactiveUI.new({
        score = 0,
        hp = 100,
        mp = 50,
    })

    -- Watch multiple keys with one callback
    -- Callback fires when ANY of the watched keys changes
    local ids = store:watch({"score", "hp", "mp"}, function(newVal, oldVal, key)
        print(string.format("[%s] %s -> %s", key, tostring(oldVal), tostring(newVal)))
    end)

    store.score = 100  -- prints: [score] 0 -> 100
    store.hp = 80      -- prints: [hp] 100 -> 80

    -- Unwatch all at once (ids is a table of watcher IDs)
    store:unwatch(ids)

    store.mp = 30      -- no longer prints
end

-- ============================================================================
-- Example 7: listSort / listClear
-- ============================================================================

local function Example_ListSortClear()
    local store = ReactiveUI.new({
        leaderboard = {
            { id = "p1", name = "Alice", score = 300 },
            { id = "p2", name = "Bob", score = 500 },
            { id = "p3", name = "Charlie", score = 100 },
        },
    })

    local container = UI.Panel { width = "100%" }

    store:bindList(container, "leaderboard", {
        key = function(item) return item.id end,
        render = function(item, index)
            return UI.Label {
                text = index .. ". " .. item.name .. " - " .. item.score,
                fontSize = 14,
            }
        end,
    })

    -- Sort by score descending -> UI reorders automatically
    store:listSort("leaderboard", function(a, b)
        return a.score > b.score
    end)
    -- Result: 1. Bob - 500, 2. Alice - 300, 3. Charlie - 100

    -- Clear the entire list -> container becomes empty
    store:listClear("leaderboard")
end

-- ============================================================================
-- Example 8: Anti-patterns (Common Mistakes)
-- ============================================================================

local function Example_AntiPatterns()
    local store = ReactiveUI.new({
        score = 0,
        combo = 0,
        items = {},
    })

    -- ❌ WRONG: modify store inside effect -> potential infinite loop
    -- store:effect(function(s)
    --     if s.score > 100 then
    --         store.combo = s.combo + 1  -- writes to tracked key\!
    --     end
    -- end)

    -- ✅ CORRECT: use watch for side effects that modify store
    store:watch("score", function(newVal)
        if newVal > 100 then
            store.combo = store.combo + 1
        end
    end)

    -- ❌ WRONG: forget batch -> N notifications for N fields
    -- store.score = 100
    -- store.combo = 5

    -- ✅ CORRECT: batch -> 1 notification
    store:batch(function()
        store.score = 100
        store.combo = 5
    end)

    -- ❌ WRONG: direct assignment for list bound via bindList
    -- store.items = { {id="a"}, {id="b"} }

    -- ✅ CORRECT: use list operations
    store:listReplace("items", { {id = "a"}, {id = "b"} })
end


-- ============================================================================
-- Example 9: keys / has - Store Introspection
-- ============================================================================

local function Example_KeysHas()
    local store = ReactiveUI.new({
        score = 0,
        hp = 100,
        name = "Player",
        items = {},
    })

    store:computed("dps", { "score" }, function(s) return s * 2 end)

    -- keys(): get all data keys (excludes computed)
    local allKeys = store:keys()
    -- allKeys = { "score", "hp", "name", "items" } (order not guaranteed)

    -- has(): check existence (includes both data and computed)
    print(store:has("score"))    -- true  (data key)
    print(store:has("dps"))      -- true  (computed key)
    print(store:has("unknown"))  -- false

    -- Practical: conditional binding based on key existence
    if store:has("hp") then
        local hpLabel = UI.Label { text = "" }
        store:bind(hpLabel, "text", "hp", function(v) return "HP: " .. v end)
    end

    -- Practical: iterate all keys for debug dump
    for _, key in ipairs(store:keys()) do
        print(key, "=", tostring(store:get(key)))
    end
end

-- ============================================================================
-- Example 10: listRemoveAll / listUpdateAll - Batch List Operations
-- ============================================================================

local function Example_BatchListOps()
    local store = ReactiveUI.new({
        inventory = {
            { id = "sword",  name = "Iron Sword",     count = 1, rarity = "common" },
            { id = "potion", name = "Health Potion",   count = 0, rarity = "common" },
            { id = "gem",    name = "Ruby",            count = 3, rarity = "rare" },
            { id = "scroll", name = "Fire Scroll",     count = 0, rarity = "common" },
            { id = "ring",   name = "Magic Ring",      count = 1, rarity = "epic" },
        },
    })

    local container = UI.Panel { width = "100%" }

    store:bindList(container, "inventory", {
        key = function(item) return item.id end,
        render = function(item, index)
            return UI.Label {
                text = item.name .. " x" .. item.count,
                fontSize = 14,
            }
        end,
        update = function(widget, item, index)
            widget:SetText(item.name .. " x" .. item.count)
        end,
    })

    -- listRemoveAll: remove all consumed items (count <= 0) in one call
    local removed = store:listRemoveAll("inventory",
        function(item) return item.count <= 0 end
    )
    print(removed .. " empty items removed")
    -- Removes "potion" and "scroll", triggers ONE notification

    -- listUpdateAll: mark all common items as "reviewed"
    local updated = store:listUpdateAll("inventory",
        function(item) return item.rarity == "common" end,
        { reviewed = true }
    )
    print(updated .. " common items updated")
    -- Updates "sword" (only remaining common item), triggers ONE notification

    -- ❌ WRONG: loop with single operations (N notifications)
    -- for i = #items, 1, -1 do
    --     if items[i].count <= 0 then
    --         store:listRemove("inventory", i)  -- each triggers notification\!
    --     end
    -- end

    -- ✅ CORRECT: use listRemoveAll (1 notification)
    -- store:listRemoveAll("inventory", function(item) return item.count <= 0 end)
end

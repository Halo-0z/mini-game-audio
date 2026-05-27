--[[
    ReactiveUI - UrhoX UI 响应式状态管理框架
    =============================================
    数据驱动的局部 UI 更新，告别整树重建。

    用法:
        local ReactiveUI = require "ReactiveUI"
        local store = ReactiveUI.new({ score = 0, hp = 100 })

        local label = UI.Label { text = "Score: 0" }
        store:bind(label, "text", "score", function(v) return "Score: " .. v end)

        store.score = 999  -- label.text 自动更新为 "Score: 999"
]]

local ReactiveUI = {}

-- ═══════════════════════════════════════════════════════════════
-- 构造函数
-- ═══════════════════════════════════════════════════════════════

function ReactiveUI.new(initialData)
    -- 私有状态（闭包隔离，外部无法直接访问）
    local data            = {}       -- 实际数据
    local watchers        = {}       -- { [key] = { {id=N, fn=fn}, ... } }
    local nextWatcherId   = 1
    local computed        = {}       -- { [key] = {deps, fn, value} }
    local batching        = false
    local pendingKeys     = {}       -- 批量模式变更记录 { [key] = {old=v} }
    local bindings        = {}       -- { [bindId] = {widget, prop, watcherIds} }
    local nextBindId      = 1
    local widgetBindMap   = {}       -- { [widget] = {bindId, ...} }
    local listBindings    = {}       -- { [key] = listBinding }

    local trackingStack   = {}       -- effect 自动依赖追踪栈

    -- 复制初始数据
    if initialData then
        for k, v in pairs(initialData) do
            data[k] = v
        end
    end

    -- 方法表（通过 __index 暴露）
    local methods = {}
    local store   = {}

    -- ═══════════════════════════════════════════════════════════
    -- 内部通知机制
    -- ═══════════════════════════════════════════════════════════

    local function notifyWatchers(key, newVal, oldVal)
        local list = watchers[key]
        if not list then return end
        local n = #list
        local snapshot = {}
        for i = 1, n do snapshot[i] = list[i] end
        for i = 1, n do
            local w = snapshot[i]
            if w and w.fn then
                w.fn(newVal, oldVal, key)
            end
        end
    end

    -- 拓扑排序缓存，computed 定义变更时需置脏
    local topoOrder   = {}  -- { name1, name2, ... }  按依赖深度升序
    local topoDirty   = true

    local function rebuildTopoOrder()
        -- Kahn 算法按依赖层级排序 computed
        local inDegree = {}
        local children = {}  -- { [dep] = { name, ... } }
        for name, comp in pairs(computed) do
            inDegree[name] = 0
            children[name] = children[name] or {}
        end
        for name, comp in pairs(computed) do
            for _, dep in ipairs(comp.deps) do
                if computed[dep] then
                    inDegree[name] = inDegree[name] + 1
                    children[dep] = children[dep] or {}
                    children[dep][#children[dep] + 1] = name
                end
            end
        end
        local queue = {}
        for name, deg in pairs(inDegree) do
            if deg == 0 then queue[#queue + 1] = name end
        end
        topoOrder = {}
        while #queue > 0 do
            local cur = table.remove(queue, 1)
            topoOrder[#topoOrder + 1] = cur
            if children[cur] then
                for _, ch in ipairs(children[cur]) do
                    inDegree[ch] = inDegree[ch] - 1
                    if inDegree[ch] == 0 then
                        queue[#queue + 1] = ch
                    end
                end
            end
        end
        topoDirty = false
    end

    local function updateComputed(changedKey)
        if topoDirty then rebuildTopoOrder() end
        -- 按拓扑序遍历，收集所有受影响的 computed 并逐层更新
        local affected = { [changedKey] = true }
        for _, name in ipairs(topoOrder) do
            local comp = computed[name]
            local dominated = false
            for _, dep in ipairs(comp.deps) do
                if affected[dep] then
                    dominated = true
                    break
                end
            end
            if dominated then
                local oldVal = comp.value
                local args = {}
                for i, dep in ipairs(comp.deps) do
                    local cv = computed[dep]
                    args[i] = cv and cv.value or data[dep]
                end
                comp.value = comp.fn(table.unpack(args))
                if comp.value ~= oldVal or type(comp.value) == "table" then
                    notifyWatchers(name, comp.value, oldVal)
                    affected[name] = true
                end
            end
        end
    end

    local function notifyKey(key, newVal, oldVal)
        notifyWatchers(key, newVal, oldVal)
        updateComputed(key)
    end

    -- ═══════════════════════════════════════════════════════════
    -- Metatable
    -- ═══════════════════════════════════════════════════════════

    local mt = {
        __index = function(_, key)
            local m = methods[key]
            if m then return m end
            -- effect 自动依赖追踪：记录当前访问的 key
            local n = #trackingStack
            if n > 0 then
                trackingStack[n][key] = true
            end
            local comp = computed[key]
            if comp then return comp.value end
            return data[key]
        end,

        __newindex = function(_, key, value)
            if computed[key] then
                error('ReactiveUI: cannot write to computed key "' .. tostring(key) .. '"')
            end

            local old = data[key]
            if old == value and type(value) ~= "table" then return end

            data[key] = value

            if batching then
                if pendingKeys[key] == nil then
                    pendingKeys[key] = { old = old }
                end
                return
            end

            notifyKey(key, value, old)
        end,

        __tostring = function()
            local parts = {}
            for k, v in pairs(data) do
                parts[#parts + 1] = k .. "=" .. tostring(v)
            end
            return "ReactiveUI{" .. table.concat(parts, ", ") .. "}"
        end,
    }

    setmetatable(store, mt)

    -- ═══════════════════════════════════════════════════════════
    -- watch / unwatch
    -- ═══════════════════════════════════════════════════════════

    ---@param keyOrKeys string|string[]
    ---@param fn fun(newVal: any, oldVal: any, key: string)
    ---@return integer|integer[]
    function methods.watch(self, keyOrKeys, fn)
        if type(keyOrKeys) == "table" then
            local ids = {}
            for _, key in ipairs(keyOrKeys) do
                local wid = nextWatcherId
                nextWatcherId = nextWatcherId + 1
                if not watchers[key] then watchers[key] = {} end
                watchers[key][#watchers[key] + 1] = { id = wid, fn = fn }
                ids[#ids + 1] = wid
            end
            return ids
        else
            local wid = nextWatcherId
            nextWatcherId = nextWatcherId + 1
            if not watchers[keyOrKeys] then watchers[keyOrKeys] = {} end
            watchers[keyOrKeys][#watchers[keyOrKeys] + 1] = { id = wid, fn = fn }
            return wid
        end
    end

    ---@param idOrIds integer|integer[]
    function methods.unwatch(self, idOrIds)
        if type(idOrIds) == "table" then
            for _, id in ipairs(idOrIds) do
                methods.unwatch(self, id)
            end
            return
        end
        local targetId = idOrIds
        for _, list in pairs(watchers) do
            for i = #list, 1, -1 do
                if list[i].id == targetId then
                    table.remove(list, i)
                    return
                end
            end
        end
    end

    -- ═══════════════════════════════════════════════════════════
    -- batch
    -- ═══════════════════════════════════════════════════════════

    ---@param fn fun()
    function methods.batch(self, fn)
        if batching then
            fn()
            return
        end

        batching = true
        pendingKeys = {}

        local ok, err = pcall(fn)

        batching = false

        for key, info in pairs(pendingKeys) do
            local newVal = data[key]
            local oldVal = info.old
            if newVal ~= oldVal or type(newVal) == "table" then
                notifyKey(key, newVal, oldVal)
            end
        end
        pendingKeys = {}

        if not ok then error(err, 2) end
    end

    -- ═══════════════════════════════════════════════════════════
    -- silent / get / set
    -- ═══════════════════════════════════════════════════════════

    function methods.silent(self, key, value)
        if computed[key] then
            error('ReactiveUI: cannot write to computed key "' .. tostring(key) .. '"')
        end
        data[key] = value
    end

    ---@param keyOrKeys? string|string[]  指定刷新的 key，省略则刷新所有 key
    function methods.refresh(self, keyOrKeys)
        if keyOrKeys == nil then
            for key, val in pairs(data) do
                notifyKey(key, val, val)
            end
        elseif type(keyOrKeys) == "table" then
            for _, key in ipairs(keyOrKeys) do
                local val = data[key]
                notifyKey(key, val, val)
            end
        else
            local val = data[keyOrKeys]
            notifyKey(keyOrKeys, val, val)
        end
    end

    function methods.get(self, key)
        -- 触发 effect 依赖追踪，与 store.key 行为一致
        local n = #trackingStack
        if n > 0 then
            trackingStack[n][key] = true
        end
        local comp = computed[key]
        if comp then return comp.value end
        return data[key]
    end

    function methods.set(self, key, value)
        store[key] = value
    end

    --- 返回所有数据 key（不含 computed）
    ---@return string[]
    function methods.keys(self)
        local result = {}
        for k in pairs(data) do
            result[#result + 1] = k
        end
        return result
    end

    --- 检查 key 是否存在（data 或 computed）
    ---@param key string
    ---@return boolean
    function methods.has(self, key)
        return data[key] ~= nil or (computed[key] ~= nil)
    end

    -- ═══════════════════════════════════════════════════════════
    -- computed
    -- ═══════════════════════════════════════════════════════════

    ---@param name string
    ---@param deps string[]
    ---@param fn function
    ---@return any
    function methods.computed(self, name, deps, fn)
        local args = {}
        for i, dep in ipairs(deps) do
            local cv = computed[dep]
            args[i] = cv and cv.value or data[dep]
        end
        local initialValue = fn(table.unpack(args))

        computed[name] = {
            deps  = deps,
            fn    = fn,
            value = initialValue,
        }
        topoDirty = true

        return initialValue
    end

    ---@param name string
    function methods.removeComputed(self, name)
        if not computed[name] then return end
        -- 移除该 computed 的所有 watcher
        if watchers[name] then
            watchers[name] = {}
        end
        computed[name] = nil
        topoDirty = true
    end

    -- ═══════════════════════════════════════════════════════════
    -- effect（自动依赖追踪）
    -- ═══════════════════════════════════════════════════════════

    --- 创建一个自动追踪依赖的 effect。fn(store) 执行期间访问的 key 会被
    --- 自动收集为依赖，任何依赖变化时 fn 会重新执行并重新收集依赖。
    --- 返回 dispose 函数，调用后 effect 停止响应。
    ---@param fn fun(store: table)
    ---@return fun() dispose
    function methods.effect(self, fn)
        local watchIds = {}
        local disposed = false
        local running  = false  -- 防止无限递归

        local function runEffect()
            if disposed then return end
            if running then return end  -- 防止 effect 内修改依赖 key 导致无限循环
            running = true

            -- 清除上一轮的 watcher
            for _, id in ipairs(watchIds) do
                methods.unwatch(self, id)
            end
            watchIds = {}

            -- 压入追踪上下文
            local deps = {}
            trackingStack[#trackingStack + 1] = deps

            -- 执行 effect 函数，期间 __index 会记录依赖
            -- 使用 pcall 确保 trackingStack 在异常时也能正确弹出
            local ok, err = pcall(fn, self)

            -- 弹出追踪上下文（无论成功或失败）
            table.remove(trackingStack)

            running = false

            if not ok then
                -- effect 执行失败，不注册 watcher，传播错误
                error("ReactiveUI: effect error: " .. tostring(err), 2)
            end

            -- 为收集到的每个依赖注册 watcher
            for key in pairs(deps) do
                local wid = nextWatcherId
                nextWatcherId = nextWatcherId + 1
                if not watchers[key] then watchers[key] = {} end
                watchers[key][#watchers[key] + 1] = { id = wid, fn = runEffect }
                watchIds[#watchIds + 1] = wid
            end
        end

        runEffect()

        return function()
            disposed = true
            for _, id in ipairs(watchIds) do
                methods.unwatch(self, id)
            end
            watchIds = {}
        end
    end

    -- ═══════════════════════════════════════════════════════════
    -- bind / unbind
    -- ═══════════════════════════════════════════════════════════

    local function hookWidgetDestroy(widget)
        if rawget(widget, '_rsHooked') then return end

        local origDestroy = widget.Destroy
        if not origDestroy then return end  -- widget 无 Destroy 方法则跳过钩子（也不标记）

        rawset(widget, '_rsHooked', true)
        rawset(widget, '_rsBindings', {})
        rawset(widget, 'Destroy', function(self)
            local rb = rawget(self, '_rsBindings')
            if rb then
                for i = #rb, 1, -1 do
                    rb[i].store:unbind(rb[i].id)
                end
                rawset(self, '_rsBindings', nil)
            end
            return origDestroy(self)
        end)
    end

    local function removeBindWatchers(watcherIds)
        for _, wid in ipairs(watcherIds) do
            for _, list in pairs(watchers) do
                for i = #list, 1, -1 do
                    if list[i].id == wid then
                        table.remove(list, i)
                        break
                    end
                end
            end
        end
    end

    ---@param widget table
    ---@param prop   string
    ---@param keyOrKeys string|string[]
    ---@param transform? function
    ---@return integer
    function methods.bind(self, widget, prop, keyOrKeys, transform)
        local bindId = nextBindId
        nextBindId = nextBindId + 1
        local watcherIds = {}

        if type(keyOrKeys) == "table" then
            local keys = keyOrKeys

            local function doUpdate()
                local args = {}
                for i, k in ipairs(keys) do
                    local cv = computed[k]
                    args[i] = cv and cv.value or data[k]
                end
                local value = transform and transform(table.unpack(args)) or args[1]
                widget[prop] = value
            end

            doUpdate()

            for _, key in ipairs(keys) do
                local wid = nextWatcherId
                nextWatcherId = nextWatcherId + 1
                if not watchers[key] then watchers[key] = {} end
                watchers[key][#watchers[key] + 1] = { id = wid, fn = doUpdate }
                watcherIds[#watcherIds + 1] = wid
            end
        else
            local key = keyOrKeys

            local function doUpdate(newVal)
                local value = transform and transform(newVal) or newVal
                widget[prop] = value
            end

            local cv = computed[key]
            doUpdate(cv and cv.value or data[key])

            local wid = nextWatcherId
            nextWatcherId = nextWatcherId + 1
            if not watchers[key] then watchers[key] = {} end
            watchers[key][#watchers[key] + 1] = { id = wid, fn = doUpdate }
            watcherIds[#watcherIds + 1] = wid
        end

        bindings[bindId] = {
            widget     = widget,
            prop       = prop,
            watcherIds = watcherIds,
        }

        if not widgetBindMap[widget] then
            widgetBindMap[widget] = {}
        end
        widgetBindMap[widget][#widgetBindMap[widget] + 1] = bindId

        hookWidgetDestroy(widget)
        local rb = rawget(widget, '_rsBindings')
        if rb then
            rb[#rb + 1] = { store = self, id = bindId }
        end

        return bindId
    end

    ---@param bindId integer
    function methods.unbind(self, bindId)
        local binding = bindings[bindId]
        if not binding then return end

        removeBindWatchers(binding.watcherIds)

        local wbm = widgetBindMap[binding.widget]
        if wbm then
            for i = #wbm, 1, -1 do
                if wbm[i] == bindId then
                    table.remove(wbm, i)
                    break
                end
            end
            if #wbm == 0 then
                widgetBindMap[binding.widget] = nil
            end
        end

        bindings[bindId] = nil
    end

    ---@param widget table
    function methods.unbindWidget(self, widget)
        local bids = widgetBindMap[widget]
        if not bids then return end

        local copy = {}
        for i, v in ipairs(bids) do copy[i] = v end
        for _, bid in ipairs(copy) do
            methods.unbind(self, bid)
        end

        widgetBindMap[widget] = nil
    end

    function methods.unbindAll(self)
        for key in pairs(watchers) do
            watchers[key] = {}
        end
        -- 销毁 listBinding 持有的所有 Widget，防止内存泄漏
        for _, lb in pairs(listBindings) do
            for _, w in pairs(lb.itemWidgets) do
                if lb.removeFn then lb.removeFn(w) end
                w:Destroy()
            end
            lb.container:ClearChildren()
        end
        bindings       = {}
        widgetBindMap  = {}
        listBindings   = {}
        -- 注意：不重置 nextBindId / nextWatcherId，避免外部仍持有旧 ID 时发生碰撞
    end

    -- ═══════════════════════════════════════════════════════════
    -- bindList
    -- ═══════════════════════════════════════════════════════════

    ---@param container table
    ---@param key       string
    ---@param opts      table  { key=fn, render=fn, update=fn?, remove=fn? }
    function methods.bindList(self, container, key, opts)
        local keyFn    = opts.key
        local renderFn = opts.render
        local updateFn = opts.update
        local removeFn = opts.remove

        local itemWidgets = {}
        local itemOrder   = {}

        local items = data[key] or {}
        for i, item in ipairs(items) do
            local k = keyFn(item)
            local w = renderFn(item, i)
            itemWidgets[k] = w
            itemOrder[#itemOrder + 1] = k
            container:AddChild(w)
        end

        local lb = {
            container   = container,
            keyFn       = keyFn,
            renderFn    = renderFn,
            updateFn    = updateFn,
            removeFn    = removeFn,
            itemWidgets = itemWidgets,
            itemOrder   = itemOrder,
        }

        listBindings[key] = lb
        return lb
    end

    -- ═══════════════════════════════════════════════════════════
    -- 列表操作
    -- ═══════════════════════════════════════════════════════════

    function methods.listAppend(self, key, item)
        local items = data[key]
        if not items then
            items = {}
            data[key] = items
        end
        items[#items + 1] = item

        local lb = listBindings[key]
        if lb then
            local k = lb.keyFn(item)
            local w = lb.renderFn(item, #items)
            lb.itemWidgets[k] = w
            lb.itemOrder[#lb.itemOrder + 1] = k
            lb.container:AddChild(w)
        end

        notifyKey(key, items, items)
    end

    function methods.listInsert(self, key, index, item)
        local items = data[key]
        if not items then
            items = {}
            data[key] = items
        end
        table.insert(items, index, item)

        local lb = listBindings[key]
        if lb then
            local k = lb.keyFn(item)
            local w = lb.renderFn(item, index)
            lb.itemWidgets[k] = w
            table.insert(lb.itemOrder, index, k)
            lb.container:InsertChild(w, index)
        end

        notifyKey(key, items, items)
    end

    function methods.listRemove(self, key, predicateOrIndex)
        local items = data[key]
        if not items then return end

        local removeIndex
        if type(predicateOrIndex) == "number" then
            removeIndex = predicateOrIndex
        elseif type(predicateOrIndex) == "function" then
            for i, item in ipairs(items) do
                if predicateOrIndex(item) then
                    removeIndex = i
                    break
                end
            end
        end

        if not removeIndex or removeIndex < 1 or removeIndex > #items then return end

        local removedItem = items[removeIndex]
        table.remove(items, removeIndex)

        local lb = listBindings[key]
        if lb then
            local k = lb.keyFn(removedItem)
            local w = lb.itemWidgets[k]
            if w then
                if lb.removeFn then lb.removeFn(w) end
                lb.container:RemoveChild(w)
                w:Destroy()
                lb.itemWidgets[k] = nil
            end
            for i = #lb.itemOrder, 1, -1 do
                if lb.itemOrder[i] == k then
                    table.remove(lb.itemOrder, i)
                    break
                end
            end
        end

        notifyKey(key, items, items)
    end

    --- 批量删除所有匹配项
    ---@param key string
    ---@param predicate fun(item: table): boolean
    ---@return integer removedCount
    function methods.listRemoveAll(self, key, predicate)
        local items = data[key]
        if not items then return 0 end

        -- 从后往前收集所有匹配索引，避免删除时索引偏移
        local toRemove = {}
        for i = #items, 1, -1 do
            if predicate(items[i]) then
                toRemove[#toRemove + 1] = i
            end
        end

        if #toRemove == 0 then return 0 end

        local lb = listBindings[key]
        for _, idx in ipairs(toRemove) do
            local removedItem = items[idx]
            table.remove(items, idx)

            if lb then
                local k = lb.keyFn(removedItem)
                local w = lb.itemWidgets[k]
                if w then
                    if lb.removeFn then lb.removeFn(w) end
                    lb.container:RemoveChild(w)
                    w:Destroy()
                    lb.itemWidgets[k] = nil
                end
                for i = #lb.itemOrder, 1, -1 do
                    if lb.itemOrder[i] == k then
                        table.remove(lb.itemOrder, i)
                        break
                    end
                end
            end
        end

        notifyKey(key, items, items)
        return #toRemove
    end

    function methods.listUpdate(self, key, predicate, patch)
        local items = data[key]
        if not items then return end

        for i, item in ipairs(items) do
            if predicate(item) then
                for pk, pv in pairs(patch) do
                    item[pk] = pv
                end

                local lb = listBindings[key]
                if lb then
                    local k = lb.keyFn(item)
                    local w = lb.itemWidgets[k]
                    if w and lb.updateFn then
                        lb.updateFn(w, item, i)
                    elseif w then
                        -- 先创建新 Widget 并插入到旧节点之前，再移除旧节点
                        -- 避免 RemoveChild 后索引偏移导致 InsertChild 越界
                        if lb.removeFn then lb.removeFn(w) end
                        local newW = lb.renderFn(item, i)
                        lb.itemWidgets[k] = newW
                        lb.container:InsertChild(newW, i)
                        lb.container:RemoveChild(w)
                        w:Destroy()
                    end
                end
                break
            end
        end

        notifyKey(key, items, items)
    end

    --- 批量更新所有匹配项
    ---@param key string
    ---@param predicate fun(item: table): boolean
    ---@param patch table
    ---@return integer updatedCount
    function methods.listUpdateAll(self, key, predicate, patch)
        local items = data[key]
        if not items then return 0 end

        local lb = listBindings[key]
        local count = 0

        for i, item in ipairs(items) do
            if predicate(item) then
                for pk, pv in pairs(patch) do
                    item[pk] = pv
                end
                count = count + 1

                if lb then
                    local k = lb.keyFn(item)
                    local w = lb.itemWidgets[k]
                    if w and lb.updateFn then
                        lb.updateFn(w, item, i)
                    elseif w then
                        if lb.removeFn then lb.removeFn(w) end
                        local newW = lb.renderFn(item, i)
                        lb.itemWidgets[k] = newW
                        lb.container:InsertChild(newW, i)
                        lb.container:RemoveChild(w)
                        w:Destroy()
                    end
                end
            end
        end

        if count > 0 then
            notifyKey(key, items, items)
        end
        return count
    end

    function methods.listReplace(self, key, newItems)
        local old = data[key]
        data[key] = newItems

        local lb = listBindings[key]
        if not lb then
            notifyKey(key, newItems, old)
            return
        end

        local newKeySet   = {}
        local newKeyOrder = {}
        for i, item in ipairs(newItems) do
            local k = lb.keyFn(item)
            newKeySet[k] = { item = item, index = i }
            newKeyOrder[#newKeyOrder + 1] = k
        end

        -- 快速路径：key 集合和顺序完全一致时，只做就地更新，不拆解布局树
        local orderUnchanged = #newKeyOrder == #(lb.itemOrder or {})
        if orderUnchanged then
            for i, k in ipairs(newKeyOrder) do
                if (lb.itemOrder or {})[i] ~= k then
                    orderUnchanged = false
                    break
                end
            end
        end

        if orderUnchanged and lb.updateFn then
            -- 顺序不变，就地更新每个 widget 的数据
            for i, k in ipairs(newKeyOrder) do
                local info = newKeySet[k]
                local existingW = lb.itemWidgets[k]
                if existingW then
                    lb.updateFn(existingW, info.item, i)
                end
            end
            notifyKey(key, newItems, old)
            return
        end

        -- 慢速路径：有增删或顺序变化，需要重建布局树
        -- 先清空容器（一次性移除所有子节点），再销毁被删除的 Widget
        lb.container:ClearChildren()

        for k, w in pairs(lb.itemWidgets) do
            if not newKeySet[k] then
                if lb.removeFn then lb.removeFn(w) end
                w:Destroy()
                lb.itemWidgets[k] = nil
            end
        end

        for i, k in ipairs(newKeyOrder) do
            local info = newKeySet[k]
            local existingW = lb.itemWidgets[k]

            if existingW then
                if lb.updateFn then
                    lb.updateFn(existingW, info.item, i)
                    lb.container:AddChild(existingW)
                else
                    -- 无 updateFn 时销毁旧 Widget 重新创建，避免显示过期数据
                    if lb.removeFn then lb.removeFn(existingW) end
                    existingW:Destroy()
                    local w = lb.renderFn(info.item, i)
                    lb.itemWidgets[k] = w
                    lb.container:AddChild(w)
                end
            else
                local w = lb.renderFn(info.item, i)
                lb.itemWidgets[k] = w
                lb.container:AddChild(w)
            end
        end

        lb.itemOrder = newKeyOrder
        notifyKey(key, newItems, old)
    end

    function methods.listSort(self, key, comparator)
        local items = data[key]
        if not items then return end

        table.sort(items, comparator)

        local lb = listBindings[key]
        if lb then
            lb.container:ClearChildren()
            lb.itemOrder = {}
            for i, item in ipairs(items) do
                local k = lb.keyFn(item)
                lb.itemOrder[#lb.itemOrder + 1] = k
                local w = lb.itemWidgets[k]
                if w then
                    if lb.updateFn then
                        lb.updateFn(w, item, i)
                    end
                    lb.container:AddChild(w)
                end
            end
        end

        notifyKey(key, items, items)
    end

    function methods.listClear(self, key)
        local lb = listBindings[key]
        if lb then
            for _, w in pairs(lb.itemWidgets) do
                if lb.removeFn then lb.removeFn(w) end
                w:Destroy()
            end
            lb.container:ClearChildren()
            lb.itemWidgets = {}
            lb.itemOrder   = {}
        end

        local old = data[key]
        data[key] = {}
        notifyKey(key, {}, old)
    end

    -- ═══════════════════════════════════════════════════════════
    -- 调试工具
    -- ═══════════════════════════════════════════════════════════

    function methods.dump(self)
        local result = {}
        for k, v in pairs(data) do
            result[k] = v
        end
        for k, comp in pairs(computed) do
            result[k] = comp.value
        end
        return result
    end

    function methods.getBindingCount(self)
        local count = 0
        for _ in pairs(bindings) do count = count + 1 end
        return count
    end

    function methods.getWatcherCount(self, key)
        if key then
            return watchers[key] and #watchers[key] or 0
        end
        local count = 0
        for _, list in pairs(watchers) do
            count = count + #list
        end
        return count
    end

    return store
end

return ReactiveUI

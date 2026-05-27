local Config          = require("Config")
local GameState       = require("GameState")
local UI              = require("urhox-libs/UI")
local SoldierManager  = require("SoldierManager")
local BuildingManager = require("BuildingManager")

local HUD = {}

-- 控件引用
local resLabels_    = {}
local dayLabel_     = nil
local phaseLabel_   = nil
local phaseIcon_    = nil
local msgContainer_ = nil   ---@type Widget
local gamePanel_    = nil   ---@type Widget
local menuPanel_    = nil   ---@type Widget
local endPanel_     = nil   ---@type Widget
local endTitle_     = nil   ---@type Widget
local endIcon_      = nil   ---@type Widget
local onBuildSelect_ = nil

-- 侧边栏 Tab 状态
local activeTab_       = "BUILD"
local cardRefs_        = {}
local tabBtnRefs_      = {}
local tabLblRefs_      = {}
local tabContentRefs_  = {}

-- DEPLOY Tab 控件引用
local deployHintLbl_  = nil    ---@type Widget
local deployCardRefs_ = {}     -- stype -> {card, btn}
local deploySlotRefs_ = {}     -- 训练槽行（3个）
local onRecruitCb_    = nil    -- function(stype) -> bool, msg

-- SOLDIER Tab 控件引用
local soldierCountLbl_  = nil  ---@type Widget
local soldierInfectLbl_ = nil  ---@type Widget
local soldierRowPool_   = {}   -- 士兵行对象池
local SOLDIER_POOL_SIZE = 20

-- 士兵类型顺序
local SOLDIER_TYPES = {"ASSAULT", "MEDIC", "ENGINEER", "FARMER"}

-- 颜色常量
local COL_BG     = {18,  20,  25,  220}
local COL_EDGE   = {60,  70,  80,  255}
local COL_TEXT   = {210, 215, 220, 255}
local COL_GOLD   = {255, 200, 60,  255}
local COL_RED    = {255, 70,  60,  255}
local COL_GRN    = {80,  220, 80,  255}
local COL_DARK   = {10,  12,  15,  255}
local COL_PANEL  = {15,  17,  22,  248}
local COL_TAB_A  = {50,  12,  12,  255}
local COL_TAB_N  = {14,  16,  22,  255}
local COL_CARD_N = {22,  25,  30,  220}
local COL_CARD_S = {55,  15,  15,  235}
local COL_CARD_D = {14,  15,  18,  180}

-- 素材路径
local IMG_CARD_N = "image/ui_card_normal_20260524100921.png"
local IMG_CARD_S = "image/ui_card_selected_20260524100909.png"
local IMG_CARD_D = "image/ui_card_disabled_20260524100919.png"
local IMG_SIDE   = "image/ui_side_panel_v2_20260524100926.png"

-- 资源定义
local RES_DEFS = {
    {key="SCRAP", label="废铁"},
    {key="FOOD",  label="食物"},
    {key="POWER", label="电力"},
    {key="BIO",   label="生物样本"},
    {key="VIRUS", label="病毒"},
}

-- 建筑按钮顺序
local BLD_BTNS = {
    "HQ","BARRACKS","POWER_PLANT","HOSPITAL",
    "WORKSHOP","WALL","WATCHTOWER","FARM","LAB","PROCESSOR"
}

-- Tab 定义
local TABS_DEF = {
    { id="BUILD",    label="建造" },
    { id="DEPLOY",   label="出征" },
    { id="RESEARCH", label="研究" },
    { id="SOLDIER",  label="士兵" },
}

-- ===================== 工具函数 =====================

local function canAfford(btype)
    local cfg = Config.BUILDINGS[btype]
    if not cfg or not cfg.cost then return true end
    for res, amount in pairs(cfg.cost) do
        if (GameState.resources[res] or 0) < amount then
            return false
        end
    end
    return true
end

local function updateCardState(btype)
    local ref = cardRefs_[btype]
    if not ref then return end
    local selected   = (GameState.selectedBuildingType == btype)
    local affordable = canAfford(btype)
    if selected then
        ref.backgroundImage = IMG_CARD_S
        ref.backgroundColor = COL_CARD_S
    elseif not affordable then
        ref.backgroundImage = IMG_CARD_D
        ref.backgroundColor = COL_CARD_D
    else
        ref.backgroundImage = IMG_CARD_N
        ref.backgroundColor = COL_CARD_N
    end
end

local function switchTab(tabId)
    activeTab_ = tabId
    for _, tab in ipairs(TABS_DEF) do
        local id    = tab.id
        local isAct = (id == tabId)
        if tabContentRefs_[id] then
            tabContentRefs_[id]:SetVisible(isAct)
        end
        if tabBtnRefs_[id] then
            tabBtnRefs_[id].backgroundColor = isAct and COL_TAB_A or COL_TAB_N
        end
        if tabLblRefs_[id] then
            tabLblRefs_[id].color = isAct and COL_GOLD or {110, 115, 125, 255}
        end
    end
end

-- ===================== 主菜单 =====================

local function makeMenuPanel()
    return UI.Panel {
        width="100%", height="100%",
        justifyContent="center", alignItems="center",
        backgroundColor=COL_DARK,
        children={
            UI.Panel {
                width=420, padding=40,
                flexDirection="column", alignItems="center",
                backgroundColor={25, 28, 35, 250},
                borderRadius=12,
                borderWidth=1, borderColor=COL_EDGE,
                children={
                    UI.Panel {
                        backgroundImage=Config.PHASE_ICONS.LOSE,
                        backgroundFit="contain",
                        backgroundColor=false,
                        width=56, height=56,
                        marginBottom=8,
                    },
                    UI.Label {
                        text="尸城：第99天",
                        fontSize=30, fontWeight="bold",
                        color=COL_GOLD,
                        marginBottom=8,
                    },
                    UI.Label {
                        text="在第 " .. Config.DAY.TOTAL_DAYS .. " 天后获得胜利",
                        fontSize=14, color={160,160,160,255},
                        marginBottom=32,
                    },
                    UI.Button {
                        text="开始游戏",
                        fontSize=18,
                        width="100%", height=50,
                        backgroundColor={60,120,200,255},
                        borderRadius=6,
                        marginBottom=12,
                        onClick=function()
                            SendEvent("StartGame", VariantMap())
                        end,
                    },
                    UI.Label {
                        text="[右键拖动视角]  [左键建造]  [Space跳过阶段]",
                        fontSize=11, color={100,100,100,255},
                        marginTop=16,
                    },
                },
            },
        },
    }
end

-- ===================== 游戏结束面板 =====================

local function makeEndPanel()
    local icon = UI.Panel {
        backgroundImage=Config.PHASE_ICONS.LOSE,
        backgroundFit="contain",
        backgroundColor=false,
        width=64, height=64,
        marginBottom=12,
    }
    local title = UI.Label {
        text="据点失守",
        fontSize=28, fontWeight="bold",
        color=COL_RED,
        marginBottom=24,
    }
    local panel = UI.Panel {
        width="100%", height="100%",
        justifyContent="center", alignItems="center",
        backgroundColor={0,0,0,170},
        visible=false,
        children={
            UI.Panel {
                width=380, padding=40,
                flexDirection="column", alignItems="center",
                backgroundColor={25, 28, 35, 250},
                borderRadius=12,
                borderWidth=1, borderColor={80,40,40,255},
                children={
                    icon,
                    title,
                    UI.Button {
                        text="重新开始",
                        fontSize=16,
                        width=200, height=46,
                        backgroundColor={70,30,30,255},
                        borderRadius=6,
                        onClick=function()
                            SendEvent("RestartGame", VariantMap())
                        end,
                    },
                },
            },
        },
    }
    endTitle_ = title
    endIcon_  = icon
    return panel
end

-- ===================== 资源栏 =====================

local function makeResBar()
    local children = {}
    for _, def in ipairs(RES_DEFS) do
        local lbl = UI.Label {
            text="0",
            fontSize=13,
            color=COL_TEXT,
            marginLeft=3,
        }
        resLabels_[def.key] = lbl
        local iconPath = Config.RES_ICONS[def.key]
        table.insert(children, UI.Panel {
            flexDirection="row", alignItems="center",
            marginRight=14,
            children={
                UI.Panel {
                    backgroundImage=iconPath,
                    backgroundFit="contain",
                    backgroundColor=false,
                    width=22, height=22,
                },
                lbl,
            },
        })
    end
    return UI.Panel {
        width="100%", height=Config.HUD.TOP_H,
        flexShrink=0,
        flexDirection="row", alignItems="center",
        paddingLeft=16, paddingRight=16,
        backgroundColor={10, 12, 16, 240},
        borderBottomWidth=1, borderColor=COL_EDGE,
        children=children,
    }
end

-- ===================== 天数栏 =====================

local function makeDayBar()
    local dayLbl = UI.Label {
        text="第 1 天",
        fontSize=13, color=COL_GOLD,
        marginLeft=8,
    }
    local phaseIcon = UI.Panel {
        backgroundImage=Config.PHASE_ICONS.DAY,
        backgroundFit="contain",
        backgroundColor=false,
        width=20, height=20,
        marginLeft=12,
    }
    local phaseLbl = UI.Label {
        text="白天",
        fontSize=12, color=COL_GRN,
        marginLeft=4,
    }
    dayLabel_   = dayLbl
    phaseLabel_ = phaseLbl
    phaseIcon_  = phaseIcon
    return UI.Panel {
        width="100%", height=36,
        flexShrink=0,
        flexDirection="row", alignItems="center",
        paddingLeft=8,
        backgroundColor={10, 12, 16, 200},
        children={
            UI.Panel {
                backgroundImage="image/icon_day_num_20260523191523.png",
                backgroundFit="contain", backgroundColor=false,
                width=20, height=20,
            },
            dayLbl,
            phaseIcon,
            phaseLbl,
        },
    }
end

-- ===================== 侧边栏：建造卡片 =====================

local function makeCostRow(cost)
    local children = {}
    local hasAny = false
    if cost then
        for res, amt in pairs(cost) do
            hasAny = true
            local icon = Config.RES_ICONS[res]
            if icon then
                table.insert(children, UI.Panel {
                    flexDirection="row", alignItems="center",
                    marginRight=7,
                    children={
                        UI.Panel {
                            backgroundImage=icon, backgroundFit="contain",
                            backgroundColor=false,
                            width=13, height=13,
                        },
                        UI.Label {
                            text=tostring(amt),
                            fontSize=10,
                            color={155, 160, 168, 255},
                            marginLeft=2,
                        },
                    },
                })
            end
        end
    end
    if not hasAny then
        table.insert(children, UI.Label {
            text="免费建造",
            fontSize=10, color={90, 200, 110, 255},
        })
    end
    return UI.Panel {
        flexDirection="row", flexWrap="wrap",
        alignItems="center",
        children=children,
    }
end

local function makeBuildCard(btype)
    local cfg     = Config.BUILDINGS[btype]
    if not cfg then return nil end
    local isoPath = Config.BUILDING_ISO_IMGS and Config.BUILDING_ISO_IMGS[btype]
    local card = UI.Button {
        width="100%", height=68,
        flexShrink=0,
        flexDirection="row",
        alignItems="center",
        paddingLeft=6, paddingRight=8,
        marginBottom=5,
        backgroundImage=IMG_CARD_N,
        backgroundFit="fill",
        backgroundColor=COL_CARD_N,
        borderRadius=4,
        onClick=function(self)
            if onBuildSelect_ then onBuildSelect_(btype) end
        end,
        children={
            UI.Panel {
                width=58, height=54,
                flexShrink=0,
                backgroundImage=isoPath,
                backgroundFit="contain",
                backgroundColor=false,
                marginRight=8,
            },
            UI.Panel {
                flex=1,
                flexShrink=1,
                flexDirection="column",
                justifyContent="center",
                children={
                    UI.Label {
                        text=cfg.name,
                        fontSize=13, fontWeight="bold",
                        color=COL_TEXT,
                        marginBottom=5,
                    },
                    makeCostRow(cfg.cost),
                },
            },
        },
    }
    cardRefs_[btype] = card
    return card
end

local function makeBuildTabContent()
    local cards = {}
    for _, btype in ipairs(BLD_BTNS) do
        local card = makeBuildCard(btype)
        if card then
            table.insert(cards, card)
        end
    end
    -- flexBasis=0 是关键：防止 ScrollView 膨胀到内容高度导致无法滚动
    local sv = UI.ScrollView {
        width="100%",
        flexGrow=1,
        flexBasis=0,
        scrollY=true,
        backgroundColor=false,
        paddingLeft=8, paddingRight=8, paddingTop=6,
    }
    for _, card in ipairs(cards) do
        sv:AddChild(card)
    end
    return sv
end

local function makeEmptyTabContent(msg)
    return UI.Panel {
        width="100%", flex=1,
        justifyContent="center", alignItems="center",
        backgroundColor=false,
        visible=false,
        children={
            UI.Label {
                text=msg,
                fontSize=13,
                color={70, 75, 82, 255},
                textAlign="center",
            },
        },
    }
end

-- ===================== 侧边栏：出征 Tab =====================

local function makeDeployTabContent()
    -- 训练槽（3个进度条行）
    local slotPanels = {}
    for i = 1, 3 do
        local progressBar = UI.Panel {
            height="100%", width="0%",
            backgroundColor={60, 180, 80, 255},
            borderRadius=2,
        }
        local bgBar = UI.Panel {
            flex=1, height=6,
            backgroundColor={30, 35, 40, 255},
            borderRadius=2,
            overflow="hidden",
            children={ progressBar },
        }
        local iconImg = UI.Panel {
            width=20, height=20, flexShrink=0,
            backgroundImage="",
            backgroundFit="contain",
            backgroundColor=false,
            marginRight=6,
        }
        local nameLbl = UI.Label {
            text="空闲", fontSize=11,
            color={60, 65, 75, 255},
            flex=1,
        }
        local slot = UI.Panel {
            width="100%", height=30, flexShrink=0,
            flexDirection="row", alignItems="center",
            paddingLeft=8, paddingRight=8,
            backgroundColor={15, 17, 22, 200},
            borderRadius=3, marginBottom=2,
            children={ iconImg, nameLbl, bgBar },
        }
        deploySlotRefs_[i] = {
            iconImg=iconImg, nameLbl=nameLbl, progressBar=progressBar,
        }
        table.insert(slotPanels, slot)
    end

    local hintLbl = UI.Label {
        text="需要建造兵营才能训练士兵",
        fontSize=10,
        color={180, 80, 50, 255},
        marginLeft=8, marginBottom=6,
    }
    deployHintLbl_ = hintLbl

    -- 士兵类型招募卡片
    local cards = {}
    for _, stype in ipairs(SOLDIER_TYPES) do
        local cfg = Config.SOLDIERS[stype]
        if not cfg then goto continueCard end

        local color = cfg.color or {200, 200, 200, 255}

        -- 费用行
        local costChildren = {}
        if cfg.cost then
            for res, amt in pairs(cfg.cost) do
                local icon = Config.RES_ICONS[res]
                table.insert(costChildren, UI.Panel {
                    flexDirection="row", alignItems="center", marginRight=6,
                    children={
                        icon and UI.Panel {
                            backgroundImage=icon, backgroundFit="contain",
                            backgroundColor=false, width=12, height=12,
                        } or UI.Label { text=res, fontSize=9, color={130,135,145,255} },
                        UI.Label {
                            text=tostring(amt), fontSize=10,
                            color={155,160,168,255}, marginLeft=2,
                        },
                    },
                })
            end
        end
        local costPanel = UI.Panel {
            flexDirection="row", flexWrap="wrap", alignItems="center",
            children=costChildren,
        }

        local recruitBtn = UI.Button {
            text="训练",
            fontSize=11,
            width=46, height=26,
            backgroundColor={45, 120, 200, 255},
            borderRadius=4,
            marginLeft=6,
            flexShrink=0,
            onClick=function(self)
                if onRecruitCb_ then
                    local ok, msg = onRecruitCb_(stype)
                    if not ok then
                        GameState.AddMessage(msg or "无法训练", Config.COLORS.RED)
                    else
                        GameState.AddMessage("开始训练：" .. cfg.name, Config.COLORS.GREEN)
                    end
                end
            end,
        }

        local iconImg = Config.SOLDIER_ICONS and Config.SOLDIER_ICONS[stype]
        local card = UI.Panel {
            width="100%", flexShrink=0,
            flexDirection="row", alignItems="center",
            paddingLeft=8, paddingRight=8,
            paddingTop=6, paddingBottom=6,
            marginBottom=4,
            backgroundColor={22, 25, 30, 220},
            borderRadius=4,
            children={
                -- 士兵头像图标
                UI.Panel {
                    width=44, height=44, flexShrink=0,
                    backgroundImage=iconImg,
                    backgroundFit="contain",
                    backgroundColor=false,
                    marginRight=8,
                },
                UI.Panel {
                    flex=1, flexShrink=1,
                    flexDirection="column",
                    children={
                        UI.Panel {
                            flexDirection="row", alignItems="center", marginBottom=2,
                            children={
                                UI.Label {
                                    text=cfg.name, fontSize=13, fontWeight="bold",
                                    color=COL_TEXT,
                                },
                                UI.Label {
                                    text=" · " .. (cfg.trainTime or 15) .. "s",
                                    fontSize=9, color={90,95,105,255}, marginLeft=4,
                                },
                            },
                        },
                        UI.Label {
                            text=cfg.desc or "",
                            fontSize=10, color={110,115,125,255}, marginBottom=2,
                        },
                        costPanel,
                    },
                },
                recruitBtn,
            },
        }
        deployCardRefs_[stype] = { card=card, btn=recruitBtn }
        table.insert(cards, card)
        ::continueCard::
    end

    local sv = UI.ScrollView {
        width="100%", flexGrow=1, flexBasis=0,
        scrollY=true,
        backgroundColor=false,
        paddingLeft=6, paddingRight=6, paddingTop=4,
    }
    for _, c in ipairs(cards) do sv:AddChild(c) end

    -- 队列区头部
    local queueHeader = UI.Panel {
        width="100%", flexShrink=0,
        paddingLeft=8, paddingRight=8,
        paddingTop=6, paddingBottom=0,
        flexDirection="column",
        children={
            UI.Label {
                text="训练队列（最多3个）",
                fontSize=10, color={130,135,145,255}, marginBottom=4,
            },
            table.unpack(slotPanels),
        },
    }

    return UI.Panel {
        width="100%", flex=1,
        flexDirection="column",
        backgroundColor=false,
        visible=false,
        children={ queueHeader, hintLbl, sv },
    }
end

-- ===================== 侧边栏：士兵 Tab =====================

local function makeSoldierRow()
    local typeIcon = UI.Panel {
        width=20, height=20, flexShrink=0,
        backgroundImage="",
        backgroundFit="contain",
        backgroundColor=false,
        marginRight=4,
    }
    local nameLbl = UI.Label {
        text="突击兵", fontSize=11,
        color=COL_TEXT,
        width=56, flexShrink=0,
    }
    local hpFill = UI.Panel {
        height="100%", width="100%",
        backgroundColor={80,200,80,255},
        borderRadius=2,
    }
    local hpBar = UI.Panel {
        flex=1, height=5,
        backgroundColor={28,32,38,255},
        borderRadius=2,
        overflow="hidden",
        children={ hpFill },
    }
    local infectFill = UI.Panel {
        height="100%", width="0%",
        backgroundColor={200,70,30,255},
        borderRadius=2,
    }
    local infectBar = UI.Panel {
        width=28, flexShrink=0, height=5,
        backgroundColor={28,32,38,255},
        borderRadius=2, marginLeft=4,
        overflow="hidden",
        children={ infectFill },
    }
    local row = UI.Panel {
        width="100%", height=26, flexShrink=0,
        flexDirection="row", alignItems="center",
        paddingLeft=8, paddingRight=8,
        backgroundColor={16, 18, 23, 170},
        borderRadius=3, marginBottom=2,
        visible=false,
        children={ typeIcon, nameLbl, hpBar, infectBar },
    }
    return { row=row, typeIcon=typeIcon, nameLbl=nameLbl, hpFill=hpFill, infectFill=infectFill }
end

local function makeSoldierTabContent()
    local countLbl = UI.Label {
        text="部队：0 名",
        fontSize=12, color={160,165,175,255},
        marginLeft=8, marginBottom=2,
    }
    local infectLbl = UI.Label {
        text="",
        fontSize=11, color={200,80,50,255},
        marginLeft=8, marginBottom=6,
        visible=false,
    }
    soldierCountLbl_  = countLbl
    soldierInfectLbl_ = infectLbl

    local sv = UI.ScrollView {
        width="100%", flexGrow=1, flexBasis=0,
        scrollY=true,
        backgroundColor=false,
        paddingLeft=6, paddingRight=6, paddingTop=2,
    }

    -- 列头
    sv:AddChild(UI.Panel {
        width="100%", height=18, flexShrink=0,
        flexDirection="row", alignItems="center",
        paddingLeft=8, paddingRight=8,
        marginBottom=2,
        backgroundColor=false,
        children={
            UI.Panel { width=22, flexShrink=0 },
            UI.Label { text="名称", fontSize=9, color={80,85,95,255}, width=56, flexShrink=0 },
            UI.Label { text="生命值", fontSize=9, color={80,85,95,255}, flex=1 },
            UI.Label { text="感染", fontSize=9, color={80,85,95,255}, width=32, flexShrink=0 },
        },
    })

    -- 对象池
    for i = 1, SOLDIER_POOL_SIZE do
        local rowData = makeSoldierRow()
        soldierRowPool_[i] = rowData
        sv:AddChild(rowData.row)
    end

    return UI.Panel {
        width="100%", flex=1,
        flexDirection="column",
        backgroundColor=false,
        visible=false,
        children={
            UI.Panel {
                width="100%", flexShrink=0,
                paddingTop=8, paddingBottom=2,
                flexDirection="column",
                children={ countLbl, infectLbl },
            },
            sv,
        },
    }
end

local function makeSidePanel()
    local buildContent    = makeBuildTabContent()
    local deployContent   = makeDeployTabContent()
    local researchContent = makeEmptyTabContent("研究\n即将开放")
    local soldierContent  = makeSoldierTabContent()

    tabContentRefs_ = {
        BUILD    = buildContent,
        DEPLOY   = deployContent,
        RESEARCH = researchContent,
        SOLDIER  = soldierContent,
    }

    -- 标签栏
    local tabBarChildren = {}
    for _, tab in ipairs(TABS_DEF) do
        local isAct = (tab.id == "BUILD")
        local lbl = UI.Label {
            text=tab.label,
            fontSize=12,
            color=isAct and COL_GOLD or {110, 115, 125, 255},
        }
        local btn = UI.Button {
            flex=1, height=38,
            flexShrink=0,
            justifyContent="center", alignItems="center",
            backgroundColor=isAct and COL_TAB_A or COL_TAB_N,
            borderRadius=3,
            margin=2,
            onClick=function(self)
                switchTab(tab.id)
            end,
            children={ lbl },
        }
        tabBtnRefs_[tab.id] = btn
        tabLblRefs_[tab.id] = lbl
        table.insert(tabBarChildren, btn)
    end

    local tabBar = UI.Panel {
        width="100%", height=46,
        flexShrink=0,
        flexDirection="row",
        alignItems="center",
        padding=3,
        backgroundColor={10, 12, 16, 245},
        borderBottomWidth=1, borderColor={55, 28, 28, 255},
        children=tabBarChildren,
    }

    return UI.Panel {
        width=Config.HUD.SIDE_W,
        alignSelf="stretch",
        flexShrink=0,
        flexDirection="column",
        backgroundColor=COL_PANEL,
        borderLeftWidth=1, borderColor={55, 28, 28, 255},
        children={
            tabBar,
            buildContent,
            deployContent,
            researchContent,
            soldierContent,
        },
    }
end

-- ===================== 消息区（悬浮在地图区左下） =====================

-- 预分配消息标签（避免每帧创建销毁）
local MSG_POOL_SIZE = 5
local msgLabels_    = {}   -- 固定池，长度 MSG_POOL_SIZE

local function makeMsgArea()
    -- 预建固定数量的 Label，通过设置 text/color/visible 来更新显示
    local children = {}
    for i = 1, MSG_POOL_SIZE do
        local lbl = UI.Label {
            text="",
            fontSize=13,
            color=COL_TEXT,
            marginBottom=2,
            visible=false,   -- 初始隐藏
        }
        msgLabels_[i] = lbl
        table.insert(children, lbl)
    end

    local container = UI.Panel {
        width=300,
        flexDirection="column",
        justifyContent="flex-end",
        padding=6,
        backgroundColor=false,
        flex=1,
        alignSelf="stretch",
        children=children,
    }
    msgContainer_ = container
    return container
end

-- ===================== 游戏主 HUD =====================

local function makeGamePanel()
    local resBar    = makeResBar()
    local dayBar    = makeDayBar()
    local sidePanel = makeSidePanel()
    local msgArea   = makeMsgArea()

    return UI.Panel {
        width="100%", height="100%",
        flexDirection="column",
        backgroundColor=false,
        visible=false,
        children={
            resBar,
            dayBar,
            -- 主内容行：左侧地图区(透明) + 右侧面板
            UI.Panel {
                width="100%",
                flex=1,
                flexShrink=1,
                flexDirection="row",
                backgroundColor=false,
                children={
                    -- 左侧透明区，消息叠在底部
                    msgArea,
                    sidePanel,
                },
            },
        },
    }
end

-- ===================== 初始化 =====================

function HUD.Init(onBuildSelectCb)
    onBuildSelect_ = onBuildSelectCb
    print("[HUD] Init start")

    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    menuPanel_ = makeMenuPanel()
    print("[HUD] menuPanel created")

    gamePanel_ = makeGamePanel()
    print("[HUD] gamePanel created")

    endPanel_  = makeEndPanel()
    print("[HUD] endPanel created")

    local root = UI.Panel {
        width="100%", height="100%",
        backgroundColor=false,
        children={ menuPanel_, gamePanel_, endPanel_ },
    }
    UI.SetRoot(root)
    print("[HUD] UI root set")
end

function HUD.SetRecruitCallback(cb)
    onRecruitCb_ = cb
end

function HUD.ShowMenu()
    if menuPanel_ then menuPanel_:SetVisible(true) end
    if gamePanel_ then gamePanel_:SetVisible(false) end
    if endPanel_  then endPanel_:SetVisible(false) end
    print("[HUD] ShowMenu")
end

function HUD.ShowGame()
    if menuPanel_ then menuPanel_:SetVisible(false) end
    if gamePanel_ then gamePanel_:SetVisible(true) end
    if endPanel_  then endPanel_:SetVisible(false) end
    print("[HUD] ShowGame")
end

function HUD.ShowGameOver(isWin)
    if endPanel_ then
        endPanel_:SetVisible(true)
        if endTitle_ then
            endTitle_.text  = isWin and "胜利！存活 30 天" or "据点失守"
            endTitle_.color = isWin and COL_GOLD or COL_RED
        end
        if endIcon_ then
            endIcon_.backgroundImage = isWin and Config.PHASE_ICONS.WIN or Config.PHASE_ICONS.LOSE
        end
    end
end

-- ===================== 每帧更新 =====================

function HUD.Update(dt)
    -- 仅在游戏进行时更新游戏面板内容（避免对隐藏节点的无效布局操作）
    if GameState.phase ~= GameState.PHASE.PLAYING then return end

    -- 资源数值
    for _, def in ipairs(RES_DEFS) do
        local lbl = resLabels_[def.key]
        if lbl then
            lbl.text = tostring(math.floor(GameState.resources[def.key] or 0))
        end
    end

    -- 天数/阶段
    if dayLabel_ then
        dayLabel_.text = "第 " .. GameState.day .. " 天"
    end
    if phaseLabel_ then
        if GameState.isDay then
            phaseLabel_.text  = "白天"
            phaseLabel_.color = COL_GRN
        else
            phaseLabel_.text  = "夜晚"
            phaseLabel_.color = COL_RED
        end
    end
    if phaseIcon_ then
        phaseIcon_.backgroundImage = GameState.isDay
            and Config.PHASE_ICONS.DAY
            or  Config.PHASE_ICONS.NIGHT
    end

    -- 建筑卡片状态
    if activeTab_ == "BUILD" then
        for _, btype in ipairs(BLD_BTNS) do
            updateCardState(btype)
        end
    end

    -- 出征 Tab 更新
    if activeTab_ == "DEPLOY" then
        -- 统计兵营数量
        local barracksCount = 0
        for _, b in ipairs(BuildingManager.GetBuildings()) do
            if b.type == "BARRACKS" then barracksCount = barracksCount + 1 end
        end
        local hasBarracks = barracksCount > 0
        if deployHintLbl_ then
            if hasBarracks then
                deployHintLbl_.text  = "兵营 " .. barracksCount .. " 座  ·  可同时训练 3 名"
                deployHintLbl_.color = {80, 200, 80, 255}
            else
                deployHintLbl_.text  = "需要建造兵营才能训练士兵"
                deployHintLbl_.color = {180, 80, 50, 255}
            end
        end
        -- 招募按钮可用性
        local queueFull = (#SoldierManager.GetTrainQueue() >= 3)
        for stype, refs in pairs(deployCardRefs_) do
            if refs.btn then
                local cfg = Config.SOLDIERS[stype]
                local affordable = true
                if cfg and cfg.cost then
                    for res, amt in pairs(cfg.cost) do
                        if (GameState.resources[res] or 0) < amt then
                            affordable = false; break
                        end
                    end
                end
                if affordable and hasBarracks and not queueFull then
                    refs.btn.backgroundColor = {45, 120, 200, 255}
                else
                    refs.btn.backgroundColor = {35, 38, 48, 255}
                end
            end
        end
        -- 训练槽进度
        local queue = SoldierManager.GetTrainQueue()
        for i = 1, 3 do
            local slot = deploySlotRefs_[i]
            if slot then
                local entry = queue[i]
                if entry then
                    local cfg = Config.SOLDIERS[entry.stype]
                    local pct = math.min(1.0, entry.timer / entry.duration)
                    slot.iconImg.backgroundImage = (Config.SOLDIER_ICONS and Config.SOLDIER_ICONS[entry.stype]) or ""
                    slot.nameLbl.text  = (cfg and cfg.name) or entry.stype
                    slot.nameLbl.color = {180, 200, 220, 255}
                    slot.progressBar.width = math.floor(pct * 100) .. "%"
                else
                    slot.iconImg.backgroundImage = ""
                    slot.nameLbl.text  = "空闲"
                    slot.nameLbl.color = {60, 65, 75, 255}
                    slot.progressBar.width = "0%"
                end
            end
        end
    end

    -- 士兵 Tab 更新
    if activeTab_ == "SOLDIER" then
        local soldiers = SoldierManager.GetSoldiers()
        if soldierCountLbl_ then
            soldierCountLbl_.text = "部队：" .. #soldiers .. " 名"
        end
        local infectCount = 0
        for i = 1, SOLDIER_POOL_SIZE do
            local rowData = soldierRowPool_[i]
            if not rowData then break end
            local s = soldiers[i]
            if s then
                local cfg = Config.SOLDIERS[s.type]
                rowData.row:SetVisible(true)
                rowData.typeIcon.backgroundImage = (Config.SOLDIER_ICONS and Config.SOLDIER_ICONS[s.type]) or ""
                rowData.nameLbl.text  = (cfg and cfg.name) or s.type
                local maxHp = (cfg and cfg.maxHp) or 100
                local hpPct = math.max(0, s.hp / maxHp)
                local hpColor
                if hpPct > 0.6 then
                    hpColor = {80, 200, 80, 255}
                elseif hpPct > 0.3 then
                    hpColor = {220, 180, 40, 255}
                else
                    hpColor = {220, 60, 60, 255}
                end
                rowData.hpFill.width           = math.floor(hpPct * 100) .. "%"
                rowData.hpFill.backgroundColor = hpColor
                local infectPct = math.min(1.0, (s.infect or 0) / 100)
                rowData.infectFill.width = math.floor(infectPct * 100) .. "%"
                if infectPct > 0.3 then infectCount = infectCount + 1 end
            else
                rowData.row:SetVisible(false)
            end
        end
        if soldierInfectLbl_ then
            if infectCount > 0 then
                soldierInfectLbl_.text = "感染警告：" .. infectCount .. " 名"
                soldierInfectLbl_:SetVisible(true)
            else
                soldierInfectLbl_:SetVisible(false)
            end
        end
    end

    -- 消息：更新预分配的标签池，不创建/销毁节点
    for i = 1, MSG_POOL_SIZE do
        local lbl = msgLabels_[i]
        if not lbl then break end
        local msg = GameState.messages[i]
        if msg then
            local alpha = math.min(255, math.floor((msg.timer / 3.0) * 255))
            local c = msg.color or COL_TEXT
            lbl.text  = msg.text
            lbl.color = {c[1], c[2], c[3], alpha}
            lbl:SetVisible(true)
        else
            lbl:SetVisible(false)
        end
    end
end

function HUD.CancelBuild()
    GameState.selectedBuildingType = nil
end

return HUD

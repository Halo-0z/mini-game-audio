local Config = {}

Config.MAP = {
    TILE_W = 64,
    TILE_H = 32,
    COLS   = 20,
    ROWS   = 20,
}

Config.DAY = {
    DAY_DURATION   = 120,
    NIGHT_DURATION = 60,
    TOTAL_DAYS     = 30,
    BOSS_INTERVAL  = 7,
}

Config.RESOURCES = {
    SCRAP = 200,
    FOOD  = 100,
    POWER = 50,
    BIO   = 0,
    VIRUS = 0,
}

Config.HUD = {
    TOP_H    = 50,
    BOTTOM_H = 100,
    SIDE_W   = 280,
}

Config.COLORS = {
    TILE_EVEN = {65,  78,  60,  255},
    TILE_ODD  = {52,  63,  48,  255},
    DAY_SKY   = {40,  60,  80,  255},
    NIGHT_SKY = {5,   5,   15,  255},
    NIGHT_OVL = {0,   0,   20,  140},
    GREEN     = {80,  220, 80,  255},
    RED       = {255, 60,  60,  255},
    GOLD      = {255, 200, 50,  255},
    TEXT      = {220, 220, 220, 255},
}

-- 建筑等距预览图（用于 HUD 卡片）
Config.BUILDING_ISO_IMGS = {
    HQ          = "image/bld_hq_iso_20260523162910.png",
    BARRACKS    = "image/bld_barracks_iso_20260523162913.png",
    POWER_PLANT = "image/bld_powerplant_iso_20260523162912.png",
    HOSPITAL    = "image/bld_hospital_iso_20260523162908.png",
    WORKSHOP    = "image/bld_workshop_iso_20260523162909.png",
    WALL        = "image/bld_wall_iso_20260523162920.png",
    WATCHTOWER  = "image/bld_watchtower_iso_20260523162908.png",
    FARM        = "image/bld_farm_iso_20260523162916.png",
    LAB         = "image/bld_lab_iso_20260523162911.png",
    PROCESSOR   = "image/bld_processor_iso_20260523162912.png",
}

-- 建筑图标图片路径
Config.BUILDING_ICONS = {
    HQ          = "image/icon_bld_hq_20260523191201.png",
    BARRACKS    = "image/icon_bld_barracks_20260523191202.png",
    POWER_PLANT = "image/icon_bld_power_20260523191210.png",
    HOSPITAL    = "image/icon_bld_hospital_20260523191213.png",
    WORKSHOP    = "image/icon_bld_workshop_20260523191212.png",
    WALL        = "image/icon_bld_wall_20260523191555.png",
    WATCHTOWER  = "image/icon_bld_watchtower_20260523191533.png",
    FARM        = "image/icon_bld_farm_20260523191544.png",
    LAB         = "image/icon_bld_lab_20260523191530.png",
    PROCESSOR   = "image/icon_bld_processor_20260523191545.png",
}

-- 资源图标图片路径
Config.RES_ICONS = {
    SCRAP = "image/icon_res_scrap_20260523191200.png",
    FOOD  = "image/icon_res_food_20260523191203.png",
    POWER = "image/icon_res_power_20260523191158.png",
    BIO   = "image/icon_res_bio_20260523191204.png",
    VIRUS = "image/icon_res_virus_20260523191205.png",
}

-- 阶段/状态图标
Config.PHASE_ICONS = {
    DAY   = "image/icon_phase_day_20260523191531.png",
    NIGHT = "image/icon_phase_night_20260523191520.png",
    WIN   = "image/icon_win_20260523191542.png",
    LOSE  = "image/icon_lose_20260523191525.png",
}

Config.BUILDINGS = {
    HQ = {
        name="总部", maxHp=5000,
        cost={}, size={w=2,h=2},
        color={120,180,255,255},
        drawScale=1.4,  -- 图片视觉比格子脚印略大，但底部对齐地面
    },
    BARRACKS = {
        name="兵营", maxHp=1500,
        cost={SCRAP=80}, size={w=2,h=1},
        color={200,100,50,255},
    },
    POWER_PLANT = {
        name="发电站", maxHp=1000,
        cost={SCRAP=60}, size={w=1,h=1},
        color={255,220,50,255},
        production={POWER=2},
    },
    HOSPITAL = {
        name="医院", maxHp=1200,
        cost={SCRAP=70}, size={w=2,h=1},
        color={255,100,100,255},
    },
    WORKSHOP = {
        name="工坊", maxHp=1500,
        cost={SCRAP=100}, size={w=2,h=1},
        color={150,150,100,255},
        production={SCRAP=1},
    },
    WALL = {
        name="围墙", maxHp=2000,
        cost={SCRAP=20}, size={w=1,h=1},
        color={100,100,120,255},
    },
    WATCHTOWER = {
        name="瞭望塔", maxHp=800,
        cost={SCRAP=50}, size={w=1,h=2},
        color={80,160,80,255},
        attack={range=5, damage=15, rate=1.0},
    },
    FARM = {
        name="农场", maxHp=600,
        cost={SCRAP=40}, size={w=2,h=2},
        color={100,200,80,255},
        production={FOOD=1},
        workerSlots = 2,    -- 最多容纳农民数量
        workerBonus = 1,    -- 每个农民额外 +1 FOOD/s
    },
    LAB = {
        name="实验室", maxHp=1000,
        cost={SCRAP=120,BIO=10}, size={w=2,h=2},
        color={180,80,255,255},
    },
    PROCESSOR = {
        name="处理站", maxHp=800,
        cost={SCRAP=60}, size={w=1,h=1},
        color={80,80,80,255},
        production={BIO=0.5},
    },
}

-- 士兵图标
Config.SOLDIER_ICONS = {
    ASSAULT  = "image/icon_soldier_assault_20260524143730.png",
    MEDIC    = "image/icon_soldier_medic_20260524143729.png",
    ENGINEER = "image/icon_soldier_engineer_20260524143726.png",
    FARMER   = "image/icon_soldier_farmer.png",  -- 待生成
}

Config.SOLDIERS = {
    FARMER = {
        name="农民",
        desc="进驻农场工作，每人额外+1粮食/s，夜晚自动撤出参与防守",
        maxHp=60, atk=5, atkRange=1.0, atkRate=0.5, speed=2.2,
        color={120, 200, 80, 255},
        cost={SCRAP=30, FOOD=10},
        trainTime=10,
    },
    ASSAULT = {
        name="突击兵",
        desc="近战步兵，冲锋陷阵",
        maxHp=100, atk=20, atkRange=2.0, atkRate=1.0, speed=3.0,
        color={50,150,250,255},
        cost={SCRAP=60, FOOD=20},
        trainTime=15,   -- 训练所需秒数（白天训练）
    },
    MEDIC = {
        name="医疗兵",
        desc="治疗附近友军，减缓感染",
        maxHp=70, atk=8, atkRange=1.5, atkRate=0.8, speed=3.0,
        color={80,220,180,255},
        cost={SCRAP=50, BIO=10},
        trainTime=20,
    },
    ENGINEER = {
        name="工程兵",
        desc="修复受损建筑",
        maxHp=80, atk=10, atkRange=1.5, atkRate=0.8, speed=2.5,
        color={220,180,60,255},
        cost={SCRAP=70},
        trainTime=20,
    },
}

Config.ZOMBIES = {
    NORMAL = {
        name="普通尸",
        maxHp=60, atk=10, atkRange=1.0, atkRate=1.0, speed=1.5,
        color={80,160,80,220},
        drop={BIO=0.3},
    },
    CORROSIVE = {
        name="腐蚀尸",
        maxHp=80, atk=8, atkRange=1.5, atkRate=0.5, speed=1.2,
        color={100,200,80,220},
        drop={BIO=0.5},
    },
    FAT = {
        name="胖尸",
        maxHp=400, atk=25, atkRange=1.0, atkRate=0.5, speed=0.8,
        color={180,80,80,220},
        drop={BIO=1.0},
    },
    TYRANT = {
        name="暴君",
        maxHp=2000, atk=80, atkRange=2.0, atkRate=0.5, speed=1.5,
        isBoss=true,
        color={200,20,20,255},
        drop={BIO=5.0},
    },
}

return Config

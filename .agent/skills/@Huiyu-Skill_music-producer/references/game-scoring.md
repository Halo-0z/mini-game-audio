# 游戏配乐设计与自适应音乐参考

> AI 音乐制作 prompt 工程专用参考。涵盖游戏音乐设计理论、自适应音乐技术与场景配乐指南。

---

## 1. 游戏音乐 vs 影视音乐

| 维度 | 影视配乐 | 游戏配乐 |
|------|---------|---------|
| 时长 | 固定（与画面同步） | 不确定（玩家决定） |
| 播放次数 | 通常一次 | 反复循环数十/数百次 |
| 交互性 | 无 | 根据玩家行为变化 |
| 结构 | 线性叙事 | 非线性/分支 |
| 核心挑战 | 情感同步 | **可循环性 + 不厌烦** |

---

## 2. 自适应音乐技术

### 2.1 水平重组 Horizontal Re-sequencing

```
状态A（探索）:  [A1] → [A2] → [A3] → [A1] ...
                          ↓ 触发战斗
状态B（战斗）:  [B1] → [B2] → [B3] → [B1] ...
                          ↓ 战斗结束
状态A（探索）:  [A1] → [A2] → ...

原理: 音乐片段在边界处无缝切换到不同状态的片段
```

### 2.2 垂直混音 Vertical Remixing / Layering

```
层4  高潮装饰  ────────  ♪♪♪♪♪♪  ← Boss 出现时加入
层3  战斗打击  ──────── ♪♪♪♪♪♪♪♪  ← 进入战斗时加入
层2  节奏贝斯  ────── ♪♪♪♪♪♪♪♪♪♪  ← 发现敌人时加入
层1  氛围底层  ──── ♪♪♪♪♪♪♪♪♪♪♪♪  ← 始终播放

危险程度:  低 ──────────────────→ 高
活跃层数:   1    1+2    1+2+3   全部
```

### 2.3 Stinger 触发式音效

| 类型 | 触发时机 | 时长 | 示例 |
|------|---------|------|------|
| 胜利 Stinger | 完成关卡/击败Boss | 3-8秒 | 凯旋号角 + 弦乐上行 |
| 失败 Stinger | 角色死亡/游戏结束 | 2-5秒 | 下行音阶 + 低沉鼓声 |
| 发现 Stinger | 获得道具/秘密 | 1-3秒 | 叮~ 升调琶音 |
| 危险 Stinger | 血量过低/计时警告 | 循环 | 紧迫的节奏 loop |
| 转场 Stinger | 场景切换 | 1-2秒 | 刷~ 过渡音效 |

### 2.4 DSP 实时效果

| 效果 | 触发场景 | 做法 |
|------|---------|------|
| 低通滤波 | 进入水下 | 切掉高频，闷声效果 |
| 混响加大 | 进入洞穴 | 长混响尾音 |
| 降速变调 | 时间减慢 | 音乐减速+降调 |
| 失真扭曲 | 角色受伤 | 音频失真闪烁 |
| 静音渐出 | 剧情过场 | 音乐渐弱 |

---

## 3. 游戏类型配乐指南

### 3.1 RPG / JRPG

| 场景 | 音乐风格 | BPM | 编制 | AI Prompt |
|------|---------|-----|------|----------|
| 标题画面 | 管弦+合唱，史诗 | 80-100 | 全管弦+合唱 | "epic orchestral, choir, RPG title theme, grand" |
| 世界地图 | 冒险，充满希望 | 110-130 | 弦乐+木管+铜管 | "adventurous orchestral, hopeful, world map theme" |
| 城镇（和平） | 温暖，日常 | 90-110 | 原声吉他+长笛+弦乐 | "peaceful town, acoustic guitar, warm flute, cozy" |
| 城镇（古风） | 中世纪，民谣 | 80-100 | 竖琴+笛子+手鼓 | "medieval town, lute, harp, tavern music" |
| 森林/原野 | 自然，清新 | 90-110 | 木管+弦乐+竖琴 | "forest theme, nature, pastoral woodwinds, gentle" |
| 地牢/迷宫 | 神秘，紧张 | 70-90 | 弦乐震音+低音 | "dungeon, mysterious, dark ambient, tense strings" |
| 普通战斗 | 激烈，驱动 | 140-170 | 弦乐+铜管+打击 | "battle theme, intense, driving orchestra, fast strings" |
| Boss 战 | 极致紧张 | 150-180 | 全管弦+合唱+打击 | "boss battle, epic choir, intense percussion, dramatic" |
| 最终 Boss | 史诗绝望→希望 | 160-190 | 超大编制管弦 | "final boss, apocalyptic, choir, desperation turning to hope" |
| 胜利/升级 | 凯旋 | — | 铜管号角 | "victory fanfare, triumphant brass, celebration" |
| 悲伤剧情 | 催泪 | 50-70 | 钢琴独奏/弦乐 | "sad piano, emotional strings, melancholic, heartbreaking" |
| 浪漫/回忆 | 温柔 | 60-80 | 钢琴+弦乐 | "romantic, nostalgic, gentle piano and strings" |

### 3.2 动作/射击 Action / FPS

| 场景 | 音乐风格 | BPM | AI Prompt |
|------|---------|-----|----------|
| 主菜单 | 电子+管弦融合 | 100-120 | "cinematic hybrid, electronic and orchestra, menu theme" |
| 潜行/侦查 | 低调紧张 | 80-100 | "stealth, tense, minimal, suspenseful, low pulse" |
| 战斗 | 高强度摇滚/电子 | 140-170 | "intense combat, heavy drums, distorted guitar, aggressive" |
| 高潮战斗 | 金属+管弦 | 160-190 | "epic battle, metal guitar, orchestral, relentless" |
| 胜利 | 英雄凯旋 | — | "victory, heroic, triumphant, mission complete" |
| 失败 | 低沉 | — | "defeat, somber, game over, dark ending" |

### 3.3 恐怖 Horror

| 场景 | 音乐风格 | AI Prompt |
|------|---------|----------|
| 探索 | 氛围噪声 | "horror ambient, dark drone, unsettling, creepy atmosphere" |
| 紧张 | 心跳节奏 | "tension, heartbeat, creeping dread, dissonant strings" |
| 追逐 | 快速不协和 | "chase music, frantic, panicking, fast dissonant, running" |
| Jump Scare | 突然爆发 | "jump scare, sudden orchestral hit, shocking" |
| 安全室 | 虚假安全感 | "false safety, music box, eerie calm, unsettling lullaby" |

### 3.4 模拟/经营 Simulation

| 场景 | 音乐风格 | BPM | AI Prompt |
|------|---------|-----|----------|
| 正常运营 | 轻快愉悦 | 100-120 | "cheerful, light, casual, happy management sim" |
| 建造/创造 | 活泼好奇 | 110-130 | "creative, building, curious, playful, construction" |
| 成功发展 | 满足成就 | 110-130 | "prosperous, thriving, achievement, uplifting" |
| 危机 | 紧张焦虑 | 120-140 | "urgent, crisis, time pressure, alarming" |

### 3.5 休闲/益智 Casual / Puzzle

| 场景 | 音乐风格 | BPM | AI Prompt |
|------|---------|-----|----------|
| 主界面 | 清新可爱 | 90-120 | "cute, cheerful, casual game, bubbly, bright" |
| 游玩中 | 不干扰思考 | 80-110 | "ambient, minimal, relaxing puzzle, gentle, non-intrusive" |
| 限时挑战 | 紧迫但轻松 | 130-150 | "time pressure, light urgency, ticking, playful tension" |
| 通关 | 短奖励音 | — | "level complete, reward jingle, happy, ding" |

### 3.6 竞速 Racing

| 场景 | 音乐风格 | BPM | AI Prompt |
|------|---------|-----|----------|
| 菜单/选车 | 酷炫电子 | 110-130 | "cool electronic, racing menu, high-tech, sleek" |
| 比赛中 | 高能驱动 | 140-180 | "high energy, driving electronic, adrenaline, fast, racing" |
| 最终圈 | 更高强度 | 160-190 | "final lap, intensifying, faster, more urgent" |
| 颁奖 | 胜利 | — | "podium, celebration, champion, victorious" |

### 3.7 沙盒/开放世界 Open World

| 场景 | 时段/天气 | AI Prompt |
|------|----------|----------|
| 白天探索 | 晴天 | "open world, daytime, adventurous, expansive, freedom" |
| 夜晚探索 | 夜晚 | "nighttime exploration, calm, mysterious, starlit" |
| 雨天 | 下雨 | "rainy atmosphere, melancholic, contemplative, patter" |
| 沙漠 | 炎热 | "desert, dry heat, Middle Eastern influence, vast" |
| 雪地 | 寒冷 | "winter, snow, cold, crystalline, serene" |
| 海洋 | 海风 | "ocean, maritime, sailing, vast sea, nautical" |

### 3.8 塔防 Tower Defense

| 场景 | AI Prompt |
|------|----------|
| 布阵阶段 | "strategic planning, calm preparation, thinking music" |
| 战斗阶段 | "tower defense battle, waves attacking, action, defending" |
| Boss 波 | "boss wave, epic, intensifying, final stand" |
| 胜利 | "wave cleared, victory, relief, rewarding" |

---

## 4. 主题动机设计（Leitmotif）

### 什么是主题动机

**角色/概念的音乐名片**：一段简短（4-8个音符）、可辨识的旋律，与特定角色或概念绑定。

### 主题动机设计原则

| 原则 | 说明 | 示例 |
|------|------|------|
| 简短可记 | 4-8个音符足够 | 《塞尔达》：5个音符的主旋律 |
| 音程特征 | 用特定音程表达性格 | 英雄=上行大跳；反派=半音下行 |
| 乐器绑定 | 角色配专属乐器 | 主角=小提琴；魔法师=竖琴 |
| 可变形 | 同旋律变换编曲 | 温柔版→战斗版→悲伤版 |

### 主题动机变形手法

| 手法 | 做法 | 情感效果 |
|------|------|---------|
| 大调→小调 | 调式切换 | 欢乐→悲伤 |
| 慢速→快速 | 速度变化 | 平静→紧张 |
| 独奏→齐奏 | 配器扩大 | 孤独→壮丽 |
| 正常→倒影 | 旋律反向 | 正面→阴暗面 |
| 完整→碎片 | 只出现几个音 | 暗示/回忆 |

---

## 5. 循环音乐设计

### 无缝循环要点

| 要点 | 说明 |
|------|------|
| 首尾和声匹配 | 结尾和弦自然解决到开头和弦 |
| 节奏连续 | 尾部节奏型可以无缝接头部 |
| 避免强辨识头尾 | 开头不要太有标志性（否则循环感明显） |
| 长度适当 | 探索BGM: 2-4分钟；战斗: 1.5-3分钟 |
| 渐变过渡 | 最后2-4小节向开头回归 |

### 抗疲劳设计

| 方法 | 描述 |
|------|------|
| 足够长度 | 短于1分钟会快速厌烦 |
| 低信息密度 | 避免过于复杂的旋律（探索BGM） |
| 变化段落 | 内部有A/B段变化 |
| 动态层次 | 垂直分层系统随游戏状态变化 |
| 环境融合 | 与游戏音效/环境声融为一体 |

---

## 6. 情感曲线与音乐节奏

### 典型游戏情感曲线

```
情感强度
  ↑
  |          ╱Boss╲
  |    ╱战斗╲╱      ╲    ╱最终╲
  |   ╱      ╲        ╲  ╱ Boss ╲
  |  ╱ 探索   ╲ 解谜   ╲╱       ╲ 结局
  | ╱          ╲                    ╲
  |╱ 开场       ╲                    ╲→
  +————————————————————————————————————→ 时间

音乐配合:
低谷 = 氛围/环境/轻柔
上升 = 节奏加密/层次增多
高潮 = 全编制/高强度
下降 = 逐步减层/回归宁静
```

---

## 7. 音乐与游戏元素对应表

### 属性/元素 → 音乐特征

| 游戏元素 | 调式 | 乐器 | 节奏 | AI Prompt |
|---------|------|------|------|----------|
| 火 Fire | 小调/弗利几亚 | 打击乐+铜管+弦乐 | 快速密集 | "fire element, aggressive, fiery, intense brass" |
| 水 Water | 利底亚/大调 | 竖琴+长笛+钢琴 | 流动自由 | "water element, flowing, liquid, gentle, serene" |
| 风 Wind | 混合利底亚 | 长笛+弦乐泛音 | 轻快飘逸 | "wind element, airy, breezy, light, floating" |
| 土 Earth | 多利亚 | 大提琴+圆号+定音鼓 | 稳重厚实 | "earth element, grounded, deep, sturdy, heavy" |
| 光 Light | 大调/利底亚 | 钟琴+竖琴+弦乐 | 开阔明亮 | "light element, radiant, celestial, pure, bright" |
| 暗 Dark | 洛克利亚/弗利几亚 | 低音弦乐+低音管 | 缓慢压抑 | "dark element, ominous, shadowy, menacing" |
| 雷 Thunder | 混合利底亚 | 铜管+定音鼓+弦乐 | 间歇爆发 | "thunder, powerful, electric, booming, striking" |
| 冰 Ice | 自然小调 | 钢琴高音+钟琴+弦乐 | 清冷稀疏 | "ice element, crystalline, cold, frozen, delicate" |

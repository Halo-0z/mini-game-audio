# 混音声场摆位与频率工程参考

> AI 音乐制作 prompt 工程专用参考。聚焦混音空间、声场定位与频率分布知识。

---

## 1. 立体声声场三维模型

```
        【高频/亮度】
            ↑
            |
  左 ←——————+——————→ 右    【声像/Panning】
            |
            ↓
        【低频/厚度】

  近 ←——————————————→ 远    【深度/Depth: 由音量+混响控制】
```

### 声场定位三要素

| 维度 | 控制方式 | AI Prompt 关键词 |
|------|---------|-----------------|
| 左右（Panning） | 声像旋钮 L/R | wide stereo, centered, panned left/right |
| 前后（Depth） | 音量 + 混响量 | upfront, distant, spacious reverb |
| 上下（Frequency） | EQ 高低频分布 | bright, dark, airy, deep |

---

## 2. 标准乐器声像定位图

### 管弦乐团标准摆位（观众视角）

```
                    【指挥】

    小提琴I    小提琴II    中提琴    大提琴    低音提琴
    L:30%      L:15%      C→R:10%   R:25%    R:40%

         长笛    双簧管    单簧管    巴松管
         L:20%   L:10%    R:10%    R:20%

              圆号      小号      长号    大号
              L:25%     R:15%    R:25%   R:35%

                    打击乐（分散）
              定音鼓C    钹R:20%    三角铁L:15%

                    竖琴 L:35%
```

### 流行/摇滚乐队标准摆位

| 乐器 | 声像位置 | Panning 值 | 说明 |
|------|---------|-----------|------|
| 人声 Lead Vocal | 正中 | C (0%) | 永远居中 |
| 贝斯 Bass | 正中 | C (0%) | 低频居中保稳定 |
| 底鼓 Kick | 正中 | C (0%) | 低频居中 |
| 军鼓 Snare | 近中 | C~L:5% | 微偏或居中 |
| 踩镲 Hi-Hat | 偏侧 | R:30-50% | 右侧（鼓手视角左） |
| 吉他 L | 左侧 | L:50-80% | 双吉他分左右 |
| 吉他 R | 右侧 | R:50-80% | |
| 键盘/合成器 | 宽幅 | L:40%~R:40% | 立体声展宽 |
| 和声人声 | 两侧 | L:30%+R:30% | 双轨分左右 |
| 弦乐垫底 | 宽幅 | L:60%~R:60% | 营造空间感 |

---

## 3. 频率频段速查表

### 频率频段划分

| 频段 | 频率范围 | 名称 | 特征 | AI Prompt 关键词 |
|------|---------|------|------|-----------------|
| 次低频 | 20-60 Hz | Sub-bass | 体感震动，不可闻 | sub bass, deep rumble |
| 低频 | 60-250 Hz | Bass | 温暖厚重 | warm bass, punchy low end |
| 中低频 | 250-500 Hz | Low-mid | 浑浊区，需小心 | muddy（负面）, full body |
| 中频 | 500-2000 Hz | Mid | 人声基频，乐器主体 | present, full, telephone-like |
| 中高频 | 2-4 kHz | Upper-mid | 穿透力，攻击感 | cutting, aggressive, presence |
| 高频 | 4-8 kHz | Presence | 清晰度，齿音 | crisp, clear, bright |
| 极高频 | 8-20 kHz | Brilliance/Air | 空气感，闪亮 | airy, sparkling, shimmering |

### 常见乐器基频范围

| 乐器 | 基频范围 (Hz) | 泛音/特征频段 |
|------|-------------|-------------|
| 低音提琴 | 41-262 | 低频厚度 |
| 大提琴 | 65-1047 | 中低频温暖 |
| 贝斯吉他 | 41-330 | 低频 + 800Hz 弹性 |
| 底鼓 | 60-100 | 40-60Hz 冲击 |
| 军鼓 | 150-250 | 3-5kHz 响线 |
| 吉他 | 82-1175 | 2-4kHz 咬弦 |
| 人声（男） | 85-350 | 3kHz 穿透力 |
| 人声（女） | 165-700 | 4-5kHz 明亮 |
| 钢琴 | 28-4186 | 全频段 |
| 小提琴 | 196-3520 | 中高频明亮 |
| 小号 | 165-988 | 1-5kHz 辉煌 |
| 长笛 | 262-2349 | 高频空灵 |

---

## 4. 频率冲突与解决策略

### 常见频率冲突对

| 冲突组合 | 冲突频段 | 解决方案 | AI Prompt 调整 |
|---------|---------|---------|---------------|
| 贝斯 vs 底鼓 | 60-100 Hz | 底鼓切60Hz以下，贝斯补80Hz | tight bass, punchy kick |
| 吉他 vs 人声 | 1-3 kHz | 吉他切2kHz凹槽 | guitar sits behind vocal |
| 钢琴 vs 吉他 | 200-800 Hz | 分频段各占位 | piano left, guitar right |
| 弦乐 vs 人声 | 300-3000 Hz | 弦乐做背景，降音量 | strings pad underneath |

### EQ 互补原则

```
乐器A在某频段 boost → 乐器B在相同频段 cut
= 互不遮挡，各有空间
```

---

## 5. 混响与空间深度

### 混响类型与用途

| 混响类型 | 特征 | 适用场景 | AI Prompt 关键词 |
|---------|------|---------|-----------------|
| Room 房间 | 小空间，亲密 | 鼓组、吉他 | room reverb, intimate space |
| Hall 音乐厅 | 大空间，壮丽 | 管弦乐、史诗 | concert hall, grand reverb |
| Cathedral 教堂 | 极长尾音 | 合唱、氛围 | cathedral reverb, ethereal |
| Plate 板式 | 平滑明亮 | 人声、军鼓 | plate reverb, smooth |
| Chamber 室内 | 中等空间 | 室内乐 | chamber reverb, warm space |
| Spring 弹簧 | 复古特色 | 复古摇滚 | spring reverb, vintage |

### 混响量与距离感

| 干湿比 | 效果 | 适用 |
|--------|------|------|
| 95/5 (极干) | 极近、亲密 | 独白、ASMR |
| 80/20 (偏干) | 近距离、清晰 | 主唱、独奏 |
| 60/40 (平衡) | 中距离、自然 | 合奏、乐队 |
| 40/60 (偏湿) | 远距离、空间 | 背景乐器 |
| 20/80 (极湿) | 极远、梦幻 | 环境氛围 |

---

## 6. 音量层次与动态

### 标准混音层次（从前到后）

| 层次 | 典型乐器 | 相对音量 | 作用 |
|------|---------|---------|------|
| 前景 | 主唱、独奏 | 0 dB (基准) | 主角 |
| 中前 | 鼓组、贝斯 | -3~-6 dB | 节奏骨架 |
| 中景 | 吉他、键盘 | -6~-10 dB | 和声填充 |
| 背景 | 弦乐垫底、效果 | -10~-18 dB | 氛围空间 |
| 远景 | 环境音、极远混响 | -18~-30 dB | 空间深度 |

### 动态与压缩

| 风格 | 动态范围 | 特点 | AI Prompt |
|------|---------|------|----------|
| 古典管弦乐 | 大 (>20 dB) | 有呼吸感 | dynamic, expressive dynamics |
| 爵士 | 中-大 (15-20 dB) | 自然动态 | natural dynamics, live feel |
| 流行/摇滚 | 中 (10-15 dB) | 稳定有力 | polished, radio-ready |
| EDM/嘻哈 | 小 (<10 dB) | 响度最大化 | loud, compressed, punchy |
| 环境音乐 | 中-大 | 缓慢呼吸 | ambient, breathing dynamics |

---

## 7. 立体声展宽技术

| 技术 | 原理 | 效果 | AI Prompt 关键词 |
|------|------|------|-----------------|
| 双轨录制 | 同内容两次录制分L/R | 自然宽度 | double-tracked, wide |
| 延迟展宽 | 一侧加 10-30ms 延迟 | Haas 效应展宽 | wide stereo, spacious |
| Mid/Side | 增强 Side 信号 | 宽度可调 | wide mix, expansive |
| 合唱效果 | Chorus/Ensemble | 厚度+宽度 | chorus effect, lush, ensemble |
| 八度叠加 | 高低八度分左右 | 丰满空间 | octave layering, full |

---

## 8. 音乐制作质感关键词

### 整体混音风格

| 风格 | 描述 | AI Prompt |
|------|------|----------|
| Lo-fi | 低保真，温暖失真 | lo-fi, vinyl crackle, warm distortion |
| Hi-fi | 高保真，清澈透明 | hi-fi, crystal clear, pristine |
| Raw | 未处理，粗糙 | raw, unpolished, garage |
| Polished | 精心打磨 | polished, radio-ready, professional |
| Vintage | 复古模拟 | vintage, analog warmth, retro |
| Modern | 现代数字 | modern production, clean, digital |
| Spacious | 空间开阔 | spacious, wide, atmospheric |
| Tight | 紧凑有力 | tight, punchy, controlled |
| Warm | 温暖圆润 | warm, smooth, round |
| Bright | 明亮闪耀 | bright, crisp, shimmering |

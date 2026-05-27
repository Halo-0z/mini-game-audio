# 古典音乐与交响乐参考

> AI 音乐制作 prompt 工程专用参考。涵盖音乐时期、曲式结构、交响乐编制与术语。

---

## 1. 西方古典音乐时期总览

| 时期 | 年代 | 代表作曲家 | 风格特征 | AI Prompt 关键词 |
|------|------|----------|---------|-----------------|
| 中世纪 Medieval | 500-1400 | 希尔德加德 | 单声部/复调，教会音乐 | medieval, gregorian chant, modal |
| 文艺复兴 Renaissance | 1400-1600 | 帕莱斯特里纳、拉索 | 复调对位，人声为主 | renaissance polyphony, a cappella |
| 巴洛克 Baroque | 1600-1750 | 巴赫、维瓦尔第、亨德尔 | 华丽装饰，通奏低音 | baroque, harpsichord, ornamental, basso continuo |
| 古典 Classical | 1750-1820 | 莫扎特、海顿、早期贝多芬 | 均衡对称，奏鸣曲式 | classical period, elegant, balanced, sonata form |
| 浪漫 Romantic | 1820-1900 | 肖邦、李斯特、瓦格纳、柴可夫斯基 | 情感强烈，乐队扩大 | romantic, expressive, emotional, large orchestra |
| 晚期浪漫 Late Romantic | 1880-1910 | 马勒、理查·施特劳斯、拉赫玛尼诺夫 | 极致管弦，色彩斑斓 | late romantic, massive orchestra, rich harmonies |
| 印象主义 Impressionism | 1880-1920 | 德彪西、拉威尔 | 色彩朦胧，全音阶 | impressionist, dreamy, whole-tone, atmospheric |
| 现代 Modern | 1900-1960 | 斯特拉文斯基、巴托克、勋伯格 | 无调性/十二音/原始主义 | modern classical, atonal, dissonant, avant-garde |
| 当代 Contemporary | 1960-今 | 约翰·威廉姆斯、久石让、汉斯·季默 | 电影配乐，新调性 | contemporary classical, cinematic, neo-tonal |
| 新古典 Neoclassical | 1920-今 | 普罗科菲耶夫、欧陆新古典 | 古典形式+现代和声 | neoclassical, modern baroque, clean |
| 极简主义 Minimalism | 1960-今 | 莱利、格拉斯、赖希 | 重复变化，渐进过程 | minimalist, repetitive, phasing, process |

---

## 2. 交响乐团编制

### 标准交响乐团座位图（观众视角）

```
                        ┌──────────┐
                        │  指挥台  │
                        └──────────┘

  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
  │ 小提琴I │  │ 小提琴II│  │ 中提琴  │  │ 大提琴  │  │低音提琴 │
  │  (左前) │  │ (中左)  │  │  (中)   │  │ (中右)  │  │  (右后) │
  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘

        ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
        │ 长笛 │  │双簧管│  │单簧管│  │巴松管│
        │ (左) │  │(中左)│  │(中右)│  │ (右) │
        └──────┘  └──────┘  └──────┘  └──────┘

           ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
           │ 圆号 │  │ 小号 │  │ 长号 │  │ 大号 │
           │ (左) │  │(中)  │  │(中右)│  │ (右) │
           └──────┘  └──────┘  └──────┘  └──────┘

                    ┌────────────────┐
                    │  打击乐器组    │
                    │ (定音鼓居中)   │
                    └────────────────┘

   ┌──────┐                                    ┌──────┐
   │ 竖琴 │                                    │ 钢琴 │
   │ (左) │                                    │ (右) │
   └──────┘                                    └──────┘
```

### 编制规模对比

| 编制 | 木管配置 | 弦乐人数 | 总人数 | 典型时期 | AI Prompt |
|------|---------|---------|-------|---------|----------|
| 双管编制 | 各2支 | 40-50 | 55-65 | 古典时期 | classical orchestra |
| 三管编制 | 各3支 | 50-60 | 70-80 | 浪漫时期 | romantic orchestra |
| 四管编制 | 各4支 | 60-70 | 90-110 | 晚浪漫/现代 | large symphony orchestra |

---

## 3. 曲式结构大全

### 3.1 奏鸣曲式 Sonata Form（最重要）

```
呈示部 (Exposition)
├── 主题 I（主调）     ← 性格鲜明
├── 过渡段 (Bridge)    ← 调性转换
├── 主题 II（属调）    ← 对比性格
└── 结束段 (Codetta)

展开部 (Development)
├── 主题变形/碎片化
├── 转调探索
└── 和声冲突与高潮

再现部 (Recapitulation)
├── 主题 I（主调）
├── 主题 II（主调！）  ← 回归主调
└── 尾声 (Coda)
```

### 3.2 回旋曲式 Rondo Form

```
A - B - A - C - A - (Coda)
主题  插部1  主题  插部2  主题   尾声

特点: 主题反复出现，插部提供变化
AI Prompt: "rondo form, recurring theme"
```

### 3.3 变奏曲式 Theme and Variations

```
主题 → 变奏1 → 变奏2 → 变奏3 → ... → 尾声
      (节奏变) (调性变) (配器变)

AI Prompt: "theme and variations, evolving"
```

### 3.4 赋格 Fugue

```
主题(声部1) → 答题(声部2) → 主题(声部3) → 展开 → 紧接段 → 终止

特点: 严格的对位法，主题在不同声部间模仿
AI Prompt: "fugue, contrapuntal, polyphonic"
```

### 3.5 三部曲式 Ternary Form (ABA)

```
A（主段）→ B（对比段）→ A（再现）

AI Prompt: "ABA form, contrasting middle section"
```

---

## 4. 交响曲标准四乐章结构

| 乐章 | 速度 | 曲式 | 性格 | AI Prompt |
|------|------|------|------|----------|
| 第一乐章 | 快板 Allegro | 奏鸣曲式 | 戏剧性、严肃 | "symphonic first movement, dramatic allegro" |
| 第二乐章 | 慢板 Adagio/Andante | 三段式/变奏 | 抒情、深沉 | "slow movement, lyrical adagio" |
| 第三乐章 | 小步舞/谐谑 | 三段式 (ABA) | 轻快、幽默 | "scherzo, playful, dance-like" |
| 第四乐章 | 快板/急板 | 奏鸣/回旋 | 辉煌、总结 | "finale, triumphant, brilliant" |

---

## 5. 速度术语表

| 术语 | BPM 范围 | 含义 | AI Prompt |
|------|---------|------|----------|
| Grave | 20-40 | 极慢，庄重 | grave, solemn, very slow |
| Largo | 40-60 | 广板，宽广 | largo, broad, stately |
| Adagio | 60-76 | 柔板，从容 | adagio, slow, gentle |
| Andante | 76-108 | 行板，步行速度 | andante, walking pace |
| Moderato | 108-120 | 中板 | moderato, moderate tempo |
| Allegretto | 112-120 | 稍快板 | allegretto, moderately fast |
| Allegro | 120-156 | 快板 | allegro, fast, lively |
| Vivace | 156-176 | 活泼 | vivace, vivacious, spirited |
| Presto | 176-200 | 急板 | presto, very fast |
| Prestissimo | 200+ | 最急板 | prestissimo, as fast as possible |

### 速度变化术语

| 术语 | 含义 | AI Prompt |
|------|------|----------|
| Accelerando (accel.) | 渐快 | accelerating, building speed |
| Ritardando (rit.) | 渐慢 | slowing down, ritardando |
| Rubato | 自由速度 | rubato, flexible tempo, expressive timing |
| A tempo | 回原速 | returning to tempo |
| Fermata | 延长记号 | held note, fermata, pause |

---

## 6. 力度术语表

| 符号 | 术语 | 含义 | 相对音量 |
|------|------|------|---------|
| ppp | Pianississimo | 极弱 | ~10% |
| pp | Pianissimo | 很弱 | ~20% |
| p | Piano | 弱 | ~35% |
| mp | Mezzo-piano | 中弱 | ~50% |
| mf | Mezzo-forte | 中强 | ~65% |
| f | Forte | 强 | ~80% |
| ff | Fortissimo | 很强 | ~90% |
| fff | Fortississimo | 极强 | ~100% |

### 力度变化

| 符号 | 含义 | AI Prompt |
|------|------|----------|
| crescendo (cresc.) | 渐强 | building, crescendo, growing |
| decrescendo/diminuendo | 渐弱 | fading, diminuendo, dying away |
| sforzando (sfz) | 突强 | sudden accent, sforzando |
| fp | 强后即弱 | forte then piano |

---

## 7. 古典音乐体裁速查

| 体裁 | 特征 | 典型编制 | AI Prompt |
|------|------|---------|----------|
| 交响曲 Symphony | 4乐章，最高形式 | 管弦乐团 | symphony, symphonic |
| 协奏曲 Concerto | 独奏+乐队对话 | 独奏+管弦 | concerto, virtuoso solo with orchestra |
| 奏鸣曲 Sonata | 独奏/小编制 | 钢琴/小提琴等 | sonata, solo instrument |
| 弦乐四重奏 String Quartet | 4件弦乐 | 2小提+中提+大提 | string quartet, intimate chamber |
| 序曲 Overture | 歌剧/音乐会开场 | 管弦乐团 | overture, dramatic opening |
| 组曲 Suite | 多段舞曲集 | 灵活 | suite, dance movements |
| 赋格 Fugue | 对位法杰作 | 键盘/合唱 | fugue, contrapuntal |
| 练习曲 Etude | 技巧训练 | 独奏 | etude, virtuosic, technical |
| 夜曲 Nocturne | 夜晚抒情 | 钢琴 | nocturne, dreamy, night music |
| 前奏曲 Prelude | 自由即兴风格 | 钢琴/管弦 | prelude, improvisatory |
| 圆舞曲 Waltz | 3/4拍舞曲 | 管弦/钢琴 | waltz, 3/4 time, elegant dance |
| 进行曲 March | 行进节奏 | 管乐/管弦 | march, military, processional |
| 安魂曲 Requiem | 追悼弥撒 | 合唱+管弦 | requiem, solemn, sacred |
| 弥撒曲 Mass | 宗教仪式 | 合唱+管弦 | mass, choral, sacred |
| 歌剧 Opera | 戏剧+音乐 | 歌手+管弦 | operatic, dramatic, aria |
| 芭蕾 Ballet | 舞蹈配乐 | 管弦乐团 | ballet music, dance, graceful |
| 交响诗 Symphonic Poem | 叙事性管弦 | 管弦乐团 | symphonic poem, tone poem, narrative |

---

## 8. 管弦乐色彩组合速查

| 色彩效果 | 乐器组合 | AI Prompt |
|---------|---------|----------|
| 明亮辉煌 | 小号+小提琴+长笛 | brilliant, radiant, shining |
| 黑暗深沉 | 大号+低音提琴+巴松 | dark, ominous, deep |
| 温暖柔和 | 圆号+中提琴+单簧管 | warm, mellow, gentle |
| 空灵飘渺 | 竖琴+长笛+弦乐泛音 | ethereal, floating, transparent |
| 尖锐刺耳 | 短笛+小提琴高音+铜钹 | piercing, sharp, cutting |
| 庄严肃穆 | 圆号齐奏+定音鼓 | majestic, solemn, stately |
| 田园宁静 | 双簧管+长笛+弦乐拨弦 | pastoral, peaceful, idyllic |
| 狂暴激烈 | 全管弦forte+打击乐 | furious, violent, stormy |
| 神秘莫测 | 弦乐震音+独奏低音单簧 | mysterious, eerie, shadowy |
| 童话梦幻 | 钟琴+竖琴+弦乐 | fairy-tale, magical, whimsical |

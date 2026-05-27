# 配器法与管弦乐编配参考

> AI 音乐制作 prompt 工程专用参考。聚焦可直接转化为 AI prompt 关键词的配器知识。

---

## 1. 四大乐器族概览

| 族 | 乐器 | 音域范围 | AI Prompt 关键词 |
|----|------|---------|-----------------|
| **弦乐 Strings** | 小提琴 Violin | G3–E7 | violin, orchestral strings, lush strings |
| | 中提琴 Viola | C3–E6 | viola, warm strings |
| | 大提琴 Cello | C2–C6 | cello, deep strings, rich cello |
| | 低音提琴 Double Bass | E1–G4 | double bass, contrabass, deep bass strings |
| | 竖琴 Harp | C1–G7 | harp, harp arpeggios, ethereal harp |
| **木管 Woodwinds** | 长笛 Flute | C4–D7 | flute, airy flute, pastoral flute |
| | 双簧管 Oboe | Bb3–A6 | oboe, pastoral oboe, melancholic oboe |
| | 单簧管 Clarinet | D3–Bb6 | clarinet, warm clarinet, jazz clarinet |
| | 巴松管 Bassoon | Bb1–Eb5 | bassoon, deep woodwind |
| | 短笛 Piccolo | D5–C8 | piccolo, bright piccolo |
| **铜管 Brass** | 小号 Trumpet | F#3–D6 | trumpet, bright trumpet, fanfare trumpet |
| | 圆号 French Horn | B1–F5 | french horn, warm horn, heroic horn |
| | 长号 Trombone | E2–F5 | trombone, powerful trombone |
| | 大号 Tuba | D1–F4 | tuba, deep brass, bass brass |
| **打击 Percussion** | 定音鼓 Timpani | D2–C4 | timpani, orchestral drums, timpani rolls |
| | 钹 Cymbals | — | crash cymbal, suspended cymbal |
| | 三角铁 Triangle | — | triangle, delicate percussion |
| | 钟琴 Glockenspiel | G5–C8 | glockenspiel, bright bells |
| | 马林巴 Marimba | C2–C7 | marimba, warm mallet |
| | 颤音琴 Vibraphone | F3–F6 | vibraphone, jazz vibes |

---

## 2. 弦乐演奏技法与 Prompt 关键词

| 技法 | 意大利术语 | 效果描述 | AI Prompt 关键词 |
|------|----------|---------|-----------------|
| 弓奏（长弓） | Arco / Legato | 连绵流畅 | legato strings, sustained strings |
| 断奏 | Staccato | 短促跳跃 | staccato strings, plucked feel |
| 拨弦 | Pizzicato | 拨弦清脆 | pizzicato, plucked strings |
| 震音 | Tremolo | 快速交替 | tremolo strings, shimmering strings |
| 颤音 | Vibrato | 音高微颤 | expressive vibrato, warm vibrato |
| 泛音 | Harmonics | 空灵透明 | string harmonics, ethereal harmonics |
| 滑音 | Glissando | 音高滑动 | glissando, sliding strings |
| 跳弓 | Spiccato | 弹跳弓法 | spiccato, bouncing bow |
| 碎弓 | Col legno | 弓杆击弦 | col legno, percussive strings |
| 弱音器 | Con sordino | 柔和朦胧 | muted strings, con sordino |
| 强力齐奏 | Tutti | 全体齐奏 | full orchestra, tutti strings |

---

## 3. 配器原则与平衡

### 3.1 音域分层原则（自下而上）

```
高音区 (Soprano)  ← 旋律/装饰    小提琴、长笛、短笛、小号
中高音 (Alto)     ← 副旋律/和声   中提琴、双簧管、单簧管、圆号
中低音 (Tenor)    ← 和声填充      大提琴、巴松管、长号
低音区 (Bass)     ← 根音/基础     低音提琴、大号、定音鼓
```

### 3.2 配器密度与情感对应

| 密度 | 乐器数量 | 情感效果 | AI Prompt 描述 |
|------|---------|---------|---------------|
| 极薄 | 1-2件 | 孤独、亲密、脆弱 | solo instrument, intimate, sparse |
| 轻薄 | 3-5件 | 细腻、优雅、室内乐 | chamber music, delicate, light orchestration |
| 中等 | 8-15件 | 平衡、叙事、电影感 | moderate orchestra, cinematic, balanced |
| 丰厚 | 20-40件 | 宏大、史诗、壮丽 | full orchestra, epic, grand, lush |
| 极厚 | 60+ | 压倒性、高潮 | massive orchestra, overwhelming, climactic |

### 3.3 常用配器组合（AI Prompt 模板）

| 组合名称 | 乐器搭配 | 适用场景 | Prompt 示例 |
|---------|---------|---------|------------|
| 弦乐四重奏 | 2小提+中提+大提 | 优雅、古典 | "string quartet, classical, elegant" |
| 木管五重奏 | 长笛+双簧+单簧+圆号+巴松 | 田园、轻快 | "woodwind quintet, pastoral, light" |
| 铜管合奏 | 小号+圆号+长号+大号 | 庄严、英雄 | "brass ensemble, heroic, majestic" |
| 弦乐+竖琴 | 弦乐组+竖琴 | 浪漫、梦幻 | "strings with harp, romantic, dreamy" |
| 弦乐+木管 | 弦乐+长笛/双簧 | 温暖、叙事 | "strings and woodwinds, warm, narrative" |
| 全管弦乐 | 全部四族 | 史诗、高潮 | "full symphony orchestra, epic, powerful" |

---

## 4. 里姆斯基-科萨科夫配器法要点

### 4.1 音色融合三法则

1. **同族融合**: 同族乐器音色天然融合（弦乐组、木管组内部）
2. **八度叠加**: 不同乐器演奏相同旋律的不同八度，增强音色厚度
3. **交叉配器**: 旋律在不同乐器间传递，保持色彩变化

### 4.2 力度平衡公式

```
1 小号 ≈ 2 圆号 ≈ 2 长号 ≈ 4 单簧管 ≈ 8 小提琴
```

### 4.3 音域间距规则

- 低音区：间距宽（≥五度），避免浑浊
- 中音区：间距中等（三度至五度）
- 高音区：间距窄（二度至三度），可以密集

---

## 5. 民族/世界乐器速查

| 地区 | 乐器 | 特色 | AI Prompt 关键词 |
|------|------|------|-----------------|
| 中国 | 二胡 | 悲怨抒情 | erhu, chinese fiddle, melancholic |
| 中国 | 古筝 | 流水意境 | guzheng, chinese zither, flowing |
| 中国 | 琵琶 | 铿锵有力 | pipa, chinese lute, dramatic |
| 中国 | 竹笛 | 清新悠扬 | chinese bamboo flute, dizi, pastoral |
| 日本 | 尺八 | 空灵禅意 | shakuhachi, zen flute, meditative |
| 日本 | 三味线 | 传统戏剧 | shamisen, japanese traditional |
| 日本 | 太鼓 | 震撼力量 | taiko drums, powerful japanese drums |
| 印度 | 西塔尔 | 冥想异域 | sitar, indian classical, meditative |
| 印度 | 塔布拉 | 复杂节奏 | tabla, indian percussion |
| 爱尔兰 | 锡哨 | 凯尔特风 | tin whistle, celtic, irish |
| 爱尔兰 | 风笛 | 苏格兰/爱尔兰 | bagpipes, celtic pipes |
| 中东 | 乌德琴 | 阿拉伯风 | oud, arabic, middle eastern |
| 非洲 | 姆比拉 | 灵性节奏 | mbira, kalimba, african thumb piano |
| 拉丁 | 班卓琴 | 乡村蓝草 | banjo, bluegrass, country |

---

## 6. 管弦乐编制规模

| 编制 | 弦乐 | 木管 | 铜管 | 打击 | 总人数 | AI Prompt |
|------|------|------|------|------|-------|----------|
| 室内乐 | 4-8 | 0-2 | 0 | 0-1 | 5-12 | chamber orchestra, intimate |
| 小型管弦 | 8-16 | 4-6 | 2-4 | 1-2 | 20-30 | small orchestra |
| 古典编制（双管） | 16-24 | 8 | 4-6 | 2-3 | 35-50 | classical orchestra |
| 浪漫编制（三管） | 24-32 | 12 | 8-10 | 3-4 | 55-75 | romantic orchestra, large |
| 现代大编制（四管） | 32-40 | 16 | 12-14 | 4-6 | 80-110 | massive orchestra, epic |

---

## 7. AI Prompt 中的配器关键词速查

### 按情绪选配器

| 情绪 | 推荐配器 Prompt |
|------|---------------|
| 悲伤/忧郁 | "solo cello, melancholic oboe, muted strings" |
| 欢快/活泼 | "playful flute, pizzicato strings, light percussion" |
| 紧张/悬疑 | "tremolo strings, low brass, timpani rolls" |
| 史诗/壮丽 | "full orchestra, brass fanfare, choir, timpani" |
| 温暖/治愈 | "warm strings, gentle woodwinds, harp arpeggios" |
| 恐怖/不安 | "dissonant strings, col legno, eerie harmonics" |
| 神秘/魔幻 | "celesta, ethereal harp, string harmonics, choir" |
| 英雄/胜利 | "heroic brass, triumphant trumpet, full strings" |
| 田园/自然 | "pastoral flute, oboe, light strings, bird sounds" |
| 宫廷/华丽 | "harpsichord, baroque strings, ornamental flute" |

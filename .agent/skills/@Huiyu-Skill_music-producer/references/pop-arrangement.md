# 流行音乐编曲与制作参考

> AI 音乐制作 prompt 工程专用参考。涵盖流行乐六层编曲模型、风格配方与制作技术。

---

## 1. 六层编曲模型

```
第6层  装饰层 (Ear Candy)     ← 效果音、反转混响、ad-lib
第5层  旋律层 (Melody)         ← 主唱、合成器 lead
第4层  和声层 (Harmony/Pad)    ← 和弦垫底、弦乐、合成器 pad
第3层  节奏层 (Rhythm)         ← 吉他扫弦、hi-hat pattern、shaker
第2层  低音层 (Bass)           ← 贝斯、808 低音
第1层  基底层 (Foundation)     ← 底鼓、军鼓骨架
```

### 各层详解

| 层次 | 角色 | 常用乐器 | 编曲技巧 | AI Prompt 关键词 |
|------|------|---------|---------|-----------------|
| 基底 | 节拍骨架 | Kick, Snare, Clap | 四四拍底鼓，2/4拍军鼓 | punchy kick, crisp snare |
| 低音 | 和声根基 | 贝斯, 808, Sub Bass | 跟随和弦根音 | deep bass, 808 bass, sub |
| 节奏 | 律动驱动 | Hi-hat, Percussion, 吉他 | 16分音符变化 | rhythmic, groovy, percussive |
| 和声 | 色彩铺底 | Pad, 弦乐, 钢琴 | 全音符/二分音符长音 | lush pads, warm chords |
| 旋律 | 核心主线 | 人声, Lead Synth | Hook + 副歌旋律 | catchy melody, vocal hook |
| 装饰 | 画龙点睛 | FX, Risers, Fills | 转场前后使用 | ear candy, fx, transitions |

---

## 2. 加减法编曲原则

### 加法原则（Build Up）

```
Intro  → 基底+低音（2层）
Verse  → +节奏+和声（4层）
Pre    → +旋律+部分装饰（5层）
Chorus → 全部6层开满
Bridge → 减至2-3层后重建
Outro  → 逐层递减
```

### 减法原则（Drop Out）

| 手法 | 描述 | 效果 | AI Prompt |
|------|------|------|----------|
| 突然停止 | 所有乐器同时停止 | 巨大反差 | "sudden stop, dramatic pause" |
| 底鼓抽离 | 去掉底鼓保留其他 | 悬浮感 | "kick drops out, floating" |
| 贝斯抽离 | 去掉低音 | 轻盈感 | "bass drops out, airy" |
| 只留人声 | 其他全部静音 | 亲密/震撼 | "vocals only, a cappella moment" |
| 高频滤波 | 低通滤波器逐步开启 | 水下到水面 | "filtered, muffled then opening" |

---

## 3. 风格编曲配方

### 3.1 Pop 流行

| 元素 | 标准配置 | AI Prompt |
|------|---------|----------|
| 节拍 | 4/4, 100-130 BPM | "pop beat, four-on-the-floor" |
| 底鼓 | 四分音符 | "steady kick, pop drums" |
| 贝斯 | 电贝斯/合成贝斯 | "pop bass, synth bass" |
| 和声 | 钢琴/吉他/合成器 pad | "piano chords, synth pads" |
| 旋律 | 人声为主 + 合成器 hook | "catchy vocal melody, hook" |
| 制作 | 精致压缩，响度优化 | "polished pop production, radio-ready" |

### 3.2 Hip-Hop / Trap

| 元素 | 标准配置 | AI Prompt |
|------|---------|----------|
| 节拍 | 4/4, 60-90 BPM (half-time 130-170) | "trap beat, hip-hop drums" |
| Hi-hat | 快速三连音/32分音符滚奏 | "rolling hi-hats, trap hi-hats" |
| 808 | 长延音低音合成器 | "808 bass, booming 808, sub bass" |
| 旋律 | 合成器 lead + 钢琴 | "dark melody, minor key synth" |
| 人声 | Auto-Tune + ad-lib | "auto-tuned vocals, ad-libs" |
| 效果 | 反转808, 枪声FX | "producer tags, fx hits" |

### 3.3 R&B / Soul

| 元素 | 标准配置 | AI Prompt |
|------|---------|----------|
| 节拍 | 4/4, 65-95 BPM | "R&B groove, smooth drums" |
| 和声 | 七和弦、九和弦为主 | "jazzy chords, extended harmony, 7th chords" |
| 贝斯 | 温暖电贝斯，指弹 | "warm bass, fingerstyle bass, groovy" |
| 键盘 | Rhodes/Wurlitzer 电钢 | "rhodes piano, electric piano, warm keys" |
| 人声 | 转音、和声层叠 | "silky vocals, vocal runs, harmonies" |
| 氛围 | 温暖混响+延迟 | "smooth, sultry, late-night vibe" |

### 3.4 EDM / Electronic

| 子类型 | BPM | 特征 | AI Prompt |
|--------|-----|------|----------|
| House | 120-130 | 四四底鼓，off-beat hi-hat | "house music, four-on-the-floor, dancefloor" |
| Techno | 130-150 | 机械节拍，暗黑合成器 | "techno, dark, mechanical, industrial" |
| Trance | 130-150 | 持续Pad，渐进展开 | "trance, euphoric, building, arpeggiated synth" |
| Dubstep | 140 (half-time 70) | 重低音 wobble bass | "dubstep, heavy bass, wobble, drop" |
| Future Bass | 140-160 | 弯音合成器，侧链 | "future bass, pitch-bent synths, sidechain" |
| Drum & Bass | 160-180 | 快速碎拍+重低音 | "drum and bass, fast breakbeats, rolling bass" |
| Lo-fi House | 115-125 | 复古采样+vinyl质感 | "lo-fi house, vinyl, nostalgic, warm" |
| Synthwave | 80-120 | 80年代合成器复古 | "synthwave, retro 80s, analog synths, neon" |

### 3.5 Rock / Alternative

| 子类型 | 特征 | AI Prompt |
|--------|------|----------|
| Pop Rock | 吉他+流行结构 | "pop rock, electric guitar, driving drums" |
| Indie Rock | 复古录音质感 | "indie rock, lo-fi, jangly guitars, DIY" |
| Alternative | 实验+主流平衡 | "alternative rock, grunge, raw, emotional" |
| Post-Rock | 渐进展开无人声 | "post-rock, atmospheric, crescendo, no vocals" |
| Punk Rock | 快速简单三和弦 | "punk rock, fast, aggressive, raw energy" |
| Metal | 失真吉他+双踩 | "metal, heavy distortion, double bass drums" |

### 3.6 Country / Folk

| 元素 | 配置 | AI Prompt |
|------|------|----------|
| 吉他 | 原声吉他扫弦 | "acoustic guitar, strumming, country twang" |
| 提琴 | Fiddle 独奏 | "fiddle, country fiddle, folk violin" |
| 班卓 | Banjo 指弹 | "banjo, bluegrass, picking" |
| 贝斯 | Walking bass | "upright bass, walking bass, country bass" |
| 人声 | 叙事性强 | "storytelling vocals, country twang, heartfelt" |
| 制作 | 温暖自然 | "Nashville production, warm, organic" |

### 3.7 Jazz

| 子类型 | 特征 | AI Prompt |
|--------|------|----------|
| Swing | 摇摆节奏，大乐队 | "swing jazz, big band, swinging rhythm" |
| Bebop | 快速即兴，复杂和声 | "bebop, fast improvisation, complex harmonies" |
| Cool Jazz | 冷静克制 | "cool jazz, laid-back, subdued, Miles Davis" |
| Bossa Nova | 巴西节奏+爵士和声 | "bossa nova, brazilian, gentle sway, nylon guitar" |
| Smooth Jazz | 柔和电气化 | "smooth jazz, mellow, saxophone, easy listening" |
| Jazz Fusion | 爵士+摇滚/funk | "jazz fusion, funky, electric, complex" |
| Lo-fi Jazz | 采样+beats | "lo-fi jazz, jazzy lo-fi, chill, sample-based" |

### 3.8 Latin

| 类型 | 节奏 | AI Prompt |
|------|------|----------|
| Reggaeton | Dembow 节奏 | "reggaeton, dembow rhythm, perreo, latin urban" |
| Salsa | 复杂打击乐 | "salsa, congas, timbales, latin groove" |
| Samba | 巴西节奏 | "samba, brazilian percussion, carnival" |
| Cumbia | 哥伦比亚节奏 | "cumbia, accordion, latin folk" |
| Flamenco | 西班牙吉他 | "flamenco, spanish guitar, passionate, clapping" |

---

## 4. 人声编曲技术

### 人声层次类型

| 层次 | 作用 | 录制方式 | AI Prompt |
|------|------|---------|----------|
| Lead Vocal | 主旋律 | 单轨居中 | "lead vocals, front and center" |
| Double | 加厚 | 相同旋律再录一遍 | "double-tracked vocals, thick" |
| Harmony (3度) | 和声 | 高/低三度 | "vocal harmonies, third harmony" |
| Harmony (5度) | 开阔感 | 纯五度 | "fifth harmony, open, wide" |
| Octave | 宽度 | 高/低八度 | "octave vocals, powerful" |
| Ad-lib | 装饰 | 即兴填充 | "ad-libs, vocal fills, yeah" |
| Whisper | 质感 | 耳语叠加 | "whispered vocals, intimate" |
| Choir | 壮丽 | 多人合唱 | "choir, chorus, gang vocals" |

---

## 5. 转场与过渡技巧

| 技巧 | 描述 | 位置 | AI Prompt |
|------|------|------|----------|
| Riser | 上行白噪声 | 进副歌前 | "riser, building tension, sweep up" |
| Impact/Hit | 低频冲击 | 副歌第一拍 | "impact, bass drop, downbeat hit" |
| Reverse Cymbal | 反转钹声 | 段落衔接 | "reverse cymbal, transition" |
| Fill | 鼓组过门 | 小节末尾 | "drum fill, tom fill, snare roll" |
| Tape Stop | 磁带减速效果 | 突然变化处 | "tape stop effect, vinyl brake" |
| Filter Sweep | 滤波器扫频 | 持续过渡 | "filter sweep, opening up" |
| Vocal Chop | 人声切片 | 装饰过渡 | "vocal chops, chopped vocals" |
| Reverse Vocal | 反转人声 | 人声进入前 | "reversed vocals, ghostly" |
| Silence | 静默 | 最强反差 | "moment of silence, dramatic pause" |

---

## 6. 现代制作技术关键词

| 技术 | 描述 | AI Prompt |
|------|------|----------|
| Sidechain Compression | 底鼓触发其他乐器闪避 | "sidechain, pumping, ducking" |
| Vocal Tuning | 音准修正 | "tuned vocals, pitch-perfect" |
| Auto-Tune | 明显音准效果 | "auto-tune, T-Pain effect, robotic vocals" |
| Vocoder | 人声合成器 | "vocoder, robotic, talk box" |
| Sampling | 采样复用 | "sample-based, chopped samples" |
| Bit-crushing | 降低采样精度 | "bitcrushed, lo-fi, retro digital" |
| Saturation | 谐波饱和 | "saturated, warm distortion, analog warmth" |
| Granular | 颗粒合成 | "granular synthesis, textured, glitchy" |
| Time-stretching | 时间拉伸 | "time-stretched, warped, morphing" |

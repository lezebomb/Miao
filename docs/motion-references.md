# 妙妙动作研究与参考

网络视频只用于研究真实猫咪的动作阶段、受力与节奏。妙妙的脸、毛色、体态、尾巴和其他身份特征只来自本地照片、视频与现有渲染帧；仓库不保存或重新分发其他人的完整视频。

参考优先级：妙妙自己的视频 ＞ 网络真实猫咪视频 ＞ 动画推测。

## 本地视频观察

### `撒娇打滚.mp4` 与 `打滚 蹭人.mp4`

- 妙妙先降低胸口，肩膀早于骨盆接触地面；
- 侧躺后脊柱形成弧线，骨盆随后翻转，尾巴比躯干晚半拍；
- 露腹时前爪弯曲而不是伸直，后腿放松分开；
- 翻回侧面后有清楚停顿，再用前肢支撑恢复；
- “蹭人”片段证明动作是放松索取互动，不应做成快速翻筋斗。

### `踩奶.mp4`

- 妙妙头部低而稳定，肩线随左右前爪交替产生小幅起伏；
- 爪子抬起幅度很小，按下阶段比抬爪阶段停留更久；
- 胸口只有轻微上下运动，后腿、臀部和尾巴基本不参与；
- 一个完整左右周期适合约 2 秒，重复 3 次后自然回到双爪支撑。

### `躺着用爪子洗脸.mp4`

- 每次擦脸前先低头舔湿前爪；
- 抬爪比下擦慢，爪子贴近脸颊或耳根时有短暂停顿；
- 下擦由爪子带动，头只轻微配合，不横向漂移；
- 两次“舔爪→抬爪→贴脸→下擦”足以构成 4–6 秒完整动作。

本地关键帧接触表位于 `assets/video-keyframes/*-contact-sheet.jpg`。

## 网络真实猫咪视频

### 撒娇打滚

1. [Orange cat flops over for belly rubs](https://www.dailymotion.com/video/x9xnpny)
2. [Lazy pet cat falls down and rolls over](https://www.dailymotion.com/video/x7r10pl)
3. [Why Do Cats Roll on Their Back?（含实拍）](https://www.gradyvet.com/blog/why-do-cats-roll-on-their-back/)
4. [Tonkinese cat rolling around](https://commons.wikimedia.org/wiki/File:Tonkinese_cat_rolling_around_-_Japan_-_2025_mar_22.webm)

共同规律：胸肩先下沉，骨盆和后腿随后翻转；真正翻身可略快，但侧躺、露腹和翻回后的姿势都需要停顿。尾巴用于平衡并略滞后于脊柱，不应在每帧跳到另一侧。

### 踩奶

1. [Cat gets cozy on Christmas morning](https://vimeo.com/496271383)
2. [Cat Purrs and Kneads Blanket](https://www.dailymotion.com/video/xag3ja2)
3. [A Cute Cat Moving Her Paws on the Blanket](https://www.dailymotion.com/video/x9zid2o)
4. [Cat Wakes Up to Knead the Pillow](https://www.dailymotion.com/video/xa16cfw)
5. [Tika the cat kneading a blanket](https://knowyourmeme.com/videos/163450-cats)

共同规律：左右前爪不是同时起落；一侧按压时同侧肩稍低，另一爪只小幅卸重。爪落下后的压实停顿是动作可读性的关键，头部与后半身不应跟着左右摆。

### 洗脸

1. [Bengal cat licking paws and washing face in slow motion](https://motionarray.com/stock-video/footage-of-cat-licking-paws-and-washing-face-slow-motion-view-of-bengal-cat-3514212/)
2. [Cat licking paws and washing face（20 秒实拍）](https://www.vecteezy.com/video/9580974-cat-grooming-itself-at-home-cat-licking-paws-and-washing-face)
3. [Cute cat licking paws and washing face（12 秒实拍）](https://www.vecteezy.com/video/24587171-cute-cat-grooming-itself-at-home-cat-licking-paws-and-washing-face)
4. [Tabby cat washing face in slow motion](https://motionarray.com/stock-video/tabby-cat-washing-face-extreme-close-up-in-slow-motion-3359432/)
5. [A regular cat washing its face](https://www.bilibili.tv/video/4798794131576833)

共同规律：洗脸是离散循环而非连续扫动。舔爪时头低、腕关节靠近嘴；抬爪由肩和肘缓慢折叠；接触脸侧后从耳根/脸颊向下擦；爪落地后再舔一次，最后回到稳定坐姿。

## 本次动作时序

### 打滚：18 帧，5.20 秒

1. 准备与降低身体：帧 00–03，1.24 秒；
2. 肩先落地并进入侧躺：帧 04–07，0.90 秒；
3. 翻向背部与露腹：帧 08–10，0.96 秒，其中露腹核心帧停留 0.70 秒；
4. 翻回侧面并停留：帧 11–13，0.80 秒；
5. 缓慢起身回待机：帧 14–17，1.30 秒。

### 踩奶：12 帧 × 3，单周期 1.88 秒，加 4 帧恢复，总计 6.24 秒

帧 00–05 完成左爪抬起/落下/压实，帧 06–11完成右爪对应动作；压实帧分别保留 170–200ms，比卸重抬爪帧更长。第三周期结束后用 0.60 秒从双爪支撑经过低姿态和坐姿回到待机。

### 洗脸：12 个洗脸姿势 + 2 个恢复姿势，5.00 秒

帧 00–05 为第一次舔爪、抬爪、贴脸与下擦；帧 06–11重复第二次并回到坐姿。贴脸和下擦帧分别保留 420–450ms，帧 12–13 从低姿态自然回到站立待机。

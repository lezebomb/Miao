# 妙妙：金渐层交互桌宠

妙妙是在现有项目和真实照片基础上持续迭代的金渐层桌宠。本轮没有重做角色设计，保留了圆脸、绿色眼睛、金色黑毛尖、正常长度黑尾尖和原有桌宠尺寸。

![妙妙动作总览](previews/actions-v2/contact-sheet.jpg)

## 本轮动画修复

- 完全移除了整只猫之间的 `premultiplied_blend`、`tween_loop` 和 crossfade 插帧。
- 构建器现在只接受两类帧：原图集里的干净关键帧，或独立绘制的完整动作姿势。
- `idle`：10 个独立姿势，包含闭眼、睁眼、侧看和轻微头耳变化。
- `running-right` / `running-left`：各 10 个真实步态姿势；左跑由已验收的右跑逐帧镜像，帧序不变。
- `knead`：14 个独立姿势，前半身支起，左右前爪交替抬起和按压，肩背轻微联动。
- `wash-face`：14 个独立姿势，按“抬爪 → 擦脸 → 再擦 → 放下”组织。
- `roll`：16 个独立姿势，包含趴低、侧躺、翻背露肚、转向和恢复。
- 抚摸或 hover 在项目交互桌宠中以 `50% / 50%` 随机触发 `roll` 或 `knead`。
- `wash-face` 是低频随机 idle 分支，冷却时间随机为 35–65 秒。

所有扩展帧均为 `192×208` 透明 PNG。生成过程不会把两张完整猫图混合在一起。

## 启动项目交互桌宠

双击：

```text
launch-miaomiao-desktop.cmd
```

交互：

- 鼠标移入或单击：随机打滚 / 踩奶
- 左右拖动：对应方向跑动
- 待机：普通待机，低频随机洗脸
- 右键：关闭

仅检查动作包：

```powershell
.\launch-miaomiao-desktop.ps1 -CheckOnly
```

## 一键更新并启动 Codex 宠物

先完全退出 Codex，再双击：

```text
launch-codex-miaomiao.cmd
```

启动器会先把当前仓库中的 `pet.json` 和 `spritesheet.webp` 同步到
`%USERPROFILE%\.codex\pets\miaomiao`，校验 SHA-256 后再启动 Codex。因此每次拉取或重建项目后，无需重复运行安装脚本。

Codex 当前的标准 v2 渲染器仍固定各状态帧数，并把 hover 映射到 `jumping`；`pet.json` 本身不支持随机事件或自定义 idle 池。因此：

- Codex 内置宠物会使用本轮更新后的 6 帧 idle 和各 8 帧左右跑。
- 50/50 抚摸随机、14 帧踩奶、14 帧洗脸和 16 帧打滚由项目交互启动器读取 `behavior.json` 实现。

## 关键文件

```text
pet/miaomiao/
  pet.json
  spritesheet.webp
  behavior.json
  actions/*/*.png
  pose-sources/*/*.png

previews/actions-v2/
  contact-sheet.jpg
  contact-sheet-black.jpg
  contact-sheet-white.jpg
  black/*.gif
  white/*.gif
  validation.json

scripts/build_action_assets.py
scripts/extract_action_pose_sheet.py
scripts/update_codex_atlas_actions.py
```

独立姿势的生成源表保留在 `assets/action-generation/`，裁切后的规范姿势位于 `pet/miaomiao/pose-sources/`；真实动作参考关键帧位于 `assets/video-keyframes/`。

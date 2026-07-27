# 妙妙 Canvas 动画渲染器

当前桌宠主运行链路为：

```text
PowerShell 启动/跟随外壳
  → Electron Main Process
    → Renderer Process
      → requestAnimationFrame
        → Animator
        → PetStateMachine
        → CanvasRenderer
```

## 动画原则

- PNG 序列帧始终是一只独立、清晰、完整的妙妙。
- 禁止两张完整猫图进行 Alpha crossfade；过渡使用两张独立准备姿势。
- `requestAnimationFrame` 仅插值位移、旋转、受力缩放和呼吸，不生成双轮廓。
- 每帧停留时间由 `frameDurationsMs` 决定，动作重复由 `repeatCount` 决定。

## 踩奶

`renderer/motionProfiles.js` 根据左右爪相位叠加：

- 下压：`scale(1.04, 0.96)`；
- 抬爪：`scale(0.98, 1.02)`；
- 身体：1–3px 正弦沉浮；
- 肩线：左右不超过 `±1.35deg` 的倾斜。

PNG 本身不进行透明混合，变形只在 Canvas 合成阶段作用于当前单帧。

## 打滚

- 快速翻滚帧约为 12–15fps；
- 露肚帧相对标准翻滚帧保持 2.75–3 倍时长；
- 恢复末段通过三个 transform keyframe 完成 overshoot、反向回弹和稳定。

## FSM

1. `idle`：呼吸和随机微动作；
2. 30 秒无操作：随机抖耳、洗脸或伸展；
3. 3 分钟无操作：进入闭眼低频呼吸；
4. 睡眠中触摸：先播放 `wake`，然后进入准备帧和目标交互动作。

`roll` 与 `knead` 均通过 120ms、两帧的独立准备动作进入，不直接硬切，也不叠加完整猫图。

## 验证

```powershell
npm test
npm run validate:renderer
.\launch-miaomiao-desktop.ps1 -CheckOnly
.\scripts\test_desktop_lifecycle.ps1
```

运行时规则报告位于 `previews/actions-v4/runtime-validation.json`。Electron 冒烟截图位于同一目录。

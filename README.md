# 妙妙：Windows 透明桌宠

妙妙是基于项目内真实照片和动作视频制作的半写实金渐层桌宠。当前项目只采用一套主要运行方案：`behavior.json + actions/` 驱动 Windows 透明桌宠窗口，并让妙妙跟随原生 Codex Windows 窗口。

![妙妙动作总览](previews/actions-v3/contact-sheet-white.jpg)

## 推荐启动方式

双击：

```text
launch-miaomiao-with-codex.cmd
```

启动器会：

1. 检查原生 Codex Windows 应用是否已运行；
2. 必要时启动 Codex，并等待主窗口出现；
3. 启动唯一一个妙妙透明窗口；
4. 将妙妙放在 Codex 右下角附近；
5. 在 Codex 移动或缩放时自动跟随；
6. 在 Codex 最小化时隐藏、恢复时显示、关闭时退出。

启动流程不设置 `WSL_DISTRO_NAME`、`WSLENV` 或任何 WSL 兼容变量，也不需要运行 `install.ps1`。

## 交互

- 鼠标单击：立即随机播放打滚或踩奶，各 50%；
- 鼠标停留约 500ms：随机播放打滚或踩奶；
- 播放特殊动作期间忽略重复触发，冷却 2000ms；
- 主要水平拖动：按方向播放左跑或右跑；
- 主要垂直拖动：只移动窗口，不播放跑动；
- 右键：关闭妙妙；
- 全程静音。

## 单独启动妙妙

调试动画而不跟随 Codex：

```text
launch-miaomiao-desktop.cmd
```

仅检查配置、动作文件和生命周期参数：

```powershell
.\launch-miaomiao-with-codex.ps1 -CheckOnly
.\launch-miaomiao-desktop.ps1 -CheckOnly
```

## 配置

运行时设置集中在 [`miaomiao.config.json`](miaomiao.config.json)：

- `globalDurationScale`：`1.0` 为默认；大于 `1.0` 更慢，小于 `1.0` 更快；
- `windowScale`：桌宠窗口缩放；
- `idlePauseRangeMs`：普通待机的安静停留区间；
- `hoverDwellMs`：悬停触发时间；
- `triggerCooldownMs`：抚摸触发冷却；
- `drag`：水平拖动阈值和水平/垂直优势比；
- `codexWindow`：相对 Codex 的位置、边缘留白、跟随频率和启动等待时间。

动作逐帧时长、重复次数、随机动作池和权重集中在
[`pet/miaomiao/behavior.json`](pet/miaomiao/behavior.json)。

## 当前动作

| 动作 | 帧数 | 默认时长 | 触发 |
| --- | ---: | ---: | --- |
| 安静待机 | 1 | 3–6 秒停留 | 默认 |
| 眨眼 | 3 | 0.62 秒 | 随机微动作 |
| 侧看 | 3 | 1.50 秒 | 随机微动作 |
| 耳朵微动 | 3 | 0.72 秒 | 随机微动作 |
| 尾巴微摆 | 4 | 1.50 秒 | 随机微动作 |
| 向左 / 向右跑 | 各 8 | 每周期 0.84 秒 | 明显水平拖动 |
| 撒娇打滚 | 18 | 5.20 秒 | 单击 / hover，50% |
| 踩奶 | 12 + 4 帧回待机 | 单周期 1.88 秒 × 3 + 0.60 秒恢复，共 6.24 秒 | 单击 / hover，50% |
| 洗脸 | 12 + 2 帧回待机 | 5.00 秒 | 每 30–60 秒检查，30% 权重 |

洗脸的理论平均触发间隔约 2.5 分钟。普通待机微动作的平均间隔约 5.6 秒（平均 4.5 秒安静停留，加一次约 1.1 秒微动作）。

## 动画来源与验证

- 妙妙自己的 4 段视频始终是最高优先级动作参考；
- 网络真实猫咪视频只用于研究阶段、受力和停顿，不用于改变妙妙外观；
- 打滚、踩奶与洗脸使用独立姿势，不使用 crossfade、透明叠加或重影插帧；
- 动作研究见 [`docs/motion-references.md`](docs/motion-references.md)；
- 黑/白背景正常速度、0.5 倍速 GIF、带编号接触表和验证报告位于
  [`previews/actions-v3/`](previews/actions-v3/)。

## 旧版 Codex 原生宠物

旧 `pet.json + spritesheet.webp`、安装器和 WSL 兼容启动器保留在
`legacy/codex-native/`，仅用于历史复现，不再推荐，也不是当前运行依赖。

当前支持目标是原生 Windows Codex；macOS、Linux、WSL 和 Codex 原生宠物渲染器不在本方案的运行范围内。

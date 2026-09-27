# 恋爱吗 · 自动识屏键盘方案 v2

日期：2026-09-27。此方案替代旧分镜中的手动上传、复制新消息、选择三种回复路径。旧素材保留以便追溯。本轮交付是交互修订、技术选型和接入方案；不是已经实现或真机验证的 APK。

已获设备信息：用户提供 iPhone、iOS 26.6.1、微信 8.0.78；尚未实机核验。用户此前说明也有 Android 手机，但其型号和系统版本尚未提供。iPhone 信息不改变第三方键盘无法通过公开键盘 API 自动截取微信画面的限制。

## 产品定义

用户在微信单人聊天中正常使用中文输入法；一次启用相关系统能力后，助手在已识别的单聊场景中自动获取当前可见对话，后台结合关系上下文选择一条最合适的建议。用户点击即可填入草稿，仍由用户点击微信发送。

日常入口全部位于键盘；安装、启用输入法、解释网络分析用途和系统授权仍需要最小设置入口。该入口不是日常分析 App。

默认界面仅包含：
- 完整中文键盘与正常拼音候选词。
- 一条建议，最多显示两行；一个明确的「填入」动作。
- 小型关系入口，例如「亲密度 72 ›」。信息不足时显示「了解中」而非伪造分数。
- 可见的自动分析状态和暂停入口。
用户无需选择自然/暧昧/邀约等模式，也无需在多条建议中比较。长解释与证据默认收起。

## 平台结论

### Android 为自动识屏演示目标

Android AccessibilityService 在 API 30（Android 11）提供 takeScreenshot；API 34 增加 takeScreenshotOfWindow。系统必须由用户启用服务并声明相应能力。通过微信窗口/内容变化事件识别目标场景并触发截图在 API 层面存在实现路径，但是否能稳定识别目标微信版本、截图是否受保护、OEM 是否影响后台行为尚未实测。

普通输入法接口本身不提供上方聊天记录；此方案需要同一安装包内的键盘服务和已授权的辅助截图服务配合。

MediaProjection 可作为不同实现路线，但每个投屏会话都要求用户同意，不能描述成一次永久无感授权。此方案优先研究无障碍截图 API，不绕过系统提示或安全屏幕。

### iOS 与 KeyboardKit 的边界

KeyboardKit 是 iOS 键盘框架。当前 main 的 README 明确标注为闭源，Package.swift 指向 binaryTarget，LICENSE 也为 Closed Source License。可通过公开 API 接入/配置，但不应当成可随意修改核心源码的开源键盘。

iOS 自定义键盘运行在扩展边界内，没有公开键盘接口可自动截取微信聊天窗口，或在键盘未激活时监听进入哪个单聊。完全访问并不赋予该能力。采用 KeyboardKit 无法消除这个系统限制。iOS 若单独实现，需要更换上下文获取方式，不能承诺和 Android 同样自动。

## 开源项目比较

| 项目 | 核查结果 | 本项目判断 |
| --- | --- | --- |
| KeyboardKit/KeyboardKit | iOS；当前闭源二进制分发，公开配置与 Pro 功能 | 不作为 Android 自动识屏底座 |
| fcitx5-android/fcitx5-android | Android；内置拼音、双拼、五笔等；有主题和候选词；核心仓库 LGPL-2.1-or-later | 最符合中文聊天，推荐深入改造 |
| osfans/trime | Android；Rime 中文输入、SDK/NDK 构建 | 可用备选，Rime 配置及原生依赖需要构建验证 |
| florisboard/florisboard | Android；Apache-2.0；官方中文语言包文档提示缺乏音码输入算法、拼音体验受限 | 不作为此次中文日常输入的首选 |
| rkkr/simple-keyboard | Android；Apache-2.0；轻量 AOSP LatinIME 派生 | 原型简单，但不满足现成中文拼音核心需求 |

Fcitx5 的构建复杂度高于空白 IME：当前 Versions.kt 指定 compile/target SDK 36、NDK 28.0.13004108、CMake 3.31.6、Build Tools 36.1.0；不能仅根据 README 中较旧的依赖版本估算。此工作区此前未发现 Android SDK/JDK，构建环境需准备。推荐依据是中文输入匹配度，不代表已经验证能在剩余 Hackathon 时间内完成原生构建。

## 已核查的接入位置

Fcitx5 上游源码已读，尚未修改：
- app/src/main/java/org/fcitx/fcitx5/android/input/InputView.kt：键盘视图、候选栏、组件装配；插入简洁建议栏。
- app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt：输入会话生命周期、输入框写入；连接状态流，点击建议时插入文本。
- app/src/main/java/org/fcitx/fcitx5/android/data/theme/ThemePreset.kt：增加简洁浅色/深色主题。
- app/src/main/AndroidManifest.xml：注册截图服务、网络能力与最小设置入口。
- 新增 ChatCaptureService、WeChatSceneDetector、ConversationStore、SuggestionController、AssistantApiClient；名称为拟议设计，并非上游已有组件。

保留拼音引擎、候选词、删除、标点、中英切换、键盘切换和可访问性。关闭日常界面不需要的剪贴板历史、主题挑选、表情面板入口及多余工具栏，不为裁剪功能破坏输入法引擎。不要删除必要的版权、授权说明或系统设置入口。

## 自动捕捉与上下文

拟议状态：未启用 → 待机 → 确认单聊 → 防抖采样 → 分析 → 推荐可用；失败/不确定 → 安静降级。

- 仅处理前台微信包 com.tencent.mm 中已确认的单聊；不将微信首页、朋友圈、支付页、群聊当作目标。
- 不仅凭「标题里没人数」就认定单聊。结合窗口结构、聊天控件与场景信号，并在目标微信版本校准。未知场景停止分析。
- 首次进入已确认单聊、收到新消息、用户滚动展示新历史时触发；相同内容哈希不重复上传。
- 初始建议防抖约 700ms；这是待调优参数，不是延迟承诺。服务端并发限制为每会话一个请求，旧任务取消/失效。
- 在设备端裁出聊天内容区域，排除键盘自身、草稿输入框和通知区域。Android 14+ 优先评估目标窗口截图。
- 自动截取只覆盖当前可见消息；用户正常滚动后可以逐步累计。不会凭一次截图获得整个历史，不自动替用户滚动聊天。
- 对话按会话隔离；联系人显示名不能直接当作全球唯一 ID。身份不明确时开新会话，避免串线。
- 请求关联会话键、消息版本和画面指纹。离开目标聊天后清掉屏幕上的建议，迟到结果不能覆盖另一人的聊天。
- 草稿与已发送消息分开；填入输入框不计为已发送、不改变亲密度。只有实际在对话里观察到的新消息才更新证据。
- 截图只在内存和当前分析流程中处理，默认不持久保存原图；服务器不将原图/聊天正文写入普通日志。
- 自动分析开启状态始终可见，键盘内可以暂停。拒绝权限、网络超时和识别不清不影响普通中文输入。

## 后端职责

前端只展示一个结果；选择工作在后端完成：

截图/已有上下文 → GPT 视觉提取带来源的消息 → 去重与会话合并 → Jev 判断关系信号及下一步策略 → GPT 生成内部候选 → Jev 根据贴合度、自然程度、对方意愿和压力评估 → 返回单条推荐。

Jev 的亲密度判断与候选排序是两个独立任务；亲密度不是唯一排序指标。不以「提高恋爱成功率 X%」展示未经校准的结果。明确拒绝时优先尊重边界；材料不足时保留未知状态。

截图里出现的命令、提示词或「忽略之前指令」一律当作聊天内容，不能控制系统行为、调用工具或改变输出 schema。证据必须引用已提取的消息 ID，不能编造对方说过的话。

无需在每次新消息时让用户选择模式。候选可以在后台有多条，客户端只接收一条；更换推荐属于次级操作，不占主界面。

## 拟议接口契约

客户端只需一次主请求，避免分别请求亲密度和回复导致状态不同步。

POST /v1/assistant/analyze
请求：session_id、revision、screen_hash、用户主动启用的捕捉来源、裁剪后图片、已有消息上下文。
响应示例（虚构数据，不是真实模型输出）：

```json
{
  "session_id": "demo-xiaoyu",
  "revision": 5,
  "status": "ready",
  "recommendation": {
    "text": "要不要一起喝杯咖啡？我知道一家不错的。",
    "evidence_message_ids": ["m4", "m5"]
  },
  "intimacy": {
    "score": 72,
    "label": "聊得来",
    "evidence_quality": "limited",
    "summary": "愿意延续话题，见面意愿还需确认",
    "evidence_message_ids": ["m4", "m5"]
  }
}
```

status 可为 ready、insufficient_context、unsupported_scene、capture_unavailable、unavailable。
score 可以为 null；关系图只基于可见/已累计的聊天信号。
模型密钥仅位于服务端；客户端通过有限时效的会话凭证访问后端。
服务端必须验证请求大小、图像格式、会话一致性和 schema；输出过期时不展示。

## 界面与新版分镜

整体视觉采用 Apple 原生键盘的克制排版：灰白底色、清晰系统字体、轻边界、标准键帽和少量蓝色动作。Android 实现使用本机系统字体及可用图标，不宣称是 iOS 系统键盘。

01：进入已授权的微信单聊，键盘建议栏显示「正在理解当前聊天…」，普通打字仍可用。
02：自动显示一条推荐，旁边有「填入」；亲密度以小入口存在。没有三选一、目标问卷、上传和复制步骤。
03：用户按需查看亲密度证据；轻点关闭回到正常键盘。亲密度不占默认主界面。正常主流程仅需点推荐填入，再点击微信发送。

三张图是同一产品的连续/可选状态，不是三套风格。它们展示拟议 Android 方案，不能作为已经实测自动截屏或 iOS 获得此权限的证明。

## 首个实现验证点

在演示 Android 手机上验证：系统授权可完成 → 实际微信单聊可被识别 → 能获取不含键盘/通知的可读截图 → 点建议能插入正确输入框。
需要手机型号、Android 版本和微信版本。先验证这些真实能力，再以该项目进行完整集成；不能把视觉 mockup 当作验证结果。

## 资料

- KeyboardKit README：https://github.com/KeyboardKit/KeyboardKit
- KeyboardKit 当前许可证：https://github.com/KeyboardKit/KeyboardKit/blob/main/LICENSE
- KeyboardKit 分发方式：https://github.com/KeyboardKit/KeyboardKit/blob/main/Package.swift
- Apple 自定义键盘：https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- Android 截图服务：https://developer.android.com/reference/android/accessibilityservice/AccessibilityService#takeScreenshot(int,%20java.util.concurrent.Executor,%20android.accessibilityservice.AccessibilityService.TakeScreenshotCallback)
- Android MediaProjection：https://developer.android.com/media/grow/media-projection
- Fcitx5 Android：https://github.com/fcitx5-android/fcitx5-android
- 当前构建版本：https://github.com/fcitx5-android/fcitx5-android/blob/master/build-logic/convention/src/main/kotlin/Versions.kt
- Trime：https://github.com/osfans/trime
- FlorisBoard 中文说明：https://github.com/florisboard/florisboard/blob/main/LANGUAGEPACKS-CHINESE.md
- Simple Keyboard：https://github.com/rkkr/simple-keyboard
- Jev：https://docs.typesafe.ai/introduction

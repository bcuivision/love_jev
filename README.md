# 恋爱吧 · iOS 微信聊天键盘

Xcode 原生工程与 TypeScript 后端。用户启动一次系统屏幕广播，回到微信并展开恋爱吧键盘，点击星光（Sparkle）按钮；识别本次可见文字后，由 Jev 判断关系阶段和互动信号，再规划下一步行动及期望结果，GPT 据此生成候选，最后由 Jev 核对并选出一句。点「填入」只写入草稿，发送由用户完成。推荐旁的问号默认收起，点击后才展示推荐原因。

**打开 `ios/恋爱吧.xcodeproj`，选择「恋爱吧」scheme。** 已通过模拟器编译，并使用团队签名安装到 iPhone。三个 Target 的 App Group 签名与描述文件已核验，手机上的共享容器已创建。本地后端的 Jev → GPT → Jev 真实调用已通过；手机连接及微信广播全链路仍需验收。

## 工程结构

| 位置 / Target | 用途 |
| --- | --- |
| `LianAiBa` / `ios/App` | 最小设置 App、系统广播选择器、分镜交互预览、真实键盘测试输入框 |
| `LianAiBaKeyboard` / `ios/KeyboardExtension` | 系统 Custom Keyboard Extension，联网分析和草稿插入 |
| `LianAiBaBroadcast` / `ios/BroadcastExtension` | ReplayKit 视频采样、本地 Vision OCR、单聊布局过滤 |
| `ios/Shared` | 原生键盘 UI、基础拼音、会话隔离、App Group 通信、HTTP 客户端 |
| `server` | Jev → GPT → Jev 服务，鉴权、超时、数据校验及离线测试 |
| `design/keyboard-v2` | 已确认的分镜一、二、三参考图 |
| `design/ios-validation` | 实际模拟器截图 |

使用 UIKit / SwiftUI 与系统框架，无需下载 KeyboardKit 或购买其附加服务。推荐使用 `ios/恋爱吧.xcodeproj`；原来的 `ios/LianAiKeyboard.xcodeproj` / `LianAi` scheme 也已同步为兼容入口，包含相同的三个 Target、共享文件和 App Group 配置。

## 现在就看界面

1. 在 Xcode 打开新工程，选择 iPhone 模拟器运行。
2. 点「预览键盘交互」，点星光体验「识别聊天 → 一句推荐 + 填入」。右上角菜单可切换升温、降温、平稳三种发送前预估示例。
3. 填入后可编辑。预览中的发送只增加本地虚构气泡。

预览明确标注示例数据。真正的键盘扩展不会在未连接服务时显示这条示例推荐。

## 关系判断与推荐原因

`ANALYSIS_MODE=jev` 使用四次串行模型调用：Jev 关系阶段/当前信号 → Jev 行动与期望结果 → GPT 三条不同说法 → Jev 按同一计划筛选。阶段不是由亲密度分数换算；信息不足时不判断关系阶段，也不评分。明确拒绝优先于积极信号，只有双方明确表达见面意愿时才开放邀请选项。候选都不符合计划时返回错误，不强行选一句。

接口新增 `reason`：`relationshipStage`、`observation`、`action`、`expectedResult`。这些是模型选择结果对应的简短说明，属于决策摘要，不是模型内部推理文本。说明使用“希望”描述沟通目标，不保证对方的感受或反应。生成和筛选使用同一份计划，避免先写回复、再补理由。

键盘问号按钮有 44pt 点击区域；点开后，在原键盘按键区域内显示可滚动的“当前判断 / 建议行动 / 期望效果”，推荐与填入按钮继续可用。关闭后恢复原键盘；填入、开始新分析或草稿状态变化会关闭旧说明。客户端兼容没有 `reason` 的旧响应，只显示已有说明，不编造原因。显式 `reply_only` 与服务 fixture 模式返回 `reason: null`。

2026-09-27 验证：TypeScript 类型检查、47 项后端测试、36 项 Swift 测试和 iOS 模拟器编译通过。使用虚构对话调用真实 Jev/GPT，双向见面意愿与明确拒绝两种情形均返回匹配的行动、期望结果和回复，分别约 8.8s / 10.0s。请求总时限为服务端 32s / iOS 客户端 35s。模拟器已核对展开、关闭和填入交互；此次修改尚未在真机微信中验收。

截图和交互记录见 `design/recommendation-reason/README.md`。运行 `cd server && npm run check:recommendation` 可用两段固定虚构聊天验证真实链路（会调用配置的模型服务）。

### 回复人设：松弛、机灵、有温度、懂分寸

在既定“关系阶段 → 行动 → 期望结果”之后，增加表达风格层。GPT 生成和 Jev 最终筛选共用 `server/src/reply-persona.ts` 中的人设，保持四次模型调用。人设只调整说法，不影响关系评分，不替用户虚构经历或亲密程度。

- 真人感：接住聊天中的具体细节，参考用户已有的用词，使用自然口语，减少客服套话、说教和模板安慰。
- 高情商：轻松时可善意调侃；低落、误解或明确拒绝时切换为认真温和的口吻，先回应感受和边界。关系不明时不装熟。
- 简洁：目标通常为 8–22 字，硬上限保持 32 字；最多一个问题，可以只接一句话，不再要求每次都追问。
- 幽默：从当前话题里找一点小反差，不硬凑段子、土味情话或堆叠语气词。邀请通过轻松的问法留出选择，避免每次都追加“不方便也没关系”。

最终筛选同时考虑行动是否匹配、说话是否自然、情绪是否合适。合适的轻幽默优先于模板话；安慰和拒绝场景则优先真诚直白。显式 `reply_only` 模式也使用同一人设，由生成模型根据可见聊天调整口吻。

`cd server && npm run check:persona` 使用五段虚构聊天检查邀请、拒绝、日常调侃、安慰和误解场景，输出仅包含虚构样例结果。自动化测试验证口吻选择及其在生成、筛选之间的一致性；真实表达质量需结合样例人工判断。

本次人设修改通过 TypeScript 类型检查与 51 项后端测试，本地后端已重新加载。五场景真实联调受间歇性的 `ECONNRESET` / 连接超时影响，只返回部分样例，尚未完成全部风格验收。联调中发现的“表达被打断后的不满被误判为停止交流”已通过信号判定提示修正，修正后的真实模型表现仍需网络恢复后复验。

## 发送前亲密度预估

亲密度数值和 0–100 进度条固定显示在键盘顶部，不依赖推荐卡片、草稿或拼音候选的状态。Jev 完成本次聊天判断后就先返回评分，再继续生成推荐；同一聊天重新分析、输入、清空或推荐失败时保留已有分数，必要时标记「上次评分」。首次未获得评分或新聊天证据不足时显示「待评估」，不填入虚构数字。切换输入文档或撤销授权会清除上一会话评分。

推荐出现后，自动用 Jev 预估这条推荐的影响，单独显示「预计 +8 分／−3 分／0 分」，无需先填入。编辑草稿时切换为草稿影响，预估期间不沿用推荐的旧增减值。当前亲密度不会因为推荐、填入或预测而自动增减；只有新的聊天评分会更新它。发送后预计值基于顶部当前评分和影响增量计算，并限制在 0–100。

推荐接口可通过 `Accept: application/x-ndjson` 分阶段接收 `intimacy`、`suggestion` 或终止 `error` 事件；原 JSON 客户端仍然兼容。新客户端也能读取旧后端的普通 JSON 响应，但旧后端无法提前返回评分。推荐影响复用草稿评分接口，额外调用一次 Jev。

开启聊天分析和系统屏幕广播后，在恋爱吧键盘点星光识别本次聊天。输入、粘贴或编辑未发送草稿，停笔约 0.9 秒后自动调用一次 Jev，显示「预计 +8 分」等增减值、当前值到预计值以及简短依据。

- 加分：火焰图标与橙红渐变；减分：雪花图标与冰蓝渐变；0 分：中性色。绝对变化越大，颜色越浓。色条使用键盘顶部原有的辅助区域。
- 拼音尚未选词时先等待。修改草稿立即撤下旧分数并取消请求；相同内容不重复调用，请求间隔至少 2.5 秒。
- 清空/发送、键盘收起、切换输入文档、关闭授权或广播失效都会清除预估。发送后再次输入，需要点星光更新聊天；本次上下文最长保留 2 分钟，对方新消息出现时也应点星光刷新。不会自动识别新的聊天帧。
- 分数是 JEV 按互动量表产生的游戏化预估，不是对方真实反应或关系变化。当前值为 0–100 分；单句影响量表的五个锚点为 −12、−6、0、+6、+12，连续评分插值取整后按 0–100 边界截取，增减值始终等于预计值减当前值。尊重拒绝和边界，不把单方示好当成双向好感。
- 草稿来自系统输入代理可读取的光标前文、选区和后文，长文本可能不完整。不会为读取全文移动光标。请求上限 2,000 个 UTF-16 单元；信息不足、未配置 Jev、网络错误或示例服务均不显示数字。

新接口为 `POST /v1/assistant/draft-impact`，复用原服务鉴权、限流与无缓存策略；请求带 `sessionID`、上下文 `revision` 和唯一 `draftID`，迟到结果不能覆盖新草稿。草稿只在内存中处理，不写入 App Group 或服务日志。`reply_only` 模式不启用此接口。

`npm run check:draft`（在 `server` 目录）会用两份虚构草稿产生两次真实 Jev 请求，只输出分数与耗时。固定 UI 示例可以用 `--preview-warm`、`--preview-cold`、`--preview-neutral` 启动 App 查看；任意输入不会被预览模式伪评分。

## 配置后端

需要 Node.js 22.18+，本机依赖已经安装；其他机器先执行：

```sh
cd server
npm ci
cp -n .env.example .env
```

本机 `server/.env` 已创建，并生成了随机 `APP_ACCESS_TOKEN`。模型密钥只填到这个文件，不写进 iOS 工程。`DEMO_MODE=0` 调用真实模型。`ANALYSIS_MODE=jev` 启用 Jev → GPT → Jev；`reply_only` 只生成回复，亲密度为 null。必需密钥缺失时返回 503，不静默伪造结果。

支持 OpenAI 兼容服务。`OPENAI_BASE_URL` 填含版本前缀的 HTTPS 地址，`OPENAI_API` 选择 `responses` 或 `chat_completions`。例如使用当前团队提供的服务：

```dotenv
OPENAI_BASE_URL=https://api.0-0.pro/v1
OPENAI_API=chat_completions
OPENAI_MODEL=gpt-5.4-mini
OPENAI_REASONING_EFFORT=none
JEV_PROVIDER=shared
JEV_MODEL=jev-latest
ANALYSIS_MODE=jev
```

`JEV_PROVIDER=shared` 明确让 Jev 复用 `OPENAI_BASE_URL` 与 `OPENAI_API_KEY`。当前供应商列出了 `jev-latest`，其 `/v1/systemone` 已返回 `jev-1.13.0`；GPT 仍走 `/v1/chat/completions`。两种协议使用同一服务和同一密钥，不需要另填 `TYPESAFE_API_KEY`。后端拒绝把重复的 `/v1` 加入地址，也拒绝跟随供应商重定向。

如使用官方 TypeSafe，改为 `JEV_PROVIDER=typesafe`，单独配置 `TYPESAFE_API_KEY` 与可选的 `TYPESAFE_BASE_URL`。未选择共享模式时不会把回复服务密钥自动发给 TypeSafe。修改 `.env` 后重启服务。

运行 `npm run check:openai` 可用一段虚构聊天单独验证回复接口；此命令会产生一次真实模型请求，不调用 Jev，也不读取手机聊天。模型名是否可用以供应商实际响应为准。

```sh
npm start
```

默认监听 `http://127.0.0.1:8787`，`GET /health` 可查看是否已配置。真实模型默认 `gpt-4.1-mini` 和 `jev-latest`，可在 `.env` 修改。服务不保存聊天记录，不记录请求体；OpenAI 请求设为 `store: false`，供应商自身的数据政策仍适用。

正式部署使用手机可访问的 **HTTPS 地址**。本地 Debug 演示也支持同一 Wi-Fi 内的 `.local` 主机名或私有 IPv4 地址，通过 HTTP 连接 Mac。Release 构建仍拒绝远程 HTTP。不要把手机上的 `localhost` 当成 Mac。

本地运行（在项目根目录）：

```sh
python3 scripts/local_backend.py start
python3 scripts/local_backend.py status
# 更换配置后先 stop 再 start；演示结束后也可以 stop。
python3 scripts/local_backend.py stop
```

本机已设 `HOST=0.0.0.0`，服务只在 Mac 运行，没有部署公共服务。日志位于忽略的 `.build/local-server/`，不记录聊天或密钥。当前网络使用 Mac 的 `127.0.0.1:7897` 代理；后端通过 `.env` 中的 `HTTPS_PROXY` / `NO_PROXY` 使用它。更换网络或关闭代理后，需更新该配置并重启。

安装 Debug App 后，可以自动传入服务地址和访问口令：

```sh
xcrun devicectl list devices
python3 scripts/local_backend.py configure-iphone --device YOUR_DEVICE_ID
```

重新打开恋爱吧，配置会从 App 私有目录导入共享容器，随后删除临时文件。供应商密钥不会传到手机，现有分析授权开关不会被改变。手机与 Mac 保持同一 Wi-Fi，并在手机上允许「本地网络」。App 的「测试服务连接」使用虚构聊天验证真实模型请求。

`DEMO_MODE=1 npm start` 是明确的接口联调模式，不调用模型，返回 `isDemo: true`、无亲密度分数；键盘显示「示例推荐 · 未调用模型」。这不是实际 GPT / Jev 演示。

## 真机安装与启动

1. Xcode → Settings → Accounts 登录你们的付费开发团队。
2. 复制 `ios/Config/Local.xcconfig.example` 为同目录 `Local.xcconfig`，填写 Team ID 和属于团队的 Bundle ID / App Group ID。
3. 在三个 Target 的 Signing & Capabilities 中确认同一团队、启用同一个 App Group。三个 Bundle ID 分别为根 ID、根 ID + `.keyboard`、根 ID + `.broadcast`。不要只改一个 Target。
4. 连接 iPhone，启用开发者模式，选择「恋爱吧」scheme 后 Run。首次可能需要在手机信任开发者。
5. 设置 → 通用 → 键盘 → 键盘 → 添加「恋爱吧」，打开「允许完全访问」。
6. 打开恋爱吧 App，导入本地连接或填写 HTTPS 地址及 `APP_ACCESS_TOKEN`，点「测试服务连接」，开启「允许分析当前聊天文字」。现场演示建议填写测试联系人名称，降低其他页面误判的可能。
7. 点「开始屏幕广播」，在系统面板确认并等待倒计时；回到微信文字单聊，用地球键切换到恋爱吧。
8. 点击键盘左侧星光（Sparkle）按钮，依次识别当前聊天、分析评分并推荐下一句话。每次点击只执行一轮识别与推荐；有了本次上下文后，输入或填入草稿会在停笔时自动预估亲密度变化。点「填入」后仍需自己发送；再次点星光可更新上下文与建议。结束广播通过系统状态栏或控制中心操作。

完整准备和验收步骤见 `docs/demo-runbook.md`。

## 实现边界

- 完全访问用于网络与共享容器，不是截图权限。每段新广播会话仍需系统确认。
- OCR 只处理每次点击后当前屏幕可见聊天，不读取微信数据库或屏幕外历史，不累计点击之间的聊天。连续两帧标题和文字一致后才提交本次识别结果。
- 会话和点击请求隔离；切换输入文档、收起键盘、开始新一轮分析或修改设置会撤下旧建议，迟到结果不会覆盖新请求。结果是本次点击的快照，不随新消息自动更新；重新点击星光时才识别新内容。识别最多等待 10 秒，超时后需要手动重试。
- 单聊识别依赖布局和气泡颜色，是启发式判断。群人数标题、陌生页面及横屏会被过滤；还需在指定微信版本、深色模式和真机内存限制下校准，不能保证识别所有微信页面。
- 亲密度是 Jev 按互动证据量表转换的 0–100 分，不是恋爱概率；上下文不足时不评分。
- 中文输入目前是基础离线拼音词库。完整中文、语音和表情可用地球键切回系统键盘。
- 系统可能在安全输入框、特定宿主或资源限制下切回系统键盘。

## 已执行验证

- 三个 Target：模拟器编译成功，iPhone 架构无签名编译成功。
- 系统设置添加后，实际键盘扩展已成功加载到测试输入框。
- Swift 核心 32 项测试：手动捕获门控、一次点击一次推荐、输入与设置，以及草稿防抖、未提交拼音、撤销授权、清空/隐藏、迟到响应和分数契约。
- TypeScript 类型检查与后端 32 项测试：两种回复协议、Jev 配置与身份校验、草稿评分/边界/不足证据、鉴权、错误数据、超时与明确示例标识；模型响应使用模拟数据。
- 发送前预估新增验证：模拟器编译成功；虚构聊天真实 Jev 返回邀约 +8、冷淡回应 −9（`isDemo=false`）。截图位于 `design/ios-validation/draft-impact/`。手机微信输入代理与广播的完整联动仍需真机验收。
- 本机使用虚构聊天发起真实 HTTP 请求，完整 Jev → GPT → Jev 流程返回 HTTP 200、推荐与互动评分，`isDemo=false`，单次耗时约 9.5 秒；这不代表手机连接或微信广播全链路已验证。
- 实际 Swift HTTP 客户端访问本机 Node 服务的联调通过（fixture 模式，没有调用模型）。
- 实际广播 OCR 类在 macOS 测试画面上提取 5 条聊天，正确识别双方气泡；这是图像测试，不代表真机广播已验证。

```sh
swift test --scratch-path .build/core-tests
cd server
npm run typecheck
npm test
```

编译命令：

```sh
xcodebuild -project 'ios/恋爱吧.xcodeproj' -scheme '恋爱吧' \
  -sdk iphonesimulator -configuration Debug -derivedDataPath .build/lianaiba \
  CODE_SIGNING_ALLOWED=NO build
```

`Package.swift` 仅用于共享逻辑的 macOS 测试。`scripts/generate_xcode_project.py` 用于初始生成工程；在 Xcode 修改签名或工程设置之后不要重新运行，以免覆盖修改。详细验证记录见 `design-qa.md`。

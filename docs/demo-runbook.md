# 恋爱吧现场演示手册

## 交付物与未接通项

代码已包含主 App、输入法扩展、屏幕广播扩展、OCR 与 GPT / Jev 后端。2026-09-27 已完成团队签名及 iPhone 安装，核验三个 Target 的 App Group 授权。Mac 本地后端正在运行。Jev 已改为复用团队提供的兼容服务地址及密钥，`/v1/systemone` 实测返回 `jev-1.13.0`，当前使用完整 `jev` 模式。本机虚构聊天的完整 Jev → GPT → Jev 请求实测 HTTP 200，约 9.5 秒返回真实推荐与互动评分。手机连接及微信广播全链路仍需继续联调。

## 团队配置

- `ios/Config/Local.xcconfig`：填写 Team ID 与 Bundle ID / App Group。示例文件同目录。该本地文件已加入忽略列表。
- `server/.env`：模型服务密钥、服务地址和 API 协议、Jev 提供商模式、可修改的模型名、随机服务口令。当前共享模式只需一份模型密钥。该文件不会提交。
- `server/.env.example`：可安全共享的空白模板。
- 手机 App：只使用恋爱吧服务地址和服务口令，不填写模型密钥。本地 Debug 版可自动导入局域网连接。

三个 Target 必须拥有同一个已注册的 App Group：App 负责写设置，键盘写当前会话状态，广播写识别结果。若设置 App 出现「共享数据不可用」，先检查签名与 entitlement，不要继续模型排查。无签名模拟器构建会出现这个提示，是当前测试环境的已知限制。

## 后端部署

本地开发：Node 22.18+，进入 `server` 运行 `npm ci`、填写 `.env`、运行 `npm start`。返回 `GET /health` 的 `status: ready, mode: live` 只表示密钥已经配置，不证明密钥有效或模型有额度。

本次本地配置：`OPENAI_BASE_URL=https://api.0-0.pro/v1`、`OPENAI_API=chat_completions`、`OPENAI_MODEL=gpt-5.4-mini`、`OPENAI_REASONING_EFFORT=none`、`JEV_PROVIDER=shared`、`JEV_MODEL=jev-latest`、`ANALYSIS_MODE=jev`。Jev 复用 `OPENAI_API_KEY`，使用同一地址下的 `/v1/systemone` 决策接口，不需要额外 TypeSafe 密钥。供应商没有列出旧默认回复模型 `gpt-4.1-mini`。运行 `npm run check:openai` 只验证 GPT 回复接口，不验证完整 Jev 流程。

从项目根目录运行 `python3 scripts/local_backend.py start` / `status` / `stop` 管理本地进程。手机和 Mac 使用同一 Wi-Fi，在手机允许「本地网络」，保持 Mac 唤醒与网络代理运行。安装 Debug App 后，使用 `configure-iphone --device <设备 ID>` 自动传入地址和服务口令，再重新打开 App。点「测试服务连接」应出现「真实推荐测试通过」，然后开启聊天分析和屏幕广播。

已有托管平台可直接以 `server` 为根目录，用 `npm ci --omit=dev` 构建、`npm start` 启动。配置 `HOST=0.0.0.0`、平台要求的 `PORT`、模型服务配置和 `APP_ACCESS_TOKEN`，平台需提供 HTTPS。Docker 部署使用同目录 Dockerfile。此项目未替你们创建云账号、付费资源或公开服务。

`APP_ACCESS_TOKEN` 是团队演示共享口令，不是完整的多用户账户系统；不要放进截图或公开仓库。接口最多同时处理 4 个请求、每分钟 30 个，22 秒超时。请求或供应商错误不会返回聊天正文或密钥。

## 推荐的 90 秒演示流程

1. 提前启用键盘、完全访问和分析服务，在两台设备的测试账号准备一个双方知情的文字单聊。
2. 在恋爱吧点击系统广播控件，确认开始。返回微信并展开恋爱吧键盘。
3. 对方发送一句自然延续聊天的信息。点击键盘左侧星光（Sparkle）按钮，依次显示「正在识别当前聊天」「正在分析评分和推荐」，完成后展示一句推荐。未点击时不识别、不分析。
4. 上下文足够时点亲密度查看依据；不足时显示「推荐说明」且不打分。再点「填入」，文字进入微信草稿，可修改，由演示者按微信发送。
5. 保持聊天不动，展示推荐不会反复刷新；有新消息后，再次点星光更新。结束时停止系统广播并收起键盘。

不要在介绍中声称「能读取完整聊天记录」「完全访问可截图」「亲密度就是恋爱成功率」或「无需用户启动广播」。

## 真机验收顺序

1. 先用设置页测试输入框验证真实键盘可加载、拼音候选可提交、删除与地球键可用。
2. 模型尚未准备时可临时设 `DEMO_MODE=1` 验证网络和推荐展示，界面会明确标示示例；正式演示恢复 `DEMO_MODE=0` 并重启后端。
3. 广播系统面板应出现恋爱吧，进入微信后有系统录屏状态。若控件不弹面板，不要用模拟器表现推断真机能力。
4. 点击星光后，用短文字单聊检查 OCR 对象名、双方归属与键盘区域排除；新消息必须再次点击才更新。建议先限制为一个测试联系人，使用竖屏、默认文字大小、浅色模式。
5. 切换输入文档或收起键盘，确认旧建议撤下；迟到响应不应重新显示。进入群聊、联系人列表与其他 App 后点击星光，确认不支持画面不会得到新建议。手动模式不持续识别标题，宿主若复用同一个输入文档，页面变化可能只能在下次点击时发现。多个联系人同名和画面中通知覆盖需单独检查。
6. 识别过程中停止广播、收起键盘或断网时，应结束或超时当前请求，普通键盘仍可使用。已完成的建议是本次点击快照，停止广播不会自动重算；收起键盘会清除建议。
7. 连续运行几分钟，在 Xcode / 设备日志观察 Broadcast 扩展是否因资源限制退出，记录实际端到端延迟。Vision 内存占用及微信布局尚未真机测量。

## 常见问题

| 表现 | 检查 |
| --- | --- |
| 无法保存设置 / 共享数据不可用 | 三个 Target 的团队、App Group 与签名 entitlement |
| 请允许完全访问 | 系统键盘设置中开启，再收起重开键盘 |
| 请先启动系统屏幕广播 | 在手机启动新广播；系统结束或超时后重新启动 |
| 点星光，帮你接下一句 | 点击左侧星光开始一次分析；先确保广播已启动、当前单聊至少两条可识别文字 |
| 未识别到稳定的单聊内容 | 停止滚动，保持聊天画面稳定，检查联系人名称、竖屏和气泡布局，再点星光 |
| 分析服务 401 | 手机服务口令与服务端 APP_ACCESS_TOKEN 是否一致 |
| 503 | 服务端模型密钥是否齐全；配置后重启服务 |
| 502 / 504 | 模型凭证、配额、网络与超时；不要将提供商详细错误打印进包含聊天的日志 |
| 只有推荐说明、没有分数 | Jev 判断上下文证据不足；若手动选择 reply_only 模式，也不会评分 |
| 无法连接本地服务 | 手机与 Mac 同一 Wi-Fi、本地网络权限开启、Mac 服务与所需代理运行；访客 Wi-Fi 可能隔离设备 |
| 拼音不能输入某个词 | 当前是小型演示词库；切换系统键盘完成输入 |

## 研发复现

`npm test` 使用模拟模型响应，不产生外部 API 费用。

OCR 图像测试：

```sh
swiftc -module-cache-path .build/ocr-cache \
  ios/Shared/AssistantModels.swift ios/Shared/ChatScene.swift \
  ios/BroadcastExtension/FrameRecognizer.swift scripts/OCRCheck.swift -o .build/ocr-check
.build/ocr-check design/ios-validation/02-recommendation.png 0.60
```

客户端 / 服务端真实 HTTP 协议测试（需要本机服务以 fixture 模式运行）：

```sh
swiftc -module-cache-path .build/ocr-cache \
  ios/Shared/AssistantModels.swift scripts/ServiceCheck.swift -o .build/service-check
node scripts/check_service.mjs
```

脚本只从本地 `.env` 读取服务口令，不输出凭证。OCR 脚本仅使用项目内的虚构聊天截图；不要把真实用户聊天混入测试产物。

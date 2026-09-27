# iOS 手动分析：星光按钮与系统屏幕广播

核查日期：2026-09-27。用户提供 iOS 26.6.1 / 微信 8.0.78；这两项真机版本尚未现场核验。用户已批准系统广播路线。

## 平台条件

键盘的「允许完全访问」用于网络和共享容器，不提供读取微信画面的能力。ReplayKit 是独立的系统入口：用户开始广播后，Broadcast Upload Extension 可接收跨应用的屏幕帧；本项目在设备上提取文字，没有向直播平台公开播放。

每段新广播需要用户在系统面板确认。不能仅靠进入微信自动开始一段新广播，也不能隐藏系统录屏状态。开发团队、App Group 和真机行为仍需要验证。

## 已实现的流程

1. App 中配置分析服务、文字分析授权，并用系统设置启用键盘和完全访问。
2. `RPSystemBroadcastPickerView` 指向本项目 `.broadcast` 扩展，由系统确认和启动。
3. 键盘上的星光（Sparkle）按钮创建唯一捕获请求，10 秒内有效。`RPBroadcastSampleHandler` 只处理视频，最多每 0.6 秒检查一帧；只有键盘可见、心跳有效且存在未完成的点击请求时才运行 OCR。未点击时只维护轻量心跳，不识别画面。
4. 图像缩放至最多 720 像素宽、裁剪上方区域，再用 Vision 识别简体中文和英文；不保存截图、录像或音频。
5. 用标题位置、群人数过滤、可选联系人名和气泡颜色筛选场景。标题与消息内容连续两帧一致后才生成上下文；双方归属由气泡颜色推断。
6. App Group 传递本次点击的请求 ID 和 OCR 文字，不累计点击之间的历史。提交前再次检查键盘会话、请求 ID、有效期及设置；完成的请求不再执行 OCR。
7. 键盘仅接受当前点击对应的捕获结果，最多请求后端一次。后端按 Jev 评估 → GPT 三条短候选 → Jev 选一句返回。界面分别显示识别、分析状态，完成后呈现推荐和可查看依据的亲密度评分。处理中星光按钮禁用；失败后由用户点击重试。
8. 响应通过会话、当前点击 ID 与版本核对后才显示。建议保留至下次点击、键盘关闭、输入文档变化或设置变化；不会因捕获快照过期重新分析。填入只写草稿。

App Group 中保存设置、当前键盘状态和最近一次 OCR 上下文，不保存原始画面；文件不参与备份。空闲心跳和正常停止会用空上下文覆盖。已完成的捕获在键盘消费前保留，避免被心跳覆盖。系统强杀可能留下最后一次文字文件，但只有当前点击对应且 6 秒内新鲜的快照可用于发起分析。后端不持久化聊天。

## 不能据此声称的能力

- 单聊场景判断是启发式的，不能保证前台 App 一定是微信。SDK 的 `broadcastAnnotated(withApplicationInfo:)` 只承诺首个应用信息，未用于实时前台跟踪。
- 同名联系人、短暂动画、通知覆盖和深色主题可能影响判断。联系人限制能缩小范围，不能证明联系人真实身份。
- 暂不支持横屏识别。锁屏、受保护画面、扩展资源限制等需要实机验证。
- 亲密度按文本中的互动证据评分，不能确定是否能恋爱。
- 720 像素采样、限频与清理缓存用于降低消耗；尚未测得实际 Broadcast 扩展的峰值内存或端到端延迟。

## 当前验证状态

星光手动触发流程已通过核心回归测试、三个 Target 的模拟器编译及预览交互检查。静置不请求、重复点击不重入、超时不自动重试和跨会话迟到结果均由本地测试覆盖。预览使用示例数据，真机微信广播流程仍待验证。

三 Target 已编译，系统已实际加载键盘扩展，OCR 图像测试与 Swift → Node 示例 HTTP 联调通过。模拟器没有验证跨应用广播；未获得你们稍后配置的签名和模型凭证，故真实微信与 GPT / Jev 全链路未运行。

## 官方参考

- [Apple：Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Apple：RequestsOpenAccess](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/requestsopenaccess)
- [Apple WWDC18：Live Screen Broadcast with ReplayKit](https://devstreaming-cdn.apple.com/videos/wwdc/2018/601nz4m863hyf0/601/601_live_screen_broadcast_with_replaykit.pdf)
- [Apple：RPSystemBroadcastPickerView](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview)
- [Apple：RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler)
- [TypeSafe：JavaScript SDK](https://docs.typesafe.ai/sdk/javascript)
- [TypeSafe：SDK 类型定义与评分语义](https://github.com/typesafe-ai/typesafe-sdk-js/blob/main/src/types.ts)
- [OpenAI：Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

本机还核查了 iPhoneOS 26.5 SDK 的 `ReplayKit.framework/Headers/RPBroadcast.h`、`RPBroadcastExtension.h` 与 Xcode Broadcast Upload Extension 模板。

# iOS 实现验证记录

日期：2026-09-27。环境：Xcode 26.6、iOS SDK 26.5、iPhone 17 Pro 模拟器 iOS 26.5。

## 结论

代码和本地验证完成，真机全链路待配置与验收。用户已经接受系统屏幕广播，并明确选择稍后配置开发团队与模型密钥；当前不再等待产品方案确认。

## 界面与交互

参考 `design/keyboard-v2/01-auto-context.png` 与 `02-one-recommendation.png`，使用同一个原生组件实现分析态和单条推荐态。保留灰白键帽、蓝色填入、亲密度入口与暂停。系统状态栏、安全区域与地球键按 iOS 调整。

实际截图：

- `design/ios-validation/01-analyzing.png`
- `design/ios-validation/02-recommendation.png`
- `design/ios-validation/03-real-keyboard-extension.png`：系统添加后实际加载的扩展，未开启完全访问时显示真实提示。

已通过模拟器点击验证预览的填入、删除、暂停；填入保留原有草稿，发送是独立动作。预览明确写明示例数据。后端限制真实推荐在 32 字内以适配两行。

## 编译与测试

- App、Keyboard、Broadcast 三个 Target 模拟器构建成功。
- 三个 Target 的 iPhone arm64 无签名构建成功；不等于真机已安装。
- 系统键盘列表已出现恋爱吧，实际 Extension 加载成功。未开启完全访问、未配置 App Group，网络链路没有通过此模拟器扩展执行。
- Swift 11 项测试全部通过：输入、拼音、暂停、会话/版本隔离、迟到结果丢弃、重叠上下文合并、不连续滚动、场景过滤、共享设置存储等。
- TypeScript 类型检查通过，Node 9 项测试全部通过：模型响应协议、选句、证据不足不评分、错误不回退示例、鉴权、请求校验、超时。
- 真实 `AssistantClient` → HTTP → Node fixture 服务联调通过；请求 ID、版本、示例标识与空分数正确解码。未调用真实模型。
- 实际 `FrameRecognizer` 在 macOS 运行 Vision，提取参考模拟器截图中的 5 条聊天并正确归属双方。像素测试发现上下翻转错误并已修正。此结果仅证明该测试图像路径，不证明广播实际运行。

## 待真机验证

- 付费团队签名、三个 Target 的 App Group 权限和安装。
- 系统广播启动、跨 App 收帧、长时间运行内存与性能。
- 用户所报 iOS 26.6.1 / 微信 8.0.78 的界面、通知覆盖、输入框切换与同名联系人。
- 真实 GPT / Jev 凭证、可用模型、服务 HTTPS、实际延迟与输出质量。
- 深色、横屏和大字号；当前自动识屏仅支持竖屏，其他画面等待而不分析。
- 中文仅有基础离线拼音词库，没有完整中文 IME。

final result: partial

界面、代码与本地验证可交付。完整微信真机 Demo 仍依赖上述配置和设备联调，不能把示例截图或 fixture 返回值当成实测模型结果。

## 后续真机修复：App Group

- 用户在微信切换键盘后遇到「共享数据不可用」。检查发现 `Shared.entitlements` 的群组数组为空；用户构建的真机键盘签名和描述文件也均为空数组。
- 恢复 `$(APP_GROUP_IDENTIFIER)` entitlement，并为两份工程的三个 Target 标记 App Groups capability。保留用户已经选择的开发团队，并通过被忽略的 `Local.xcconfig` 让新工程沿用该团队。
- 使用自动签名更新描述文件，真机签名构建成功。App / Keyboard / Broadcast 的 Info.plist、代码签名及描述文件均包含 `group.com.jevdemo.lianaiba`。
- 修复包已覆盖安装到连接的 iPhone 17 Pro Max，系统版本核实为 iOS 26.6.1；设备端已能列出该群组容器，具有读写属性。
- 自动启动 App 被设备锁屏拦截，未查看用户微信界面。需用户解锁后打开 App，并在微信重新切换键盘确认提示消失；广播和模型推理仍未真机验收。

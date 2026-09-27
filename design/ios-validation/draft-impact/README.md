# 发送前亲密度预估验收

2026-09-27，iPhone 17 Pro / iOS 26.0 模拟器。

键盘顶部保留原有高度：正向变化使用火焰与橙红渐变，负向变化使用雪花与冰蓝渐变，0 分使用中性色；每次都显示有符号增减值和前后分数。截图为明确标注的固定交互示例。

- `warm-light.png` / `warm-dark.png`：64 → 72，+8 分。
- `cold-light.png` / `cold-dark.png`：64 → 56，−8 分。
- `neutral-light.png`：64 → 64，0 分。

验证结果：

- App、Keyboard、Broadcast 模拟器构建成功；32 项 Swift 核心测试和 32 项 Node 测试通过，TypeScript 类型检查通过。
- Swift HTTP 客户端与临时 Node 服务完成推荐、草稿预估两条接口的 fixture 联调，验证鉴权、会话/版本/草稿 ID、空分数及示例标识。
- 使用已配置的真实 Jev 和两份虚构草稿调用一次评分接口：体贴邀约 78 → 86（+8，2.896 秒），冷淡回应 78 → 69（−9，0.796 秒），均 `isDemo=false`。这两次调用通过 `server/scripts/check-draft.ts` 执行，截图数字为独立 UI 示例。
- 编辑立即撤下旧结果；连续输入防抖；未提交拼音、空文本、无上下文和撤销授权不请求模型；切换会话/草稿、清空或收起后，迟到响应不能恢复旧分数。这些行为由核心测试覆盖。

真机待验收：微信光标前后文与选区读取、输入/粘贴/候选提交、实际发送后的清空、切换联系人、广播暂停和联网延迟。评分只依据本次手动识别的上下文；对方新消息到达后应重新点星光刷新。长草稿可能只有光标附近文本可供预估。

实现使用 Apple 的输入代理读取前文、选区与后文，不移动光标读取全文：[Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)。

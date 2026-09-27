# 中文组合输入与系统键盘外观

2026-09-27

## 输入行为

- 中文模式下的拼音通过 `UITextDocumentProxy.setMarkedText(_:selectedRange:)` 显示在宿主输入框。键盘不再显示独立拼音文本或「输入字母」按钮。
- 点汉字候选、空格或首次回车，用候选替换当前 marked range，再 `unmarkText()`；不会把拼音和中文一起追加到草稿。
- 组合输入中的退格只缩短 marked range；退到空之后，下一次退格才调用宿主 `deleteBackward()`。
- 标点、切换中英文、填入推荐先完成组合输入。切换输入法、关闭键盘或移动光标时保留当前原文并结束组合态；进入另一输入文档只重置本地状态，不编辑新输入框。
- 候选字复用顶部推荐区域的下半部，输入前后键盘高度一致。输入时 Sparkle 与填入入口仍可用。

## 外观

- 扩展使用 `UIInputView(inputViewStyle: .keyboard)`，由 UIKit 提供系统键盘的背景模糊、色调和外观适配；SwiftUI 内容透明，去掉原先手写 RGB 灰底。
- iOS 26 使用圆角顶部、统一浅色功能键、8 pt 连续圆角键帽、更宽空格、系统换行符号。填入按钮使用公开 Liquid Glass API。
- App 内的独立预览使用 Liquid Glass 背景；旧系统回退为系统 Material，减少透明度时使用实色。高对比度下键帽增加轮廓。
- 宿主指定的深色/浅色 `keyboardAppearance` 会同步给扩展。

## 验证与边界

输入回归测试使用带 UTF-16 选区和 marked range 的宿主替身，覆盖候选替换、已有草稿、光标中段、选中文字、退格、未知拼音、标点、切换语言、切换输入法与填入推荐。

本轮最终验证：共享逻辑 32 项测试通过（含 14 项键盘输入测试）；App、Keyboard、Broadcast 的模拟器与 iPhone arm64 无签名编译通过。在 iOS 26.5 的 UIKit 聊天预览中实际点击 `nihao → 你好`，确认原位替换且无拼音残留。真实键盘扩展已加载，并核对浅色、深色的背景、键帽、字体及竖屏尺寸。修复了扩展窗口高度导致的横屏误判，以及 SwiftUI 键帽没有及时跟随宿主深浅色的问题。

实测截图位于 `design/ios-validation/native-input/`：`01-composing.png`、`02-committed.png` 为 UIKit 预览输入验证；`03-extension-light.png`、`04-extension-dark.png` 为真实扩展外观。截图中的 App Group 提示来自无签名模拟器环境，与拼音输入和键盘材质无关。

真机微信仍需确认宿主输入框对 marked text 的具体显示。后续候选引擎修复见下文；系统听写不在此次实现范围。

真机检查：在微信输入 `nihao`，确认拼音在微信输入框中；点「你好」，确认原位替换且没有残留 `nihao`；逐字退格、在草稿中间输入、切换中英文和输入法，再检查浅色与深色外观。

Apple 参考：[UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)、[UIInputView](https://developer.apple.com/documentation/uikit/uiinputview)。


## 2026-09-27 拼音候选修复

截图中的 `dajiahao` 已正确成为宿主的 marked text；候选空白来自旧引擎只有约百条手写映射，只接受完整词条或能完整拆分的输入。`d` 没有未完成音节预测，“大家好”及其组成字词也不在词表中。

- 随 App 与 Keyboard Extension 打包 Rime `pinyin-simp` / Android Pinyin IME 的 65,125 条离线字词；固定版本、Apache 2.0 许可及来源保存在 `ios/Shared/Resources/`。候选查询不依赖网络或完全访问权限。
- 实现按频率排序、未完成末音节、连续拼音分词、词组简拼、显式音节分隔和 `v` / `ü` 输入。`d` 即出现“的、都、到、对”；`dajiahao` 首选“大家好”。
- 每个候选携带它实际消费的拼音长度。选择“大家”只提交 `dajia`，剩余 `hao` 继续在宿主中作为 marked text；继续选“好”才结束组合。未知后缀不会被吞掉。
- 缓存每次按键的候选，避免 SwiftUI 重绘重复解码；拼音变化时将横向候选条回到开头。没有恢复单独的拼音字母行。
- 扩展和 App 两份 Xcode 工程、工程生成脚本以及 Swift Package 均包含词库资源。广播扩展不加载词库。

验证：52 项共享逻辑测试通过，覆盖逐键候选、整句/简拼、分段选词、UTF-16 选区、草稿中间输入、退格、残留字母与失效候选。开发机 Debug 预热后平均候选查询约 3 ms（不是 iPhone 真机延迟）。iOS 模拟器及 iPhone arm64 无签名编译通过。

在 iOS 26.5 的 UIKit 聊天预览实际点击并确认：`d` 出候选；`dajiahao` 出“大家好”；选“大家”后草稿为 `大家hao`；再选“好”后为 `大家好`，没有拼音残留。截图在 `design/ios-validation/pinyin-candidates/`。模拟器内没有微信，这一轮没有宣称已完成微信真机验证。

边界：这是使用公开词库的自有离线解码器，不是 Apple 的私有拼音引擎；苹果键盘的个性化排序、模糊音/拼写纠错和上下文语言模型尚未实现。此次修复对齐逐键出词、组合输入和选词上屏的基本交互。

# 字幕编辑器 SubtitleEditor

一款原生 macOS 字幕编辑工具（Swift + SwiftUI + AVKit）。

## 功能

- 打开 **SRT**、**VTT** 字幕（自动识别 UTF-8 / UTF-8 BOM / UTF-16 / GB18030 编码，兼容 CRLF/LF）
- 打开视频（MP4 / MOV / M4V），**自动加载同名字幕**（`movie.srt`、`movie.vtt`，或 `movie.zh.srt` 等）；视频在左，字幕列表在右
- **点击字幕行跳转到视频对应位置**；播放时高亮当前字幕并自动滚动（可关闭）；视频上叠加显示当前字幕（可关闭）
- 直接编辑字幕文字；双击时间码（或右键 “编辑时间…”）可以修改开始/结束时间
- **拆分**：在字幕文字中按 **回车**，在光标处拆成两条，时间按两边的字符数（不含空白）比例分配
- **合并**：在行首按 **退格** 与上一条合并，在行尾按 **Delete（fn+⌫）** 与下一条合并，或用 **⇧⌘M** / 工具栏按钮将选中字幕与下一条合并；合并后取第一条的开始时间和最后一条的结束时间，文字以换行连接
- **导出**：
  - SRT（Windows 格式：CRLF 换行、UTF-8 带 BOM、重新编号）
  - VTT
  - TXT（纯文本，无时间码，每条一行）
  - MD（Markdown，无时间码，以文件名为标题，每条一段）
- 撤销 / 重做、插入 / 删除字幕、将开始/结束时间设为当前播放位置
- 支持拖放文件到窗口；保存（⌘S）会以原格式写回原文件（SRT 同样写成 Windows 格式）；有未保存的修改时，退出或打开其他字幕前会提示保存

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开（视频或字幕）/ 打开视频 / 打开字幕 | ⌘O / ⇧⌘O / ⌥⌘O |
| 保存 / 导出 SRT | ⌘S / ⇧⌘E |
| 在光标处拆分 | 回车 |
| 条内换行（不拆分） | ⌥回车 |
| 与上一条 / 下一条合并 | 行首 ⌫ / 行尾 Delete，或 ⇧⌘M |
| 下一条 / 上一条 | Tab / ⇧Tab |
| 插入新字幕 / 删除选中字幕 | ⇧⌘N / ⇧⌘⌫ |
| 开始 / 结束时间设为当前位置 | ⌘[ / ⌘] |
| 播放/暂停、后退/前进 2 秒 | ⌘↩、⌥⌘← / ⌥⌘→ |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z |

## 构建与运行

需要 macOS 14+ 和 Swift 工具链（Xcode 或 Command Line Tools 均可）。

```bash
# 打包成 build/SubtitleEditor.app（ad-hoc 签名），之后可以拖进“应用程序”文件夹
./scripts/build-app.sh
open build/SubtitleEditor.app

# 开发时直接运行（可以带上文件参数）
swift run SubtitleEditor /path/to/movie.mp4

# 运行单元测试（swift-testing）
./scripts/test.sh
```

> 只装了 Command Line Tools 时，直接运行 `swift test` 会报 “plugin for module 'TestingMacros' not found”，`scripts/test.sh` 会显式加载这个插件。

## 项目结构

- `Sources/SubtitleCore`：纯逻辑库，包括字幕模型与时间码、SRT/VTT 解析、拆分/合并、各格式导出、同名字幕查找
- `Sources/SubtitleEditor`：SwiftUI 应用，包括编辑器状态与撤销（`EditorModel`）、界面（`ContentView`）、字幕文本编辑控件（`CueTextView`，基于 NSTextView）、视频播放（`PlayerView`）
- `Tests/SubtitleCoreTests`：核心逻辑的单元测试

## 已知限制

- 视频格式受 AVFoundation 限制（MP4/MOV/M4V 等），不支持 MKV、AVI 等
- 解析 VTT 时会丢弃样式（STYLE）、区域（REGION）和 cue 设置（如 `align:start`），导出的 VTT 不含这些信息
- 只能编辑纯文本；`<i>` 之类的标签会原样保留在文字中

<div align="center">
  <img src="Assets/AppIcon.svg" width="128" alt="沙发电视图标">
  <h1>沙发电视</h1>
  <p><strong>坐回沙发，好好看电视。</strong></p>
  <p>为 macOS 设计的原生直播电视播放器。</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--only-blue.svg" alt="GPL-3.0-only"></a>
</p>

<p align="center">
  <a href="https://github.com/ztygalaxy/SofaTV/releases"><strong>发布页</strong></a>
  · <a href="#使用">使用说明</a>
  · <a href="https://github.com/ztygalaxy/SofaTV/issues">问题反馈</a>
</p>

我是一个很爱看电视的人，但在 Mac 上一直没找到一款足够清爽的直播电视。我的要求其实很简单：打开，选台，开始看；不要网页壳，也不要在画面上堆一排播放器按钮。于是有了沙发电视。

它能直接播放常见的 HLS 直播，也针对央视 H5E 和央视频网页源做了原生播放适配。频道导入、收藏、台标、独立音量、全屏观看和更新检查都收在同一个窗口里。

## 预览

<table>
  <tr>
    <td align="center"><img src="docs/images/app-idle.png" width="480" alt="沙发电视启动页面"></td>
    <td align="center"><img src="docs/images/app-playing.png" width="480" alt="沙发电视播放中页面"></td>
  </tr>
  <tr>
    <td align="center"><strong>启动页面</strong><br><sub>打开应用，选择想看的频道</sub></td>
    <td align="center"><strong>播放中</strong><br><sub>选中频道后直接进入原生播放</sub></td>
  </tr>
</table>

### Dock 状态

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/images/dock-idle.png" width="50" alt="未播放时的 Dock 图标"></td>
    <td width="50%" align="center"><img src="docs/images/dock-playing.png" width="50" alt="播放时带当前频道台标的 Dock 图标"></td>
  </tr>
  <tr>
    <td align="center"><strong>未播放</strong><br><sub>显示沙发电视 App 图标</sub></td>
    <td align="center"><strong>播放中</strong><br><sub>右上角显示当前频道台标</sub></td>
  </tr>
</table>

Dock 台标只反映当前播放状态；切台时同步更新，停止播放、播放失败或关闭主窗口后恢复原图。Finder、关于窗口和磁盘中的 App 图标不会被修改。

## 功能

- **原生 macOS 体验**：SwiftUI + AppKit 界面，支持浅色与深色外观、可调整侧栏、窗口布局记忆和独立视频全屏。
- **多种直播通道**：播放普通 HTTP/HLS、央视 H5E 直播，并可从央视频网页会话中解析媒体后交给原生播放器。
- **频道库管理**：导入本地或在线 M3U/TXT 列表；重复频道增量合并，支持删除频道、线路、分组或整份导入列表。
- **频道台标**：内置常见电视台台标与别名匹配；没有匹配时使用沙发电视图形兜底。
- **当前节目**：频道名下显示播出起止时间和正在播出的节目，跨午夜标注“次日”；后台获取 XMLTV 并缓存，节目切换、跨日或唤醒后自动更新，没有匹配数据时不显示占位文字。
- **收藏与搜索**：按频道名或分组搜索，收藏频道，并持久保存筛选、分组折叠和导入数据。
- **音量与静音**：视频区域滚轮、点击或拖动音量条调节音量；新频道默认 30%，每个频道单独保存音量。点击喇叭静音，切台保持静音，再次点击恢复原音量。
- **播放控制**：切台、线路选择、清晰度、缓冲模式、画面拉伸、诊断信息和纯视频全屏；底部控件随鼠标活动显示，支持按钮或双击进入、退出视频全屏。
- **更新检查**：通过固定的 Release 清单检查新版本，不依赖 GitHub API，也不会静默覆盖已安装应用。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac
- 可访问相应直播源的网络环境

正式发布的版本会同时提供 `arm64` 和 `x86_64` 安装包。

## 安装

1. 前往 [Releases](https://github.com/ztygalaxy/SofaTV/releases)。
2. 下载与 Mac 架构对应的 ZIP：
   - Apple Silicon：`SofaTV-<版本>-arm64.zip`
   - Intel：`SofaTV-<版本>-x86_64.zip`
3. 解压后将“沙发电视”拖入“应用程序”。
4. 打开应用并选择频道。

如果发布页暂时没有可下载版本，可以按照下方的“本地构建”说明自行编译。

## 使用

播放时，视频左边缘提供侧边栏收起/展开箭头。鼠标在视频区域移动时显示，移出视频区域或静止 3 秒后隐藏；收起后视频占满窗口可用区域，再点箭头恢复频道列表和原侧栏宽度。

### 频道列表

频道名称下方显示当前节目，数据源沿用 NativeWasmTv 的 [autoEPG](https://github.com/TvWasm/autoEPG)，主源不可用时尝试上游备用源。后台每 4 小时和跨日刷新，网络失败时保留仍在播出的缓存节目；频道匹配优先使用 M3U 的 `tvg-id`，再匹配频道名称。当前仅展示正在播出的节目，不提供节目列表和回看入口。

分组标题滚动时固定在搜索栏下方，下一个分组到达时向上顶走当前标题；点击标题仍可折叠或展开分组。

菜单栏的“频道”菜单支持：

- 导入本地 M3U/TXT 文件
- 导入在线频道列表
- 直接打开直播地址
- 恢复内置频道
- 管理和删除已导入列表

导入采用增量合并：同名、同分组的频道会补充缺失线路，新频道会追加到现有频道库，不会覆盖用户已经导入的数据。

支持标准 M3U 和常见的逗号分隔 TXT 格式。最小的 M3U 列表如下：

```m3u
#EXTM3U
#EXTINF:-1 group-title="卫视频道",示例卫视
https://example.com/live.m3u8
```

TXT 列表可以用 `分组名,#genre#` 切换分组：

```text
卫视频道,#genre#
示例卫视,https://example.com/live.m3u8
```

单条 HTTP/HLS 地址不必做成列表，使用“频道 → 打开直播地址…”即可。

### 快捷操作

| 操作 | 快捷方式 |
| --- | --- |
| 上一个 / 下一个频道 | `↑` / `↓` |
| 降低 / 增大当前频道音量 | `←` / `→` |
| 进入或退出纯视频全屏 | 双击视频 |
| 退出全屏 | `Esc` |
| 导入频道文件 | `⌘O` |
| 导入在线列表 | `⇧⌘O` |
| 打开直播地址 | `⌘L` |

视频区域不显示控制条，也不会响应单击、拖动、滚轮或快进操作，适合保持类似电视机的观看方式。

## 本地构建

需要 Xcode Command Line Tools、Swift 6、Clang 和 Python 3。

```bash
git clone https://github.com/ztygalaxy/SofaTV.git
cd SofaTV
./scripts/test-core.sh
./scripts/build-app.sh
open "dist/沙发电视.app"
```

构建产物位于 `dist/沙发电视.app`。脚本会以 Release 模式编译 Swift 可执行文件和本地解密运行库，生成多尺寸图标、资源目录和本机签名的 App bundle。

### 测试

`./scripts/test-core.sh` 覆盖频道列表解析、台标匹配、播放竞态、HLS 质量选择、TS/PES 重封装、长期状态刷新、缓存边界、更新清单和 Dock 台标渲染。

需要实际 H5E 加密样本时，可在完成构建后运行：

```bash
./scripts/test-h5e.sh /path/to/fixtures
```

直播样本不随仓库分发。

## 发布

版本号由根目录的 [`VERSION`](VERSION) 管理。维护者可手动运行 [SofaTV macOS release](https://github.com/ztygalaxy/SofaTV/actions/workflows/release.yml)：

- 不勾选 `publish`：执行双架构构建并保留 Actions 产物。
- 勾选 `publish`：发布 GitHub Release、ZIP、源码包、`update.json` 和 SHA-256 校验文件。
- 发布成功后：`github-actions[bot]` 自动将 patch 版本加 1 并提交回 `main`。

例如发布 `0.0.1` 后，仓库中的开发版本会自动更新为 `0.0.2`。若 `VERSION` 已被人工调整，工作流不会覆盖它。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `Sources/SofaTV/` | macOS 应用、界面与播放逻辑 |
| `Sources/SofaTV/Resources/` | 内置频道列表 |
| `Assets/` | App 图标、频道台标及来源说明 |
| `native/` | 本地播放运行库的桥接代码与说明 |
| `vendor/` | 构建所需的第三方及派生源码 |
| `scripts/` | 构建、打包、检查与发布脚本 |
| `tests/` | 核心逻辑和媒体处理测试 |
| `docs/images/` | README 使用的界面截图 |

## 问题反馈

如果某个频道无法播放，先在菜单栏选择“播放 → 复制播放诊断”，再到 [Issues](https://github.com/ztygalaxy/SofaTV/issues) 提交问题。请一并写明 macOS 版本、Mac 芯片、频道名称和播放诊断；直播地址如含有账号或临时令牌，请先删掉敏感参数。

## 隐私

导入的频道列表、收藏、频道音量、分组状态以及窗口和侧栏大小只保存在本机，不会上传到项目服务器。

网页解析使用非持久化 WebKit 数据存储，原生请求使用内存 Cookie。播放所需的 Cookie 只在当前运行周期内传递，不会跨启动保留网站数据。

## 许可证与来源

沙发电视采用 [GNU GPL v3 only](LICENSE)（`GPL-3.0-only`）。第三方与派生源码继续适用各自文件中保留的版权和许可证；频道台标的来源与许可见 [频道台标来源](Assets/ChannelLogos/SOURCE.md)。

频道、网站、台标及外部媒体内容的权利归各自权利人所有。本项目不提供内容授权，也不保证任何外部直播源持续可用。使用和分发时请遵守所在地法律以及内容提供方条款。

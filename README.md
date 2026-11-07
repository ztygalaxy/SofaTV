<div align="center">
  <img src="Assets/AppIcon.svg" width="128" alt="沙发电视图标">
  <h1>沙发电视</h1>
  <p><strong>坐回沙发，好好看电视。</strong></p>
  <p>为 macOS 设计的原生直播电视播放器。</p>
  <p>选一个频道安心看，或把电视放进置顶小窗，陪你做点别的。</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+"></a>
  <img src="https://img.shields.io/badge/Apple_Silicon_%2F_Intel-supported-16A085" alt="支持 Apple Silicon 与 Intel">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--only-blue.svg" alt="GPL-3.0-only"></a>
</p>

<p align="center">
  <a href="https://github.com/ztygalaxy/SofaTV/releases/latest"><strong>下载沙发电视</strong></a>
  · <a href="#快速开始">快速开始</a>
  · <a href="#使用指南">使用指南</a>
  · <a href="#常见问题">常见问题</a>
  · <a href="https://github.com/ztygalaxy/SofaTV/issues">问题反馈</a>
</p>

## 功能介绍

| 你想做的事 | 沙发电视提供的功能 |
| --- | --- |
| 找到想看的频道 | 按频道名或分组搜索，点星标收藏，在“频道”和“收藏”之间切换。 |
| 专心看一会儿电视 | 双击进入视频全屏；播放控件随鼠标活动显示，闲置时自动隐藏。 |
| 全屏时换个台 | 鼠标移到画面左侧，滑出半透明毛玻璃频道列表，直接选台。 |
| 边做事边看直播 | 一键切换置顶桌面小窗，自由拖动、按比例缩放，随时返回主窗口。 |
| 知道现在播什么 | 显示频道台标，以及匹配频道的当前节目和播出起止时间；Dock 图标也会标记正在播放的频道。 |
| 整理自己的频道库 | 导入本地或在线 M3U / TXT 列表，合并重复频道，按来源查看频道、复制地址和删除线路。 |
| 留住自己的观看习惯 | 每个频道单独记忆音量，切台保持静音状态；收藏、分组折叠、窗口与侧栏尺寸保存在本机。 |

## 页面预览

点击截图可查看原图。

<table>
  <tr>
    <td width="20%" align="center"><a href="docs/images/app-idle.png"><img src="docs/images/app-idle.png" width="192" alt="沙发电视启动页面"></a></td>
    <td width="20%" align="center"><a href="docs/images/app-playing.png"><img src="docs/images/app-playing.png" width="192" alt="沙发电视播放中页面"></a></td>
    <td width="20%" align="center"><a href="docs/images/app-fullscreen.png"><img src="docs/images/app-fullscreen.png" width="192" alt="沙发电视全屏播放页面"></a></td>
    <td width="20%" align="center"><a href="docs/images/app-mini-player.png"><img src="docs/images/app-mini-player.png" width="192" alt="沙发电视桌面小窗模式"></a></td>
    <td width="20%" align="center"><a href="docs/images/app-channel-manager.png"><img src="docs/images/app-channel-manager.png" width="192" alt="管理频道列表页面"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>启动页面</strong><br><sub>打开应用，选择想看的频道</sub></td>
    <td align="center"><strong>播放中</strong><br><sub>选中频道，开始观看直播</sub></td>
    <td align="center"><strong>全屏播放</strong><br><sub>全屏观看，滑出侧栏切换频道</sub></td>
    <td align="center"><strong>桌面小窗模式</strong><br><sub>置顶播放，自由拖动与缩放</sub></td>
    <td align="center"><strong>管理频道列表</strong><br><sub>搜索频道，管理频道与播放线路</sub></td>
  </tr>
</table>

### Dock 中的频道标记

<table>
  <tr>
    <td width="50%" align="center"><a href="docs/images/dock-idle.png"><img src="docs/images/dock-idle.png" width="50" alt="未播放时的 Dock 图标"></a></td>
    <td width="50%" align="center"><a href="docs/images/dock-playing.png"><img src="docs/images/dock-playing.png" width="50" alt="播放时带当前频道台标的 Dock 图标"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>未播放</strong><br><sub>显示沙发电视 App 图标</sub></td>
    <td align="center"><strong>播放中</strong><br><sub>右上角显示当前频道台标</sub></td>
  </tr>
</table>

## 下载安装

前往 [最新版本](https://github.com/ztygalaxy/SofaTV/releases/latest)，下载适合自己 Mac 的 ZIP 安装包。

| 你的 Mac | 选择的安装包 |
| --- | --- |
| Apple Silicon（M 系列芯片） | `SofaTV-<版本>-arm64.zip` |
| Intel 处理器 | `SofaTV-<版本>-x86_64.zip` |

解压后，将 **沙发电视.app** 拖入“应用程序”，再打开应用。

需要 **macOS 14 或更高版本**，以及可以访问相应直播源的网络。可以在苹果菜单的“关于本机”中查看芯片和系统版本。

## 快速开始

1. **加入频道**：在菜单栏选择“频道 → 恢复内置频道”，或导入自己的本地、在线频道列表。
2. **选台播放**：点击左侧频道开始观看；用搜索框查找频道，点频道右侧的星标加入收藏。
3. **选择观看方式**：保持普通窗口，双击视频进入全屏，或点击视频右上角的图钉进入置顶小窗。

已有一条直播地址时，直接选择“频道 → 打开直播地址…”，粘贴地址即可播放。

## 使用指南

### 查找和管理频道

| 操作 | 入口与用法 |
| --- | --- |
| 搜索与收藏 | 搜索框支持频道名和分组名；点星标收藏，在左上方切换“频道 / 收藏”。 |
| 调整频道列表 | 拖动侧栏与视频之间的分隔线改变宽度；点击视频左侧的箭头收起或展开列表。 |
| 管理导入来源 | 选择“频道 → 管理频道列表…”。点击一份来源，查看其中的具体频道；超过五个来源时可滚动浏览。 |
| 查看和整理线路 | 在来源详情中展开频道，查看、复制或删除播放地址，也可以删除该来源中的频道。 |
| 切换播放线路 | 选中频道后，在“播放 → 播放线路”中选择其他线路。 |
| 删除频道或分组 | 在主窗口的频道列表中右键点击频道或分组，选择对应的删除操作。 |

同名、同分组的频道会合并播放线路，并保留各自的来源。从某个来源的详情中删除频道或线路，只影响该来源，其他来源提供的内容会保留。

### 全屏和桌面小窗

**全屏观看**：双击视频，或点击右下角的全屏按钮。全屏时将鼠标移到画面左侧，即可滑出频道列表，继续搜索、收藏或换台；移回画面右侧后列表自动收起。点击退出全屏按钮、双击视频或按 `Esc` 返回普通窗口。

**桌面小窗**：点击视频右上角的图钉，主窗口会收起，视频变为置顶小窗。拖动画面移动小窗，拖动边缘按比例缩放。再次点击右上角按钮、双击画面或按 `Esc`，返回主窗口。

全屏和小窗沿用当前播放，无需重新选台。移动鼠标可唤出视频上下方的操作按钮。

### 音量和播放设置

- **调节音量**：在视频区域滚动鼠标滚轮，或点击、拖动右下角的音量条。新频道默认音量为 30%，之后按频道单独记忆。
- **静音**：点击喇叭图标。切台时保持静音，再点一次恢复音量。
- **重新播放**：点击音量和全屏按钮之间的刷新图标，重新连接当前线路。
- **调整画面**：在“播放”菜单中选择清晰度、“稳定 / 适中 / 低延迟”直播模式，或开启“拉伸画面”。

### 导入自己的频道列表

| 来源 | 入口 |
| --- | --- |
| 本地 M3U / TXT 文件 | “频道 → 导入频道文件…” |
| 在线 M3U / TXT 列表地址 | “频道 → 导入在线列表…” |
| 单条 HTTP / HLS 直播地址 | “频道 → 打开直播地址…” |

导入后可在“管理频道列表”中查看对应来源及其频道。

<details>
<summary>M3U 与 TXT 格式示例</summary>

M3U 使用 `group-title` 指定分组：

```m3u
#EXTM3U
#EXTINF:-1 group-title="卫视频道",示例卫视
https://example.com/live.m3u8
```

TXT 使用“频道名,地址”，通过 `分组名,#genre#` 切换分组：

```text
卫视频道,#genre#
示例卫视,https://example.com/live.m3u8
```

示例地址仅用于说明格式，请替换为可用的直播地址。

</details>

## 快捷操作

| 操作 | 快捷方式 |
| --- | --- |
| 上一个 / 下一个频道 | `↑` / `↓` |
| 降低 / 增大当前频道音量 | `←` / `→` |
| 进入或退出视频全屏 | 双击视频，或点击右下角全屏按钮 |
| 退出全屏 / 返回主窗口 | `Esc` |
| 进入或退出置顶小窗 | 视频右上角的图钉按钮 |
| 导入频道文件 | `⌘O` |
| 导入在线列表 | `⇧⌘O` |
| 打开直播地址 | `⌘L` |

## 常见问题

<details>
<summary>为什么有些频道连接慢，或者暂时无法播放？</summary>

播放速度与直播源、网络和来源网站的访问要求有关；部分网页来源需要先解析播放地址。可以先点刷新按钮重新连接，或在“播放 → 播放线路”中换一条线路。内置频道也可以通过“频道 → 恢复内置频道”重新导入。

沙发电视优先使用原生播放，网页来源在后台解析；需要时也会使用网页播放通道。

</details>

<details>
<summary>为什么部分频道没有节目信息？</summary>

当前节目依赖节目单来源及频道名称、标识的匹配结果。匹配到的频道会显示正在播出的节目和起止时间，节目数据自动更新；没有匹配结果时仍可选台播放。

</details>

<details>
<summary>如何检查和安装更新？</summary>

在菜单栏选择“沙发电视 → 检查更新…”。发现新版本后可以打开发布页，下载对应芯片的安装包，退出应用后替换“应用程序”中的旧版本。

版本说明与历史安装包也可在 [Releases](https://github.com/ztygalaxy/SofaTV/releases) 中查看。

</details>

## 数据与隐私

频道列表、收藏、频道音量、分组状态，以及窗口和侧栏尺寸保存在本机，不会上传到项目服务器。

播放直播和获取节目信息会访问对应内容来源；检查更新会访问 GitHub。网页解析使用临时网站数据，播放所需的 Cookie 只在当前运行期间使用，不跨启动保留。

## 为什么做沙发电视

我一直很喜欢看电视。

客厅是一个家最有温度的地方：一家人围坐在一起，看节目、聊几句天，让平常的夜晚也慢慢暖起来。

工作以后，我还是喜欢看电视，不用想去看什么剧，调到哪台看哪台。但我始终没能在 Mac 上找到一款足够清爽的直播电视——打开，选台，然后安心地看；没有网页的喧闹，也不让一排播放器按钮打扰画面。

于是有了沙发电视。

希望它能把那种窝在沙发里、和家人一起看电视的感觉，带回每一个寻常的夜晚。

## 开发与贡献

应用使用 **Swift 6、SwiftUI、AppKit、AVKit 和 WebKit**。欢迎提交问题、改进建议或 Pull Request。

### 本地构建

需要 macOS 14+、Swift 6 工具链、Python 3 和 Clang。Swift 与 Clang 可由 Xcode 或 Command Line Tools 提供。

```sh
git clone https://github.com/ztygalaxy/SofaTV.git
cd SofaTV
./scripts/build-app.sh
```

构建结果位于 `dist/沙发电视.app`。构建脚本会同时生成原生播放所需的动态库、应用图标和资源。

运行核心检查：

```sh
./scripts/test-core.sh
```

### 问题反馈

请到 [Issues](https://github.com/ztygalaxy/SofaTV/issues) 反馈，附上应用版本、macOS 版本、Mac 芯片和复现步骤。播放问题可以通过“播放 → 复制播放诊断”附上诊断信息；界面问题可附截图。

## 许可证与来源

沙发电视采用 [GNU GPL v3 only](LICENSE)（`GPL-3.0-only`）。第三方与派生源码继续适用各自文件中保留的版权和许可证；频道台标的来源与许可见 [频道台标来源](Assets/ChannelLogos/SOURCE.md)。

频道、网站、台标及外部媒体内容的权利归各自权利人所有。本项目不提供内容授权，也不保证任何外部直播源持续可用。使用和分发时请遵守所在地法律以及内容提供方条款。

<div align="center">
  <img src="Assets/AppIcon.svg" width="128" alt="沙发电视图标">
  <h1>SofaTV / 沙发电视</h1>
  <p><strong>坐回沙发，好好看电视。</strong></p>
  <p>为 macOS 设计的原生直播电视播放器，随手选台、浏览节目单，也能放在桌面小窗里慢慢看。</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+"></a>
  <img src="https://img.shields.io/badge/Apple_Silicon_%2F_Intel-supported-16A085" alt="支持 Apple Silicon 与 Intel">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--only-blue.svg" alt="GPL-3.0-only"></a>
</p>
<p align="center">
  <a href="https://github.com/ztygalaxy/SofaTV/releases/latest"><strong>下载沙发电视</strong></a>
  · <a href="#下载安装">安装上手</a>
  · <a href="#使用指南">使用指南</a>
  · <a href="#常见问题">常见问题</a>
  · <a href="https://github.com/ztygalaxy/SofaTV/issues">问题反馈</a>
</p>


我一直喜欢看电视：不用先决定看什么剧，调到哪台就看哪台。客厅里，一家人围坐着，看节目、聊几句，平常的夜晚也会暖起来。

工作以后，一家人团聚的机会少了，于是做了沙发电视。

希望把窝在沙发里、和家人一起看电视的感觉，带到 Mac 上，带在身边。

## 界面预览

<p align="center">
  <a href="docs/images/app-fullscreen.jpg"><img src="docs/images/app-fullscreen.jpg" width="960" alt="全屏播放、频道节目单与节目预约"></a>
</p>
<table>
  <tr>
    <td width="16.66%" align="center"><a href="docs/images/app-idle.png"><img src="docs/images/app-idle.png" width="160" alt="沙发电视启动页面"></a></td>
    <td width="16.66%" align="center"><a href="docs/images/app-playing.png"><img src="docs/images/app-playing.png" width="160" alt="沙发电视窗口播放与节目单"></a></td>
    <td width="16.66%" align="center"><a href="docs/images/app-fullscreen.jpg"><img src="docs/images/app-fullscreen.jpg" width="160" alt="沙发电视全屏播放与节目单"></a></td>
    <td width="16.66%" align="center"><a href="docs/images/app-mini-player.png"><img src="docs/images/app-mini-player.png" width="160" alt="沙发电视桌面小窗模式"></a></td>
    <td width="16.66%" align="center"><a href="docs/images/app-channel-manager.png"><img src="docs/images/app-channel-manager.png" width="160" alt="编辑频道来源页面"></a></td>
    <td width="16.66%" align="center"><a href="docs/images/app-program-reservations.png"><img src="docs/images/app-program-reservations.png" width="160" alt="节目单中预约节目并显示预约成功提示"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>频道列表</strong><br><sub>搜索、收藏，选择想看的频道</sub></td>
    <td align="center"><strong>播放与节目单</strong><br><sub>查看当天排期，直播继续播放</sub></td>
    <td align="center"><strong>全屏与节目单</strong><br><sub>滑出频道列表，悬停浏览排期</sub></td>
    <td align="center"><strong>桌面小窗模式</strong><br><sub>置顶播放，自由拖动与缩放</sub></td>
    <td align="center"><strong>编辑频道来源</strong><br><sub>搜索频道，管理频道与播放线路</sub></td>
    <td align="center"><strong>节目预约和管理</strong><br><sub>铃铛预约节目，统一查看与取消</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td width="50%" align="center"><a href="docs/images/dock-idle.png"><img src="docs/images/dock-idle.png" width="50" alt="未播放时的 Dock 图标"></a></td>
    <td width="50%" align="center"><a href="docs/images/dock-playing.png"><img src="docs/images/dock-playing.png" width="50" alt="播放时带当前频道台标的 Dock 图标"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>未播放</strong><br><sub>显示沙发电视 App 图标</sub></td>
    <td align="center"><strong>播放中</strong><br><sub>有专属台标时，在右上角显示频道标记</sub></td>
  </tr>
</table>

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 原生播放 | 支持清晰度选择、直播延迟模式和画面拉伸，提供网页来源的解析与播放支持。 |
| 节目单预览 | 悬停浏览当天节目单，自动定位当前时段；查看其他频道的排期时，直播继续播放。 |
| 节目预约 | 点击节目旁的铃铛，在开播前 10 秒收到系统通知；点击通知切台。 |
| 全屏选台 | 从画面左侧唤出频道列表，搜索、收藏、预览节目单或换台。 |
| 置顶小窗 | 一键切换桌面小窗，自由移动、按比例缩放，随时返回主窗口。 |
| 频道来源 | 导入本地或在线 M3U / TXT 列表，合并重复频道，按来源查看和删除频道、线路。 |
| 频道整理 | 自定义名称与分组，调整频道和分组顺序，导入、导出个人频道配置。 |
| 在线更新 | 启动时后台更新已添加的在线列表，更新失败仍可使用上次保存的频道。 |
| 自动恢复 | 断流或持续没有播放进度时尝试重连、切换备用线路，支持断网恢复与睡眠唤醒后重连。 |
| 观看习惯 | 保存收藏、频道音量和静音状态，记住窗口、侧栏与分组设置，支持返回上一观看频道。 |

## 下载安装

需要 **macOS 14 或更高版本**，支持 Apple Silicon 和 Intel Mac。前往 [最新版本](https://github.com/ztygalaxy/SofaTV/releases/latest)，按芯片类型选择 DMG 或 ZIP 安装包。

| 你的 Mac | 安装包 |
| --- | --- |
| Apple Silicon（M 系列芯片） | `SofaTV-<版本>-arm64.dmg` / `.zip` |
| Intel 处理器 | `SofaTV-<版本>-x86_64.dmg` / `.zip` |

打开 DMG，将 **沙发电视.app** 拖入“应用程序”文件夹即可安装。也可以解压 ZIP，将其中的 `.app` 移入“应用程序”；ZIP 内的应用文件名包含版本和芯片类型，打开后仍显示为“沙发电视”。

## 使用指南

### 第一次使用

1. **添加频道**：打开“频道 → 导入在线列表…”。地址框已预填参考来源，可以直接点击“打开”，也可以换成自己的地址；本地列表通过“导入频道文件…”添加。
2. **选台观看**：点击左侧频道开始播放，用搜索框查找频道，点星标加入收藏。
3. **按习惯整理**：在“频道 → 整理频道分组…”中改名、分组和排序；将鼠标停在频道上，还可以浏览当天节目单。

首次使用请先添加频道来源，应用预填地址仅供测试交流使用。

### 频道与节目单

搜索框支持频道名和分组名，左上角可切换“频道 / 收藏”。拖动列表与视频之间的分隔线可调整宽度，点击视频左侧的箭头可收起或展开列表。

正在播放的频道带有青色竖条。有专属台标时，Dock 图标右上角也会显示该台标；使用默认电视图标的频道则保留应用原图标。

将鼠标停在频道上，右侧会滑出当天的节目单，并定位正在播出的节目。移入面板可滚动查看前后排期，点击“回到当前”可返回当前时段；鼠标移回视频后，面板自动收起。预览其他频道的节目单时，当前直播继续播放。

正在观看的频道以青色标记“当前节目”；预览其他频道时，以白色标记“正在播出”。

当前时段缺少排期时，频道行会显示当天的下一档节目，节目单同步定位、高亮并标注“即将播出”；到开播时间后自动切换为正常的当前节目标记。

### 节目预约

点击节目单中未开播节目旁的铃铛，即可添加开播提醒。首次添加时会申请系统通知权限，启动应用不会弹出权限请求。

节目开始前 10 秒发送 macOS 系统通知。横幅消失后，仍可在通知中心点击提醒切换到对应频道。节目结束满一天后，沙发电视会在下次刷新时清理旧预约及其通知。

在“播放 → 节目预约…”或节目单底部的“节目预约…”中查看、取消提醒，也可以直接点击“观看”。

通知显示受系统通知设置、专注模式及电脑睡眠状态影响；未收到提醒时，可在“系统设置 → 通知”中检查沙发电视的权限。

### 全屏与置顶小窗

**全屏观看**：双击视频，或点击右下角全屏按钮。将鼠标移到画面左侧，滑出频道列表；悬停查看节目单，点击频道换台。鼠标移回右侧后列表自动收起。按 `Esc` 会依次收起节目单和频道列表；两者都未展开时，再按 `Esc` 退出全屏。

**置顶小窗**：点击视频右上角的图钉进入。拖动画面移动位置，拖动边缘按比例缩放；再次点击图钉、双击画面或按 `Esc` 返回主窗口。

全屏和小窗沿用当前播放，无需重新选台。移动鼠标可唤出视频操作按钮。

**停止播放**：点击右上角图钉旁的电源按钮，或选择“播放 → 停止播放”。全屏或小窗会返回主窗口，频道列表保留；手动停止后，网络恢复或电脑唤醒都不会重新开播。

### 音量与播放

- **音量**：在视频区域滚动鼠标滚轮，或拖动右下角音量条；音量按频道记忆。
- **静音**：点击喇叭图标。切台时保持静音，再点一次恢复音量。
- **刷新**：点击音量与全屏按钮之间的刷新图标，重新连接当前线路。
- **播放选项**：在“播放”菜单中选择清晰度与“稳定 / 适中 / 低延迟”模式，或开启“拉伸画面”；实际可用的清晰度取决于直播来源。
- **返回上一观看频道**：在“播放”菜单中切回上一个看过的频道。

### 频道列表与来源

| 导入内容 | 菜单入口 |
| --- | --- |
| 本地 M3U / TXT 文件 | 频道 → 导入频道文件… |
| 在线 M3U / TXT 列表 | 频道 → 导入在线列表… |
| 单条直播地址 | 频道 → 打开直播地址… |

打开“频道 → 编辑频道来源…”可查看已导入的列表、单独更新在线来源或删除整个来源。点击一份来源可查看具体频道，展开频道可复制或删除播放线路。

同名、同分组的频道会合并播放线路。从来源详情中删除频道或线路，只影响该来源；其他来源提供的内容仍会保留。主窗口支持右键删除频道或分组，手动切换线路则使用“播放 → 播放线路”。

### 整理频道与分组

打开“频道 → 整理频道分组…”：

- **频道**：拖动或点击上下箭头调整顺序；点击铅笔修改显示名称和分组。输入新分组名以创建新分组，或点击“选择已有分组”。
- **分组**：调整分组顺序、重命名分组；使用已有名称时会合并显示在该分组下。搜索时暂停拖动排序，清空搜索即可继续。
- **恢复默认顺序**：恢复来源中的频道顺序及默认分组顺序，不清除自定义名称和分组。
- **导出配置 / 导入配置**：用 JSON 文件备份或恢复来源、收藏、顺序、自定义名称与分组和音量。恢复前会确认，并停止当前播放；不支持的文件不会覆盖现有配置。

名称与分组的修改只影响本机显示，节目单仍按原始频道信息匹配。在线更新会保留已匹配频道的收藏、音量和整理设置。

### 在线更新频道

添加在线来源后，每次启动都会先显示上次保存的频道，再在后台检查更新。更新成功后采用新的频道与线路，失败时继续使用原有列表，正在观看的直播不会因此中断。

选择“频道 → 更新频道列表”可手动检查全部在线来源，也可以在“编辑频道来源…”中单独更新，并查看上次检查时间与失败提示。

从在线来源移除的频道和线路会保留删除记录，需要时可在来源详情中选择“恢复已移除内容”。删除整个来源后，需要重新导入才会添加回来。

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

### 快捷操作

| 快捷方式 | 操作 |
| --- | --- |
| `↑` / `↓` | 上一个 / 下一个频道 |
| `←` / `→` | 降低 / 增大当前频道音量 |
| 双击视频 | 切换普通窗口与全屏；小窗中双击返回主窗口 |
| `Esc`（全屏） | 先收起节目单和频道列表，再按退出全屏 |
| `Esc`（小窗） | 返回主窗口 |
| `⌘O` | 导入频道文件 |
| `⇧⌘O` | 导入在线列表 |
| `⌘L` | 打开直播地址 |

## 常见问题

<details>
<summary>为什么有些频道连接慢，或者无法播放？</summary>

连接速度受直播来源、网络和来源网站的访问要求影响，部分网页来源还需要先解析播放地址。可点击刷新重新连接，或在“播放 → 播放线路”中尝试其他线路；频道地址失效时，可先选择“频道 → 更新频道列表”。

沙发电视优先使用原生播放，网页来源在后台解析，必要时使用网页播放通道。

</details>

<details>
<summary>断流后会自动恢复吗？</summary>

断流或持续没有播放进度时，应用会尝试重连，并在有备用线路时自动切换。断网时等待网络恢复，电脑唤醒后重新连接；全部线路尝试失败后会暂停自动重试，此时可以手动刷新或换台。

</details>

<details>
<summary>为什么部分频道没有节目单？</summary>

节目信息依赖节目单来源，以及频道名称、标识的匹配结果。匹配成功时会显示当前节目和当天已获取的排期，数据自动更新。不同频道的排期完整度可能不同；没有节目单也可以正常选台播放。

</details>

<details>
<summary>如何更新应用？</summary>

应用启动后会在后台检查新版本；正在观看时会跳过自动提示。也可以随时选择“沙发电视 → 检查更新…”。

点击“下载并安装”会下载对应芯片的 ZIP 更新包，校验后替换应用并重新打开，保留频道与设置。也可以选择“稍后”或“跳过此版本”；跳过的版本仍可通过手动检查查看。

历史版本和更新说明见 [Releases](https://github.com/ztygalaxy/SofaTV/releases)。

</details>

## 数据与隐私

频道列表、收藏、上一观看频道记录、节目预约、音量、静音状态、自定义名称与分组、排序，以及窗口和侧栏设置都保存在本机，不上传到项目服务器。

网页解析使用临时网站数据，播放所需的 Cookie 仅在当前运行期间使用，不跨启动保留。

## 开发与贡献

应用使用 **Swift 6、SwiftUI、AppKit、AVKit 和 WebKit**。欢迎通过 [Issue](https://github.com/ztygalaxy/SofaTV/issues) 反馈问题、提出想法，或提交 Pull Request；参与项目的朋友见 [Contributors](https://github.com/ztygalaxy/SofaTV/graphs/contributors)。

本地构建需要 macOS 14+、Swift 6 工具链、Python 3 和 Clang。Swift 与 Clang 可由 Xcode 或 Command Line Tools 提供。

```sh
git clone https://github.com/ztygalaxy/SofaTV.git
cd SofaTV
./scripts/build-app.sh
```

产物位于 `dist/沙发电视.app`，包含原生播放所需的动态库、图标和资源。

生成当前芯片对应的 ZIP 和 DMG：

```sh
./scripts/package-app.sh
```

运行核心检查：

```sh
./scripts/test-core.sh
```

## 许可证与来源

沙发电视采用 [GNU GPL v3 only](LICENSE)（`GPL-3.0-only`）。第三方与派生源码继续适用各自文件中保留的版权和许可证；频道台标的来源与许可见 [频道台标来源](Assets/ChannelLogos/SOURCE.md)。

频道、网站、台标及外部媒体内容的权利归各自权利人所有。本项目不提供内容授权，也不保证任何外部直播源持续可用。使用和分发时请遵守所在地法律以及内容提供方条款。

推荐的在线频道数据来源于互联网，仅用于开发测试与技术交流。如涉及侵权，请[联系我](mailto:zhangty1996@163.com)删除。

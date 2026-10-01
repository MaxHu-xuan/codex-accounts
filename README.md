# Codex 账号管理器

在 Mac 上集中查看多个 Codex 账号的额度、余额点数和重置卡。打开主窗口可以对比账号，点击菜单栏也能快速查看。

这是一款独立的本地工具，非 OpenAI 官方应用。

[本次更新](#036-更新) · [功能](#可以查看什么) · [使用方法](#怎么使用) · [显示说明](#怎么看列表里的信息) · [English](#english)

## 0.3.6 更新

- **余额点数更直观**：显示在额度百分比下方，方便一起查看。
- **重置卡增加到期时间**：在剩余次数下方显示最近到期时间，主窗口和菜单栏都能看到。
- **一起刷新账号信息**：每日自动刷新和手动刷新都会更新额度、点数、重置卡次数及到期信息。
- **修复获取信息失败**：修复了 Codex 桌面版更新后，部分账号信息无法获取的问题。

应用也保留了减少重复授权提醒的改进。Mac 有时仍会在更新应用后要求重新确认访问登录信息；确认后的使用体验也受系统设置影响。

## 可以查看什么

| 内容 | 显示方式 |
| --- | --- |
| 账号和套餐 | 每个账号单独一行，可以修改备注，方便区分 |
| 剩余额度 | 以百分比显示，优先展示普通 Codex 周额度 |
| 余额点数 | 显示在额度百分比下方，与额度百分比分开显示 |
| 下次额度重置 | 查看额度预计何时恢复 |
| 重置卡 | 查看剩余次数，以及最近到期时间 |
| 订阅到期日 | 根据自己的订阅页面手动填写 |
| 当前账号 | 在 Codex 中确认后，手动添加当前标记 |

重置卡只供查看，不会被本工具兑换或消耗。各账号的额度与点数分别显示，不会合并或转移。

## 怎么使用

1. 打开 Codex Accounts，点击“添加账号”。
2. 在官方登录页面完成登录，返回后即可查看账号信息。
3. 点击“刷新全部”更新所有账号；也可以在单个账号右侧菜单中选择“刷新账号信息”。
4. 在“设置”中选择每日更新时间，默认是本地时间 09:00。
5. 平时点击菜单栏图标即可快速查看；需要修改备注、填写订阅日期或移除账号时，打开主窗口操作。

电脑关机或休眠期间不会执行刷新；下次打开应用或唤醒后会补一次。列表展示的是最近一次获取的信息，想确认最新状态时可以手动刷新。

### 辅助切换账号

选择“辅助切换到 Codex”后，工具会打开 Codex 设置并给出操作指引。请在 Codex 中完成切换，再把对应账号标记为“当前（手动确认）”。

当前标记由你手动维护，工具不会自动识别 Codex 正在使用哪个账号，也不会替你退出登录。

### 填写订阅日期

“订阅到期”需要手动填写，可按自己的订阅页面记录。它与额度恢复时间、重置卡到期时间是三件不同的事，不会互相代替。

## 怎么看列表里的信息

### 0 和“未提供”有什么区别？

- **0%、0 点、0 次**：最近一次获取的信息明确显示为零，分别对应额度、点数和重置卡。
- **未提供**：尚未获取到这项信息，或当前无法获得；不代表为零。
- **暂无可用卡**：重置卡剩余次数为零，因此没有可显示的到期时间。

余额点数最多显示两位小数，鼠标悬停可以查看更完整的数值。很小的正余额会显示为“<0.01 点”，不会被当成零。

### 重置卡到期时间怎么看？

| 显示 | 含义 |
| --- | --- |
| 到期 + 日期 | 多张可用卡中最早的到期时间 |
| 已知到期 + 日期 | 目前只拿到了部分卡的详情；显示这些卡中最早的已知时间，其他卡可能更早到期 |
| 到期未提供 | 无法确定到期时间，不等于不过期 |
| 不过期 | 已获得完整详情，确认当前可用卡均无到期时间 |
| 到期需刷新 / 已知到期需刷新 | 保存的时间已经过去，需要刷新确认；工具不会自行扣减次数 |

日期按 Mac 的本地时区显示，鼠标悬停可查看包含年份和时区的完整时间。额度下方的“重置”是额度恢复时间，与重置卡的“到期”不同。

## 下载与使用条件

目前还没有可直接下载的安装包；后续版本见[下载页面](../../releases)。

当前版本适用于搭载 Apple 芯片、运行 macOS 15 或更新版本的 Mac。使用前，请在电脑上安装可用的 Codex 或 ChatGPT 桌面版。

## 隐私

登录信息保存在这台 Mac 的系统安全存储中，账号列表和最近一次查询结果也保存在本机。工具不会把你的账号列表上传到自己的服务器，也不会读取或复制现有 Codex 桌面会话的登录信息。

移除账号只会删除本工具保存的记录，不会删除你的 OpenAI 账号或订阅。反馈问题时，请遮住账号信息和私人内容。

## 常见问题

**为什么更新应用后，Mac 又要求我输入密码？**

Mac 会确认访问已保存登录信息的应用身份。更新后可能需要为每个账号重新允许一次。保持应用身份一致有助于记住“始终允许”，但无法保证系统在所有情况下都不再询问。若同一版本每次刷新都提示，可反馈版本号和提示文字，并隐藏账号信息。

**为什么工具里的信息和 Codex 页面不同？**

列表保存的是最近一次查询结果。先尝试刷新；仍有差异时，请以 Codex 和 OpenAI 页面显示的信息为准。

**账号提示登录失效怎么办？**

在对应账号的菜单中选择“重新登录”，完成官方登录后再刷新。

---

## English

Codex Account Manager is an independent macOS utility for checking multiple Codex accounts in one window or from the menu bar. It shows plans, remaining quota, credit balances, usage reset credits and expiry dates. It is not an official OpenAI app.

### What's new in 0.3.6

- Credit balances appear below quota percentages.
- The nearest reset-credit expiry appears below the remaining count.
- Daily and manual refreshes update these details together.
- Fixes an issue that prevented account details from loading after a Codex desktop update.

### Getting started

1. Open Codex Accounts, select Add Account and complete the official sign-in.
2. Use Refresh All or the menu beside an account to update its information.
3. Choose a daily refresh time in Settings; the default is 09:00 local time.
4. Use the menu bar for a quick check and the main window to manage saved accounts.

Switching is guided: finish the switch in Codex yourself, then mark the account as Current (manually confirmed). Subscription expiry dates are entered manually.

Zero means the latest result reported zero. Not provided means the information is unknown. For reset credits, Known expiry covers only the cards whose details are available; other cards may expire sooner. No expiry appears only when complete details confirm it. Dates use your Mac's local time zone. Expired dates prompt a refresh without automatically changing the count. Reset credits are displayed only and are never redeemed by this app.

Account records stay on your Mac. Removing a saved account does not delete the OpenAI account or subscription. There is no ready-to-download installer yet; future versions will appear on the [download page](../../releases). Requires an Apple silicon Mac with macOS 15 or later and a working Codex or ChatGPT desktop app.

## 许可证 / License

[MIT License](LICENSE)

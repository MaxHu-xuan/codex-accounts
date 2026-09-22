# Codex 账号管理器：Mac 上的账号、额度和重置时间查看器

Codex 账号管理器（Codex Account Manager） 是一款适用于 macOS 的轻量工具，用一个清晰的窗口和菜单栏列表，集中查看多个 Codex 账号的套餐、剩余额度和下次重置时间。

它适合同时使用个人账号、工作账号，或需要区分多个 ChatGPT / Codex 订阅的人。你可以每天查看一次所有账号的状态，减少反复登录、打开多个页面和手动记录额度的麻烦。

> 这是一款独立的本地工具，非 OpenAI 官方应用，也不会自动轮换账号或绕过服务限制。

## 你可以看到什么

- 账号列表：集中查看已经添加的 Codex 账号。
- 套餐名称：自动显示 Pro20X、Pro5X 等套餐等级。
- 剩余额度：优先显示普通 Codex 周额度；不同账号可以直接对比。
- 下次重置时间：在余额下方显示额度何时恢复，使用电脑的本地时区。
- 订阅到期日：官方没有提供这个日期时，可以自己填写并保存。
- 当前账号标记：你在 Codex 中确认当前账号后，可以在列表中标记“当前（手动确认）”。
- 菜单栏入口：不用打开复杂页面，点击菜单栏即可查看账号和额度。
- Dock 图标：应用正在运行时，会出现在 Dock 中，方便重新打开。

## 什么时候有用

- 你有多个 Pro20X 或 Pro5X 账号，需要快速比较剩余额度。
- 你想知道某个账号什么时候恢复额度。
- 你需要把个人和工作账号分开管理。
- 你不想每次都退出 Codex、重新打开网页，再手动记下额度。
- 你希望把账号信息留在自己的 Mac 上，不使用第三方在线账号管理网站。

## 怎么使用

1. 打开 Codex Accounts。
2. 点击 添加账号，在官方登录页面完成登录。
3. 登录完成后，账号、套餐、余额和下次重置时间会显示在列表中。
4. 菜单栏可以快速查看；主窗口可以修改备注、填写订阅到期日、重新登录或移除账号。
5. 在主窗口的“设置”中选择每天自动查看的时间。默认是本地时间 09:00。

每天自动查看一次就够了。电脑关机或休眠时不会后台运行；下次打开或唤醒后会补一次。你也可以随时手动刷新。

## 账号切换说明

目前 Codex 桌面版没有提供公开的“一键切换账号”功能。因此本工具提供的是辅助切换：选择目标账号后，它会打开 Codex 设置，并告诉你下一步该怎么做。完成登录后，你可以把对应账号标记为“当前（手动确认）”。

这个标记只是你的确认记录，不会假装自动识别桌面里当前登录的是哪个账号。它不会中断正在运行的 Codex 任务，也不会擅自替你退出或登录。

## 隐私和安全

- 登录信息只保存在这台 Mac 的系统安全存储中。
- 账号查询在本机独立进行，不会把你的账号列表上传到本工具的服务器。
- 不会读取或复制你正在使用的 Codex 桌面登录状态。
- 不会把账号密码、登录令牌或额度数据写入公开仓库。
- 移除账号只会移除本工具保存的记录，不会删除你的 OpenAI 账号或订阅。

使用前仍应确认你遵守 OpenAI 服务条款、账号所属组织的规定和当地法律。请不要把登录信息、截图或本机账号记录发布到公开页面。

## 额度和订阅日期的区别

余额下方的“下次重置”是服务返回的额度恢复时间，会随额度查询更新。

“订阅到期”是你自己填写的订阅日期。由于官方额度信息不包含订阅账单到期日，工具不会猜测，也不会拿额度重置时间代替订阅到期日。

如果服务没有返回重置时间，列表会显示“未提供”。如果保存的时间已经过去，工具会提示需要刷新，不会自行把余额改成 100%。

## 常见问题

### 这是 OpenAI 官方应用吗？

不是。这是一款个人本地工具，使用 Codex 提供的登录和额度能力。OpenAI、ChatGPT 和 Codex 名称及相关商标归其各自所有者所有。

### 它会自动帮我换账号吗？

不会。Codex 桌面版目前没有公开的一键换号入口，工具只能打开官方设置并提供操作指引。你可以在列表中手动记录当前账号，避免记错。

### 它会把多个账号的额度合在一起吗？

不会。每个账号分别显示，余额不会合并，也不会自动把一个账号的额度转给另一个账号。

### 为什么有的账号显示 0%？

这表示该账号当前普通 Codex 额度已经用完或额度快照显示为 0%。请查看“下次重置”时间；备用模型额度不代替普通 Codex 额度。

### 为什么看不到订阅到期日？

官方额度信息没有提供订阅账单到期日。你可以在主窗口点击“未设置”，按自己的订阅页面填写日期。

### 支持哪些 Mac？

当前版本面向 macOS 15 或更新版本的 Apple silicon Mac，并要求电脑上已经安装可用的 Codex 或 ChatGPT 桌面应用。

## 项目状态

这是一个个人维护的本地工具。Codex 的登录方式、套餐名称和额度规则可能变化，使用前请以 Codex 和 OpenAI 页面显示的信息为准。

欢迎反馈界面问题、错误提示和额度显示问题。请不要在公开反馈中附带邮箱、账号截图、登录信息或其他私人资料。

## 许可证

本项目采用 MIT License 发布。

---

# Codex Account Manager: macOS Account, Quota, and Reset-Time Viewer

Codex Account Manager is a lightweight macOS menu bar utility for people who use more than one Codex account. It brings account names, subscription tiers, remaining quota, and the next quota reset time into one simple list.

It is useful for separating personal and work accounts, comparing multiple ChatGPT / Codex subscriptions, and checking usage without repeatedly signing in and out or opening several pages.

> This is an independent local utility. It is not an official OpenAI app, and it does not rotate accounts or bypass usage limits.

## What you can see

- Account list: Keep saved Codex accounts together in one place.
- Plan labels: Show Pro20X, Pro5X, and other available plan names.
- Remaining quota: Compare each account's ordinary Codex weekly quota.
- Next reset time: See when the displayed quota is expected to reset in your Mac's local time zone.
- Subscription expiry: Enter and save an expiry date when the official account information does not provide one.
- Current-account marker: After checking Codex yourself, mark one account as “Current (manually confirmed)”.
- Menu bar access: View the important account information without opening a large window.
- Dock presence: Keep the running app easy to find and reopen.

## Who it is for

Codex Account Manager is useful when you:

- use personal and work Codex accounts on the same Mac;
- have multiple Pro20X or Pro5X subscriptions;
- want to compare remaining quota and reset times;
- want one place to record subscription expiry dates; or
- prefer a local account viewer instead of a third-party online dashboard.

## How to use it

1. Open Codex Accounts.
2. Select Add Account and finish sign-in on the official OpenAI page.
3. After sign-in, the account, plan, remaining quota, and next reset time appear in the list.
4. Use the main window to rename an account, enter a subscription expiry date, sign in again, or remove a saved account.
5. Choose the daily refresh time in Settings. The default is 09:00 local time.

The app checks accounts once per day by default. It does not keep polling every minute. If the Mac was asleep or off at the scheduled time, the next launch or wake-up performs a catch-up check. You can always refresh manually.

## Account switching

The Codex desktop app does not currently expose a public one-click account switcher. This utility therefore provides guided switching: select an account, open the official Codex settings, and follow the sign-out and sign-in steps there.

After you finish signing in, you can mark that account as Current (manually confirmed). The marker records your confirmation; it does not pretend to detect which account the Codex desktop app is using. The utility does not interrupt a running Codex task or sign you out without your action.

## Privacy and security

- Login information stays in the Mac's secure system storage.
- Account checks run locally and are not sent to a server operated by this utility.
- The utility does not read or copy the login state of your existing Codex desktop session.
- Account passwords, login tokens, and personal quota snapshots are not included in this public repository.
- Removing an account removes the copy saved by this utility; it does not delete your OpenAI account or subscription.

Use the app in accordance with the OpenAI terms and policies that apply to your account, your organization, and your location. Do not publish login information, private screenshots, or account records in an issue or public repository.

## Quota reset versus subscription expiry

The next reset shown below a balance is the reset time returned for that quota window and is refreshed with the account check.

Subscription expiry is a date you enter yourself. The official quota information does not expose the billing expiry date, so the app does not guess it or substitute a quota reset time.

If the service does not provide a reset time, the list shows Not provided. If a saved reset time has passed, the app asks you to refresh; it does not automatically change the balance to 100%.

## Frequently asked questions

### Is this an official OpenAI app?

No. It is an independent local utility that uses Codex sign-in and quota capabilities. OpenAI, ChatGPT, and Codex names and trademarks belong to their respective owners.

### Does it switch accounts automatically?

No. The Codex desktop app does not currently provide a public one-click account-switching entry point. The utility opens the official settings and provides guidance. You can mark the account you confirmed so it is easier to remember later.

### Does it combine quotas across accounts?

No. Every account is shown separately. Quotas are not merged, transferred, or redistributed.

### Why does an account show 0%?

It means the displayed ordinary Codex quota is currently exhausted or the latest snapshot reports zero remaining. Check the next reset time. A reserve-model quota is not substituted for the ordinary Codex quota.

### Why is the subscription expiry date blank?

The official quota information does not include the billing expiry date. In the main window, select the blank expiry date and enter the date shown on your subscription page.

### Which Macs are supported?

The current version targets Apple silicon Macs running macOS 15 or later and requires a working Codex or ChatGPT desktop installation.

## Project status

This is a personal local utility. Codex sign-in, plan names, and quota rules may change over time, so use the information shown by Codex and OpenAI as the final reference.

Feedback about the interface, error messages, or quota display is welcome. Please do not include email addresses, account screenshots, login details, or other private information in public feedback.

## License

Released under the MIT License.

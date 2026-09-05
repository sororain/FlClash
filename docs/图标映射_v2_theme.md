# v2_theme 图标 → Flutter Material Icons 映射表

## v2_theme 侧边栏完整映射

| # | 中文 | v2_theme (Simple Line Icons) | Flutter App (Material Icons) | 所在页面 |
|---|------|---------------------------|------------------------------|---------|
| 1 | 仪表盘 | `si si-speedometer` | — | — |
| 2 | 使用文档 | `si si-book-open` | — | — |
| 3 | 购买订阅 | `si si-bag` | `Icons.shopping_bag_outlined` | `shop.dart` |
| 4 | 节点状态 | `si si-check` | — | — |
| 5 | 我的订单 | `si si-list` | `Icons.receipt_long_outlined` | `shop.dart` |
| 6 | **我的邀请** | **`si si-users`** | **`Icons.people_outlined`** | `shop.dart` |
| 7 | 个人中心 | `si si-user` | — | — |
| 8 | 我的工单 | `si si-support` | `Icons.confirmation_number_outlined` | `user.dart` |
| 9 | 流量明细 | `si si-bar-chart` | — | — |

## Flutter App 中的菜单项

### `lib/views/shop.dart`（商店页）

| 菜单项 | Material Icon | 对应 v2_theme |
|-------|--------------|--------------|
| 购买套餐 | `Icons.shopping_bag_outlined` | `si si-bag` |
| 我的订单 | `Icons.receipt_long_outlined` | `si si-list` |
| 我的邀请 | `Icons.people_outlined` | `si si-users` |
| 访问官网 | `Icons.language_outlined` | — |
| 联系客服 | `Icons.headphones_outlined` | — |

### `lib/views/user.dart`（用户页）

| 菜单项 | Material Icon | 对应 v2_theme |
|-------|--------------|--------------|
| 重置流量 | `Icons.refresh_rounded` | — |
| 同步订阅 | `Icons.sync_rounded` | — |
| 我的钱包 | `Icons.account_balance_wallet_outlined` | — |
| 我的工单 | `Icons.confirmation_number_outlined` | `si si-support` |
| 高级工具 | `Icons.construction_outlined` | — |
| 检查更新 | `Icons.system_update_outlined` | — |
| 退出登录 | `Icons.logout` | — |

## Simple Line Icons 参考

v2_theme 使用的图标库是 [Simple Line Icons](https://simplelineicons.github.io/)。常用图标一览：

| CSS Class | 图标含义 | 推荐 Material 替代 |
|-----------|---------|-------------------|
| `si si-speedometer` | 速度表/仪表盘 | `Icons.speed` |
| `si si-book-open` | 打开的书/文档 | `Icons.menu_book_outlined` |
| `si si-bag` | 购物袋 | `Icons.shopping_bag_outlined` |
| `si si-check` | 勾选/状态正常 | `Icons.check_circle_outline` |
| `si si-list` | 列表/订单 | `Icons.receipt_long_outlined` |
| `si si-users` | 用户组/邀请 | `Icons.people_outlined` |
| `si si-user` | 单个用户 | `Icons.person_outline` |
| `si si-support` | 客服头戴 | `Icons.headphones_outlined` |
| `si si-bar-chart` | 柱状图/流量 | `Icons.bar_chart_outlined` |

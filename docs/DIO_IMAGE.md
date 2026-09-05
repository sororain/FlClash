# DioImage 加载占位策略

| 场景 | 文件 | loadingWidget | 加载中效果 |
|------|------|-------------|-----------|
| **头像** | `lib/iqoo/pages/user.dart` | `SizedBox.shrink()` | 无占位，外层圆形 `cs.primaryContainer` 背景透出 |
| **公告/仪表盘弹窗图片** | `lib/iqoo/services/notice_service.dart` | `Center(20×20, CircularProgressIndicator strokeWidth:2)` | 只有转圈，无灰色背景 |
| **其他 DioImage 默认** | `lib/iqoo/widgets/dio_image.dart` | 不传（null） | 灰色 `surfaceContainerHighest` 背景 + 14px 转圈 |

`DioImage` 构造参数：`loadingWidget` 自定义加载占位，`errorWidget` 自定义错误占位（默认 `SizedBox.shrink()`）。

# EZ 主题 — 文档/知识库模块 API

> 源文件：`apiez/src/api/docs.js`

## 接口列表

共 **2 个接口**，均需要登录认证（需带 token）。

---

### 1. 获取知识库文章列表

- **函数名**: `fetchKnowledgeList(language)`
- **请求方式**: GET
- **接口路径**: `/user/knowledge/fetch`
- **参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `language` | string | 语言代码，用于返回对应语言的文章（如 `zh_CN`、`en`） |

- **说明**: 返回知识库文章分类和文章列表

---

### 2. 获取知识库文章详情

- **函数名**: `fetchKnowledgeDetail(id, language)`
- **请求方式**: GET
- **接口路径**: `/user/knowledge/fetch`
- **参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | number | 文章 ID |
| `language` | string | 语言代码 |

- **说明**: 两个接口使用同一个路径，通过是否传 `id` 区分列表/详情

---

### 请求示例

```javascript
// 获取列表
GET /api/v1/user/knowledge/fetch?language=zh_CN

// 获取文章详情
GET /api/v1/user/knowledge/fetch?id=1&language=zh_CN
```

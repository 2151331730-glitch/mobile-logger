# 手机随手记（mobile-logger）

一个 200 行的单文件网页，手机打开就能记东西：文字 + 图片，直接写进云数据库，回到电脑再一键同步进本地 Markdown。

**没有后端服务器。** 整个链路只有三层：静态网页 → 数据库 REST 接口 → 本地同步脚本。

```
手机浏览器
   │  index.html（内联 CSS/JS，单文件）
   │  fetch + Bearer <PublishableKey>
   ▼
腾讯云开发 CloudBase
   ├─ 静态托管：放 index.html
   └─ SQL 型数据库（PostgreSQL + PostgREST）：entries 表
          │
          │  sync-to-onedrive.ps1（每 2 小时，计划任务）
          ▼
OneDrive/随手记.md（追加到「原始记录」区）
```

## 为什么这样设计

- **不要后端**：只是给自己记点东西，起一个服务、写鉴权、做部署，成本远大于收益。CloudBase 的 PostgREST 直接暴露一张表，网页拿到匿名 key 就能读写。
- **单文件网页**：部署就是传一个 `index.html`，手机上打开不用装 App，也不用等加载框架。
- **图片在前端压**：手机原图 3–5 MB，直接入库既慢又贵。用 canvas 缩到最长边 1280px、JPEG 质量 0.72，单张落到 100–300 KB。
- **同步走文件而不是数据库**：笔记最终要能给人看、能在手机上用 OneDrive 打开，所以目的地是 Markdown，不是又一个数据库。

## 功能

- 输入文字即时发送，回车即发
- 添加图片：前端 canvas 压缩后以 base64 data URL 存库
- 列表按时间倒序显示最近 30 条，点图片可全屏查看
- `sync-to-onedrive.ps1` 按 id 去重，只追加新记录，首次运行只建立基线、不导入历史数据

## 快速开始

### 1. 建库建表

在 CloudBase 控制台创建「SQL 型数据库」环境，执行：

```sql
CREATE TABLE entries (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  text       text,
  image      text        -- 可空；前端 canvas 压缩后的 base64 data URL
);
```

然后给这张表配好 RLS（行级权限）。**这是唯一的安全边界**——匿名 key 是公开的，能读到它的人就能读写表里的数据。

### 2. 填配置

```powershell
Copy-Item config.example.js config.local.js
```

编辑 `config.local.js`，填入你的环境地址和 Publishable Key。这个文件已被 `.gitignore` 排除。

> 改表结构（加列、建表）不能走 PostgREST，要用 CLI：`tcb db execute -e <envId> --sql "ALTER TABLE ..."`

### 3. 部署

```powershell
Copy-Item index.html web\index.html -Force
Copy-Item config.local.js web\config.local.js -Force
tcb hosting deploy .\web -e <envId>
```

### 4. 同步到 Markdown

在 `OneDrive/随手记.md` 里放一个锚点 `<!-- SYNC-APPEND-HERE -->`，然后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-to-onedrive.ps1
```

注册成每 2 小时跑一次的计划任务（`schtasks /Create`）。

## 文件说明

| 文件 | 作用 |
|---|---|
| `index.html` | 网页源码，部署到静态托管 |
| `config.example.js` | 配置模板，复制成 `config.local.js` 使用 |
| `sync-to-onedrive.ps1` | 增量同步到 Markdown（按 id 去重） |
| `ocr.ps1` | 可选：调 Windows 自带 OCR 识别截图文字 |

## 已知限制

- 没有鉴权体系，靠 RLS 兜底；多用户场景不适用
- 记录列表固定取最近 30 条，没有分页
- 图片以 base64 存在 `text` 类型的列里，没有走对象存储

## License

MIT

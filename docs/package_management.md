# Uya Package Management v1 Draft

**状态**: design draft, MVP prototype implemented in current branch
**更新日期**: 2026-05-29
**适用范围**: `uya.toml`、`uya.lock`、`uya upm`、带依赖的 `uya build/check/run/test`

---

## 1. 背景与当前实现

本仓库当前稳定的模块系统仍以“模块根目录 + `UYA_ROOT`”为核心：

- 无 manifest 时，编译器把输入文件所在目录，或输入目录本身，当作模块查找根。
- 依赖查找的现状是先查本地模块根，再查 `UYA_ROOT` 指向的标准库目录。
- 当前已发布/已文档化的工作流仍然支持：
  - `uya build file.uya`
  - `uya build dir/`
  - `uya run/test/check ...`
- 中央 registry、版本求解、多版本并存、workspace 和 publish 流程都还不是 v1 目标。

历史文档与当前源码之间还有几处需要明确拆开的漂移：

- `docs/uya.md` 旧版本把“项目根目录”直接等同于“包含 `main` 的目录”，不足以覆盖 package root / source root。
- 旧设计/待办文本曾把 `--project-root` 当作现成能力引用，但当前源码主线在包管理 MVP 落地前仍主要依赖自动推导的 module root。
- 旧草案默认 `uya.toml + src/ + deps/`，但没有先定义 package root 与 source root 的关系。

本草案的目标不是推翻现有模块系统，而是在它之上补一层与现状兼容的包管理模型。

---

## 2. 术语

### 2.1 package root

包含 `uya.toml` 的目录。一个 Uya 包的元数据、lockfile 和内部依赖目录都相对于这个目录定义。

### 2.2 source root

`[package].source-dir` 指向的源码根目录，默认值为 `"."`。它相对于 package root 解析，且必须落在 package root 内部。

### 2.3 module root

编译器真正用于 `use ...;` 模块查找的根目录。

- package mode 下：`module root = package root + source-dir`
- legacy mode 下：`module root` 继续等于当前编译器自动推导出的“项目根目录”
- 对当前实现层：若出现 `--project-root` 或旧变量名 `project_root`，默认都应理解为 `module root`

### 2.4 legacy mode

找不到 `uya.toml` 时的兼容模式。legacy mode 下：

- 不要求存在 package root。
- 继续允许直接 `uya build file.uya`。
- 模块路径继续相对于自动推导出的本地模块根解析。

### 2.5 dependency root

依赖被解析并准备给编译器使用后的源码根。v1 对用户暴露 alias 和 import 规则，不要求用户直接引用内部 vendor 路径。

### 2.6 install directory

包管理器为当前 package root 写入依赖内容的本地目录。v1 采用隐藏目录：

- `.uya/deps/`：已安装依赖
- `.uya/git-cache/`：Git clone/cache

### 2.7 lockfile

`uya.lock`。用于记录一次依赖解析后得到的精确结果，保证后续 `install/build` 的可重现性。

---

## 3. 目标与非目标

### 3.1 v1 目标

- 定义 `uya.toml`
- 定义 `uya.lock`
- 支持 `path` 依赖
- 支持 `git` 依赖
- 定义带依赖时的模块查找与冲突规则
- 提供 `uya upm` / `cmd/upm` 最小命令集

### 3.2 明确非目标

v1 不承诺以下能力：

- 中央 registry
- publish
- semver range / SAT solver / 版本回溯
- workspaces / monorepo 统一锁定
- 同一 import alias 的多版本并存
- checksum / signature / registry mirror
- 二进制包和预编译缓存

---

## 4. 目录布局与根语义

### 4.1 package root 与 source root

`uya.toml` 必须位于 package root。源码根由 `source-dir` 指定：

- 默认 `source-dir = "."`
- 允许显式 `source-dir = "src"`
- `source-dir` 必须是 package root 内部路径
- v1 明确禁止 `source-dir = "../src"` 这类越出 package root 的配置

### 4.2 布局示例

#### flat layout

```text
hello/
  uya.toml
  main.uya
  util/
    fmt.uya
```

- package root: `hello/`
- source root: `hello/`
- module root: `hello/`

#### src layout

```text
hello/
  uya.toml
  src/
    main.uya
    util/
      fmt.uya
```

- package root: `hello/`
- source root: `hello/src/`
- module root: `hello/src/`

#### library package

```text
http/
  uya.toml
  src/
    client.uya
    server.uya
```

- 可以没有 `main`
- 仍然必须有 `uya.toml`
- 其它包通过 alias 方式导入，例如 `use http.client;`

### 4.3 manifest 发现

v1 的 manifest 发现顺序：

1. 若显式传入 `--manifest-path <path>`，直接使用它。
2. 否则，从当前 Uya 源文件所在目录开始向上查找；若输入本身是目录，则从该目录开始向上查找 `uya.toml`。
3. 若找到 manifest，则进入 package mode。
4. 若找不到 manifest，则回退 legacy mode。

换句话说，`project root` 的包管理语义应当是：

- 从“当前被编译的 Uya 源文件目录”向上
- 取第一个包含 `uya.toml` 的目录
- 该目录就是 package root

但在兼容 CLI 语义里：

- `--project-root` 覆盖的是 `module root`
- 它不是 `package root` 的别名
- `package root` 仍然由 manifest 发现规则决定

### 4.4 与现有 `project_root` 概念的关系

- 对用户文档：优先讲 `package root` / `source root` / `module root`
- 对实现层：
  - 当前主线已经优先统一为 `module_root`
  - `--project-root` 仍保留为兼容 CLI 名称
- 对语义解释：
  - 讨论 manifest 发现时，使用 `package root`
  - 讨论 `use` 解析与编译器查找顺序时，使用 `module root`
  - 不要再把 `project root` 同时指向这两个概念
- 语义上，旧实现里的 `project_root` 应理解为“当前一次编译实际使用的 module root”

---

## 5. `uya.toml` 规范

### 5.1 顶层约束

- 文件名固定为 `uya.toml`
- v1 只要求一个 TOML 子集，不要求仓库先提供完整 TOML 标准库
- 未识别字段应报出明确错误或被文档明确标成“保留字段”

### 5.2 `[package]`

v1 最小字段集合：

```toml
[package]
name = "hello"
version = "0.1.0"
source-dir = "."
description = "optional"
license = "optional"
repository = "optional"
```

字段规则：

- `name`：必填；包名
- `version`：必填；版本字符串
- `source-dir`：可选；默认 `"."`
- `description` / `license` / `repository`：可选元数据

### 5.3 名称规则

- package 名和 dependency alias 都使用 ASCII 小写字母、数字、`-`、`_`
- import alias 额外要求能稳定映射为模块首段，推荐只使用小写字母、数字、`_`
- v1 大小写敏感，但规范推荐清一色小写，避免跨平台路径歧义

### 5.4 依赖表

v1 支持：

- `[dependencies]`
- `[dev-dependencies]`

语义：

- `[dependencies]`：普通构建依赖，参与 `build/check/run/test/install/update`
- `[dev-dependencies]`：只在开发工作流使用；v1 文档定义其语义，但 MVP 可以先不让普通 `build` 自动拉入它们

### 5.5 依赖声明格式

依赖表的 key 就是 import alias。v1 仅支持显式 inline table：

```toml
[dependencies]
http = { path = "../http" }
json = { git = "https://example.com/json.git", tag = "v1.2.3" }
util = { git = "ssh://git@example.com/util.git", commit = "abc123" }
```

规则：

- 一个依赖必须二选一：`path` 或 `git`
- Git 依赖的 `tag` / `branch` / `commit` 三选一
- 不支持字符串 shorthand，如 `http = "../http"`
- `path` 相对当前 manifest 所在目录解析
- path 依赖与 git 依赖都要求目标包自身包含 `uya.toml`

### 5.6 保留字段

`authors`、`build` 等字段不是 v1 必需字段。若保留：

- 必须在文档中标记为 reserved / future
- MVP 不要求解析和执行这些字段

---

## 6. `uya.lock` 规范

### 6.1 文件格式

`uya.lock` 采用 TOML，与 manifest 同风格，顶层包含锁文件版本：

```toml
version = 1

[[package]]
alias = "http"
name = "http"
source_kind = "git"
git = "https://example.com/http.git"
commit = "0123456789abcdef"
source_dir = "."
dependencies = ["util"]
```

### 6.2 锁定内容

每个锁定条目至少记录：

- `alias`
- `name`
- `source_kind`
- 对 path：
  - 原始 manifest 相对路径
  - 规范化后的绝对 package root
  - v1 不记录 manifest hash / mtime
- 对 git：
  - `git` URL
  - 精确 `commit`
- `source_dir`
- 直接依赖 alias 列表

### 6.3 分支和标签

manifest 中允许写：

- `tag`
- `branch`
- `commit`

但写入 lockfile 时必须全部落成精确 `commit`。

### 6.4 更新时机

v1 约定：

- `upm install`：若 lockfile 缺失，则解析并生成
- `upm update`：重新解析并刷新 lockfile
- `upm add/remove`：当该命令进入 MVP 时，应同步重写 lockfile
- `uya build/check/run/test`：
  - 优先读取 lockfile
  - lockfile 缺失时允许按 manifest 解析，并生成 lockfile

### 6.5 过期与手改

- lockfile 缺失、无法匹配当前依赖或无法读取时，当前 MVP 按“需要重新解析”处理，而不是直接报错
- `uya.lock` 不应手动编辑
- lockfile 保障的是“同一份解析结果可重现”
- lockfile 不保证下载源永久可用
- v1 不做 checksum / signature / registry mirror

---

## 7. 依赖解析与模块查找

### 7.1 查找顺序

package mode 下推荐顺序：

1. root package 的 source root
2. 已解析依赖的 alias 根
3. `UYA_ROOT`
4. 编译器保留内置目录（若未来保留）

### 7.2 alias 到模块路径的映射

若 manifest 中写：

```toml
[dependencies]
http = { path = "../http" }
```

且依赖包的 `source-dir = "src"`，那么：

- `use http.client;`
- 逻辑上表示导入 alias `http`
- 它映射到依赖包的 source root，再在其中查找 `client.uya` 或 `client/`

换言之，用户看到的是 `http.client`，而不是 `.uya/deps/http/src/client`。

### 7.3 目录模块与文件模块

依赖包内的模块规则与 root package 保持一致：

- 目录模块仍然成立
- 单文件模块别名仍然成立
- `source-dir` 只改变模块根，不改变目录/文件模块本身的规则

### 7.4 冲突策略

v1 明确采用“及早报错”：

- root source root 下若已存在顶层模块 `http`，再声明 alias `http`，报冲突
- 两个依赖都声明 alias `http`，但解析到不同来源/不同 commit，报冲突
- 同一 alias 在不同位置要求不同版本，报冲突
- 同一 package 名若被解析到不同 path 来源或不同 git commit，即使 alias 不同，也直接报错
- v1 不支持同一 alias 多版本 side-by-side

### 7.5 循环依赖

- 模块内循环依赖：沿用当前编译器规则
- 包级依赖循环：v1 直接拒绝

---

## 8. 安装目录与安全边界

### 8.1 本地目录

v1 采用隐藏目录：

```text
.uya/
  deps/
  git-cache/
```

- `.uya/deps/`：安装好的依赖内容
- `.uya/git-cache/`：Git 下载缓存
- package mode 的临时 build root 当前放在 `TMPDIR` 或 `/tmp` 下，例如 `/tmp/uya-upm-build-<pid>/root/`

### 8.2 path 依赖安全规则

- manifest 中的 `path` 先相对 manifest 目录解析，再做规范化
- 目标必须是存在的目录，且目录内必须有 `uya.toml`
- `source-dir` 必须位于该依赖的 package root 内部
- 检测到 path 循环引用时直接报错

---

## 9. CLI 工作流

### 9.1 public naming

v1 的 canonical public UX 是：

- `uya upm <subcommand>`

仓库内的真实入口是：

- `cmd/upm`
- `bin/cmd/upm`
- `bin/uya-upm-stage2`（repo-local stage2 launcher，用于在主编译器入口完全并入前验证 `build` / `upm` 工作流）

`uyapm` 作为独立别名不是 v1 必需项；若将来提供，必须明确说明它只是 `uya upm` 的别名。

### 9.2 MVP 子命令

当前实现已支持：

- `upm init`
- `upm install`
- `upm update`
- `upm build`
- `upm add`
- `upm remove`

其中 `add/remove` 当前提供的最小 UX 为：

- `upm add <alias> --path <dir>`
- `upm add <alias> --git <url> --branch <name>`
- `upm add <alias> --git <url> --tag <name>`
- `upm add <alias> --git <url> --commit <sha>`
- `upm add <alias> --dev ...`（写入 `[dev-dependencies]`）
- `upm remove <alias>`
- `upm remove <alias> --dep`
- `upm remove <alias> --dev`

### 9.3 语义

- `upm init`：生成最小 `uya.toml`；默认生成 flat layout，可选生成 `src/` layout
- `upm install`：解析 manifest / lockfile，安装依赖并写回 lockfile
- `upm update`：刷新可变 ref（如 branch/tag）并重写 lockfile
- `upm build`：wrapper，按 package mode 准备依赖后调用现有构建流程
- `upm add`：直接改写 `uya.toml` 后自动执行一次 `install`，并同步刷新 `uya.lock`
- `upm add --dev`：把依赖写入 `[dev-dependencies]`
- `upm remove`：从 manifest 删除指定 alias 后自动执行一次 `install`
- `upm remove --dep`：只从 `[dependencies]` 删除
- `upm remove --dev`：只从 `[dev-dependencies]` 删除

### 9.4 示例

```bash
uya upm add gui_uya --git https://github.com/uya-lang/gui-uya.git --branch main
uya upm add gui_uya --dev --path ../gui_uya
uya upm remove gui_uya --dep
uya upm remove gui_uya --dev
```

### 9.5 remove 的分区语义

- `upm remove <alias>`：在 `[dependencies]` 与 `[dev-dependencies]` 中都允许匹配；命中即删除
- `upm remove <alias> --dep`：只检查并删除 `[dependencies]`
- `upm remove <alias> --dev`：只检查并删除 `[dev-dependencies]`
- 若目标分区中没有该 alias，应报错，而不是静默成功
- 当前实现按 alias 对应的整行声明做最小文本删除，不做完整 TOML 重排

### 9.6 manifest 发现

`upm install/update/build` 默认在当前目录向上查找 manifest，并支持显式：

```text
--manifest-path <path>
```

---

## 10. 错误与诊断

v1 至少要能稳定报出以下错误：

- manifest 不存在
- `source-dir` 非法或越界
- path 依赖路径不存在
- 依赖包缺少 `uya.toml`
- alias 冲突
- lockfile 写入失败
- Git ref 无法解析
- 包级循环依赖

诊断中应尽量包含：

- 当前 manifest 路径
- 发生冲突的 alias
- 冲突双方的源信息

---

## 11. 与 legacy mode 的兼容

以下工作流必须继续可用：

- `uya build file.uya`
- `uya build dir/`
- `uya run/test/check ...`

也就是说：

- `uya.toml` 不是进入编译器的必需前提
- 只有当 manifest 被发现时，才切换到 package mode
- 没有 manifest 的仓库和示例，不能因为包管理引入而回归

---

## 12. 当前实现状态

本节用于防止规范写成“已经全部存在”的口吻。

### 12.1 已存在的基础

- legacy mode 模块系统
- `UYA_ROOT` 标准库查找
- `uya build/check/run/test`

### 12.2 本草案要求的 MVP

- 已实现：
  - manifest 发现
  - manifest/lock 子集解析
  - path 依赖安装与构建接入
  - git 依赖安装、lockfile 落地与 branch/update 行为
  - `cmd/upm`
  - repo-local `bin/uya-upm-stage2` 调度与 package build 验证入口
- 仍保留为第二批：
  - `upm add`
  - `upm remove`

### 12.3 明确尚未承诺

- registry
- publish
- semver range
- multi-version
- workspace

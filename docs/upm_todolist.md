# UPM TODO List

基于 [`docs/upm_evolution_design.md`](./upm_evolution_design.md) 第 12 节“实施优先级与里程碑表”整理。

---

## P0 / M1：拆出基础层

**状态**：已完成（2026-06-12）

### 目标

把 `src/cmd/upm/upm_lib/main.uya` 中最稳定的基础能力拆出，形成独立模块，同时保持现有行为不变。

### TODO

- [x] 新建 `src/cmd/upm/upm_lib/types.uya`
- [x] 迁移 UPM 基础常量到 `types.uya`
- [x] 迁移 UPM enum 定义到 `types.uya`
- [x] 迁移 `UPMDependency` / `UPMManifest` / `UPMLockItem` / `UPMPackageBuildPlan` 等结构到 `types.uya`
- [x] 迁移 `upm_manifest_init()` 到 `types.uya`
- [x] 迁移 `upm_build_plan_init()` 到 `types.uya`
- [x] 新建 `src/cmd/upm/upm_lib/path_utils.uya`
- [x] 迁移 path normalize / join / dirname / exists / source-dir 安全校验等工具到 `path_utils.uya`
- [x] 新建 `src/cmd/upm/upm_lib/manifest.uya`
- [x] 迁移 manifest string value parse 到 `manifest.uya`
- [x] 迁移 dependency inline table parse 到 `manifest.uya`
- [x] 迁移 semver-like compare 与 `uya_min_version` 校验到 `manifest.uya`
- [x] 迁移 `upm_parse_manifest()` 到 `manifest.uya`
- [x] 更新 `src/cmd/upm/upm_lib/main.uya` 引用新模块
- [x] 删除 `main.uya` 中已迁移的重复定义
- [x] 跑 `tests/verify_upm_suite.sh`

### 完成定义

- [x] `main.uya` 不再承载基础类型和 manifest 解析
- [x] `tests/verify_upm_suite.sh` 全绿
- [x] 对外 CLI 行为无变化

---

## P0 / M2：拆出核心子模块

**状态**：主体已完成（2026-06-12；resolver 与 staging 仍有过渡期耦合）

### 目标

把 lockfile、git 获取、resolver、build plan 从 `main.uya` 中拆出，并形成 resolved graph 思维。

### TODO

- [x] 新建 `src/cmd/upm/upm_lib/lockfile.uya`
- [x] 迁移 lock item record 逻辑到 `lockfile.uya`
- [x] 迁移 lock item exact ref/source match 逻辑到 `lockfile.uya`
- [x] 迁移 lockfile 写入逻辑到 `lockfile.uya`
- [x] 迁移 locked git commit 读取逻辑到 `lockfile.uya`
- [x] 新建 `src/cmd/upm/upm_lib/git_fetch.uya`
- [x] 迁移 git binary 查找逻辑到 `git_fetch.uya`
- [x] 迁移 fork/exec git 相关逻辑到 `git_fetch.uya`
- [x] 迁移 `clone / checkout / rev-parse / prepare checkout` 到 `git_fetch.uya`
- [x] 在 `types.uya` 中新增 `UPMResolvedDep`
- [x] 在 `types.uya` 中新增 `UPMResolvedGraph`
- [x] 新建 `src/cmd/upm/upm_lib/resolver.uya`
- [x] 迁移 manifest discovery 到 `resolver.uya`
- [x] 迁移 manifest path resolve 到 `resolver.uya`
- [x] 迁移 conflict detection 到 `resolver.uya`
- [x] 迁移 recursive dependency resolve 到 `resolver.uya`
- [x] 让 resolver 输出 resolved graph，而不是直接依附 build plan
- [x] 新建 `src/cmd/upm/upm_lib/build_plan.uya`
- [x] 迁移 shell quote/run/remove/copy/mkdir 等物化相关逻辑到 `build_plan.uya`
- [x] 迁移 build root cleanup 到 `build_plan.uya`
- [x] 迁移 compile input / module root 计算到 `build_plan.uya`
- [x] 迁移 `upm_prepare_build_plan()` / `upm_prepare_build_plan_ex()` 到 `build_plan.uya`
- [x] 更新 `src/cmd/upm/upm_lib/main.uya`，仅保留 glue + CLI + manifest 编辑
- [x] 跑 `tests/verify_upm_suite.sh`

### 完成定义

- [x] resolver 已能形成独立的 resolved graph
- [x] build plan 不再兼任依赖图语义承载层
- [x] git / lockfile / build root 逻辑边界清晰

---

## P1 / M3：将 package mode 下沉到编译器

**状态**：已完成（2026-06-12）

### 目标

让 `uya build/check/run/test` 在 manifest 项目中原生 package-aware，而不是长期依赖 `upm build` 独占这条路径。

### TODO

- [x] 在共享类型中新增 `UPMPackageContext`
- [x] 为 `UPMPackageContext` 定义 `active / manifest_path / package_root / source_root / module_root / resolved_graph / lockfile_path / materialized_root` 等字段
- [x] 修改 `src/main.uya`，在 build 流程中加入 manifest discovery
- [x] 找到 `uya.toml` 时进入 package mode
- [x] 找不到 `uya.toml` 时保持 legacy mode
- [x] 让 `uya build` 复用 resolver / package context
- [x] 让 `uya check` 复用 package context
- [x] 让 `uya run` 接入 package discovery 与依赖准备逻辑
- [x] 让 `uya test` 接入 package discovery 与依赖准备逻辑
- [x] 修改 `src/driver/modules.uya`（或对应模块解析实现）以支持 package mode
- [x] 在 package mode 下支持 dependency alias -> dependency source root 映射
- [x] 保留 legacy mode 下当前 `project_root -> UYA_ROOT` 查找顺序
- [x] 明确并落实 alias 与本地顶层模块冲突策略
- [x] 确保 staging 仍可作为过渡期 build materialization 方案
- [x] 跑 `tests/verify_upm_suite.sh`
- [x] 补充 `uya build/check/run/test` 的 package mode 回归测试

### 完成定义

- [x] `uya build` 在 manifest 项目中原生可用
- [x] `uya check` 进入 package mode
- [x] `uya run/test` 至少共享 package discovery 与依赖准备链路
- [x] legacy mode 无回归

---

## P2 / M4：引入身份 / 缓存 / 校验 / 版本

**状态**：已完成（2026-06-14）

### 目标

把 `upm` 从“能拉依赖”升级为“能稳定标识、缓存、验证依赖”的模块系统。

### TODO

- [x] 在 `UPMManifest` 中增加 `module` 字段
- [x] 在 manifest 解析中支持 `[package].module`
- [x] 在 dependency 声明中解析 `module + version`
- [x] 支持 path/git 依赖携带 `module + version` 进行 identity 校验
- [x] 支持纯 `module + version`（无 path/git 来源）解析到真实来源
- [x] 保持旧 `path/git` 声明兼容
- [x] 在 `UPMLockItem` 中增加 `module / resolved_version / resolved_commit / content_hash`
- [x] 扩展 lockfile 写回字段并兼容读取旧 `commit`
- [x] 明确 lockfile version/v2 头部与完整读取策略
- [x] 设计全局缓存目录布局：`~/.uya/pkg/vcs/` 与 `~/.uya/pkg/mod/`
- [x] 在 git fetch 流程中优先查 `~/.uya/pkg/vcs/`
- [x] cache miss 时执行 git fetch，并写入全局 VCS 缓存
- [x] 实际写入并复用 `~/.uya/pkg/mod/` 模块内容层
- [x] 新增 checksum 规则（源码树 hash）
- [x] install/build 时生成并写入 checksum
- [x] git 依赖 build/install 时校验 lockfile checksum
- [x] path 依赖按旧 lockfile checksum 做强校验
- [x] 在 `UPMResolvedDep` 中增加 `module / requested_version / resolved_version / content_hash`
- [x] 将 `content_hash` 写入 resolved graph 条目
- [x] 支持 path/git 依赖的 exact version 校验模型
- [x] 支持纯 `module + version` exact version resolve
- [x] 保持旧 path/git 项目继续可用
- [x] 为 module identity / cache / checksum / exact version 增加测试

### 完成定义

- [x] manifest 可表达稳定 module identity
- [x] lockfile 可表达 resolved identity + checksum
- [x] git 依赖可跨项目复用全局 VCS 缓存
- [x] path/git 依赖携带 `module + version` 时 exact version 语义稳定可用
- [x] 纯 `module + version` 依赖可解析到真实来源
- [x] `~/.uya/pkg/mod/` 模块内容层可实际复用

---

## P3 / M5：生态扩展

### 目标

在核心模块系统稳定后，扩展到 proxy / registry / workspace / publish / diagnostics。

### TODO

- [ ] 抽象统一 fetcher 接口
- [ ] 支持 path / git / proxy / registry backend
- [ ] 新建 `src/cmd/upm/upm_lib/fetch_proxy.uya`
- [ ] 支持配置 proxy 地址
- [ ] resolver 优先走 proxy backend
- [ ] 新建 `src/cmd/upm/upm_lib/registry.uya`
- [ ] 支持 module -> source metadata 查询
- [ ] 支持版本列表查询
- [ ] 设计 workspace 语义
- [ ] 新建 `src/cmd/upm/upm_lib/workspace.uya`
- [ ] 支持本地多 package root 联调
- [ ] 支持 workspace 内本地模块优先策略
- [ ] 设计 publish 最小协议
- [ ] 新建 `src/cmd/upm/upm_lib/publish.uya`
- [ ] 支持 version 唯一性检查 / metadata 校验 / checksum 固化
- [ ] 新建 `src/cmd/upm/upm_lib/diagnostics.uya`
- [ ] 增加 `upm graph`
- [ ] 增加 `upm why`
- [ ] 增加 `upm doctor`
- [ ] 增加 `upm cache dir`
- [ ] 增加 `upm vendor`
- [ ] 增加 proxy / registry / workspace / diagnostics 相关测试

### 完成定义

- [ ] fetch backend 可扩展
- [ ] proxy / registry 具备最小闭环
- [ ] workspace 可支持本地多包联调
- [ ] publish / diagnostics 有最小可用入口

---

## 全局约束

- [ ] legacy mode 不能回归
- [ ] 前三阶段优先重构边界，不引入不必要的协议变化
- [ ] 在 M3 之前不引入大规模 lockfile / cache / identity 协议升级
- [ ] 生态层能力必须后置于 resolver 与编译器 package mode 稳定之后
- [ ] 每个里程碑结束后都执行完整 upm 回归测试

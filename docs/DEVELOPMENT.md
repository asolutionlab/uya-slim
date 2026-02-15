# Uya 开发指导说明

**版本**：v0.3.4+  
**更新日期**：2026-02-15

本文档定义 Uya 编译器的开发流程。自 v0.3.4 起，**C 编译器（compiler-c/）已退役**，仅维护自举编译器。

---

## 开发模式

### 自举编译架构

```
bin/uya.c (已提交的 C99 代码)
    ↓ gcc -std=c99
bin/uya (可执行编译器)
    ↓ 编译 src/*.uya
bin/uya.c (新生成的 C99 代码)
    ↓ 自举验证 (make b)
提交新版本
```

### 关键原则

1. **单一编译器源**：`src/` 目录是唯一的编译器源代码
2. **C99 代码作为引导**：`bin/uya.c` 是自举编译器输出的 C99 代码，作为仓库的"种子"
3. **自举验证必须通过**：每次修改后必须运行 `make b` 验证自举一致性

---

## 从零开始构建

### 首次克隆仓库

```bash
git clone https://github.com/uya-lang/uya.git
cd uya

# 方式一：从 C99 代码构建（推荐，零依赖）
gcc -std=c99 -O2 bin/uya.c -o bin/uya -lm
make tests-uya  # 验证构建

# 方式二：使用 Makefile
make from-c     # 从 bin/uya.c 构建
```

### 开发流程

```bash
# 1. 修改编译器源代码
vim src/checker.uya

# 2. 使用当前编译器编译新版本
make uya        # bin/uya 编译 src/*.uya → bin/uya.c

# 3. 验证自举一致性
make b          # 新编译器编译自身，输出与 bin/uya.c 对比

# 4. 运行测试
make tests-uya  # 348 个测试

# 5. 提交
git add -A && git commit -m "fix: 描述修复内容"
```

---

## Makefile 目标

| 目标 | 说明 |
|------|------|
| `make from-c` | 从 bin/uya.c 构建 bin/uya（零依赖，首次克隆后使用） |
| `make uya-c` | 构建 C 编译器 bin/uya-c（用于编译 src/*.uya） |
| `make uya` | 使用 bin/uya-c 编译 src/*.uya → bin/uya.c，然后构建 bin/uya |
| `make b` | 自举验证：新编译器编译自身，对比输出 |
| `make tests-uya` | 运行自举编译器测试 |
| `make tests-c` | （已废弃）运行 C 编译器测试 |
| `make clean` | 清理构建产物 |

---

## 代码结构

```
uya/
├── bin/
│   ├── uya          # 可执行编译器
│   └── uya.c        # 自举编译器输出的 C99 代码（已提交）
├── src/             # 编译器源代码（唯一维护源）
│   ├── main.uya     # 入口
│   ├── lexer.uya    # 词法分析
│   ├── parser.uya   # 语法分析
│   ├── checker.uya  # 类型检查 + 宏展开
│   ├── codegen/     # 代码生成
│   │   └── c99/     # C99 后端
│   └── ...
├── lib/             # 标准库
│   ├── std/         # 核心库
│   └── libc/        # C 库绑定
├── tests/           # 测试文件
│   └── programs/    # 348 个测试程序
├── docs/            # 文档
└── compiler-c/      # （已退役）C 编译器，仅供参考
```

---

## 自举验证详解

### `make b` 流程

```bash
# 1. 当前编译器编译自身 → bin/uya_bootstrap.c
bin/uya --c99 src/*.uya -o bin/uya_bootstrap.c

# 2. 对比新旧 C99 代码
diff bin/uya.c bin/uya_bootstrap.c

# 3. 一致则通过
```

### 验证失败处理

如果 `make b` 失败：

1. 检查是否有未提交的改动
2. 确认修改是否影响代码生成顺序
3. 排序相关的输出必须稳定（如 err_union 按名称排序）

---

## 发布流程

```bash
# 1. 确保测试通过
make tests-uya && make b

# 2. 更新版本号（如 v0.3.5）
# 编辑相关文档

# 3. 创建版本说明
vim docs/RELEASE_v0.3.5.md

# 4. 提交并打标签
git add -A
git commit -m "release: v0.3.5"
git tag -a v0.3.5 -m "v0.3.5: 版本描述"

# 5. 推送
git push origin main --tags
```

---

## 注意事项

### 已退役组件

- **compiler-c/**：C 语言实现的编译器，自 v0.3.4 起不再维护
- **make tests-c**：已废弃，仅保留 `make tests-uya`

### bin/uya.c 必须提交

- 这是仓库的"种子"，新克隆者从此开始
- 每次 `make uya` 后，如自举验证通过，应提交新的 bin/uya.c
- 确保提交的 bin/uya.c 能通过 `make tests-uya`

---

## 相关文档

- **回归测试说明**：[TESTING.md](./TESTING.md)
- **版本历史**：[RELEASE_*.md](./)
- **语言规范**：[uya.md](./uya.md)
- **变更日志**：[changelog.md](./changelog.md)

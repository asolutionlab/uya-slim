# Uya 编译器使用指南

## 安装

### 从源码构建

#### 系统要求

- GCC (支持 C99)
- Make
- Bash

#### 构建步骤

```bash
# 克隆仓库
git clone https://github.com/your-repo/uya.git
cd uya

# 从备份恢复并构建（首次构建）
make from-c

# 或者使用自举构建（需要已有编译器）
make uya
```

### 验证安装

```bash
# 验证编译器工作正常
make check

# 查看版本
./bin/uya --version
```

---

## 编译 Uya 程序

### 基本用法

```bash
# 编译 Uya 源文件生成 C 代码
./bin/uya source.uya -o output.c

# 编译并直接链接为可执行文件
./bin/uya source.uya -o output.c --link
```

### 命令行参数

| 参数 | 说明 |
|------|------|
| `-c <file>` | 指定输入源文件 |
| `-o <file>` | 指定输出文件名 |
| `--link` | 编译后自动链接为可执行文件 |
| `--safety-proof` | 启用内存安全证明 |
| `--no-safety-proof` | 禁用内存安全证明 |
| `--help` | 显示帮助信息 |
| `--version` | 显示版本信息 |

### 编译流程

```
Uya 源文件 (.uya)
       ↓
  词法/语法分析
       ↓
    AST 构建
       ↓
    类型检查
       ↓
   代码生成 (C99)
       ↓
   C 源文件 (.c)
       ↓
    GCC 编译
       ↓
   可执行文件
```

---

## 项目结构

```
uya/
├── bin/                    # 编译器二进制文件
│   ├── uya                 # 可执行文件
│   └── uya.c               # 自举 C 源码（种子文件）
├── src/                    # 编译器源代码
│   ├── main.uya            # 入口
│   ├── lexer.uya           # 词法分析器
│   ├── parser.uya          # 语法分析器
│   ├── checker.uya         # 类型检查器
│   ├── codegen/            # 代码生成器
│   └── ...
├── lib/                    # 标准库
│   ├── std/                # Uya 标准库
│   └── libc/               # C 标准库绑定
├── tests/                  # 测试文件
├── examples/               # 示例代码
└── docs/                   # 文档
```

---

## Make 命令速查

### 编译选项

可通过环境变量覆盖默认编译选项：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CFLAGS` | `-std=c99 -O0 -g -fno-builtin` | C 编译选项（默认调试模式） |
| `LDFLAGS` | （空） | 链接选项 |

```bash
# 使用自定义编译选项
CFLAGS='-std=c99 -O2' make from-c

# 构建发布版本（自动使用 -O3 优化）
make release
```

### 常用命令

| 命令 | 说明 |
|------|------|
| `make check` | 验证（自举 + 测试）**推荐** |
| `make uya` | 构建自举编译器 |
| `make b` | 自举验证 |
| `make tests-uya` | 运行测试 |
| `make from-c` | 从备份恢复并构建 |
| `make backup` | 验证 + 备份 |
| `make release` | 构建发布版本（-O3 优化） |
| `make clean` | 清理构建产物 |

---

## 内存安全证明

Uya 支持编译期内存安全证明，在编译时验证数组访问安全。

### 启用安全证明

```bash
./bin/uya --safety-proof source.uya -o output.c
```

### 安全证明示例

```uya
// 安全：编译器可以证明
fn safe_access() void {
    var arr: [i32: 10] = [...];
    var i: i32 = 5;
    
    if i >= 0 && i < 10 {
        arr[i] = 42;  // 安全：已验证边界
    }
}

// 不安全：编译错误
fn unsafe_access() void {
    var arr: [i32: 10] = [...];
    var i: i32 = get_value();  // 未知值
    
    arr[i] = 42;  // 编译错误：无法证明安全
}
```

### 安全证明规则

1. **边界检查**：数组索引必须在编译期可验证范围内
2. **空指针检查**：指针解引用前必须通过空检查
3. **未初始化检测**：变量使用前必须初始化

---

## 开发流程

### TDD 开发流程

```bash
# 1. 先写测试
vim tests/programs/test_new_feature.uya

# 2. 运行测试，确认失败
make tests-uya

# 3. 编写代码
vim src/related_module.uya

# 4. 验证
make check
```

### 自举验证

自举验证确保编译器能正确编译自身：

```bash
# 构建编译器
make uya

# 自举验证
make b
```

---

## 常见问题

### 编译段错误

如果编译时出现段错误，可能是栈空间不足：

```bash
# 增大栈限制
ulimit -s 65536

# 然后重新编译
make check
```

### 找不到编译器

```bash
# 从备份恢复
make from-c
```

### 测试失败

```bash
# 运行单个测试
./bin/uya tests/programs/test_xxx.uya -o /tmp/test.c
gcc /tmp/test.c -o /tmp/test && /tmp/test
```

---

## 更多资源

- [语法快速参考](grammar_quick.md)
- [语法正式规范](grammar_formal.md)
- [内置函数](builtin_functions.md)
- [测试指南](testing_guide.md)
- [变更日志](changelog.md)

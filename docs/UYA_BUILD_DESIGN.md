# Uya Build 命令设计文档

## 需求概述

`uya build` 命令应直接运行 gcc 编译出二进制文件，行为类似 gcc：

1. **无 `-o` 选项**：默认输出 `a.out` 二进制文件
2. **`-o <binary>`**：输出指定的二进制文件
3. **`-o <name>.c`**：输出 C 源代码文件（不调用 gcc 链接）

## 命令行为

### 1. 默认行为（无 -o）

```bash
uya build main.uya
# 输出: a.out（可执行文件）
# 流程: main.uya → /tmp/uya_xxx.c → a.out
```

### 2. 指定二进制输出

```bash
uya build main.uya -o myapp
# 输出: myapp（可执行文件）
# 流程: main.uya → /tmp/uya_xxx.c → myapp
```

### 3. 指定 C 源代码输出

```bash
uya build main.uya -o main.c
# 输出: main.c（C 源代码）
# 流程: main.uya → main.c（不调用 gcc 链接）
```

### 4. 使用 --nostdlib

```bash
uya build main.uya --nostdlib
# 输出: a.out（静态链接，零依赖）
# 流程: main.uya → /tmp/uya_xxx.c（含 _start）→ a.out
```

## 实现方案

### 修改 main.uya 中的 parse_args 函数

1. **移除 build 命令必须指定 -o 的限制**
   - 删除 `if command[0] == CommandType.COMMAND_BUILD && output_file_index[0] < 0` 的错误处理

2. **添加默认输出逻辑**
   - build 命令无 -o 时：
     - 输出 C 文件到临时目录 `/tmp/uya_<pid>.c`
     - 调用 gcc 链接为 `a.out`

3. **检测输出类型**
   - 如果 `-o` 参数以 `.c` 结尾：只生成 C 代码
   - 否则：生成 C 代码后调用 gcc 链接

### 编译流程

```
输入文件 (.uya)
    ↓
[词法分析 → 语法分析 → 类型检查 → C99 代码生成]
    ↓
C 源代码 (.c)
    ↓
[检测输出类型]
    ├─ 以 .c 结尾 → 直接输出 C 文件（结束）
    └─ 其他 → 调用 gcc 链接 → 可执行文件
```

### gcc 链接选项

```bash
# 普通模式
gcc -std=c99 -O2 /tmp/uya_xxx.c -o a.out

# --nostdlib 模式（零依赖）
gcc -std=c99 -O2 -nostdlib -fno-builtin -static /tmp/uya_xxx.c -o a.out
```

## 代码修改位置

### main.uya

1. **parse_args 函数**（约第 1237 行）
   - 删除 build 命令必须指定 -o 的错误检查
   - 添加默认输出路径生成逻辑

2. **main 函数**（约第 1792 行）
   - 添加 build 命令无 -o 时的处理逻辑
   - 添加调用 gcc 链接的功能

### 新增辅助函数

```uya
// 检测是否为 C 文件输出（以 .c 结尾）
fn is_c_output(output_path: &byte) i32 {
    if output_path == null { return 0; }
    const len: usize = strlen(output_path as *byte);
    if len < 2 { return 0; }
    return output_path[len - 2] == 46 as byte && output_path[len - 1] == 99 as byte;
}

// 调用 gcc 链接生成可执行文件
fn link_with_gcc(c_file: &byte, output: &byte, is_nostdlib: i32) i32 {
    // 构建命令: gcc [选项] c_file -o output
    // 执行 system() 调用
}
```

## 测试用例

```bash
# 测试 1: 默认输出 a.out
uya build hello.uya
./a.out
rm a.out

# 测试 2: 指定二进制输出
uya build hello.uya -o hello
./hello
rm hello

# 测试 3: 输出 C 源代码
uya build hello.uya -o hello.c
gcc -std=c99 hello.c -o hello
./hello

# 测试 4: --nostdlib 模式
uya build hello.uya --nostdlib
./a.out
```

## 兼容性说明

- 现有 `uya build file.uya -o file.c` 行为不变
- 新增默认输出 `a.out` 行为
- `uya run` 和 `uya test` 命令行为不变

## 实现优先级

1. 移除 build 命令必须指定 -o 的限制
2. 实现默认输出 a.out 的逻辑
3. 实现调用 gcc 链接的功能
4. 处理 --nostdlib 模式
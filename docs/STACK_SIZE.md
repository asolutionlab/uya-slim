# Uya 编译器自动堆栈大小设置

## 概述

Uya 编译器**默认设置 16MB 堆栈大小**，通过 `setrlimit` 系统调用在启动时自动设置。也可以通过 `--stack-size` 选项自定义堆栈大小。

## 默认设置

**默认堆栈大小：16MB (16384 KB)**

编译器在 `main()` 函数启动后会自动调用 `setrlimit(RLIMIT_STACK, ...)` 设置 16MB 堆栈限制。

**注意**：Makefile 在编译时也设置了 32MB 的临时堆栈限制（`ulimit -s 32768`），确保编译器有足够空间启动。

## 功能特性

### 1. 默认 16MB 堆栈

无需任何参数，编译器默认使用 16MB 堆栈：

```bash
# 使用默认 16MB 堆栈
bin/uya src/main.uya -o output.c --c99
```

**实现原理**：
- 编译器 `stack_size` 默认值为 `16384` (16MB)
- 在 `main()` 函数中调用 `sys_setrlimit(RLIMIT_STACK, &rlim)`
- 使用 Linux 系统调用直接设置当前进程的堆栈限制

### 2. compile.sh 集成

`compile.sh` 脚本的 `--stack-size` 选项会传递给编译器，由编译器在启动时设置。

```bash
# 设置 16MB 堆栈
./src/compile.sh --stack-size 16384 --c99 -e
```

**注意**：堆栈大小由 Uya 编译器代码中的 `setrlimit` 设置，不是通过 shell 的 `ulimit`。

### 2. 生成的 C 代码中的堆栈提示

当使用 `--stack-size` 选项编译时，生成的 C 代码会包含堆栈大小提示注释：

```c
// C99 代码由 Uya Mini 编译器生成
// 使用 -std=c99 编译
//
// 堆栈大小提示：此程序需要至少 8192 KB 的堆栈空间
// 编译时请使用：ulimit -s 8192
//
```

### 4. 帮助信息

```bash
# 查看编译器帮助
bin/uya --help | grep -A1 "stack-size"

# 查看 compile.sh 帮助
./src/compile.sh --help | grep -A1 "stack-size"
```

输出：
```
  --stack-size <KB>    设置堆栈大小（KB），默认自动设置
```

## 使用场景

### 场景 1：编译大型项目

当编译包含大量源代码或复杂泛型的项目时，编译器可能需要较大的栈空间：

```bash
# 使用默认 8MB 堆栈
./src/compile.sh --c99 -e

# 如果栈溢出，增加到 16MB
./src/compile.sh --stack-size 16384 --c99 -e
```

### 场景 2：运行需要大栈空间的程序

当运行包含大数组或深度递归的程序时：

```bash
# 编译时设置大堆栈
bin/uya --stack-size 16384 myprogram.uya -o myprogram.c --c99
gcc -std=c99 -O2 myprogram.c -o myprogram -lm

# 运行时设置堆栈（使用 ulimit）
ulimit -s 16384
./myprogram
```

### 场景 3：自举编译

自举编译编译器自身时，推荐使用较大的堆栈：

```bash
# 使用 16MB 堆栈进行自举
./src/compile.sh --stack-size 16384 --c99 -e -b
```

## 技术实现

### 编译器 (main.uya)

添加了 `--stack-size` 命令行参数解析：

```uya
var stack_size: i32 = 0;  // 堆栈大小（KB），0 表示自动设置

// 在 parse_args 中解析
if strcmp(arg, "--stack-size" as *byte) == 0 {
    // 解析参数值并设置
}
```

### 编译脚本 (compile.sh)

1. **脚本开头自动设置**：
```bash
# 在脚本开始时设置较大的堆栈大小（8MB）
ulimit -s 8192 2>/dev/null || true
```

2. **支持 --stack-size 选项**：
```bash
--stack-size)
    STACK_SIZE="$2"
    shift 2
    ;;
```

3. **编译时应用设置**：
```bash
if [ -n "$STACK_SIZE" ]; then
    ulimit -s "$STACK_SIZE" 2>/dev/null || true
else
    ulimit -s 8192 2>/dev/null || true
fi
```

## 推荐配置

| 场景 | 推荐堆栈大小 | 说明 |
|------|-------------|------|
| 日常开发 | 8MB (默认) | 适用于大多数情况 |
| 大型项目编译 | 16MB | 包含 50+ 源文件 |
| 自举编译 | 16MB | 编译编译器自身 |
| 深度递归程序 | 32MB+ | 根据实际需求调整 |

## 注意事项

1. **ulimit 限制**：`ulimit -s` 设置受系统限制，可能需要 root 权限才能设置超过系统限制的值

2. **跨平台兼容性**：`ulimit` 命令在 Linux/Unix 系统上有效，Windows 需要使用其他方式

3. **内存消耗**：过大的堆栈设置会消耗更多系统内存，应根据实际需求调整

4. **调试栈溢出**：如果程序栈溢出，可以逐步增加堆栈大小直到问题解决：
   ```bash
   # 从 8MB 开始
   ./src/compile.sh --stack-size 8192 --c99 -e
   
   # 如果失败，增加到 16MB
   ./src/compile.sh --stack-size 16384 --c99 -e
   
   # 继续增加直到成功
   ```

## 示例

### 示例 1：编译编译器自身

```bash
cd /media/winger/_dde_home/winger/uya

# 使用默认堆栈大小
./src/compile.sh --c99 -e

# 使用 16MB 堆栈（推荐用于自举）
./src/compile.sh --stack-size 16384 --c99 -e
```

### 示例 2：编译大型项目

```bash
# 编译大型项目
bin/uya --stack-size 16384 large_project.uya -o large_project.c --c99
gcc -std=c99 -O3 large_project.c -o large_project -lm
./large_project
```

## 故障排除

### 问题：段错误（Segmentation Fault）

**症状**：编译过程中出现段错误

**解决方案**：
```bash
# 增加堆栈大小
./src/compile.sh --stack-size 32768 --c99 -e

# 或者在运行前设置
ulimit -s 32768
./src/compile.sh --c99 -e
```

### 问题：ulimit 设置失败

**症状**：`ulimit: stack size: cannot modify limit: Operation not permitted`

**解决方案**：
- 检查系统限制：`ulimit -a`
- 可能需要修改 `/etc/security/limits.conf`
- 或者联系系统管理员

## 相关文档

- [DEVELOPMENT.md](./docs/DEVELOPMENT.md) - 开发指导
- [usage_guide.md](./docs/usage_guide.md) - 编译器使用指南
- [compile.sh](./src/compile.sh) - 编译脚本源码

## 版本历史

- **v0.7.5** (2026-02-26): 初始版本，添加自动和手动堆栈大小设置功能

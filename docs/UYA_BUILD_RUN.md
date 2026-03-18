# Uya build/run 与宿主工具链说明

## 概述

Uya 编译器支持 `build` 和 `run` 子命令，可以在生成 C99 之后自动调用**宿主工具链**完成链接。

当前共享工具链模型已经统一为：

- `HOST_OS` / `HOST_ARCH`
- `TARGET_OS` / `TARGET_ARCH` / `TARGET_TRIPLE`
- `RUNTIME_MODE`
- `LINK_MODE`
- `TOOLCHAIN`
- `CC`
- `CC_DRIVER`
- `CC_TARGET_FLAGS`

默认仍可使用系统 `cc` / `clang` / `gcc`，但对于 Linux、macOS、Windows 与交叉编译统一入口，推荐优先使用 `zig cc`。

## 使用方法

### 方式一：使用包装脚本（推荐）

```bash
# build 命令：编译并链接
./bin/uya-wrapper.sh build input.uya -o output.c --c99

# run 命令：编译、链接并运行
./bin/uya-wrapper.sh run input.uya -o output.c --c99
```

包装脚本会自动添加 `-e` 选项，触发 compile.sh 中的自动链接逻辑。

### 方式二：手动添加 -e 选项

```bash
# 直接使用编译器
bin/uya build input.uya -o output.c --c99 -e

# run 命令
bin/uya run input.uya -o output.c --c99 -e
```

### 方式二点五：显式选择 zig cc

```bash
# 使用 /home/winger/zig/zig 作为统一工具链
TOOLCHAIN=zig ZIG=/home/winger/zig/zig bin/uya build input.uya -o output.c --c99 -e

# 等价写法：直接指定 CC_DRIVER
CC_DRIVER="/home/winger/zig/zig cc" bin/uya build input.uya -o output.c --c99 -e
```

### 方式三：使用 compile.sh

```bash
cd src
./compile.sh --c99 -e input.uya
```

## 链接选项

`compile.sh` 在 `-e` 模式下会自动使用宿主工具链。逻辑上区分两条路径：

```bash
# hosted 模式（默认）
${CC_DRIVER:-cc} ${CC_TARGET_FLAGS} -std=c99 -fno-builtin input.c -o output

# --nostdlib 模式（当前仅 Linux x86_64 已实现）
${CC_DRIVER:-cc} ${CC_TARGET_FLAGS} -std=c99 -fno-builtin -nostdlib -static input.c -o output -lgcc
```

如果设置了 `TARGET_TRIPLE` 且未手动设置 `CC_TARGET_FLAGS`，脚本会自动补出 `-target <triple>`。

## 工作原理

1. **包装脚本** (`uya-wrapper.sh`):
   - 检测 `build`/`run` 子命令
   - 自动添加 `-e` 选项
   - 调用实际编译器

2. **compile.sh**:
   - 检测 `-e` 选项
   - C99 编译成功后，调用宿主工具链链接
   - `--nostdlib` 模式下向编译器传入 `--nostdlib`，由生成 C 内含 `_start`（不再拼接重复序言）
   - 非 Linux 目标的 `--nostdlib` 当前会直接报“未实现”，不再误走 Linux `_start`

3. **生成的 C 代码**:
   - 包含 `#include <stdlib.h>` 用于 `exit` 等函数
   - 包含 `#include <sys/resource.h>` 用于 `setrlimit`

## 推荐工具链

### 原生 Linux / macOS

```bash
# 使用系统工具链
make uya-hosted

# 使用 zig cc 统一工具链
TOOLCHAIN=zig ZIG=/home/winger/zig/zig make uya-hosted
```

### Windows hosted 交叉链接

```bash
TOOLCHAIN=zig \
ZIG=/home/winger/zig/zig \
TARGET_OS=windows \
TARGET_ARCH=x86_64 \
TARGET_TRIPLE=x86_64-windows-gnu \
make uya-hosted
```

### Darwin hosted 交叉链接

```bash
TOOLCHAIN=zig \
ZIG=/home/winger/zig/zig \
TARGET_OS=macos \
TARGET_ARCH=arm64 \
TARGET_TRIPLE=aarch64-macos-none \
make uya-hosted
```

注意：

- `zig cc` 是当前推荐的**统一构建驱动**，特别适合共享基础、Windows 目标和交叉编译。
- 原生平台 bring-up 时仍可继续使用系统 `cc` / `clang` 做对照验证。
- 交叉产出“能否运行”仍取决于目标平台 ABI、runtime、`@syscall`、`pthread`、`std.async` 等后续迁移状态。

## 示例

```bash
# 创建测试文件
cat > /tmp/test.uya << 'EOF'
export fn main() i32 {
    return 42;
}
EOF

# 使用 zig cc 统一工具链编译
TOOLCHAIN=zig ZIG=/home/winger/zig/zig ./bin/uya-wrapper.sh build /tmp/test.uya -o /tmp/test.c --c99

# 运行生成的可执行文件
/tmp/test
echo "退出码：$?"  # 输出 42
```

## 注意事项

1. **0 依赖限制**:
   - 不能使用标准库函数（printf, malloc 等）
   - 需要使用 libc 模块的系统调用
   - 参考 `lib/libc/` 下的实现

2. **_start 入口**:
   - `--nostdlib` 模式下，编译器在生成 C 中写入 `_start`；`compile.sh` 直接编译该 C 并链接 `crti.o`/`crtn.o`
   - 支持 x86-64 Linux 平台

3. **平台支持**:
   - `hosted` 路径已具备 host/target/toolchain 统一入口
   - `--nostdlib` 目前仍仅支持 Linux x86-64
   - Darwin / Windows / full cross-platform 仍需后续平台迁移文档逐步落地

## 相关文件

- `bin/uya-wrapper.sh` - 包装脚本
- `src/compile.sh` - 编译脚本（包含工具链与链接逻辑）
- `Makefile` - 顶层 host/target/toolchain 入口
- `lib/std/runtime/entry/entry.uya` - C main 入口（设置堆栈大小）

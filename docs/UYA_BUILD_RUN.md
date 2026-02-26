# Uya build/run 命令自动执行 gcc 说明

## 概述

Uya 编译器支持 `build` 和 `run` 子命令，可以自动调用 gcc 链接生成可执行文件，使用 `-nostdlib -fno-builtin` 实现 0 依赖。

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

### 方式三：使用 compile.sh

```bash
cd src
./compile.sh --c99 -e input.uya
```

## 链接选项

compile.sh 在 `-e` 模式下会自动使用以下 gcc 选项：

```bash
# --nostdlib 模式（0 依赖）
gcc -std=c99 -nostdlib -fno-builtin -static -o output input.c

# 普通模式（使用标准库）
gcc -std=c99 -o output input.c
```

## 工作原理

1. **包装脚本** (`uya-wrapper.sh`):
   - 检测 `build`/`run` 子命令
   - 自动添加 `-e` 选项
   - 调用实际编译器

2. **compile.sh**:
   - 检测 `-e` 选项
   - C99 编译成功后，调用 gcc 链接
   - `--nostdlib` 模式下嵌入 `_start` 内联汇编

3. **生成的 C 代码**:
   - 包含 `#include <stdlib.h>` 用于 `exit` 等函数
   - 包含 `#include <sys/resource.h>` 用于 `setrlimit`

## 示例

```bash
# 创建测试文件
cat > /tmp/test.uya << 'EOF'
export fn main() i32 {
    return 42;
}
EOF

# 使用包装脚本编译
./bin/uya-wrapper.sh build /tmp/test.uya -o /tmp/test.c --c99

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
   - `--nostdlib` 模式下，compile.sh 会自动嵌入 `_start` 内联汇编
   - 支持 x86-64 Linux 平台

3. **平台支持**:
   - 目前仅支持 Linux x86-64
   - 其他平台需要修改 `_start` 内联汇编

## 相关文件

- `bin/uya-wrapper.sh` - 包装脚本
- `src/compile.sh` - 编译脚本（包含链接逻辑）
- `lib/std/runtime/entry/entry.uya` - C main 入口（设置堆栈大小）

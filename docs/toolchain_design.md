# Uya 工具链模块化架构设计文档

## 1. 概述

Uya 工具链采用**子命令独立程序**架构，每个子命令是一个独立的小程序，`uya` 作为主入口进行转发。

```
┌──────────────────────────────────────────────────────┐
│                       uya                            │
│                    (主入口)                          │
├──────────────────────────────────────────────────────┤
│  uya build  ──────▶ uya-build  (编译器)             │
│  uya check  ──────▶ uya-check  (前端检查器)         │
│  uya run    ──────▶ uya-run    (编译并运行)         │
│  uya test   ──────▶ uya-test   (测试运行器)         │
│  uya lint   ──────▶ uya-lint   (静态分析)           │
│  uya doc    ──────▶ uya-doc    (文档生成)           │
└──────────────────────────────────────────────────────┘
```

这种架构的优势：
- ✅ **模块化**：每个工具独立开发、测试、发布
- ✅ **可替换**：用户可以用自定义工具替换默认工具
- ✅ **轻量**：只需安装需要的工具
- ✅ **并行编译**：多个工具可同时构建
- ✅ **类似 Git/Rust**：用户熟悉的命令模式

---

## 2. 架构总览

### 2.1 目录结构

```
uya-asm/
├── src/
│   ├── main.uya           # uya 主入口（转发器）
│   ├── tools/             # 独立工具目录
│   │   ├── build.uya      # uya-build 入口
│   │   ├── check.uya      # uya-check 入口
│   │   ├── run.uya        # uya-run 入口
│   │   ├── test.uya       # uya-test 入口
│   │   ├── lint.uya       # uya-lint 入口（未来）
│   │   └── doc.uya        # uya-doc 入口（未来）
│   ├── checker/           # 类型检查器（共享）
│   ├── parser/            # 解析器（共享）
│   ├── lexer.uya          # 词法分析（共享）
│   └── ast.uya            # AST 定义（共享）
├── lib/                   # 标准库
│   ├── std/
│   └── libc/
├── bin/                   # 编译输出
│   ├── uya                # 主入口
│   ├── uya-build
│   ├── uya-check
│   ├── uya-run
│   └── uya-test
└── Makefile
```

### 2.2 工具职责划分

| 工具 | 职责 | 入口文件 | 依赖模块 |
|------|------|----------|----------|
| `uya` | 子命令转发 | `main.uya` | 无 |
| `uya-build` | 编译为可执行文件 | `tools/build.uya` | lexer, parser, checker, codegen |
| `uya-check` | 只执行到 checker | `tools/check.uya` | lexer, parser, checker |
| `uya-run` | 编译并运行 | `tools/run.uya` | build (调用) |
| `uya-test` | 运行测试 | `tools/test.uya` | build (调用) |

### 2.3 依赖关系图

```
                    ┌─────────┐
                    │   uya   │ (转发器)
                    └────┬────┘
                         │ exec()
        ┌───────┬───────┐
        ▼       ▼       ▼
   ┌────────┐┌────────┐┌────────┐
   │uya-build││uya-run ││uya-test│
   └───┬────┘└───┬────┘└───┬────┘
       │         │         │
       ▼         │         │
┌───────────────┐ │         │
│ 共享编译核心   │ │         │
│ • lexer       │ │         │
│ • parser      │ │         │
│ • checker     │ │         │
│ • codegen     │ │         │
└───────────────┘ │         │
       ▲         │         │
       │         ▼         ▼
       │    调用 uya-build 调用 uya-build
       │    然后 exec()    然后 exec()
```

---

## 3. 主入口设计（uya）

### 3.1 main.uya - 极简转发器

```uya
// main.uya - uya 主入口（转发器）
// 职责：解析子命令，转发到对应工具

use libc;
use libc.stdio;
use libc.stdlib;
use libc.string;
use libc.unistd;  // execv

const PATH_MAX: usize = 4096;

// 子命令映射
const TOOL_COUNT: i32 = 4;
const TOOL_NAMES: [&byte: 4] = [
    "build" as *byte,
    "run" as *byte,
    "test" as *byte,
    "lint" as *byte
];

const TOOL_BINS: [&byte: 4] = [
    "uya-build" as *byte,
    "uya-run" as *byte,
    "uya-test" as *byte,
    "uya-lint" as *byte
];

// 打印使用说明
fn print_usage(program_name: &byte) void {
    fprintf(libc.stderr, "Uya - 零GC系统编程语言工具链\n" as *byte);
    fprintf(libc.stderr, "\n用法:\n" as *byte);
    fprintf(libc.stderr, "  %s <命令> [选项] [文件]\n" as *byte, program_name as *byte);
    fprintf(libc.stderr, "\n命令:\n" as *byte);
    fprintf(libc.stderr, "  build    编译为可执行文件\n" as *byte);
    fprintf(libc.stderr, "  run      编译并运行\n" as *byte);
    fprintf(libc.stderr, "  test     运行测试\n" as *byte);
    fprintf(libc.stderr, "  lint     静态分析（开发中）\n" as *byte);
    fprintf(libc.stderr, "\n运行 '%s <命令> --help' 获取更多信息\n" as *byte, program_name as *byte);
}

// 查找工具可执行文件
fn find_tool_binary(tool_name: &byte, buffer: &byte, buffer_size: usize) i32 {
    // 方式1：从编译器所在目录查找
    const argv0: *byte = get_argv(0);
    if argv0 != null {
        // 提取目录
        const last_slash: *byte = strrchr(argv0, 47);  // '/'
        if last_slash != null {
            const dir_len: usize = ptr_diff(last_slash, argv0 as &byte) + 1;
            if dir_len + strlen(tool_name as *byte) + 1 < buffer_size {
                memcpy(buffer as *void, argv0 as *void, dir_len);
                strcpy(buffer + dir_len, tool_name as *byte);
                
                // 检查文件是否存在且可执行
                if access(buffer as *byte, 1) == 0 {  // X_OK = 1
                    return 0;
                }
            }
        }
    }
    
    // 方式2：从 PATH 环境变量查找
    const path_env: *byte = getenv("PATH" as *byte);
    if path_env != null {
        // 解析 PATH，逐个目录查找
        var path_copy: [byte: 4096] = [];
        strcpy(&path_copy[0], path_env);
        
        var start: &byte = &path_copy[0];
        while start[0] != 0 {
            // 找到下一个冒号或结尾
            var end: &byte = start;
            while end[0] != 0 && end[0] != 58 {  // ':'
                end = end + 1;
            }
            
            // 提取目录
            const dir_len: usize = ptr_diff(end, start);
            if dir_len + strlen(tool_name as *byte) + 2 < buffer_size {
                memcpy(buffer as *void, start as *void, dir_len);
                buffer[dir_len] = 47 as byte;  // '/'
                strcpy(buffer + dir_len + 1, tool_name as *byte);
                
                if access(buffer as *byte, 1) == 0 {
                    return 0;
                }
            }
            
            // 移动到下一个目录
            if end[0] == 58 {
                start = end + 1;
            } else {
                break;
            }
        }
    }
    
    return -1;  // 未找到
}

// 主函数
export fn main() i32 {
    const argc: i32 = get_argc();
    
    if argc < 2 {
        var name: &byte = "uya" as *byte;
        const argv0: *byte = get_argv(0);
        if argv0 != null {
            name = argv0 as &byte;
        }
        print_usage(name);
        return 1;
    }
    
    const first_arg: *byte = get_argv(1);
    if first_arg == null {
        fprintf(libc.stderr, "错误: 无法获取命令参数\n" as *byte);
        return 1;
    }
    
    // 检查是否是帮助请求
    if strcmp(first_arg, "-h" as *byte) == 0 || 
       strcmp(first_arg, "--help" as *byte) == 0 ||
       strcmp(first_arg, "help" as *byte) == 0 {
        var name: &byte = "uya" as *byte;
        const argv0: *byte = get_argv(0);
        if argv0 != null {
            name = argv0 as &byte;
        }
        print_usage(name);
        return 0;
    }
    
    // 检查是否是版本请求
    if strcmp(first_arg, "-v" as *byte) == 0 || 
       strcmp(first_arg, "--version" as *byte) == 0 ||
       strcmp(first_arg, "version" as *byte) == 0 {
        fprintf(libc.stderr, "Uya v0.9.2\n" as *byte);
        return 0;
    }
    
    // 查找对应的工具
    var tool_bin: &byte = null;
    var i: i32 = 0;
    while i < TOOL_COUNT {
        if strcmp(first_arg, TOOL_NAMES[i]) == 0 {
            tool_bin = TOOL_BINS[i];
            break;
        }
        i = i + 1;
    }
    
    if tool_bin == null {
        fprintf(libc.stderr, "错误: 未知命令 '%s'\n" as *byte, first_arg);
        fprintf(libc.stderr, "运行 'uya --help' 查看可用命令\n" as *byte);
        return 1;
    }
    
    // 查找工具可执行文件
    var tool_path: [byte: PATH_MAX] = [];
    if find_tool_binary(tool_bin, &tool_path[0] as &byte, PATH_MAX) != 0 {
        fprintf(libc.stderr, "错误: 未找到工具 '%s'\n" as *byte, tool_bin as *byte);
        fprintf(libc.stderr, "请确保 uya 工具链已正确安装\n" as *byte);
        return 1;
    }
    
    // 构建参数数组（跳过第一个参数，保留子命令名）
    // argv[0] = tool_path, argv[1..] = 原始参数[2..]
    var argv_array: [&byte: 128] = [];
    argv_array[0] = &tool_path[0];
    
    var arg_count: i32 = 1;
    i = 2;  // 从第3个参数开始
    while i < argc && arg_count < 127 {
        const arg: *byte = get_argv(i);
        if arg != null {
            argv_array[arg_count] = arg;
            arg_count = arg_count + 1;
        }
        i = i + 1;
    }
    argv_array[arg_count] = null;
    
    // 执行工具
    execv(&tool_path[0], &argv_array[0]);
    
    // 如果 execv 返回，说明执行失败
    fprintf(libc.stderr, "错误: 无法执行 '%s'\n" as *byte, &tool_path[0] as *byte);
    return 1;
}
```

---

## 4. 独立工具设计

### 4.1 uya-build - 编译器

`src/tools/build.uya`：

```uya
// build.uya - uya-build 入口
// 职责：编译 Uya 代码为可执行文件

use main;  // 收集同目录模块
use parser;
use checker;
use codegen.c99;
use std.runtime.entry;
use libc;
use libc.stdlib;
use libc.syscall;

// 编译统计结构体
struct CompileStats {
    parse_time_ms: i64,
    check_time_ms: i64,
    codegen_time_ms: i64,
    total_time_ms: i64,
    file_count: i32,
}

// 打印使用说明
fn print_usage(program_name: &byte) void {
    fprintf(libc.stderr, "Uya 编译器 - 编译为可执行文件\n" as *byte);
    fprintf(libc.stderr, "\n用法:\n" as *byte);
    fprintf(libc.stderr, "  %s <文件> [-o <输出>] [选项]\n" as *byte, program_name as *byte);
    fprintf(libc.stderr, "\n选项:\n" as *byte);
    fprintf(libc.stderr, "  -o <文件>            指定输出文件名\n" as *byte);
    fprintf(libc.stderr, "  --c99                生成 C99 代码\n" as *byte);
    fprintf(libc.stderr, "  --opt=<0-3>          优化级别\n" as *byte);
    fprintf(libc.stderr, "  -O0, -O1, -O2, -O3   优化级别（简写）\n" as *byte);
    fprintf(libc.stderr, "  --safety-proof       启用内存安全证明\n" as *byte);
    fprintf(libc.stderr, "  --nostdlib           无标准库模式\n" as *byte);
    fprintf(libc.stderr, "  -h, --help           显示帮助\n" as *byte);
}

// 主函数
export fn main() i32 {
    const argc: i32 = get_argc();
    if argc < 2 {
        print_usage("uya-build" as *byte);
        return 1;
    }
    
    // 检查帮助
    const first_arg: *byte = get_argv(1);
    if first_arg != null && 
       (strcmp(first_arg, "-h" as *byte) == 0 || 
        strcmp(first_arg, "--help" as *byte) == 0) {
        print_usage("uya-build" as *byte);
        return 0;
    }
    
    // 调用编译核心（复用现有 compile_files 函数）
    // ... 编译逻辑 ...
    
    fprintf(libc.stderr, "编译完成\n" as *byte);
    return 0;
}
```

### 4.2 uya-run - 编译并运行

`src/tools/run.uya`：

```uya
// run.uya - uya-run 入口
// 职责：编译代码并运行

use libc;
use libc.stdio;
use libc.stdlib;

fn print_usage(program_name: &byte) void {
    fprintf(libc.stderr, "Uya 运行器 - 编译并运行\n" as *byte);
    fprintf(libc.stderr, "\n用法:\n" as *byte);
    fprintf(libc.stderr, "  %s <文件> [编译选项] [-- <运行参数>]\n" as *byte, program_name as *byte);
    fprintf(libc.stderr, "\n选项:\n" as *byte);
    fprintf(libc.stderr, "  -- <参数>  传递给程序的参数\n" as *byte);
}

export fn main() i32 {
    // 1. 解析参数，找到 -- 分隔符
    // 2. 调用 uya-build 编译
    // 3. 执行生成的可执行文件
    
    var build_cmd: [byte: 4096] = [];
    // ... 构建命令 ...
    
    // 编译
    const build_result: i32 = system(&build_cmd[0]);
    if build_result != 0 {
        return build_result;
    }
    
    // 运行
    const run_result: i32 = system("/tmp/uya_out");
    return run_result;
}
```

### 4.3 uya-test - 测试运行器

`src/tools/test.uya`：

```uya
// test.uya - uya-test 入口
// 职责：运行测试用例

use libc;
use libc.stdio;

// 测试结果
struct TestResult {
    passed: i32,
    failed: i32,
    skipped: i32,
}

fn print_usage(program_name: &byte) void {
    fprintf(libc.stderr, "Uya 测试运行器\n" as *byte);
    fprintf(libc.stderr, "\n用法:\n" as *byte);
    fprintf(libc.stderr, "  %s <文件或目录> [选项]\n" as *byte, program_name as *byte);
    fprintf(libc.stderr, "\n选项:\n" as *byte);
    fprintf(libc.stderr, "  -v, --verbose  详细输出\n" as *byte);
    fprintf(libc.stderr, "  --filter <模式> 过滤测试\n" as *byte);
}

export fn main() i32 {
    // 1. 查找测试文件
    // 2. 编译测试
    // 3. 运行并收集结果
    
    fprintf(libc.stderr, "运行测试...\n" as *byte);
    
    // ... 测试逻辑 ...
    
    return 0;
}
```

### 4.4 Formatter（已移除）

Formatter 功能已删除，工具链不再提供 `uya-fmt` 或 `uya fmt`。


---

## 5. 共享模块

### 5.1 编译核心模块

`src/core/` 目录，供 build/check/run/test 共享：

```
src/core/
├── compiler.uya    # 编译器核心（compile_files）
├── dependency.uya  # 依赖收集
├── linker.uya      # 链接器接口
└── config.uya      # 编译配置
```

### 5.2 解析核心模块

`src/parser/` 和 `src/lexer.uya`，供所有工具共享：

```
src/
├── lexer.uya       # 词法分析
├── ast.uya         # AST 定义
├── arena.uya       # 内存管理
└── parser/         # 语法分析
    ├── main.uya
    ├── expr.uya
    └── stmt.uya
```

---

## 6. 构建流程

### 6.1 Makefile

```makefile
# 工具链
TOOLS = bin/uya bin/uya-build bin/uya-run bin/uya-test

# 默认目标
all: $(TOOLS)

# 主入口（转发器）
bin/uya: src/main.uya
	./bin/uya build src/main.uya -o bin/uya.c --c99
	gcc -O2 -o bin/uya bin/uya.c

# 编译器
bin/uya-build: src/tools/build.uya src/core/*.uya src/parser/*.uya
	./bin/uya build src/tools/build.uya -o bin/uya-build.c --c99
	gcc -O2 -o bin/uya-build bin/uya-build.c

# 运行器
bin/uya-run: src/tools/run.uya
	./bin/uya build src/tools/run.uya -o bin/uya-run.c --c99
	gcc -O2 -o bin/uya-run bin/uya-run.c

# 测试运行器
bin/uya-test: src/tools/test.uya
	./bin/uya build src/tools/test.uya -o bin/uya-test.c --c99
	gcc -O2 -o bin/uya-test bin/uya-test.c

# 安装
install: $(TOOLS)
	install -m 755 bin/uya /usr/local/bin/
	install -m 755 bin/uya-build /usr/local/bin/
	install -m 755 bin/uya-run /usr/local/bin/
	install -m 755 bin/uya-test /usr/local/bin/

# 清理
clean:
	rm -f bin/uya bin/uya-build bin/uya-run bin/uya-test
	rm -f bin/*.c
```

### 6.2 自举构建

```bash
# 第一阶段：用现有编译器构建工具链
make all

# 第二阶段：用新编译器自举
make clean
bin/uya-build src/tools/build.uya -o bin/uya-build.c --c99
gcc -O2 -o bin/uya-build bin/uya-build.c
# ... 重复其他工具 ...
```

---

## 7. 使用示例

### 7.1 直接使用工具

```bash
# 编译
uya-build main.uya -o myapp

# 运行
uya-run main.uya

# 测试
uya-test tests/

```

### 7.2 通过主入口使用

```bash
# 编译
uya build main.uya -o myapp

# 运行
uya run main.uya

# 测试
uya test tests/

```

### 7.3 CI 集成

```yaml
# .github/workflows/ci.yml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build
        run: uya-build src/main.uya -o app
        
      - name: Test
        run: uya-test tests/
        
```

---

## 8. 与其他工具链对比

| 工具链 | 架构 | 主入口 | 子命令 |
|--------|------|--------|--------|
| **Git** | 独立程序 | `git` | `git-add`, `git-commit` |
| **Rust** | 独立程序 | `cargo` | `rustc`, `rustfmt`, `clippy` |
| **Go** | 内置 | `go` | 内置子命令 |
| **Uya** | 独立程序 | `uya` | `uya-build`, `uya-run`, `uya-test` |

Uya 采用类似 Git 的架构：
- `uya` 是极简转发器（~100 行）
- 每个子命令是独立程序
- 通过 `execv()` 调用，无缝传递参数

---

## 9. 迁移计划

### Phase 1：重构入口（不破坏现有功能）

1. 创建 `src/tools/` 目录
2. 将 `main.uya` 改为转发器
3. 创建 `build.uya` 作为独立编译器入口
4. 保持 `make check` 正常工作

### Phase 2：添加新工具

1. 创建 `run.uya`（调用 uya-build）
2. 创建 `test.uya`（调用 uya-build）

### Phase 3：优化共享模块

1. 提取 `src/core/compiler.uya`
2. 统一配置管理
3. 优化构建时间

---

## 10. 总结

**独立程序架构** 的核心优势：

1. **模块化**：每个工具独立开发、测试
2. **可扩展**：添加新工具不影响现有工具
3. **可替换**：用户可自定义工具
4. **性能**：只加载需要的代码
5. **用户体验**：`uya build` 和 `uya-build` 两种方式都可用

这种架构既保持了简洁的用户界面，又提供了灵活的底层实现。

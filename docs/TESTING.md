# Uya 回归测试说明

**版本**：v0.3.4+  
**更新日期**：2026-05-19

---

## 测试框架

自 v0.3.4 起，所有测试使用 `std.testing` 框架：

```uya
use std.testing.*;

fn test_feature() !void {
    try expect_eq(actual, expected, "description");
}

export fn main() i32 {
    test_suite_begin("Module Tests");
    run_test("feature", test_feature);
    return test_suite_end();
}
```

---

## 运行测试

### 语法 / checker 快速检查

在跑完整回归前，建议先用 `check` 做单文件快速验证：

```bash
bin/uya check tests/check_cli_no_main.uya
bin/uya check tests/error_check_missing_brace.uya
```

`check` 只跑到 checker，不生成 C、不链接、不执行程序，适合先确认语法错误、模块解析错误和类型错误。

### 完整测试套件

```bash
make tests-uya
```

输出示例：
```
================================
总计: 348 个测试
通过: 348
失败: 0
================================
```

### 并行测试

```bash
./tests/run_programs_parallel.sh
```

### Exec VM 专项回归

当改动涉及 `src/exec/`、`lib/libc/stdio.uya`、`try/catch` lowering、`@syscall` exec 路径或 `extern ABI` 边界时，建议先跑这批脚本：

```bash
bash ./tests/verify_exec_backend_progress.sh
bash ./tests/verify_exec_vm_stdio_varargs.sh
bash ./tests/verify_exec_vm_extern_bridge.sh
bash ./tests/verify_exec_vm_compiler_regressions.sh
```

其中：

- `verify_exec_vm_stdio_varargs.sh` 覆盖 `va_list` / `@va_start` / `@va_arg` / `@va_copy`，以及 `fprintf -> vfprintf -> _vfprintf_impl -> snprintf` 的 exec VM 路径
- `verify_exec_vm_compiler_regressions.sh` 覆盖“显式类型局部 + catch 标识符路径”和“字段数组 / 指针字段 / 全局数组下标写入路径”两类近期修复过的编译器回归

### 单个测试

```bash
bin/uya build tests/programs/test_basic.uya -o /tmp/test.c --c99
gcc -std=c99 /tmp/test.c -o /tmp/test -lm
/tmp/test
```

对于带 `_start` 的 `--nostdlib` 产物，链接方式需改成仓库当前使用的 freestanding 方式。例如：

```bash
bin/uya build --c99 --nostdlib tests/test_std_sql.uya -o /tmp/test_std_sql.c
gcc -std=c99 -nostdlib -static -no-pie /tmp/test_std_sql.c -o /tmp/test_std_sql
/tmp/test_std_sql
```

### 带 `@c_import` 的单个测试

如果测试文件包含 `@c_import`，有两种推荐方式：

1. 直接让编译器生成并链接可执行文件：

```bash
bin/uya build tests/test_c_import_file.uya -o /tmp/test_c_import_file --c99
/tmp/test_c_import_file
```

2. 只生成 C，再使用 sidecar 完成手动链接：

```bash
bin/uya build tests/test_c_import_dir.uya -o /tmp/test_c_import_dir.c --c99 --no-split-c
CC=gcc ./tests/link_cimports_posix.sh /tmp/test_c_import_dir.c /tmp/test_c_import_dir.bin
/tmp/test_c_import_dir.bin
```

说明：
- 当单文件 C 输出路径中检测到 `@c_import` 时，编译器会额外生成 `/tmp/test_c_import_dir.cimports.sh`
- 该 sidecar 保存了导入的 C 源、相对路径、逐 token 的 `cflags` 和聚合后的 `ldflags`
- `tests/link_cimports_posix.sh` 会读取 sidecar，先编译导入的 C object，再与主 `.c` 一起链接
- 若走 split-C / `--split-c-dir` 路径，导入的 C object 会直接进入 Makefile，不会额外生成 sidecar

---

## 测试分类

| 类别 | 文件前缀 | 数量 |
|------|----------|------|
| 基础语法 | `test_basic*.uya` | ~20 |
| 类型系统 | `test_type*.uya` | ~30 |
| 函数 | `test_fn*.uya` | ~15 |
| 结构体 | `test_struct*.uya` | ~20 |
| 联合体 | `test_union*.uya` | ~10 |
| 接口 | `test_interface*.uya` | ~10 |
| 错误处理 | `test_error*.uya`, `test_try*.uya` | ~15 |
| 宏 | `test_macro*.uya` | ~10 |
| 泛型 | `test_generic*.uya` | ~10 |
| 切片 | `test_slice*.uya` | ~15 |
| 指针 | `test_pointer*.uya` | ~20 |
| 标准库 | `test_std_*.uya`, `test_crypto_*.uya` | ~25 |
| libc | `test_ctype.uya`, `test_stdio.uya` 等 | ~10 |
| 其他 | 其他 | ~143 |

---

## 自举验证

```bash
make b
```

自举验证流程：
1. `bin/uya` 编译 `src/*.uya` → `bin/uya_bootstrap.c`
2. 对比 `bin/uya.c` 与 `bin/uya_bootstrap.c`
3. 一致则通过

如果你是在调试发布链路，也可以临时跑：

```bash
make release-dirty
```

它会在当前工作树里强行执行完整 release 流程，但不会替代 `make release` 或 `make release-clean` 作为最终结论。

---

## 测试编写规范

### 断言函数

| 函数 | 用途 |
|------|------|
| `expect_eq(actual, expected, msg)` | 通用相等断言 |
| `expect_true(cond, msg)` | 布尔断言 |
| `assert_eq_i32(a, b, msg)` | i32 相等 |
| `assert_eq_i64(a, b, msg)` | i64 相等 |
| `assert_eq_u64(a, b, msg)` | u64 相等 |

### 测试命名

- 文件名：`test_<功能>.uya`
- 测试函数：`test_<功能>_<场景>()`
- 新增标准库模块时，优先补对应回归文件，如 `tests/test_std_sql.uya`

### 错误处理

测试函数返回 `!void`，错误即测试失败：

```uya
fn test_division() !void {
    const result = divide(10, 2) catch |err| {
        return error.TestFailed;  // 显式失败
    };
    try expect_eq(result, 5, "10/2 should equal 5");
}
```

---

## CI 集成

推荐 CI 流程：

```yaml
test:
  script:
    - gcc -std=c99 -O2 bin/uya.c -o bin/uya -lm
    - make tests-uya
    - make b
```

---

## 测试覆盖率

当前状态：
- **总测试数**：约 829（`tests/*.uya` + `tests/multifile/*.uya` + `tests/cross_deps/*.uya`）
- **通过率**：100%
- **自举验证**：通过

---

## 相关文档

- **开发指导**：[DEVELOPMENT.md](./DEVELOPMENT.md)
- **测试框架源码**：`lib/std/testing/testing.uya`
- **测试规范**：[testing_guide.md](./testing_guide.md)
- **发布流程**：`make release` / `make release-clean` / `make release-dirty`
- **`@c_import` 设计**：[c_import_design.md](./c_import_design.md)

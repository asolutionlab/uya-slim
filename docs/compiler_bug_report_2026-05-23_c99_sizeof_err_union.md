# C99 backend 编译器 bug 报告（2026-05-23）

本文档记录在把 `openspeech_realtime_live` 重构为 `@async_fn` 协作任务时撞到的两类 C99 backend 问题。两者都已经压缩成不依赖业务 sample 的最小复现。

## Bug 1：`@size_of(u64)` 被错误降成 `sizeof(u64)`

现象：

```uya
export fn main() i32 {
    const n: usize = @size_of(u64);
    return n as i32;
}
```

当前生成的 C 关键片段：

```c
const size_t n = (int32_t)sizeof(u64);
```

随后 C 编译失败：

```text
error: ‘u64’ undeclared (first use in this function)
```

期望行为：

- `@size_of(u64)` 应该在 codegen 阶段被 lowering 成后端真实类型的 `sizeof(...)`；
- 或者在前端常量折叠后直接发成整数字面量 `8`；
- 无论哪种，都不应把 Uya 前端类型名 `u64` 原样泄露到 C。

最小复现：

- `tests/repros/c99_sizeof_u64_codegen_bug.uya`

复现命令：

```bash
./bin/uya build tests/repros/c99_sizeof_u64_codegen_bug.uya -o /tmp/c99_sizeof_u64_codegen_bug
```

## Bug 2：`catch |err|` 中把错误绑定回 `!T` 时生成非法初始化

现象：

```uya
use std.async;

struct F : Future<!i32> {
    fn poll(self: &Self, waker: &Waker) Poll<!i32> {
        _ = self;
        _ = waker;
        const x: !i32 = fail() catch |err| {
            const y: !i32 = err;
            return Poll<!i32>.Ready(y);
        };
        return Poll<!i32>.Ready(x);
    }

    fn release(self: &Self) void {
        _ = self;
    }
}
```

当前生成的 C 关键片段：

```c
struct err_union_int32_t y = err;
```

随后 C 编译失败：

```text
error: invalid initializer
```

问题点：

- `err` 是 `catch |err|` 的错误分支绑定，不是一个可直接赋值给 `struct err_union_*` 的完整值；
- lowering 在 `const y: !i32 = err;` 和外层 `const x: !i32 = fail() catch ...` 上都生成了非法初始化。

期望行为：

- `catch |err|` 绑定回 `!T` 时，应生成合法的错误联合构造；
- 或者在前端/类型系统明确拒绝这种写法，但当前类型检查是通过的，因此 backend 应与前端语义保持一致。

最小复现：

- `tests/repros/c99_err_union_from_catch_codegen_bug.uya`

复现命令：

```bash
./bin/uya build tests/repros/c99_err_union_from_catch_codegen_bug.uya -o /tmp/c99_err_union_from_catch_codegen_bug
```

## 影响范围

- Bug 1 会影响任何直接使用 `@size_of(u64)`、`@size_of(i64)`、或其它原生前端类型名参与 C99 codegen 的路径，尤其是手写 runtime / future / syscall glue。
- Bug 2 会影响手写 `Future<!T>`、状态机、以及任何在 `catch |err|` 内部把错误重新绑定成 `!T` 的代码。

## 当前结论

- 两个问题都不是 sample 逻辑 bug，而是前端通过、C99 backend 失败的 compiler bug。
- 这两个 repro 都足够小，建议优先补成独立回归测试，再定位 `src/codegen/c99/**` 中对应 lowering 路径。

# C99 backend 编译器 bug 报告（2026-05-28）

本文档记录一个新的 C99 backend 问题：当用户写一个**泛型 wrapper** 去直接转发 `std.thread.async_compute<T>` 时，Uya 前端可以完成类型检查和 C 代码生成，但宿主 C 编译阶段失败。

当前状态：已修复（2026-05-28）

## Bug：泛型 wrapper 转发 `std.thread.async_compute<T>` 时漏发射单态化符号

现象：

```uya
use std.async.Future;
use std.thread.ThreadPool;
use std.thread.async_compute;
use std.thread.thread_pool_new;

export struct WorkerPool {
    inner: ThreadPool
}

export fn worker_pool_new(worker_count: i32) WorkerPool {
    return WorkerPool{
        inner: thread_pool_new(worker_count),
    };
}

export fn worker_pool_async_compute<T>(pool: &WorkerPool, compute_fn: &void, arg: T) Future<!T> {
    return async_compute<T>(&pool.inner, compute_fn, arg);
}

fn double_i32(value: i32) i32 {
    return value * 2;
}

export fn main() i32 {
    var pool: WorkerPool = worker_pool_new(2);
    const future: Future<!i32> = worker_pool_async_compute<i32>(&pool, &double_i32 as &void, 21);
    _ = future;
    return 0;
}
```

复现命令：

```bash
./bin/uya build tests/repros/c99_generic_async_compute_wrapper_codegen_bug.uya -o /tmp/c99_generic_async_compute_wrapper_codegen_bug
```

当前生成到宿主 C 阶段时会报：

```text
warning: implicit declaration of function ‘std_async_compute_i32’
error: invalid initializer
错误：链接失败
```

生成的关键 C 片段类似：

```c
struct uya_interface_Future_err_i32 _uya_ret = std_async_compute_i32((&pool->inner), compute_fn, arg);
```

问题点：

- `worker_pool_async_compute<i32>` 已经被单态化；
- 但它内部依赖的 `std.thread.async_compute<i32>` 对应符号 `std_async_compute_i32` 没有被正确发射或声明；
- 最终宿主 C 把它当成隐式声明函数处理，随后在结构体初始化处报 `invalid initializer`。

期望行为：

- 对 `async_compute<T>` 的单态化应当随着 wrapper 一起被发射；
- 或者 codegen 至少生成合法原型，确保宿主 C 可以正确看到 `std_async_compute_i32`；
- 总之，这种“泛型 wrapper 直接转发标准库泛型函数”的写法应当可以正常编译。

最小复现：

- `tests/repros/c99_generic_async_compute_wrapper_codegen_bug.uya`

影响范围：

- 任何用户态泛型 wrapper，只要内部直接转发 `std.thread.async_compute<T>` 一类依赖单态化发射的标准库泛型函数，都可能命中同类问题；
- 会阻碍把标准库并发/异步原语再包装成项目本地 API。

当前结论：

- 这不是业务代码 bug，而是前端通过、C99 backend / 单态化发射阶段失败的 compiler bug；
- 复现已经压缩到不依赖业务仓库的最小示例，适合后续补成回归测试并定位 `src/codegen/c99/**` 或泛型单态化发射路径。

## 修复结果

修复思路：

- 在 C99 表达式发射阶段，对 `async_compute<T>` / `std_async_compute<T>` 的调用增加专门 lowering；
- 当它出现在泛型 wrapper 内部时，直接降成对应的 `std_thread_async_compute_future_new_<T>` + interface boxing，而不再依赖中间的 `std_async_compute_i32` 一类单态符号。

验证结果：

```bash
./bin/uya build src/main.uya -o /tmp/uya_codegen_fix
UYA_ROOT=./lib /tmp/uya_codegen_fix build tests/repros/c99_generic_async_compute_wrapper_codegen_bug.uya -o /tmp/c99_generic_async_compute_wrapper_codegen_bug
UYA_ROOT=./lib /tmp/uya_codegen_fix test tests/test_async_compute_generic_wrapper.uya
UYA_ROOT=./lib /tmp/uya_codegen_fix test tests/test_async_compute_types.uya
```

附加回归测试：

- `tests/test_async_compute_generic_wrapper.uya`

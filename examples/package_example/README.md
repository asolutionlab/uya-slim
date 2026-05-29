# package_example

这个目录给出 Uya 包管理 v1 MVP 的三个最小例子：

- `flat/`：`source-dir = "."`
- `src_layout/`：`source-dir = "src"`
- `path_dep/`：root package + path dependency

当前这批代码已经可运行的命令：

- `./bin/uya-upm-stage2 build <package-dir>`
- `./bin/uya-upm-stage2 upm build <package-dir>`：wrapper 到 package-aware build
- `./bin/uya-upm-stage2 upm install <package-dir>`
- `./bin/uya-upm-stage2 upm update <package-dir>`

当前仓库中的验证入口说明：

- canonical public UX 仍然是 `uya upm <subcommand>`
- repo 内稳定可复现的入口是 `bin/cmd/upm` 与 `bin/uya-upm-stage2`

当前仍处于规划或第二批实现的内容：

- `upm add`
- `upm remove`
- 中央 registry
- semver range / 多版本并存 / workspace

示例：

```bash
./bin/uya-upm-stage2 build examples/package_example/flat -o /tmp/pkg-flat --no-split-c
./bin/uya-upm-stage2 build examples/package_example/src_layout -o /tmp/pkg-src --no-split-c
./bin/uya-upm-stage2 build examples/package_example/path_dep/app -o /tmp/pkg-path --no-split-c
```

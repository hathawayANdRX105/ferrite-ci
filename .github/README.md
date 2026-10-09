# ferrite-ci — 私有源码仓的 CI/发布执行壳

私有源码仓（下称**主仓**，地址只写在 workflow 的 `PRIVATE_REPO` env，文档与注释不复读）
的 Rust 全量编译、测试与发布打包全部派发到本公开仓执行：公开仓 Actions 分钟数免费，
主仓配额只用来跑秒级派发器。本仓 workflow 的触发口**只有 `workflow_dispatch`**，
不会因对本仓的 push / PR 自动执行任何携带凭据的任务。

## 用法

### PR 快关（无需手动操作）

主仓 PR（opened / synchronize / reopened / ready_for_review）→ 主仓 `ci-dispatch.yml`
（秒级，只发一次 `workflow_dispatch`）→ 本仓 `ci` workflow：

- `lint-check`：fmt / clippy / web 样式守卫 / ui-kit 契约 / db 迁移布局守卫 / 形态别名检查；
- `test`：带 PostgreSQL 服务，数据库测试真实执行；PR 走 testless 影响分析快关
  （`just test-fast`，异常或零命中自动降级全量）。

两关卡并行，`report` 聚合后以 commit status **`shell-ci`** 写回主仓 commit，
主仓 branch protection 只认这个 context，红灯挡合并。

### 全量测试

- **main push**：自动全量（`ci` 的 `pr` 入参为空即走 `just test`）。
- **手动（常规，从主仓目录）**：
  `gh workflow run ci-dispatch.yml --ref <branch> -f full=true`
- **手动（应急，直接打本仓）**：Actions → `ci` → Run workflow，填
  `sha`=待测主仓 commit、`pr`=留空（=全量）、`base`=main、`full`=true。

看结果：主仓 PR / commit 的 `shell-ci` 状态点进本仓 run；
或 `gh run list -L 5`。全量是异步关卡，不阻塞合并，但结果必须回查。

### 编译与发布二进制

- **正式发布**：主仓推 tag `ferrite-v<M.R.P>-g<hash>` → 主仓 `ferrite-release.yml` 派发 →
  本仓 `release` workflow 编译**三形态**（`ferrite-local` / `ferrite-tavern` /
  `ferrite-server`，各自 `--no-default-features --features ferrite-<form>`，
  profile.release：LTO fat + codegen-units=1）→ 三份 tarball + `config.toml.example`
  → 以检出凭据把 GitHub Release（asset + 五组过滤 notes）直接建在**主仓**。
  本公开壳仓不落任何 artifact——私有代码的编译产物不进公开仓。
- **只验证构建、不发布**：主仓手动触发 `ferrite-release.yml`（等价 `dry_run=true`）；
  或直接跑本仓 `release`，`tag` 留空 / `dry_run=true`，产物随 runner 销毁。要产物必须推 tag。

### 缓存

- `~/.cargo`：键含 `Cargo.lock` hash；`~/.cache/sccache`：lint / test / release
  分角色键，按天轮换。
- 只有**写入方 run**（main push / `full=true` 手动全量 / release）回填；
  PR 触发的 run 只读不写。
- 常规淘汰靠 GitHub 7 天未访问 LRU，不做定时全量清（清一次 = 下一个 run 冷编译 20+ 分钟）。
- 强制冷启动或清垃圾：手动跑 `cache-admin`（`prefix`=要删的 key 前缀，留空 = 全部）。
- 升工具链（sccache 等）时 bump workflow 里的键前缀。

## 安全不变量（改动本仓 workflow 前必读）

- `on:` 只允许 `workflow_dispatch`。**严禁**新增 `pull_request` /
  `pull_request_target` / `issue_comment` 等外部可控触发——那等于给任意人一条
  用主仓检出凭据行事的路径。
- run 日志公开：workflow 步骤不得 echo 主仓源码 / 配置内容（测试失败的 panic
  输出除外，这是该架构已接受的代价）；凭据只经 `secrets.*` 注入，不进命令行明文、
  不进日志。
- 缓存键只在本仓 main 分支作用域生成，PR run restore-only。
- 主仓地址只在各 workflow 的 `PRIVATE_REPO` env 出现；文档、注释、commit message 不复读。

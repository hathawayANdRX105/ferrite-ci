# ferrite-ci（公开壳仓）

hathawayANdRX105/ferrite（私有源码仓）的 CI 执行壳：公开仓的 Actions 分钟数免费且近乎无上限，
私有仓 Free 计划只有 2000 分钟/月，重活（Rust 全量编译 + 测试）全部放在这里跑。

## 工作原理

1. 私有仓的 `.github/workflows/ci-dispatch.yml` 在 PR / push main 时用 PAT 触发本仓 `ci` workflow，
   传入待测 commit 的 `sha`（以及 `pr`、`base`、`full`）。
2. 本仓 workflow 用 `FERRITE_PAT`（fine-grained，Contents: Read-only + Commit statuses: Write）
   检出私有仓对应 commit，跑 lint-check 与 test 两个并行关卡。
3. `report` 关卡把聚合结果以 commit status（context `shell-ci`）写回私有仓 commit；
   私有仓 branch protection 只认该 context，红灯挡合并（`ci` 这个名字让给了
   Actions app 的同名 check，本仓 PAT 回写满足不了）。

## Secrets

| 位置 | 名称 | 用途 |
|---|---|---|
| 本仓 | `FERRITE_PAT` | 检出私有源码 + 回写 commit status |

## 安全不变量（改动本仓 workflow 前必读）

- `on:` 只允许 `workflow_dispatch`（与本仓自身 push 若需要）。**严禁**加 `pull_request` /
  `pull_request_target` / `issue_comment` 等外部可控触发——那等于给任意人一条用 `FERRITE_PAT`
  行事的路径。
- 日志公开：workflow 步骤不得 echo 私有仓源码 / 配置内容（测试失败的 panic 输出除外，
  这是该架构已接受的代价）；PAT 只经 `secrets.*` 注入，不进命令行明文。
- 缓存键只在本仓 main 分支作用域生成，PR 触发的 run 只读缓存不写回
  （写入方 = main push / `full=true` 手动全量，键按天轮换，旧键靠 GitHub 7 天 LRU 自然淘汰）。

## 缓存

- `~/.cargo`：键含 `Cargo.lock` hash，仅写入方 run 回填。
- `~/.cache/sccache`：lint / test 分角色键，按天轮换；PR run restore-only。
- 需要强制冷启动：跑 `cache-admin` workflow（手动，可按 key 前缀清除）。

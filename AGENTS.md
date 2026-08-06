# Linux_DST_SCRIPT_Master 项目规范

## 交流与变更边界

- 本项目的分析、说明和 Git 提交信息使用简体中文。
- 修改前先检查 `git status` 和真实差异，保留用户已有且与当前任务无关的改动。
- 默认只在本地或隔离 WSL 环境验证，不覆盖服务器部署目录，也不重启真实 DST 服务；部署或重启必须由用户明确要求。
- 未经用户明确要求，不执行 `git commit`、`git push`、创建 Tag 或 GitHub Release。

## 脚本验证

提交前至少执行：

```bash
bash -n DST_SCRIPT.sh
bash -n tests/test_dst_script.sh
bash tests/test_dst_script.sh
git diff --check
```

- 涉及 SteamCMD 时，同时校验命令退出码和固定成功标志 `Success! App '343050' fully installed.`。
- 隔离测试、真实 SteamCMD 校验和真实服务器端到端测试必须分别说明，不能用其中一种代替另一种。
- 不得声称已部署、已重启或真实服务器已验证，除非确实执行并取得对应日志或运行状态证据。

## 版本与 GitHub Release 流程

1. `DST_SCRIPT.sh` 中的 `script_version` 只用于脚本内部版本显示，修改它不会自动创建 GitHub Release。
2. `.github/workflows/release-dst-ws-client.yml` 由 Tag 推送触发；普通分支提交和 `main` 推送不会触发 Release。
3. 用户要求“提交”或“更新到 GitHub”时，先比较 `script_version` 与远端最新 Tag/Release：
   - `script_version` 未升级时，只提交并推送当前分支，不创建新 Tag 或 Release；
   - `script_version` 已升级时，默认执行与该版本对应的完整 Tag/Release 流程，除非用户明确要求“只推源码”或“不发布 Release”；
   - 用户明确要求“发布版本”“补 Release”或推送指定版本时，直接执行完整发布流程。
4. 创建版本 Tag 前必须同步并复核以下内容：
   - `DST_SCRIPT.sh` 中的 `script_version`；
   - `README.md` 中的 Tag 示例；
   - `.github/workflows/release-dst-ws-client.yml` 中的 Release 更新说明和脚本版本号。
5. 先运行脚本测试和差异检查，再提交并推送发布准备改动；确认远端 `main` 指向该提交后，创建与脚本版本一致的 Tag，例如 `v1.8.21`。
6. 推送 Tag 后等待 GitHub Actions 完成，并核验：
   - 远端 Tag 指向预期提交；
   - 对应 GitHub Release 已创建并标记为最新版本；
   - Release 说明与当前改动一致；
   - `dst-ws-client-linux-amd64`、`DST_SCRIPT.sh` 和 `config.example.json` 三个附件均存在。
7. 只有上述远端核验全部完成，才能说明“Release 已发布”；仅修改版本号、仅推送 `main` 或仅创建本地 Tag 都不算发布完成。

## Git 提交信息

- 提交标题优先使用 `<type>: <中文动作 + 对象 + 结果>`，例如 `docs: 补充 v1.8.21 发布说明与流程`。
- 提交前基于真实 `git diff`、`git status` 和验证结果归纳，不写入未执行或未确认的测试结论。

# Linux_DST_SCRIPT

`不允许商用` `允许转载及修改` `转载修改的时候记得注明`

这是一个用于管理《饥荒联机版》Linux 专用服务器的脚本项目。仓库现在同时包含：

- `DST_SCRIPT.sh`：服务器管理脚本。
- `dst-ws-client.go`：连接 Koishi `dst-search` 的 WebSocket 客户端，用 token 鉴权后调用 `DST_SCRIPT.sh` 的 CLI 功能。
- `config.example.json`：WebSocket 客户端示例配置。
- `.github/workflows/release-dst-ws-client.yml`：推送 tag 时自动构建 `dst-ws-client` 单文件程序并发布到 GitHub Release。

## 说明

- 开启一个普通存档（地上+地下）需要占用 1.5G-2G 内存。
- 创建存档的功能已移除，请先自行创建并上传。教程请参考 [专栏](https://www.bilibili.com/read/cv10822903)。
- 目前功能基本可用，如有其他需求，请在 issues 中提出。
- `dst-ws-client` 会主动连接 Koishi 的 WebSocket，不提供本机 WebSocket server 或 HTTP 接口。
- 编译出的 `dst-ws-client` 是单个可执行文件，运行时不需要 Node、npm、Go 或第三方库；它仍会在运行时调用同目录的 `DST_SCRIPT.sh`。

## DST 脚本功能

- 支持 Ubuntu 和 Debian。
- 游戏版本可在 `[7]更改存档开启方式` 中选择，默认正式版 32 位，仅需更改一次，之后会保持该版本。
- 自动更新服务器 mod 和服务器。
- 崩档后自动重启服务器。
- 提供默认的 token 文件模板。
- 自动识别并添加 mod，无需手动添加，不再使用 Klei 提供的 `dedicated_server_mods_setup.lua`，改用 http 和 steamcmd 下载游戏 mod。
- 每五小时自动备份一次存档，备份文件位于 `save_bak`，每个世界单独备份。
- 每分钟统计一次玩家列表备份，备份文件位于 `PlayerList`。
- 控制台功能支持查看服务器信息、回档、复活所有玩家、发送公告、通过备份回档。

## DST 脚本用法

将脚本放到服务器目录并授权：

```bash
chmod +x DST_SCRIPT.sh
./DST_SCRIPT.sh
```

上传游戏存档到：

```bash
$HOME/.klei/DoNotStarveTogether
```

常用 CLI：

```bash
./DST_SCRIPT.sh -checkprocess Cluster_1
./DST_SCRIPT.sh -get_playerList Cluster_1
./DST_SCRIPT.sh -checkupdate Cluster_1
./DST_SCRIPT.sh -checkmodupdate Cluster_1
./DST_SCRIPT.sh -addmod_by_http_or_steamcmd Cluster_1
./DST_SCRIPT.sh -restart_server Cluster_1 -AUTO
./DST_SCRIPT.sh -save_mod_info Cluster_1
```

一行初始化：

```bash
git clone "https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git" && cp "$HOME/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$HOME/DST_SCRIPT.sh" && rm -rf "$HOME/Linux_DST_SCRIPT" && chmod +x "$HOME/DST_SCRIPT.sh" && "$HOME/DST_SCRIPT.sh"
```

GitHub 网络环境不允许时可使用加速地址：

```bash
git clone "https://ghp.quickso.cn/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT" && cp "$HOME/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$HOME/DST_SCRIPT.sh" && rm -rf "$HOME/Linux_DST_SCRIPT" && chmod +x "$HOME/DST_SCRIPT.sh" && "$HOME/DST_SCRIPT.sh"
```

## 发布单文件程序

GitHub Actions 只会在推送 tag 时构建并创建 GitHub Release，普通提交和 pull request 不会主动生成版本。

当前只构建 Linux amd64：

```text
dst-ws-client-linux-amd64
```

发布新版本：

```bash
git tag v1.8.16
git push origin v1.8.16
```

推送 tag 后，进入 GitHub 仓库的 `Releases` 页面，在对应 tag 的 release 中下载 `dst-ws-client-linux-amd64`。

本地也可以自行编译：

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o dst-ws-client dst-ws-client.go
```

如果就在 Linux 服务器本机编译：

```bash
go build -trimpath -ldflags="-s -w" -o dst-ws-client dst-ws-client.go
```

## 接入 Koishi dst-search

Koishi 插件 `dst-search` 当前源码里的控制相关配置需要关注这几项。如果你的插件页面没有 `ControlTargetAlias`，说明你使用的是旧版插件，只配置 `WSSPort`、`WSSUserList` 和 `CommandAlias` 也可以使用。

- `WSSPort`: WebSocket 监听端口，例如 `12000`。
- `WSSUserList`: 新增一行即可。`名称` 是这台被控服务器的名字；`允许操作的用户` 填 Koishi 收到的用户 ID，QQ 机器人一般就是 QQ 号；`Token` 要和客户端配置里的 `token` 完全一致；`连接状态` 是隐藏字段，不用手动填。
- `ControlTargetAlias`: 可选。用于给“某台服务器里的某个存档”配置短名字，例如 `一服` 自动对应 `本机` 服务器的 `#1` 存档。
- `CommandAlias`: 可选。用于把短命令映射成真正发给客户端的命令。插件源码里已经默认内置了 `查进程`、`玩家列表`、`开服`、`关服`、`回档1` 到 `回档5`、`存档列表`。

字段示例：

```yaml
WSSPort: 12000
WSSUserList:
  - 名称: "本机"
    允许操作的用户: "123456789"
    Token: "test-token"
ControlTargetAlias:
  - 代称: "一服"
    服务器: "本机"
    存档: "#1"
  - 代称: "二服"
    服务器: "本机"
    存档: "#2"
CommandAlias:
  - 代称: "查"
    指令: "查进程"
  - 代称: "开"
    指令: "开服"
```

`控房 <目标> <命令>` 的目标可以是 `WSSUserList` 的序号，也可以是 `WSSUserList.名称`，还可以是 `ControlTargetAlias.代称`。现在客户端只保留单服务模式，一般只需要配置一行 `WSSUserList`。

DST 服务器侧推荐把程序和脚本放在同一目录，配置放到用户目录：

```text
DST_SCRIPT.sh
dst-ws-client
~/.dst-ws-client/config.json
```

首次运行时如果没有配置文件，`dst-ws-client` 会自动创建 `~/.dst-ws-client/config.json` 并提示你继续配置。推荐直接使用配置向导：

```bash
mkdir -p "$HOME/.dst-ws-client"
chmod +x DST_SCRIPT.sh dst-ws-client
./dst-ws-client config
./dst-ws-client
```

常用配置命令：

```bash
./dst-ws-client config       # 交互式修改配置
./dst-ws-client config init  # 只创建默认配置
./dst-ws-client config path  # 输出当前配置文件路径
./dst-ws-client config show  # 查看配置，token 会隐藏
```

如果要使用其他配置文件路径，可以加 `--config`：

```bash
./dst-ws-client --config ./config.json config
./dst-ws-client --config ./config.json
```

配置示例：

```json
{
  "upstreamUrl": "ws://127.0.0.1:12000",
  "scriptPath": "./DST_SCRIPT.sh",
  "defaultCluster": "auto",
  "clientReconnectMs": 1000,
  "clientPingMs": 5000,
  "clientReadTimeoutMs": 15000,
  "clientRefreshMs": 30000,
  "token": "test-token"
}
```

也可以不用配置文件，直接用环境变量运行：

```bash
DST_WS_UPSTREAM="ws://127.0.0.1:12000" \
DST_WS_TOKEN="test-token" \
DST_SCRIPT_PATH="./DST_SCRIPT.sh" \
DST_DEFAULT_CLUSTER="auto" \
./dst-ws-client
```

`upstreamUrl` 填的是 Koishi 所在机器的 WebSocket 地址，不是 DST 游戏房间地址：

- Koishi 和 `dst-ws-client` 在同一台机器：`ws://127.0.0.1:12000`。
- Koishi 在局域网另一台机器：`ws://<Koishi内网IP>:12000`。
- Koishi 在公网机器或有域名：`ws://<Koishi公网IP或域名>:12000`，同时确认防火墙和云服务器安全组放行了 `WSSPort` 对应的 TCP 端口。

不要把真实公网 IP 和 token 提交到仓库；公开文档或截图里建议用 `<Koishi公网IP或域名>` 这类占位符。

QQ 里可以这样使用：

```text
控房 1 查进程
控房 1 存档列表
控房 1 开服
控房 1 关服
控房 1 回档1
控房 1 1
控房 1 2
控房 1 3
控房 1 #1 查进程
控房 1 Cluster_1 查进程
控房 本机 查进程
控房 一服 查
控房 一服 开
```

如果使用 `ControlTargetAlias`，插件会先选中对应的服务器，再把配置里的 `存档` 自动补到命令前面。例如 `控房 一服 查` 会发给客户端 `#1 查进程`。

## 配置项

- `upstreamUrl`: Koishi WebSocket 地址，例如同机部署时使用 `ws://127.0.0.1:12000`，跨机器部署时替换为 Koishi 机器的内网 IP、公网 IP 或域名。
- `token`: Koishi 中配置的 token。程序会在 `upstreamUrl` 未带 `token` 查询参数时自动拼接。
- `scriptPath`: `DST_SCRIPT.sh` 路径，默认 `./DST_SCRIPT.sh`。
- `defaultCluster`: 未指定存档时使用的存档名。为空或 `auto` 时会自动发现存档。
- `clientReconnectMs`: 断线后的重连间隔，默认 `1000` 毫秒。Koishi 重载配置导致 WebSocket 短暂断开时，程序会自动重连。
- `clientPingMs`: WebSocket ping 心跳间隔，默认 `5000` 毫秒。
- `clientReadTimeoutMs`: 收不到任何 WebSocket 帧时主动断开并重连的超时时间，默认 `15000` 毫秒，必须大于 `clientPingMs`。
- `clientRefreshMs`: 空闲时主动刷新 WebSocket 连接的间隔，默认 `30000` 毫秒。用于处理 Koishi 重载后旧连接仍能 pong、但新插件实例不再登记该客户端的情况。
- `clientOutputLimit`: 单次回传给 Koishi 的最大字符数，默认 `3500`。
- `clusterAliases`: 存档别名到真实存档名的映射，例如 `{ "一服": "Cluster_1", "二服": "Cluster_2" }`。

常用环境变量：

```text
DST_WS_CONFIG
DST_WS_UPSTREAM
DST_WS_TOKEN
DST_SCRIPT_PATH
DST_SCRIPT_SHELL
DST_DEFAULT_CLUSTER
DST_CLUSTER_ALIASES
DST_WS_CLIENT_RECONNECT_MS
DST_WS_CLIENT_PING_MS
DST_WS_CLIENT_READ_TIMEOUT_MS
DST_WS_CLIENT_REFRESH_MS
DST_WS_CLIENT_OUTPUT_LIMIT
```

`DST_CLUSTER_ALIASES` 支持两种格式：

```bash
export DST_CLUSTER_ALIASES='一服=Cluster_1,二服=Cluster_2'
export DST_CLUSTER_ALIASES='{"一服":"Cluster_1","二服":"Cluster_2"}'
```

## 当前支持动作

| action | 调用脚本参数 |
| --- | --- |
| `checkprocess` | `-checkprocess <cluster>` |
| `getPlayerList` | `-get_playerList <cluster>` |
| `restartServer` | `-restart_server <cluster> [autoFlag]` |
| `restartAuto` | `-restart_server <cluster> -AUTO` |
| `closeServer` | source 脚本后调用 `close_server <cluster> -close` |
| `rollback1` ... `rollback5` | source 脚本后向 DST 控制台发送 `c_rollback(1)` ... `c_rollback(5)` |
| `listClusters` | 列出运行中和已保存的存档 |

服务只做白名单映射，不接受任意 shell 命令。

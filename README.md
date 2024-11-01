# Linux_DST_SCRIPT
`不允许商用` `允许转载及修改` `转载修改的时候记得注明`

### 🔔说明

- 开启一个普通存档（地上+地下）需要占用1.5G-2G的内存。
- 创建存档的功能已移除，请先自行创建并上传。教程请参考 **[专栏](https://www.bilibili.com/read/cv10822903)**。
- 目前功能基本可用，如有其他需求，请在issues中提出，我会尽量添加。
- 由于作者代码能力有限，新功能可能会有小问题，敬请谅解。

#### ✨功能

- 支持Ubuntu和Debian。
- 游戏版本可在`[7]更改存档开启方式`中选择，默认正式版32位，仅需更改一次，之后会保持该版本。
- 自动更新服务器mod和服务器。
- 崩档后自动重启服务器。
- 提供默认的token文件模板。
- 自动识别并添加mod，无需手动添加，不再使用klei提供的dedicated_server_mods_setup.lua，改用http和steamcmd来下载游戏mod。
- 每五小时自动备份一次存档。
  - 备份超过20个时，会自动删除一个月前的备份。
  - 备份文件位于save_bak，每个世界单独备份。
  - 保存格式为`master_${daysInfo}days`和`caves_${daysInfo}days`，如果无人玩，存档不会增加。
  - 可通过控制台功能利用备份进行回档 `注意：回档会覆盖文件，请先关闭服务器`。
- 每分钟统计一次玩家备份。
  - 备份超过20个时，会自动删除一个月前的备份。
  - 备份文件位于PlayerList中。
  - 保存格式为`PlayerList_${daysInfo}days`，如果无人玩，备份不会增加。
  - 帮助玩家快速找到需要ban或设置为管理的玩家Klei Id。
- `控制台功能模块`查看服务器信息（天数、季节、天气、海象巢个数、损坏的机械怪等）。
- `控制台功能模块`回档（封装游戏的c_rollback()指令）。
- `控制台功能模块`复活所有玩家。
- `控制台功能模块`发送公告到服务器。
- `控制台功能模块`通过备份回档。

#### 📋使用教程

1. 将DST_SCRIPT.sh放到服务器根目录。
2. 给予脚本执行权限:
  ```bash
  chmod 777 DST_SCRIPT.sh
  ```
3. 初始化环境:
  ```bash
  ./DST_SCRIPT.sh
  ```
4. 上传游戏存档至:
  ```bash
  $HOME/.klei/DoNotStarveTogether
  ```
5. 开始使用:
  ```bash
  ./DST_SCRIPT.sh
  ```

#### 📋纯命令行操作初始化环境
```bash
git clone "https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git" && cp "$HOME/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$HOME/DST_SCRIPT.sh" && rm -rf "$HOME/Linux_DST_SCRIPT" && chmod 777 DST_SCRIPT.sh && ./DST_SCRIPT.sh
```
Github网络环境不允许的话使用：
```bash
 git clone "https://ghp.quickso.cn/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT" && cp "$HOME/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$HOME/DST_SCRIPT.sh" && rm -rf "$HOME/Linux_DST_SCRIPT" && chmod 777 DST_SCRIPT.sh && ./DST_SCRIPT.sh
```

#### 📋CLI命令

- `-checkprocess [cluster_name]`: 检查服务器进程。
- `-get_playerList [cluster_name]`: 获取玩家列表。
- `-checkupdate [cluster_name]`: 检查游戏更新情况。
- `-checkmodupdate [cluster_name]`: 检查游戏mod更新情况。
- `-addmod_by_http_or_steamcmd [cluster_name]`: 自动添加存档所需的mod。
- `-download_mod_by_http [mod_file_url] [mod_num]`: 通过HTTP下载mod。
- `-restart_server [cluster_name] [auto_flag]`: 重启服务器。
- `-save_mod_info [cluster_name]`: 保存mod信息。

使用方法： 
假设当前的要操作的存档为**Cluster_1**,下面指令是`自动添加存档所需的mod`
```bash
./DST_SCRIPT.sh -addmod_by_http_or_steamcmd Cluster_1
```
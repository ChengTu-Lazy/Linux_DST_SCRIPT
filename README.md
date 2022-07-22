# Linux_DST_SCRIPT

## 很多脚本作者已经找不到或者不写了，所以我给它们功能重构整合了下❤

`不允许商用` `允许转载及修改` `转载修改的时候记得著明下就好`

### 🔔说明

- 开启一个普通存档（地上+地下）需要占用1.5G-2G的内存
- 创建存档的功能砍掉了，先自己创好了再上传吧，教程的话可以看我发的 **[专栏](https://www.bilibili.com/read/cv10822903)**
- 大体已经可以使用了，大家有其他需求的话，可以发到issues里面，我会尽量加进去的

#### ✨功能如下

- 不需要手动添加mod文件了，自动添加mod  `使用的是klei提供dedicated_server_mods_setup.lua`
- 自动更新服务器mod
- 自动更新服务器
- 崩档自动重启服务器
- 提供默认的token文件模板
- 支持正式版32位，正式版64位，测试版32位，测试版64位开服
- 查看当前存档里下载的所有mod
- `控制台功能模块`查看服务器信息（天数，季节，天气，海象巢个数，损坏的机械怪。。。）
- `控制台功能模块`回档
- `控制台功能模块`复活所有玩家
- `控制台功能模块`发送公告到服务器

#### 📋使用教程

1. 将DST_SCRIPT.sh放到服务器根目录
2. 给予脚本执行权限: `chmod 777 DST_SCRIPT.sh`
3. 初始化环境: `./DST_SCRIPT.sh`
4. 上传游戏存档至:`$HOME/.klei/DoNotStarveTogether`
5. 开始使用: `./DST_SCRIPT.sh`

#### 📋纯命令行操作初始化环境

1. 获取脚本: `git clone "https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git"`
2. 给予脚本执行权限: `chmod 777 DST_SCRIPT.sh`
3. 初始化环境: `./DST_SCRIPT.sh`

# Linux_DST_SCRIPT
`不允许商用` `允许转载及修改` `转载修改的时候记得著明下就好`

### 🔔说明

- 开启一个普通存档（地上+地下）需要占用1.5G-2G的内存
- 创建存档的功能砍掉了，先自己创好了再上传吧，教程的话可以看我发的 **[专栏](https://www.bilibili.com/read/cv10822903)**
- 大体已经可以使用了，大家有其他需求的话，可以发到issues里面，我会尽量加进去的
- 作者代码能力不强，新更新的功能可能经常会出现些小毛病，跟klei的更新一脉相承

#### ✨功能如下

- 支持Ubuntu，CentOS
- 开服的游戏版本可以在`[7]更改存档开启方式`中选择，默认正式版32位，只需要改一次，下次就还是开启这个版本
- 自动更新服务器mod
- 自动更新服务器
- 崩档自动重启服务器
- 提供默认的token文件模板
- 不需要手动添加mod文件了，根据mod配置文件自动识别并添加mod  `使用的是klei提供dedicated_server_mods_setup.lua`
  - 如果是用的自己魔改的mod，可能会因此用不了，如果有这方面需求，可以issue提一下，我会给它权限分离出来，尽量做到个性化
- 每五个小时进行一次存档备份 
  - 如果备份个数超过20，会自动删除一个月前的所有备份（可能会有点bug？但我想一个月前的存档应该价值不大了吧）
  - 备份文件在save_bak，每个世界单独备份
  - 保存格式`master_${daysInfo}days`和`caves_${daysInfo}days`所以说如果没人玩的话，保存的存档就不会增多了，一直就是那么些
  - 可以通过控制台功能利用这些备份进行回档 `注意：该回档为覆盖文件回档，记得关服再回`
 - 每分钟进行一次存档玩家统计 
  - 如果备份个数超过20，会自动删除一个月前的所有备份（可能会有点bug？但我想一个月前的存档应该价值不大了吧）
  - 备份文件在PlayerList中
  - 保存格式`PlayerList_${daysInfo}days，所以说如果没人玩的话，保存的存档就不会增多了，一直就是那么些
  - 旨在帮助玩家快速找到需要ban或者需要设置为管理的玩家KleiId
- `控制台功能模块`查看服务器信息（天数，季节，天气，海象巢个数，损坏的机械怪...）
- `控制台功能模块`回档（游戏的c_rollback()指令封装）
- `控制台功能模块`复活所有玩家
- `控制台功能模块`发送公告到服务器
- `控制台功能模块`通过备份回档

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

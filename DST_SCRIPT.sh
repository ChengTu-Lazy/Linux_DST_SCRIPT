#!/bin/bash
#History:
# 2022/04/12 诚徒
# 2022/04/22 适配更多的服务器
# 2022/04/22 新增更新服务器mod功能
# 2022/06/13 修复自动添加mod功能被干扰的bug
# 2022/06/14 完善开服,新增手动更新服务器功能
# 2022/06/15 自动更新mod
# 2022/06/30 自动更新服务器
# 2022/07/04 新添保护进程功能,崩档自动重开相应的存档,正式上传github,地址: https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT
# 2022/07/05 初始环境配置screen,提供默认的token文件模板,添加自动更新脚本的功能
# 2022/07/06 参考https://gitee.com/changheqin/dst-server-for-linux-shell 优化自动更新mod的方法,并且适配更多linux系统
# 2022/07/08 更好的支持多服务器开服,对于开启已开启服务器的行为做出反应,添加进行git加速的选项
# 2022/07/14 修复无限重启的bug
# 2022/07/18 新增记录开服时间功能，对关服理由进行了区分，更改脚本日志输出方式
# 2022/07/22 新增控制台功能（回档，发送通知，复活全体玩家，查看服务器玩家情况），新增64位版本游戏服务器开启选项
# 2022/07/23 新增备份功能，每次开启存档备份一次，每隔17280s(1/5天)自动备份一次档，位置在../Master/saves_bak和../Caves/saves_bak,超过二十个存档就会检测三天前的存档，如果有就会删除三天前的存档
# 2022/07/29 每隔17280s(1/5天)自动备份一次档这是忽略了执行检查的时间，实际上是每隔17280次循环自动备份一次档，24天备份一下，现在改成了150次循环备份一下，即每5h备份一次
# 2022/07/29 经过一天的测试，150次循环平均时间是一个小时，改成750，每5小时一次备份，遇到连不上klei服务器直接重启
# 2022/08/11 连不上klei服务器时检测服务器里有没有人，如果有人就不重启，不然就直接重启
# 2022/09/01 判断当前自动更新进程是否是最新开启的进程，如果是才进行服务器的更新，防止多服务器检测到更新有冲突
# 2022/10/01 更改检查服务器版本有更新的方式，减少服务器资源占用
# 2022/10/08 UI改变,重启策略更改
# 2022/10/21 更改检查服务器版本有更新的方式,保存默认开始方式,默认正式版32位，可以通过选项7更改存档的默认开启方式

: "
主要功能如下:
不需要手动添加mod文件了,自动添加mod(使用的是klei提供dedicated_server_mods_setup.lua)
自动更新服务器mod
自动更新服务器
崩档自动重启服务器
"

##全局默认变量
#脚本版本
DST_SCRIPT_version="1.6.4"
# git加速链接
use_acceleration_url="https://ghp.quickso.cn/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT"
# 饥荒存档位置
DST_save_path="$HOME/.klei/DoNotStarveTogether"
# 脚本开启的服务器版本
DST_game_version="正式版32位"
# 当前游戏位置
DST_game_path="$HOME/dst"
# 当前系统版本
os=$(awk -F = '/^NAME/{print $2}' /etc/os-release | sed 's/"//g' | sed 's/ //g' | sed 's/Linux//g' | sed 's/linux//g')
# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
flag=1
#通知内容
c_announce="服务器需要重启,给您带来的不便还请谅解！！！"

#主菜单
function Main()
{
	tput setaf 2 
	echo "============================================================"
	printf "%s\n" "                     脚本版本:${DST_SCRIPT_version}                            "
	echo "============================================================"
	while :
	do
		echo "                                          	             "
		echo "  [1]重新载入脚本       [2]启动服务器     [3]关闭饥荒服务器 "
		echo "                                          	             "
		echo "  [4]查看服务器状态     [5]控制台         [6]重启服务器     "
		echo "                                          	             "
		echo "  [7]更改存档开启方式   [8]查看存档mod    [9]获取最新脚本   "
		echo "                                          	             "
		echo "============================================================"
		echo "                                                                                  "
		echo -e "\e[92m请输入命令代号:\e[0m"
		read -r main1
		(case $main1 in
			1)PreLibrary;update_game;prepare;
			;;
			2)get_cluster_name;start_server;;
			3)close_server;;
			4)check_server;;
			5)console;;
			6)restart_server;;
			7)change_game_version;;
			8)list_all_mod;;
			9)get_mew_version;;
		esac)
    done
}

# 重启服务器
function restart_server()
{
	close_server
	howtostart
}

# 开启服务器
function start_server()
{
	if [ "$cluster_name" == "" ]; then
			Main
	elif [ -d "${DST_save_path}/$cluster_name" ];then
		get_process_name
		if [ "$(screen -ls | grep -c "$process_name_caves")" -gt 0 ] ;then
			echo "该服务器已开启地下服务器,请先关闭再启动！！"
		elif [ "$(screen -ls | grep -c "$process_name_master")" -gt 0 ];then
			echo "该服务器已开启地上服务器,请先关闭再启动！！"
		else 
			# 判断是否有token文件
			cd "${DST_save_path}/$cluster_name"|| exit
			if [ ! -e "cluster_token.txt" ]; then
				while [ ! -e "cluster_token.txt" ]; do
					echo "该存档没有token文件,是否自动添加作者的token"
					echo "请输入 Y/y 同意 或者 N/n 拒绝并自己提供一个"
					read -r token_yes
					if [ "$token_yes" == "Y" ] ||  [ "$token_yes" == "y" ]; then
						echo "pds-g^KU_iC59_53i^+AGkfKRdMm8uq3FSa08/76lKK1YA8r0qM0iMoIb6Xx4=" > "cluster_token.txt"
					elif [ "$token_yes" == "N" ] ||  [ "$token_yes" == "N" ]; then
						read -r token_no
						echo "$token_no" > "cluster_token.txt"
					else 
						echo "输入有误,请重新输入！！！"
					fi
				done
			fi
			howtostart
		fi
	else
		echo "未找到这个存档"
	fi
}

#确认存档情况
function get_cluster_flag()
{
	if [ -d "${DST_save_path}/$cluster_name/Master" ]; then
		flag=4
	else
		flag=7
	fi
	if [ -d "${DST_save_path}/$cluster_name/Caves" ] ; then
		flag=$((flag - 3))
	else
		flag=$((flag - 2))
	fi
}

# 选择开启方式
function howtostart()
{ 
	get_cluster_flag
    (case $flag in
	# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
		1)addmod;StartMaster;StartCaves;auto_update;start_serverCheck;Main;
		;;
		2)addmod;StartMaster;auto_update;start_serverCheck;Main;
		;;
		3)echo "这行纯粹凑字数,没用的" 
		;;
		4)addmod;StartCaves;auto_update;start_serverCheck;Main;
		;;
		5)echo "存档没有内容,请自行创建！！！";Main;
		;;
	esac)
}

# 关闭服务器
function close_server()
{
	get_cluster_name_processing
	get_cluster_flag
	get_process_name
	if [ "$cluster_name" == "" ]; then
			Main
	elif [ -d "${DST_save_path}/$cluster_name" ];then
		# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
		if [ "$flag" == 1 ]; then
			close_server_autoUpdate
			close_server_master
			close_server_caves
		elif [ "$flag" == 2 ]; then
			close_server_autoUpdate
			close_server_master
		elif [ "$flag" == 4 ]; then
			close_server_autoUpdate
			close_server_caves
		fi
		while :
		do
			sleep 1
			if [[ $(screen -ls | grep -c "$process_name_master") -gt 0 || $(screen -ls | grep -c "$process_name_caves") -gt 0 ]]; then
				echo -e "\e[92m进程 $cluster_name 正在关闭,请稍后。。。\e[0m"
			else
				echo -e "\r\e[92m进程 $cluster_name 已关闭!!!                   \e[0m "
				break
			fi
		done
	else
		echo "未找到这个存档"
	fi
}

# 存档进程名
function get_cluster_name_processing()
{
	printf  '=%.0s' {1..12}
	echo -e "请确保要关闭的存档版本和当前脚本版本一致(不区分位数)\c"
	printf  '=%.0s' {1..12}
	echo ""
	screen -ls
	printf  '=%.0s' {1..28}
	echo -e "请输入要关闭的存档名\c"
	printf  '=%.0s' {1..28}
	echo ""
	read -r cluster_name
	if [ "$cluster_name" == "" ]; then
			echo "存档名输入有误！"
			Main
	elif [ ! -d "${DST_save_path}/$cluster_name" ]; then 
			echo "存档不存在！"
			Main
	fi
}

# 关闭服务器地上部分
function close_server_master()
{
	if [[ $(screen -ls | grep -c "$process_name_master") -gt 0  ]]; then
		for i in $(screen -ls | grep -w "$process_name_master" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
		do
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r地上服务器正在发布公告.  "
			sleep 1.5
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r地上服务器正在发布公告.. "
			sleep 1.5
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r地上服务器正在发布公告..."
			sleep 1.5
			screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
			echo -e "\n\e[92m地上服务器公告发布完毕!!!                \e[0m"
		done
	fi
}

# 关闭服务器地下部分
function close_server_caves()
{
	if [[ $(screen -ls | grep -c "$process_name_caves") -gt 0  ]]; then
		for i in $(screen -ls | grep -w "$process_name_caves" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
		do
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r地下服务器正在发布公告.  "
			sleep 2
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r地下服务器正在发布公告.. "
			sleep 2
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r地下服务器正在发布公告..."
			sleep 2
			screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
			echo -e "\n\e[92m地下服务器公告发布完毕!!!                \e[0m"
		done
	fi
}

# 关闭服务器自动管理部分
function close_server_autoUpdate()
{
	if [ "$(screen -ls | grep -c "$process_name_AutoUpdate")" -gt 0 ] && [ "$process_name_AutoUpdate" != "" ]; then
		for i in $(screen -ls | grep -w "$process_name_AutoUpdate" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
		do
			kill "$i"
		done
	else
		echo "未找到$process_name_AutoUpdate!"
	fi
}

#检查是否成功开启
function start_serverCheck()
{
	masterlog_path="${DST_save_path}/$cluster_name/Master/server_log.txt"
	caveslog_path="${DST_save_path}/$cluster_name/Caves/server_log.txt"
	start_time=$(date +%s);
	if [[ "$(screen -ls | grep -c "$process_name_master")" -gt 0 ]];then
		while :
		do
			sleep 1
			echo -en "\r地上服务器开启中,请稍后.  "
			sleep 1
			echo -en "\r地上服务器开启中,请稍后.. "
			sleep 1
			echo -en "\r地上服务器开启中,请稍后..."
			if [[ $(grep "Sim paused" -c "$masterlog_path") -gt 0 ||  $(grep "shard LUA is now ready!" -c "$masterlog_path") -gt 0 ]];then
					echo -e "\n\e[92m地上服务器开启成功!!!                \e[0m"
					break
			fi
			if  [[ $(grep "Your Server Will Not Start !!!" -c "$masterlog_path") -gt 0  ]]; then
				echo "服务器开启未成功,请注意令牌是否成功设置且有效。也可能是klei网络问题,那就不用管。稍后会自动重启该存档。"
				close_server_master
				break
			elif  [[ $(grep "Unhandled exception during server startup: RakNet UDP startup failed: SOCKET_PORT_ALREADY_IN_USE" -c "$masterlog_path") -gt 0  ]]; then
				echo "地上服务器开启未成功,端口冲突啦，改下端口吧！"
				close_server_master
				break
			elif [[ $(grep "Failed to send shard broadcast message" -c "$masterlog_path") -gt 0 ]]; then
				echo "服务器开启未成功,可能网络有点问题,正在自动重启。"
				sleep 3
				close_server_master
				StartMaster
			fi
		done
	fi
	if [[ "$(screen -ls | grep -c "$process_name_caves")" -gt 0 ]];then
		while :
		do
			sleep 1
			echo -en "\r地下服务器开启中,请稍后.  "
			sleep 1
			echo -en "\r地下服务器开启中,请稍后.. "
			sleep 1
			echo -en "\r地下服务器开启中,请稍后..."
			if [[ $(grep "Sim paused" -c "$caveslog_path") -gt 0 || $(grep "shard LUA is now ready!" -c "$caveslog_path") -gt 0 ]];then
					echo -e "\n\e[92m地下服务器开启成功!!!                \e[0m"
					break
			fi
			if [[ $(grep "Your Server Will Not Start !!!" -c "$caveslog_path") -gt 0 || $(grep "Failed to send shard broadcast message" -c "$caveslog_path") -gt 0 ]]; then
				echo "服务器开启未成功,请注意令牌是否成功设置且有效。也可能是klei网络问题,那就不用管。稍后会自动重启该存档。"
				close_server_caves
				break
			elif  [[ $(grep "Unhandled exception during server startup: RakNet UDP startup failed: SOCKET_PORT_ALREADY_IN_USE" -c "$caveslog_path") -gt 0  ]]; then
				echo "服务器开启未成功,端口冲突啦，改下端口吧！"
				close_server_caves
				break
			elif [[ $(grep "Failed to send shard broadcast message" -c "$caveslog_path") -gt 0 ]]; then
				echo "服务器开启未成功,可能网络有点问题,正在自动重启。"
				sleep 3
				close_server_caves
				StartCaves
			fi
		done
	fi
	end_time=$(date +%s)
	cost_time=$((end_time-start_time))
	echo -e "\r\e[92m本次开服花费时间:$((cost_time/60))分$((cost_time%60))秒\e[0m"
}

# 控制台
function console()
{
	printf  '=%.0s' {1..38}
	echo -e "当前已开启的存档进程\c"
	printf  '=%.0s' {1..38}
	echo ""
	screen -ls 
	printf  '=%.0s' {1..38}
	echo -e "请输入要操作的存档名\c"
	printf  '=%.0s' {1..38}
	echo ""
	read -r cluster_name
	clear
	while :
	do
    	echo "==============================请输入需要进行的操作序号=============================="
		echo "                                                                                  "
		echo "	[1]服务器信息          [2]回档          [3]发布通知			"
		echo "                                                                                  "
		echo "	[4]全体复活            [5]查看玩家       [6]返回上一级"      
		echo "                                                                                  "
		echo "=================================================================================="
		echo "                                                                                  "
		echo -e "\e[92m请输入命令代号:\e[0m"
		read -r main2
		get_process_name
		get_server_log_path
		(case $main2 in
			1)serverinfo;;
			2)echo "请输入你要回档的天数(1~5):"
			read -r rollbackday
			    screen -r "$process_name" -p 0 -X stuff "c_rollback($rollbackday)$(printf \\r)"
		        echo "已回档$rollbackday 天！"
			;;
			3)echo "请输入你要发布的公告:"
			read -r str
				screen -r "$process_name" -p 0 -X stuff "c_announce(\"$str\")$(printf \\r)"
				echo "已发布通知！"
			;;
			4)
			screen -r "$process_name" -p 0 -X stuff "for k,v in pairs(AllPlayers) do v:PushEvent('respawnfromghost') end$(printf \\r)"
			echo "已复活全体玩家！"
			;;
			5)
			getplayerlist
			;;
			6)Main;;
		esac)
    done
}

# 日志文件路径
function get_server_log_path()
{
	if [ -d "${DST_save_path}/$cluster_name/Caves" ]; then 
		get_server_log_path="${DST_save_path}/$cluster_name/Caves/server_log.txt"
		server_log_path_caves="${DST_save_path}/$cluster_name/Caves/server_log.txt"
	fi
	if [ -d "${DST_save_path}/$cluster_name/Master" ]; then
		get_server_log_path="${DST_save_path}/$cluster_name/Master/server_log.txt"
		server_log_path_master="${DST_save_path}/$cluster_name/Master/server_log.txt"
	fi
}

# 获取最新版脚本
function get_mew_version()
{
	if [ -d "$HOME/clone_tamp" ]; then
		rm -rf "$HOME/clone_tamp"
	fi
	clear
	echo "下载时间超过10s,就是网络问题,请CTRL+C强制退出,再次尝试,实在不行手动下载最新的。"
	mkdir "$HOME/clone_tamp"
	cd "$HOME/clone_tamp" || exit

	echo "是否使用git加速链接下载?"
	echo "请输入 Y/y 同意 或者 N/n 拒绝并使用官方链接,推荐使用加速链接,失效了再用原版链接"
	read -r use_acceleration
	if [ "${use_acceleration}" == "Y" ] || [ "${use_acceleration}" == "y" ]; then
		git clone "${use_acceleration_url}"
	elif [ "${use_acceleration}" == "N" ] || [ "${use_acceleration}" == "n" ]; then
		git clone "https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git"
	else
		echo "输入有误,请重新输入"
		get_mew_version
	fi
	cp "$HOME/clone_tamp/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$HOME/DST_SCRIPT.sh"
	cd "$HOME" || exit
	clear
	./DST_SCRIPT.sh
}

# 自动更新
function auto_update()
{
	get_modoverrides_path
	get_server_log_path
	Cluster_bath="${DST_save_path}"/"$cluster_name"
	ugc_mods_path="${DST_game_path}/ugc_mods"
	dontstarve_dedicated_server_nullrenderer_path="${DST_game_path}/bin"
	masterlog_path="${DST_save_path}/$cluster_name/Master/server_log.txt"
	caveslog_path="${DST_save_path}/$cluster_name/Caves/server_log.txt"
	master_saves_path="${DST_save_path}/$cluster_name/Master"
	caves_saves_path="${DST_save_path}/$cluster_name/Caves"
	DST_game_version=$(cat "$DST_save_path/$cluster_name/gameversion.txt")
	cd "$HOME" || exit
	cd "${Cluster_bath}" || exit
	# 配置auto_update.sh
	printf "%s" "#!/bin/bash
	##配置常量
	# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
	flag=$flag
	# 游戏版本
	DST_game_version=\"$DST_game_version\"
	#查看进程执行情况
	function CheckProcess()
	{
		if [  -d \"$master_saves_path\" ];then
			if [[ \$(screen -ls | grep -c \"$process_name_master\") -ne 1 ]]; then
				shutdown_master
				start_server_master
			fi
			if [[ \$(grep \"Failed to send server broadcast message\" -c \"${masterlog_path}\") -gt  0 ]]; then
				getplayerlist
				if [ \"\$have_player_master\" == false ];then
					c_announce=\"【地上】Failed to send server broadcast message,服务器需要重启,给您带来的不便还请谅解！！！\"
					shutdown_master
					start_server_master
				fi
			fi
			if [[ \$(grep \"Failed to send server listings\" -c \"${masterlog_path}\") -gt  0 ]]; then
				getplayerlist
				if [ \"\$have_player_master\" == false ];then
					c_announce=\"【地上】Failed to send server listings,服务器需要重启,给您带来的不便还请谅解！！！\"
					shutdown_master
					start_server_master
				fi
			fi
		fi
		if [ -d \"$caves_saves_path\" ];then
			if [[ \$(screen -ls | grep -c \"$process_name_caves\") -ne 1 ]]; then
				shutdown_caves
				start_server_caves
			fi
			if [[ \$(grep \"Failed to send server broadcast message\" -c \"${caveslog_path}\") -gt  0 ]]; then
				getplayerlist
				if [ \"\$have_player_caves\" == false ];then
					c_announce=\"【地下】Failed to send server broadcast message,服务器需要重启,给您带来的不便还请谅解！！！\"
					shutdown_caves
					start_server_caves
				fi
			fi
			if [[ \$(grep \"Failed to send server listings\" -c \"${caveslog_path}\") -gt  0 ]]; then
				getplayerlist
				if [ \"\$have_player_caves\" == false ];then
					c_announce=\"【地下】Failed to send server listings,服务器需要重启,给您带来的不便还请谅解！！！\"
					shutdown_caves
					start_server_caves
				fi
			fi
		fi
	}
	# 获取玩家列表
	function getplayerlist()
	{	
		if [[ \$(screen -ls | grep -c \"$process_name_master\") -gt 0 ]]; then
			allplayerslist=\$( date +%s%3N )
			screen -r \"$process_name_master\" -p 0 -X stuff \"for i, v in ipairs(TheNet:GetClientTable()) do  print(string.format(\\\"playerlist %s [%d] %s %s %s\\\", \$allplayerslist, i-1, v.userid, v.name, v.prefab )) end\$(printf \\\\r)\"
			sleep 5
			list=\$( grep \"$server_log_path_master\" -e \"playerlist \$allplayerslist\" | cut -d ' ' -f 4-15 | tail -n +2)
			if [[ \"\$list\" != \"\" ]]; then
				have_player_master=true
			else
				have_player_master=false
			fi
		elif [[ \$(screen -ls | grep -c \"$process_name_caves\") -gt 0 ]]; then
			allplayerslist=\$( date +%s%3N )
			screen -r \"$process_name_caves\" -p 0 -X stuff \"for i, v in ipairs(TheNet:GetClientTable()) do  print(string.format(\\\"playerlist %s [%d] %s %s %s\\\", \$allplayerslist, i-1, v.userid, v.name, v.prefab )) end\$(printf \\\\r)\"
			sleep 5
			list=\$( grep \"$server_log_path_caves\" -e \"playerlist \$allplayerslist\" | cut -d ' ' -f 4-15 | tail -n +2)
			if [[ \"\$list\" != \"\" ]]; then
				have_player_caves=true
			else
				have_player_caves=false
			fi
		fi
	}
	#查看游戏更新情况
	function CheckUpdate()
	{
		# #先更新服务器副本文件
		# cd $HOME/steamcmd || exit
		if [[ \"\${DST_game_version}\" == \"测试版32位\" || \"\${DST_game_version}\" == \"测试版64位\" ]]; then
			# echo \"正在同步测试版游戏服务端。\"	
			# ./steamcmd.sh  +force_install_dir \"$HOME/DST_Updatecheck/branch_DST_Beta\" +login anonymous +app_update 343050 -beta anewreignbeta validate +quit
			# rm \"$HOME/DST_Updatecheck/branch_DST_Beta/version_copy.txt\"
			# chmod 777 \"$HOME/DST_Updatecheck/branch_DST_Beta/version.txt\"
			# cp \"$HOME/DST_Updatecheck/branch_DST_Beta/version.txt\" \"$HOME/DST_Updatecheck/branch_DST_Beta/version_copy.txt\"
			curl 'https://forums.kleientertainment.com/game-updates/dst/' > \"$HOME/dst_beta/get_betaversion_info.txt\"
			grep Test \"$HOME/dst_beta/get_betaversion_info.txt\" --before-context=2 | grep '\<[2-9][0-9][0-9][0-9][0-9][0-9]\>' | cut -d '<' -f1  | sed s'/\t//g' | awk 'BEGIN {max = 0} {if (\$1+0 > max+0) max=\$1} END {print max}' > \"$HOME/dst_beta/betaversion_now.txt\"
			if [[ \$(sed 's/[^0-9\]//g' \"\$HOME/dst_beta/betaversion_now.txt\" ) -gt \$(sed 's/[^0-9\]//g' \"\$HOME/dst_beta/version.txt\") ]]; then
				echo " "
				echo -e \"\e[31m\${DST_now}: 游戏服务端有更新! \e[0m\"	
				echo " "
				CheckUpdateProces
			else
				if [[ \"\${UpdateServer_flag}\" == \"1\" ]]; then
					echo -e \"\e[92m\${DST_now}: 游戏服务端已更新,正在进行更新!\e[0m\"	
					restart_server
					UpdateServer_flag=0
				fi
				echo -e \"\e[92m\${DST_now}: 游戏服务端没有更新!\e[0m\"	
			fi
		else
			curl 'https://forums.kleientertainment.com/game-updates/dst/' > \"$HOME/dst/get_version_info.txt\"
			grep Release \"$HOME/dst/get_version_info.txt\" --before-context=2 | grep '\<[2-9][0-9][0-9][0-9][0-9][0-9]\>' | cut -d '<' -f1  | sed s'/\t//g' | awk 'BEGIN {max = 0} {if (\$1+0 > max+0) max=\$1} END {print max}' > \"$HOME/dst/version_now.txt\"
			#查看副本文件中的版本号和当前游戏的版本号是否一致
			if [[ \$(sed 's/[^0-9\]//g' \"\$HOME/dst/version_now.txt\" ) -gt \$(sed 's/[^0-9\]//g' \"\$HOME/dst/version.txt\") ]]; then
				echo " "
				echo -e \"\e[31m\${DST_now}: 游戏服务端有更新! \e[0m\"	
				echo " "
				CheckUpdateProces
			else
				if [[ \"\${UpdateServer_flag}\" == \"1\" ]]; then
					echo " "
					echo -e \"\e[92m\${DST_now}: 游戏服务端已更新,正在进行更新! \e[0m\"	
					echo " "
					restart_server
					UpdateServer_flag=0
				fi
				echo " "
				echo -e \"\e[92m\${DST_now}: 游戏服务端没有更新! \e[0m\"	
				echo " "
			fi
		fi
	}
	#查看游戏更新进程情况
	function CheckUpdateProces()
	{
		if [[ \$(screen -ls | grep -c \"AutoUpdate\") -gt 0  ]]; then
			for i in \$(screen -ls | grep \"AutoUpdate\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')
			do
				is_UpdateProces=\"\$i\"
				break
			done
		fi
		if [[ \$(screen -ls | grep \"$process_name_AutoUpdate\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')  -eq \$is_UpdateProces ]]; then
			c_announce=\"检测到游戏服务端有更新,服务器需要重启,给您带来的不便还请谅解！！！\"
			UpdateServer
		else 
			echo " "
			echo -e \"\e[31m \${DST_now}: 游戏服务端需要更新,正在等待更新! \e[0m\"	
			echo " "
			UpdateServer_flag=1
		fi
	}
	#查看游戏mod更新情况
	function CheckModUpdate()
	{
		echo " "
		echo -e \"\e[92m\${DST_now}: 同步服务端更新进程正在运行。。。\e[0m\"
		cd $dontstarve_dedicated_server_nullrenderer_path || exit
		# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
		if [ \"\$flag\" == 1 ] || [ \"\$flag\" == 2 ]; then
			# NeedsUpdate=\$(awk '/NeedsUpdate/{print \$2}' \"${ugc_mods_path}\"/\"$cluster_name\"/Master/appworkshop_322330.acf | sed 's/\"//g')
			./dontstarve_dedicated_server_nullrenderer -cluster \"$cluster_name\"  -only_update_server_mods  -ugc_directory \"$ugc_mods_path/$cluster_name\"  > $cluster_name.txt 
			if [[ \$(grep \"is out of date and needs to be updated for new users to be able to join the server\" -c \"${masterlog_path}\") -gt  0 ]]; then
				DST_has_mods_update=true
			fi
		elif [ \"\$flag\" == 4 ]; then
			./dontstarve_dedicated_server_nullrenderer -cluster \"$cluster_name\" -shard Caves -only_update_server_mods  -ugc_directory \"$ugc_mods_path/$cluster_name\"  > $cluster_name.txt 
			if [[ \$(grep \"is out of date and needs to be updated for new users to be able to join the server\" -c \"${caveslog_path}\") -gt  0 ]]; then
				DST_has_mods_update=true
			fi
		else
			DST_has_mods_update=false
		fi
		if [[ \$(grep \"DownloadPublishedFile\" -c \"${dontstarve_dedicated_server_nullrenderer_path}/$cluster_name.txt\") -gt  0 ]]; then
			DST_has_mods_update=true
		else
			DST_has_mods_update=false
		fi
		if [  \${DST_has_mods_update} == true ]; then
			echo " "
			echo -e \"\e[31m \${DST_now}: Mod 有更新！ \e[0m\"
			echo " "
			c_announce=\"检测到游戏Mod有更新,需要重新加载mod,给您带来的不便还请谅解！！！\"
			restart_server
		elif [  \${DST_has_mods_update} == false ]; then
			echo " "
			echo -e \"\e[92m \${DST_now}: Mod 没有更新! \e[0m\"
			echo " "
		fi
	}
	# 重启服务器
	function restart_server()
	{
		Shutdown
		start_server
	}
	# 更新服务器
	function UpdateServer()
	{
		Shutdown
		cd $HOME/steamcmd || exit
		if [[ \"\${DST_game_version}\" == \"测试版32位\" || \"\${DST_game_version}\" == \"测试版64位\" ]]; then
			echo \"正在同步测试版游戏服务端。\"
			 ./steamcmd.sh +force_install_dir \"$HOME/dst_beta\" +login anonymous +app_update 343050 -beta updatebeta validate  +quit
		else
			echo \"正在同步正式版游戏服务端。\"
			./steamcmd.sh +force_install_dir \"$HOME/dst\" +login anonymous +app_update 343050 validate +quit 
		fi
		start_server
	}
	# 关闭服务器
	function Shutdown()
	{
		# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
		if [ \"\$flag\" == 1 ]; then
			shutdown_master
			shutdown_caves
		elif [ \"\$flag\" == 2 ]; then
			shutdown_master
		elif [ \"\$flag\" == 4 ]; then
			shutdown_caves
		fi
	}
	# 关闭地上服务器
	function shutdown_master()
	{
		for i in \$(screen -ls | grep -w \"$process_name_master\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')
		do
			screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"\$c_announce\\\") \$(printf \\\\r)\"
			sleep 2
			screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"\$c_announce\\\") \$(printf \\\\r)\"
			sleep 2
			screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"\$c_announce\\\") \$(printf \\\\r)\"
			sleep 2
			screen -S \"\$i\" -p 0 -X stuff \"c_shutdown(true) \$(printf \\\\r)\"
			sleep 1
		done
		while :
		do
			sleep 1
			if [[ \$(screen -ls | grep -c \"$process_name_master\") -gt 0 ]]; then
				echo -e \"$cluster_name地上服务器正在关闭,请稍后。。。\"
			else
				echo -e \"$cluster_name地上服务器已关闭!!!\"
				break
			fi
		done
	}
	# 关闭地下服务器
	function shutdown_caves()
	{
		for i in \$(screen -ls | grep -w \"$process_name_caves\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')
		do
			screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"\$c_announce\\\") \$(printf \\\\r)\"
			sleep 2
			screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"\$c_announce\\\") \$(printf \\\\r)\"
			sleep 2
			screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"\$c_announce\\\") \$(printf \\\\r)\"
			sleep 2
			screen -S \"\$i\" -p 0 -X stuff \"c_shutdown(true) \$(printf \\\\r)\"
			sleep 1
		done
		while :
		do
			sleep 1
			if [[ \$(screen -ls | grep -c \"$process_name_caves\") -gt 0 ]]; then
				echo -e \"$cluster_name地上服务器正在关闭,请稍后。。。\"
			else
				echo -e \"$cluster_name地上服务器已关闭!!!\"
				break
			fi
		done
	}
	# 开启服务器
	function start_server()
	{
		Addmod
		# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
		if [ \$flag == 1 ];then
			start_server_master
			start_server_caves
		elif [ \$flag == 2 ];then
			start_server_master
		elif [ \$flag == 4 ];then
			start_server_caves
		fi
	}
	# 开启地上服务器
	function start_server_master()
	{
		screen -dmS  \"$process_name_master\" /bin/sh -c \"${DST_save_path}/$cluster_name/startmaster.sh\" 
		if [ \"\$(screen -ls | grep -c \"$process_name_master\")\" -gt 0 ];then
			while :
			do
				sleep 1
				echo -en \"\\r地上服务器开启中,请稍后.  \"
				sleep 1
				echo -en \"\\r地上服务器开启中,请稍后.. \"
				sleep 1
				echo -en \"\\r地上服务器开启中,请稍后...\"
				if [[ \$(grep \"Sim paused\" -c \"$masterlog_path\") -gt 0 ||  \$(grep \"shard LUA is now ready!\" -c \"$masterlog_path\") -gt 0 ]];then
						echo -e \"\\n\\e[92m地上服务器开启成功!!!                \\e[0m\"
						break
				fi
				if  [[ \$(grep \"Your Server Will Not Start !!!\" -c \"$masterlog_path\") -gt 0  ]]; then
					echo \"服务器开启未成功,请注意令牌是否成功设置且有效。\"
					shutdown_master
					break
				elif  [[ \$(grep \"Unhandled exception during server startup: RakNet UDP startup failed: SOCKET_PORT_ALREADY_IN_USE\" -c \"$masterlog_path\") -gt 0  ]]; then
					echo \"地上服务器开启未成功,端口冲突啦，改下端口吧！\"
					shutdown_master
					break
				elif [[ \$(grep \"Failed to send shard broadcast message\" -c \"$masterlog_path\") -gt 0 ]]; then
					echo \"服务器开启未成功,可能网络有点问题,正在自动重启。\"
					sleep 3
					shutdown_master
					start_server_master
				fi
			done
		fi
	}
	# 开启地下服务器
	function start_server_caves()
	{
		screen -dmS  \"$process_name_caves\" /bin/sh -c \"${DST_save_path}/$cluster_name/startcaves.sh\"
		if [ \"\$(screen -ls | grep -c \"$process_name_caves\")\" -gt 0 ];then
			while :
			do
				sleep 1
				echo -en \"\\r地下服务器开启中,请稍后.  \"
				sleep 1
				echo -en \"\\r地下服务器开启中,请稍后.. \"
				sleep 1
				echo -en \"\\r地下服务器开启中,请稍后...\"
				if [[ \$(grep \"Sim paused\" -c \"$caveslog_path\") -gt 0 ||  \$(grep \"shard LUA is now ready!\" -c \"$caveslog_path\") -gt 0 ]];then
						echo -e \"\\n\\e[92m地上服务器开启成功!!!                \\e[0m\"
						break
				fi
				if  [[ \$(grep \"Your Server Will Not Start !!!\" -c \"$caveslog_path\") -gt 0  ]]; then
					echo \"服务器开启未成功,请注意令牌是否成功设置且有效。\"
					shutdown_caves
					break
				elif  [[ \$(grep \"Unhandled exception during server startup: RakNet UDP startup failed: SOCKET_PORT_ALREADY_IN_USE\" -c \"$caveslog_path\") -gt 0  ]]; then
					echo \"地上服务器开启未成功,端口冲突啦，改下端口吧！\"
					shutdown_caves
					break
				elif [[ \$(grep \"Failed to send shard broadcast message\" -c \"$caveslog_path\") -gt 0 ]]; then
					echo \"服务器开启未成功,可能网络有点问题,正在自动重启。\"
					sleep 3
					shutdown_caves
					start_server_caves
				fi
			done
		fi
	}

	#自动添加存档所需的mod
	function Addmod()
	{
		echo \"正在将开启存档所需的mod添加进服务器配置文件中。。。\"
		cd \"${DST_game_path}\"/mods || exit
		rm -rf dedicated_server_mods_setup.lua
		sleep 0.1
		grep \"\\\"workshop\" < \"$modoverrides_path\" | cut -d '\"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
		do
			echo \"ServerModSetup(\"\"\$line\"\")\">>$dedicated_server_mods_setup_path
			echo \"ServerModCollectionSetup(\"\"\$line\"\")\">>$dedicated_server_mods_setup_path
			sleep 0.5
			echo \"\$line Mod添加完成\"
		done
	}
	
	timecheck=0
	# 保持运行
	while :
			do
				DST_now=\$(date +%Y年%m月%d日%H:%M)
				timecheck=\$(( timecheck%750 ))
				# 自动备份
				if [ \"\$timecheck\" == 0 ];then
					if [  -d \"$master_saves_path\" ];then
						cd \"$master_saves_path\" || exit
						if [ ! -d \"$master_saves_path/saves_bak\" ];then
							mkdir saves_bak
						fi
						cd \"$master_saves_path/saves_bak\" || exit
						master_saves_bak=\$(find . -maxdepth 1 -name '*.zip' | wc -l)
						if [ \"\$master_saves_bak\" -gt 21 ];then
							find . -maxdepth 1 -mtime +3 -name '*.zip'  | awk '{if(NR -gt 10){print \$1}}' |xargs rm -f {};
						fi
						zip -r \"bak_\${DST_now}\".zip $master_saves_path/save/
					fi
					if [ -d \"$caves_saves_path\" ];then
						cd \"$caves_saves_path\" || exit			
						if [ ! -d \"$caves_saves_path/saves_bak\" ];then
							mkdir saves_bak
						fi
						cd \"$caves_saves_path/saves_bak\" || exit
						caves_saves_bak=\$(find . -maxdepth 1 -name '*.zip' | wc -l)
						if [ \"\$caves_saves_bak\" -gt 21 ];then
							find . -maxdepth 1 -mtime +3 -name '*.zip'  | awk '{if(NR -gt 10){print \$1}}' |xargs rm -f {};
						fi
						zip -r \"bak_\${DST_now}\".zip $caves_saves_path/save/
					fi
					
				fi
				((timecheck++))
				CheckProcess
				CheckUpdate
				CheckModUpdate
				sleep 30
			done
	" > "${Cluster_bath}"/auto_update.sh
	chmod 777 "${Cluster_bath}"/auto_update.sh
	screen -dmS  "$process_name_AutoUpdate" /bin/sh -c "${DST_save_path}/$cluster_name/auto_update.sh"
	echo -e "\e[92m自动更新进程 $process_name_AutoUpdate 已启动\e[0m"
}

# mod配置文件的路径
function get_modoverrides_path()
{
	dedicated_server_mods_setup_path="${DST_game_path}"/mods/dedicated_server_mods_setup.lua
	if [ -e "${DST_save_path}/$cluster_name/Master/modoverrides.lua" ]; then
		modoverrides_path=${DST_save_path}/$cluster_name/Master/modoverrides.lua
	elif [ -e "${DST_save_path}/$cluster_name/Caves/modoverrides.lua" ]; then 
		modoverrides_path=${DST_save_path}/$cluster_name/Caves/modoverrides.lua
	fi
}

#自动添加存档所需的mod
function addmod()
{
	echo "正在将开启存档所需的mod添加进服务器配置文件中。。。"
	cd "${DST_game_path}"/mods || exit
	rm -rf dedicated_server_mods_setup.lua
	sleep 0.1
	echo "" >>dedicated_server_mods_setup.lua
	sleep 0.1
	get_modoverrides_path
	grep "\"workshop" < "$modoverrides_path" | cut -d '"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
	do
		echo "ServerModSetup(\"$line\")">>"$dedicated_server_mods_setup_path"
		echo "ServerModCollectionSetup(\"$line\")">>"$dedicated_server_mods_setup_path"
		sleep 0.05
		echo -e "\e[92m$line Mod添加完成\e[0m"
	done
}

# 存档进程
function get_process_name()
{
	if [[ $DST_game_version == "正式版32位" || $DST_game_version == "正式版64位" ]]; then
		process_name_AutoUpdate="DST $cluster_name AutoUpdate"
		process_name_caves="无"
		process_name_master="无"
		process_name="无"
		if [ -d "${DST_save_path}/$cluster_name/Caves" ]; then 
			process_name_caves="DST_Caves $cluster_name"
			process_name="DST_Caves $cluster_name"
		fi
		if [ -d "${DST_save_path}/$cluster_name/Master" ]; then
			process_name_master="DST_Master $cluster_name"
			process_name="DST_Master $cluster_name"
		fi
		
	elif [[ $DST_game_version == "测试版32位" || $DST_game_version == "测试版64位" ]]; then
		process_name_AutoUpdate="DST $cluster_name AutoUpdate_beta"
		process_name_caves="无"
		process_name_master="无"
		process_name="无"
		process_name_AutoUpdate="DST $cluster_name AutoUpdate_beta"
		if [ -d "${DST_save_path}/$cluster_name/Caves" ]; then 
			process_name_caves="DST_Caves_beta $cluster_name"
			process_name="DST_Caves_beta $cluster_name"
		fi	
		if [ -d "${DST_save_path}/$cluster_name/Master" ]; then
			process_name_master="DST_Master_beta $cluster_name"
			process_name="DST_Master_beta $cluster_name"
		fi
	fi
}

# 存档
function get_cluster_name()
{
	if [ ! -d "${DST_save_path}" ]
	then
	mkdir "$HOME"/.klei
	cd "$HOME"/.klei || exit
	mkdir "${DST_save_path}"
	fi
	printf  '=%.0s' {1..26}
	echo -e "存档目录\c"
	printf  '=%.0s' {1..26}
	echo ""
	echo ""
	cd "${DST_save_path}" || exit
	ls
	cd "$HOME"|| exit
	echo ""
	printf  '=%.0s' {1..60}
	# printf  '=%.0s' {1..12}
	# echo -e "存档名不要是Cluster_1,否则会找不到哦\c"
	# printf  '=%.0s' {1..12}
	echo ""
	echo "请输入存档代码:"
	read -r cluster_name
}

# 游戏版本
function get_dontstarve_dedicated_server_nullrenderer()
{
	if [ ! -f "$DST_save_path/$cluster_name/gameversion.txt" ]; then
		echo "正式版32位" > "$DST_save_path/$cluster_name/gameversion.txt"
	fi
	if [[ $(cat  "$DST_save_path/$cluster_name/gameversion.txt") == "正式版32位" ]]; then
		gamesPath="$HOME/dst/bin"
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer"
	elif [[ $(cat  "$DST_save_path/$cluster_name/gameversion.txt") == "正式版64位" ]]; then
		gamesPath="$HOME/dst/bin64"
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer_x64"
	elif [[ $(cat "$DST_save_path/$cluster_name/gameversion.txt") == "测试版32位" ]]; then
		gamesPath="$HOME/dst_beta/bin"
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer"
	elif [[ $(cat  "$DST_save_path/$cluster_name/gameversion.txt") == "测试版64位" ]]; then
		gamesPath="$HOME/dst_beta/bin64"
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer_x64"
	fi
}

#开启地下服务器
function StartCaves()
{
	get_dontstarve_dedicated_server_nullrenderer
	rm -rf "${DST_save_path}"/"$cluster_name"/startcaves.sh
	echo   "#!/bin/bash
	gamesPath=\"$gamesPath\"
	cd "\"\$gamesPath\" \|\| exit"
	run_shared=(./$dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard Caves" > "${DST_save_path}"/"$cluster_name"/startcaves.sh
	cd "${DST_save_path}"/"$cluster_name" || exit
	chmod u+x ./startcaves.sh
	cd "$HOME" || exit
	screen -dmS  "$process_name_caves" /bin/sh -c "${DST_save_path}/$cluster_name/startcaves.sh" 
}

#开启地面服务器
function StartMaster()
{
	get_dontstarve_dedicated_server_nullrenderer
	rm -rf "${DST_save_path}"/"$cluster_name"/startmaster.sh
	echo   "#!/bin/bash
	gamesPath=\"$gamesPath\"
	cd "\"\$gamesPath\" \|\| exit"
	run_shared=(./$dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard Master " > "${DST_save_path}"/"$cluster_name"/startmaster.sh
	cd "${DST_save_path}"/"$cluster_name" || exit
	chmod u+x ./startmaster.sh
	cd "$HOME" || exit
	screen -dmS  "$process_name_master" /bin/sh -c "${DST_save_path}/$cluster_name/startmaster.sh" 
}

# 服务器信息
function serverinfo()
{
	
	echo -e "\e[92m=============================世界信息==========================================\e[0m"
	getworldstate
	echo -e "\e[33m 天数($presentcycles)($presentseason的第$presentday天)($presentphase/$presentmoonphase/$presentrain/$presentsnow/$presenttemperature°C)\e[0m"
	getplayerlist
	getmonster
	if [[ $(screen -ls | grep -c "$process_name_master") -gt 0 ]]; then
		echo "===========================地上世界信息========================================"
		echo -e "\e[33m海象巢:($walrus_camp_master)个  触手怪:($tentacle_master)个  蜘蛛巢:($spiderden_master)个\e[0m"
		echo -e "\e[33m高脚鸟巢:($tallbirdnest_master)个  猎犬丘:($houndmound_master)个  芦苇:($reeds_master)株  墓地:($mudi_master)个\e[0m"
	fi
	sleep 2
	if [[ $(screen -ls | grep -c "$process_name_caves") -gt 0 ]]; then
		echo "===========================地下世界信息========================================"
		echo -e "\e[33m触手怪:($tentacle_caves)个  蜘蛛巢:($spiderden_caves)个  芦苇:($reeds_caves)株\e[0m"
		echo -e "\e[33m损坏的发条主教:($bishop_nightmare)个  损坏的发条战车:($rook_nightmare)个  损坏的发条骑士:($knight_nightmare)个\e[0m"
	fi
    echo -e "\e[33m================================================================================\e[0m"
}

# 获取玩家列表
function getplayerlist()
{	
	if [[ $(screen -ls | grep -c "$process_name_master") -gt 0 ]]; then
	    allplayerslist=$( date +%s%3N )
		screen -r "$process_name_master" -p 0 -X stuff "for i, v in ipairs(TheNet:GetClientTable()) do  print(string.format(\"playerlist %s [%d] %s %s %s\", $allplayerslist, i-1, v.userid, v.name, v.prefab )) end$(printf \\r)"
		sleep 5
		list=$( grep "$server_log_path_master" -e "playerlist $allplayerslist" | cut -d ' ' -f 4-15 | tail -n +2)
		if [[ "$list" != "" ]]; then
			echo -e "\e[92m服务器玩家列表:\e[0m"
			echo -e "\e[92m================================================================================\e[0m"
			echo "$list"
			echo -e "\e[92m================================================================================\e[0m"
			echo "$list" > "${DST_save_path}"/"$cluster_name"/playerlist.txt
		else
			echo -e "\e[92m服务器玩家列表:\e[0m"
	        echo -e "\e[92m================================================================================\e[0m"
			echo    "                                 当前服务器没有玩家"
			echo -e "\e[92m================================================================================\e[0m"
		fi
	elif [[ $(screen -ls | grep -c "$process_name_caves") -gt 0  ]]; then	    
	    allplayerslist=$( date +%s%3N )
		screen -r "$process_name_caves" -p 0 -X stuff "for i, v in ipairs(TheNet:GetClientTable()) do  print(string.format(\"playerlist %s [%d] %s %s %s\", $allplayerslist, i-1, v.userid, v.name, v.prefab)) end$(printf \\r)"
		sleep 5
		list=$( grep "$server_log_path_caves" -e "playerlist $allplayerslist" | cut -d ' ' -f 4-15 | tail -n +2)
		if [[ "$list" != "" ]]; then
		    echo -e "\e[92m服务器玩家列表:\e[0m"
	        echo -e "\e[92m================================================================================\e[0m"
			echo "$list"
			echo -e "\e[92m================================================================================\e[0m"
			echo "$list" > "${DST_save_path}"/"$cluster_name"/playerlist.txt
		else
			echo -e "\e[92m服务器玩家列表:\e[0m"
	        echo -e "\e[92m================================================================================\e[0m"
			echo    "                                 当前服务器没有玩家"
			echo -e "\e[92m================================================================================\e[0m"
		fi
	fi
}

# 获取怪物信息
function getmonster()
{
    if [[ $(screen -ls | grep -c "$process_name_master") -gt 0 ]]; then   									       	
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"walrus_camp\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"bishop\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"knight\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"rook\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"tallbirdnest\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"mound\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"houndmound\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"tentacle\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"reeds\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"pigtorch\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"gravestone\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"spiderden\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"spiderden_2\")$(printf \\r)"
		screen -r "$process_name_master" -p 0 -X stuff "c_countprefabs(\"spiderden_3\")$(printf \\r)"
		sleep 1
		walrus_camp_master=$( grep "$server_log_path_master" -e "walrus_camps in the world." | cut -d ':' -f4 | tail -n 1| sed 's/[^0-9\]//g' )
		reeds_master=$( grep "$server_log_path_master" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		tentacle_master=$( grep "$server_log_path_master" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		tallbirdnest_master=$( grep "$server_log_path_master" -e "tallbirdnests in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		houndmound_master=$( grep "$server_log_path_master" -e "houndmounds in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		mound_master=$( grep "$server_log_path_master" -e "mounds in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		gravestone_master=$( grep "$server_log_path_master" -e "gravestones in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_1_master=$( grep "$server_log_path_master" -e "spiderdens in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_2_master=$( grep "$server_log_path_master" -e "spiderden_2s in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_3_master=$( grep "$server_log_path_master" -e "spiderden_3s in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_master=$(( spiderden_1_master + spiderden_2_master + spiderden_3_master ))
		mudi_master=$(( mound_master + gravestone_master ))
	fi
	if [[ $(screen -ls | grep -c "$process_name_caves") -gt 0 ]]; then   									       	
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"walrus_camp\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"bishop\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"knight\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"rook\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"tallbirdnest\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"mound\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"houndmound\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"tentacle\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"reeds\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"pigtorch\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"gravestone\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"spiderden\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"spiderden_2\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"spiderden_3\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"bishop_nightmare\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"rook_nightmare\")$(printf \\r)"
		screen -r "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"knight_nightmare\")$(printf \\r)"
		sleep 1
		reeds_caves=$( grep "$server_log_path_caves" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		tentacle_caves=$( grep "$server_log_path_caves" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_1_caves=$( grep "$server_log_path_caves" -e "spiderdens in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_2_caves=$( grep "$server_log_path_caves" -e "spiderden_2s in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_3_caves=$( grep "$server_log_path_caves" -e "spiderden_3s in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		bishop_nightmare=$( grep "$server_log_path_caves" -e "bishop_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		rook_nightmare=$( grep "$server_log_path_caves" -e "rook_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		knight_nightmare=$( grep "$server_log_path_caves" -e "knight_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g' )
		spiderden_caves=$(( spiderden_1_caves + spiderden_2_caves + spiderden_3_caves ))
	fi
}

# 获取世界状态
function getworldstate()
{
    presentseason=""
	presentday=""
	presentcycles=""
	presentphase=""
	presentmoonphase=""
	presentrain=""
	presentsnow=""
	presenttemperature=""								        
	datatime=$( date +%s%3N )	
	screen  -r "$process_name" -p 0 -X stuff "print(\"\" .. TheWorld.net.components.seasons:GetDebugString() .. \" $datatime print\")$(printf \\r)"
	screen  -r "$process_name" -p 0 -X stuff "print(\"\" .. TheWorld.components.worldstate.data.phase .. \" $datatime phase\")$(printf \\r)"
	screen  -r "$process_name" -p 0 -X stuff "print(\"\" .. TheWorld.components.worldstate.data.moonphase .. \" $datatime moonphase\")$(printf \\r)"
	screen  -r "$process_name" -p 0 -X stuff "print(TheWorld.components.worldstate.data.temperature .. \" $datatime temperature\")$(printf \\r)"
	screen  -r "$process_name" -p 0 -X stuff "print(TheWorld.components.worldstate.data.cycles .. \" $datatime cycles\")$(printf \\r)"
	screen  -r "$process_name" -p 0 -X stuff "print(\"$datatime:rain:\",TheWorld.components.worldstate.data.israining)$(printf \\r)"
	screen  -r "$process_name" -p 0 -X stuff "print(\"$datatime:snow:\",TheWorld.components.worldstate.data.issnowing)$(printf \\r)"
	sleep 1
	presentseason=$( grep "$get_server_log_path" -e "$datatime print" | cut -d ' ' -f2 | tail -n +2 )
	presentday=$( grep "$get_server_log_path" -e "$datatime print" | cut -d ' ' -f3 | tail -n +2 )
	presentphase=$( grep "$get_server_log_path" -e "$datatime phase" | cut -d ' ' -f2 | tail -n +2 )
	presentmoonphase=$( grep "$get_server_log_path" -e "$datatime moonphase" | cut -d ' ' -f2 | tail -n +2 )
	presenttemperature=$( grep "$get_server_log_path" -e "$datatime temperature" | cut -d ' ' -f2 | tail -n +2 )
	presentrain=$( grep "$get_server_log_path" -e "$datatime:rain" | cut -d ':' -f6 | tail -n +2 )
	presentsnow=$( grep "$get_server_log_path" -e "$datatime:snow" | cut -d ':' -f6 | tail -n +2 | cut -d ' ' -f2 )
	presentcycles=$( grep "$get_server_log_path" -e "$datatime cycles" | cut -d ' ' -f2 | tail -n +2 )

	if [[ "$presentseason" == "autumn" ]]; then
		presentseason="秋天"
	fi
	if [[ "$presentseason" == "spring" ]]; then
		presentseason="春天"
	fi
	if [[ "$presentseason" == "summer" ]]; then
		presentseason="夏天"
	fi
	if [[ "$presentseason" == "winter" ]]; then
		presentseason="冬天"
	fi
	if [[ "$presentphase" == "day" ]]; then
		presentphase="白天"
	fi
	if [[ "$presentphase" == "dusk" ]]; then
		presentphase="黄昏"
	fi
	if [[ "$presentphase" == "night" ]]; then
		presentphase="黑夜"
	fi
	if [[ "$presentmoonphase" == "new" ]]; then
		presentmoonphase="新月"
	fi
	if [[ "$presentmoonphase" == "full" ]]; then
		presentmoonphase="满月"
	fi
	if [[ "$presentmoonphase" == "threequarter" || "$presentmoonphase" == "quarter" || "$presentmoonphase" == "half" ]]; then
		presentmoonphase="缺月"
	fi
	presenttemperature=${presenttemperature%.*}
	if [[ $( echo "$presentrain" | grep -c "true" ) -gt 0 ]]; then
		presentrain="下雨"
	fi
	if [[ $( echo "$presentrain" | grep -c "false" ) -gt 0 ]]; then
		presentrain="无雨"
	fi
	if [[ $( echo "$presentsnow" | grep -c "true" ) -gt 0 ]]; then
		presentsnow="下雪"
	fi
	if [[ $( echo "$presentsnow" | grep -c "false" ) -gt 0 ]]; then
		presentsnow="无雪"
	fi
}

# 查看游戏服务器状态
function check_server()
{
	echo " "
	printf  '=%.0s' {1..60}
	echo " "
	echo " "
	screen -ls
	echo " "
	printf  '=%.0s' {1..23}
	echo -e "输入要切换的PID\c"
	printf  '=%.0s' {1..23}
	echo ""
	echo ""
	echo "PS:回车后会进入地上或地下的运行界面"
	echo "   手动输入c_shutdown(true)回车保存退出"
	echo "   进入后不想关闭请按ctrl+a+d"
	read -r pid1
	screen -r "$pid1"
}

# 列出所有的mod
function list_all_mod()
{
	tput setaf 2 
	clear 
	get_cluster_name
	echo "                                                                                  "
    echo "                                                                                  "
	printf  '=%.0s' {1..27}
    echo -e " $cluster_name存档已下载的mod如下: \c"
	printf  '=%.0s' {1..27}
	echo ""
	if [ -d """$DST_game_path""/ugc_mods/""$cluster_name""/Master/content/322330" ]; then
		temp_mods_path="$DST_game_path"/ugc_mods/"$cluster_name"/Master/content/322330
		for i in $( find "$temp_mods_path" -maxdepth 1   -exec basename {} \; | awk '{print $NF}' )
		do
			if [[ -f "$temp_mods_path/$i/modinfo.lua" ]]; then
				name=$(grep "$temp_mods_path/$i/modinfo.lua" -e "name =" | cut -d '"' -f 2 | head -1)	
				echo -e "\e[92m$i\e[0m------\e[33m$name\e[0m" 
			fi
		done
		echo ""
		printf  '=%.0s' {1..80}
	elif [ -d """$DST_game_path""/ugc_mods/""$cluster_name""/Caves/content/322330" ]; then
		temp_mods_path="$DST_game_path"/ugc_mods/"$cluster_name"/Caves/content/322330
		for i in $( find "$temp_mods_path" -maxdepth 1   -exec basename {} \; | awk '{print $NF}' )
		do
			if [[ -f "$temp_mods_path/$i/modinfo.lua" ]]; then
				name=$(grep "$temp_mods_path/$i/modinfo.lua" -e "name =" | cut -d '"' -f 2 | head -1)	
				echo -e "\e[92m$i\e[0m------\e[33m$name\e[0m" 
			fi
		done
		echo ""
		printf  '=%.0s' {1..80}
	else	
		echo "当前存档没有配置或者下载mod"
	fi

}

# 准备环境
function PreLibrary()
{
	if [ "$os" == "Ubuntu" ];then
	echo ""
	echo "##########################"
	echo "# 加载 Ubuntu Linux 环境 #"
	echo "##########################"
	echo ""
	sudo apt-get -y update
	sudo apt-get -y wget

	# 加载 32bit 库
	sudo apt-get -y install lib32gcc1
	sudo apt-get -y install libc6-i386
	sudo apt-get -y install lib32stdc++6
	sudo apt-get -y install libcurl4-gnutls-dev:i386
	sudo dpkg --add-architecture i386
	# 加载 64bit库
	sudo apt-get -y install lib64gcc1
	sudo apt-get -y install lib64stdc++6
	sudo apt-get -y install libcurl4-gnutls-dev

	#一些必备工具
	sudo apt-get -y install screen
	sudo apt-get -y install htop
	sudo apt-get -y install gawk
	sudo apt-get -y install zip unzip

	if [ -f "/usr/lib/libcurl.so.4" ];then
		ln -sf /usr/lib/libcurl.so.4 /usr/lib/libcurl-gnutls.so.4	
	fi
	if [ -f "/usr/lib64/libcurl.so.4" ];then
		ln -sf /usr/lib64/libcurl.so.4 /usr/lib64/libcurl-gnutls.so.4
	fi


	elif [ "$os" == "CentOS" ];then

		echo ""
		echo "##########################"
		echo "# 加载 CentOS Linux 环境 #"
		echo "##########################"
		echo ""
		sudo yum -y update
		sudo yum -y wget

		# 加载 32bit 库
		sudo yum -y install glibc.i686 libstdc++.i686 libcurl.i686
		# 加载 64bit 库
		sudo yum -y install glibc libstdc++ libcurl

		# 一些必备工具
		sudo yum -y install tar wget screen
		sudo yum -y install screen
		sudo yum -y install htop
		sudo yum -y install gawk
		sudo yum -y install zip unzip

		if [ -f "/usr/lib/libcurl.so.4" ];then
			ln -sf /usr/lib/libcurl.so.4 /usr/lib/libcurl-gnutls.so.4	
		fi
		if [ -f "/usr/lib64/libcurl.so.4" ];then
			ln -sf /usr/lib64/libcurl.so.4 /usr/lib64/libcurl-gnutls.so.4
		fi
	elif [ "$os" == "Arch" ];then
		echo ""
		echo "########################"
		echo "# 加载 Arch Linux 环境 #"
		echo "########################"
		echo ""
		sudo pacman -Syyy
		sudo pacman -S --noconfirm wget screen
		sudo pacman -S --noconfirm lib32-gcc-libs libcurl-gnutls
	else
		echo "该系统未被本脚本支持！"
	fi
}

#前期准备
function prepare()
{
	cd "$HOME" || exit
	if [ ! -d "./steamcmd" ] ||[ ! -d "./dst"  ] ||[ ! -d "./dst_beta"  ] || [ ! -d "./.klei/DoNotStarveTogether"  ] ;then
		PreLibrary
		mkdir "$HOME/dst"
		mkdir "$HOME/dst_beta"
		
		mkdir "$HOME/steamcmd"
		mkdir "$HOME/.klei"
		mkdir "$HOME/.klei/DoNotStarveTogether"
		mkdir "${DST_save_path}"
		cd "$HOME/steamcmd" || exit 
		wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
		tar -xvzf steamcmd_linux.tar.gz
		sleep 1
		rm -f steamcmd_linux.tar.gz
	fi
	if [[ ${DST_game_version} == "正式版32位" || ${DST_game_version} == "正式版64位" ]]; then
		cd "$HOME/dst" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
		fi
	else
		cd "$HOME/dst_beta" || exit
		if [ ! -e "version.txt" ] ; then
			cd "$HOME/steamcmd" || exit
			 ./steamcmd.sh +force_install_dir "$HOME/dst_beta" +login anonymous +app_update 343050 -beta updatebeta validate  +quit
		fi
	fi
	cd "$HOME" || exit 
	Main
}

# 切换游戏版本
function change_game_version()
{

	echo "###########################"
	echo "##### 请选择游戏版本: #####"
	echo "#      1.正式版32位       #"
	echo "#      2.正式版64位       #"
	echo "#      3.测试版32位       #"
	echo "#      4.测试版64位       #"
	echo "###########################"
	read -r game_version
	get_cluster_name
	if [ "$game_version" == "1" ]; then
		echo "更改服务端版本为正式版32位!"	
		echo "正式版32位" > "$DST_save_path/$cluster_name/gameversion.txt"
		cd "$HOME/dst" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
		fi
	elif [ "$game_version" == "2" ]; then
		echo "更改服务端版本为正式版64位!"	
		echo "正式版64位" > "$DST_save_path/$cluster_name/gameversion.txt"
		cd "$HOME/dst" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
		fi
	elif [ "$game_version" == "3" ]; then
		echo "更改服务端版本为测试版32位!"	
		echo "测试版32位" > "$DST_save_path/$cluster_name/gameversion.txt"
		cd "$HOME/dst_beta" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			 ./steamcmd.sh +force_install_dir "$HOME/dst_beta" +login anonymous +app_update 343050 -beta updatebeta validate  +quit
		fi
	elif [ "$game_version" == "4" ]; then
		echo "更改服务端版本为测试版64位!"	
		echo "测试版64位" > "$DST_save_path/$cluster_name/gameversion.txt"
		cd "$HOME/dst_beta" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			 ./steamcmd.sh +force_install_dir "$HOME/dst_beta" +login anonymous +app_update 343050 -beta updatebeta validate  +quit
		fi
	else
		echo "输入有误,请重新输入"
		change_game_version
	fi
    Main
}

# 更新游戏
function update_game()
{
	cd "$HOME/steamcmd" || exit
    echo "正在更新游戏,请稍后。。。更新之后重启服务器生效哦。。。"
    if [[ ${DST_game_version} == "正式版32位" || ${DST_game_version} == "正式版64位" ]]; then
	    echo "当前服务端版本为${DST_game_version}"
	    ./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
	else
        echo "当前服务端版本为${DST_game_version}"
	     ./steamcmd.sh +force_install_dir "$HOME/dst_beta" +login anonymous +app_update 343050 -beta updatebeta validate  +quit
    fi
}

prepare
clear
Main | column -t
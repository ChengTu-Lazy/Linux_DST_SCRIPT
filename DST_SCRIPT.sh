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
# 2022/11/28 更改备份命名格式，增加使用备份存档回档的功能
# 2023/01/09 新增存储玩家信息功能,位置在"${DST_SAVE_PATH}"/"$cluster_name"/PlayerList/，方便查找id来ban人，查看房间人数方法调整，更改备份数量至20为上限
# 2023/01/10 优化代码结构，更改保存人物信息为有人在服务器的时候再保存
# 2023/01/11 更加智能的更新脚本，不在绝对路径更新到最高级目录
# 2023/02/08 增加仅在服务器无人时更新的设置（在控制台功能中）
# 2023/04/16 修复开启存档时出现存档崩溃卡在检测开启的阶段的bug
# 2023/04/17 修改一部分ui，更方便选择，直接输入数字即可
# 2023/06/05 给代码归类，加注释，方便查阅更改，统一初始化，不再独立初始化


##常量区域

#测试版token
BETA_TOKEN="returnofthembeta"
# 饥荒存档位置
DST_SAVE_PATH="$HOME/.klei/DoNotStarveTogether"
# 默认游戏路径
DST_DEFAULT_PATH="$HOME/DST"
DST_BETA_PATH="$HOME/DST_BETA"
#脚本版本
script_version="1.7.3"
# git加速链接
use_acceleration_url="https://ghp.quickso.cn/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT"
# 当前系统版本
os=$(awk -F = '/^NAME/{print $2}' /etc/os-release | sed 's/"//g' | sed 's/ //g' | sed 's/Linux//g' | sed 's/linux//g')
# 脚本当前所在目录
script_path=$(pwd)
# 脚本当前名称
SCRIPT_NAME=$(basename "$0")

##基础数据的获取
#数据统一初始化
init(){
	cluster_name=$1
	if [ "$cluster_name" == "" ]; then
		ehco "存档名有误"
		return 0
	fi
	# 获取存档所在路径
	get_path_cluster "$cluster_name"
	# 脚本文件所在路径
	get_path_script_files "$cluster_name"
	# 获取游戏版本和版本对应获取buildid的flag
	get_path_games "$cluster_name"
	# 获取游戏官方开服脚本所在位置和名字
	get_path_dontstarve_dedicated_server_nullrenderer "$cluster_name"
	# 获取游戏版本
	get_cluster_dst_game_version "$cluster_name"
	#确认存档情况
	get_cluster_flag "$cluster_name"
	# 获取mod自动更新配置文件位置
	get_dedicated_server_mods_setup "$cluster_name"
	# 获取存档路径和主要存档，地上优先于地下，主要是用于控制台指令的选择
	get_cluster_main "$cluster_name"
	# 获取存档进程名
	get_process_name  "$cluster_name"
	#获取日志文件路径
	get_path_server_log  "$cluster_name"
	# 获取存档的日志路径
	get_path_server_log "$cluster_name"
	# 获取进程名（判断是否有开启）
	get_process_name "$cluster_name"
	# 获取当前存档的世界分布情况
	get_cluster_flag "$cluster_name"
	# 保存独立存档mod文件的位置
	ugc_mods_path="${gamesPath}/ugc_mods/$cluster_name"
	# 获取mod所在目录
	modoverrides_path=$cluster_main/modoverrides.lua
	# 判断是否成功开启存档的标志
	check_flag=0
}

# 获取存档所在路径
get_path_cluster(){
	cluster_name=$1
	cluster_path="${DST_SAVE_PATH}"/"$cluster_name"
}

# 脚本文件所在路径
get_path_script_files(){
	cluster_name=$1
	get_path_cluster "$cluster_name"
	script_files_path="$cluster_path/ScriptFiles"
	# 判断是否存在这个文件夹，不存在就创建
	if [ ! -d "$script_files_path" ]; then
		mkdir "$script_files_path"
	fi
	# 删除旧版本脚本残余文件
	if [ -f "$script_files_path/gameversion.txt" ];then
		rm -rf "$script_files_path/gameversion.txt"
	fi
}

# 获取游戏版本和版本对应获取buildid的flag
get_path_games(){
	cluster_name=$1
	get_path_script_files "$cluster_name"
	if [[ $(grep --text -c "正式版" "$script_files_path/config.txt") -gt 0 ]]; then
		gamesPath="$DST_DEFAULT_PATH"
		buildid_version_flag="public"
	else
		gamesPath="$DST_DEFAULT_PATH_BETA"
		buildid_version_flag="updatebeta"
	fi
}

# 获取游戏官方开服脚本所在位置和名字
get_path_dontstarve_dedicated_server_nullrenderer(){
	cluster_name=$1
	get_path_games "$cluster_name"
	get_path_script_files "$cluster_name"
	if [[ $(grep --text -c "32位" "$script_files_path/config.txt") -gt 0 ]]; then
		dontstarve_dedicated_server_nullrenderer_path="${gamesPath}"/bin
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer"
	else
		dontstarve_dedicated_server_nullrenderer_path="${gamesPath}"/bin64
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer_x64"
	fi
}

# 获取游戏版本
get_cluster_dst_game_version(){
	cluster_name=$1
	get_path_script_files "$cluster_name"
	cluster_dst_game_version=$(grep version "$script_files_path/config.txt" | awk '{print $3}')
}

#确认存档情况
get_cluster_flag() {
	cluster_name=$1
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Master" ]; then
		cluster_flag=4
	else
		cluster_flag=7
	fi
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Caves" ]; then
		cluster_flag=$((cluster_flag - 3))
	else
		cluster_flag=$((cluster_flag - 2))
	fi
}

# 获取mod自动更新配置文件位置
get_dedicated_server_mods_setup(){
	cluster_name=$1
	get_path_games "$cluster_name"
	dedicated_server_mods_setup="${gamesPath}"/mods/dedicated_server_mods_setup.lua
}

# 获取存档路径和主要存档，地上优先于地下，主要是用于控制台指令的选择
get_cluster_main(){
	cluster_name=$1
	# 存档所在路径
	get_path_cluster "$cluster_name"
	# 地上存档的路径
	master_saves_path="$cluster_path/Master"
	# 地下存档的路径
	caves_saves_path="$cluster_path/Caves"
	if [ -d "$master_saves_path" ]; then
		cluster_main="$master_saves_path"
	else
		cluster_main="$caves_saves_path"
	fi
}

# 获取存档进程名
get_process_name() {
	cluster_name=$1
	# 自动更新脚本的进程名
	process_name_AutoUpdate="AutoUpdate $cluster_name"
	# 获取游戏版本
	get_cluster_dst_game_version "$cluster_name"
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Caves" ]; then
		if [[ $cluster_dst_game_version == "正式版32位" || $cluster_dst_game_version == "正式版64位" ]]; then
			process_name_caves="DST_Caves $cluster_name"
			process_name_main="DST_Caves $cluster_name"
		else
			process_name_caves="DST_Caves_beta $cluster_name"
			process_name_main="DST_Caves_beta $cluster_name"
		fi
	fi
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Master" ]; then
		if [[ $cluster_dst_game_version == "正式版32位" || $cluster_dst_game_version == "正式版64位" ]]; then
			process_name_master="DST_Master $cluster_name"
			process_name_main="DST_Master $cluster_name"
		else
			process_name_master="DST_Master_beta $cluster_name"
			process_name_main="DST_Master_beta $cluster_name"
		fi
	fi
}

#获取日志文件路径
get_path_server_log() {
	cluster_name=$1
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Caves" ]; then
		server_log_path_main="${DST_SAVE_PATH}/$cluster_name/Caves/server_log.txt"
		server_log_path_caves="${DST_SAVE_PATH}/$cluster_name/Caves/server_log.txt"
	fi
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Master" ]; then
		server_log_path_main="${DST_SAVE_PATH}/$cluster_name/Master/server_log.txt"
		server_log_path_master="${DST_SAVE_PATH}/$cluster_name/Master/server_log.txt"
	fi
}

# 配置文件
setconfig(){
	cluster_name=$1
	if [ ! -f "$script_files_path/config.txt" ]; then
		echo "version = 正式版32位" > "$script_files_path/config.txt"
		echo "auto_update_anyway = true" >> "$script_files_path/config.txt"
	fi
}


## 开服相关

# 开启服务器
start_server() {
	if [ "$cluster_name" == "" ]; then
		main
	elif [ -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		if [ "$(screen -ls | grep --text -c "\<$process_name_caves\>")" -gt 0 ]; then
			echo "该服务器已开启地下服务器,请先关闭再启动！！"
		elif [ "$(screen -ls | grep --text -c "\<$process_name_master\>")" -gt 0 ]; then
			echo "该服务器已开启地上服务器,请先关闭再启动！！"
		else
			# 判断是否有token文件
			cd "${DST_SAVE_PATH}/$cluster_name" || exit
			if [ ! -e "cluster_token.txt" ]; then
				while [ ! -e "cluster_token.txt" ]; do
					echo "该存档没有token文件,是否自动添加作者的token"
					echo "请输入 Y/y 同意 或者 N/n 拒绝并自己提供一个"
					read -r token_yes
					if [ "$token_yes" == "Y" ] || [ "$token_yes" == "y" ]; then
						echo "pds-g^KU_iC59_53i^+AGkfKRdMm8uq3FSa08/76lKK1YA8r0qM0iMoIb6Xx4=" >"cluster_token.txt"
					elif [ "$token_yes" == "N" ] || [ "$token_yes" == "N" ]; then
						read -r token_no
						echo "$token_no" >"cluster_token.txt"
					else
						echo "输入有误,请重新输入！！！"
					fi
				done
			fi
			howtostart "$cluster_name"
		fi
	else
		echo -e "\e[31m未找到这个存档 \e[0m"
	fi
}

# 选择开启方式
howtostart() {
	cluster_name=$1
	check_player=$3
	addmod "$cluster_name"
	(case $cluster_flag in
		# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
		1)
			start_server_select "$cluster_name" "$process_name_master" "start_server_master.sh"
			start_server_select "$cluster_name" "$process_name_caves" "start_server_caves.sh"
			;;
		2)
			start_server_select "$cluster_name" "$process_name_master" "start_server_master.sh"
			;;
		3)
			echo "这行纯粹凑字数,没用的"
			;;
		4)
			start_server_select "$cluster_name" "$process_name_caves" "start_server_caves.sh"
			;;
		5)
			echo "存档没有内容,请自行创建！！！"
			;;
		esac)
	if [ "$cluster_flag" == "" ]; then
		echo "出错了,请联系作者QQ1549737287!!!"
	else
		start_server_check "$cluster_name"
		if [ "$cluster_flag" != 5 ] && [[ $check_flag == 1 ]] && [[ $2 == "" ]]; then
			auto_update "$cluster_name"
		fi
	fi
}

#开启服务器
start_server_select() {
	cluster_name=$1
	process_name_select=$2
	script_start_server=$3
	if [ "$script_start_server" == "start_server_master.sh" ]; then
		shard_name="Master"
	else
		shard_name="Caves"
	fi
	echo "#!/bin/bash
	cd \"$dontstarve_dedicated_server_nullrenderer_path\" || exit
	run_shared=(./$dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard $shard_name" >"$script_files_path"/"$script_start_server"
	grep --text -m 1 buildid "$gamesPath"/steamapps/appmanifest_343050.acf | sed 's/[^0-9]//g' > "$script_files_path"/"cluster_game_buildid.txt"
	chmod 777 "$script_files_path"/"$script_start_server"
	screen -dmS "$process_name_select" /bin/sh -c "$script_files_path/$script_start_server"
}

#检查是否成功开启
start_server_check() {
	cluster_name=$1
	start_time=$(date +%s)
	if [[ "$(screen -ls | grep --text -c "\<$process_name_master\>")" -gt 0 ]]; then
		start_server_check_select "地上" "$server_log_path_master"
	fi
	if [[ "$(screen -ls | grep --text -c "\<$process_name_caves\>")" -gt 0 ]]; then
		start_server_check_select "地下" "$server_log_path_caves"
	fi
	end_time=$(date +%s)
	cost_time=$((end_time - start_time))
	cost_minutes=$((cost_time / 60))
	cost_seconds=$((cost_time % 60))
	cost_echo="$cost_minutes分$cost_seconds秒"
	if [ $cost_echo == "00分00秒" ] || [ $cost_echo == "0分0秒" ]; then
		start_server_check_fix
	else
		echo -e "\r\e[92m本次开服花费时间$cost_echo:\e[0m"
		check_flag=1
		sleep 1
		return 1
	fi
}

# 判断是否成功开启
start_server_check_select() {
	w_flag=$1
	logpath_flag=$2
	auto_flag=$3
	mod_flag=1
	download_flag=1
	check_flag=0
	while :; do
		checkprocess "$cluster_name" "no_output"
		if [ "$check_flag" == 0 ] && [ $mod_flag == 0 ]; then
			echo -en "\r$w_flag服务器开启中,请稍后.                              "
			sleep 1
			echo -en "\r$w_flag服务器开启中,请稍后..                             "
			sleep 1
			echo -en "\r$w_flag服务器开启中,请稍后...                            "
			sleep 1
		fi
		if [ $mod_flag == 1 ] && [[ $(grep --text "FinishDownloadingServerMods Complete!" -c "$logpath_flag") -eq 0 ]] && [[ $(grep --text "SUCCESS: Loaded modoverrides.lua" -c "$logpath_flag") -eq 0 ]]; then
			echo -en "\r正在检测$w_flag服务器mod是否完成下载,请稍后.                    "
			sleep 1
			echo -en "\r正在检测$w_flag服务器mod是否完成下载,请稍后..                   "
			sleep 1
			echo -en "\r正在检测$w_flag服务器mod是否完成下载,请稍后...                  "
			sleep 1
		fi
		if [[ $(grep --text "FinishDownloadingServerMods Complete!" -c "$logpath_flag") -gt 0 ]] || [[ $(grep --text "SUCCESS: Loaded modoverrides.lua" -c "$logpath_flag") -gt 0 ]] && [ $mod_flag == 1 ]; then
			echo -e "\r\e[92m$w_flag服务器mod下载完成!!!                                                                  \e[0m"
			mod_flag=0
			download_flag=0
		elif [[ $(grep --text "[Workshop] OnDownloadPublishedFile" -c "$logpath_flag") -gt 0 ]] && [ $download_flag == 1 ]; then
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后.                         "
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后..                        "
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后...                       "
			sleep 1
		fi
		if [[ $(grep --text "Sim paused" -c "$logpath_flag") -gt 0 || $(grep --text "shard LUA is now ready!" -c "$logpath_flag") -gt 0 ]] && [ $mod_flag == 0 ] && [ $download_flag == 0 ] && [ "$check_flag" == 0 ]; then
			echo -e "\r\e[92m$w_flag服务器开启成功!!!                          \e[0m"
			sleep 1
			check_flag=1
			return 1
		fi
		if [[ $(grep --text "Your Server Will Not Start !!!" -c "$logpath_flag") -gt 0 ]]; then
			echo -e "\r\e[1;31m$w_flag服务器开启未成功,请注意令牌是否成功设置且有效。也可能是klei网络问题,那就不用管。稍后会自动重启该存档。\e[0m"
			close_server "$cluster_name" "$auto_flag"
			start_server "$cluster_name" "$auto_flag"
		fi
		if [[ $(grep --text "PushNetworkDisconnectEvent With Reason: \"ID_DST_INITIALIZATION_FAILED\", reset: false" -c "$logpath_flag") -gt 0 ]]; then
			echo -e "\r\e[1;31m$w_flag服务器开启未成功,端口冲突啦，改下端口吧,正在关闭服务器，请调整后重新开服！！！            \e[0m"
			close_server "$cluster_name" "$auto_flag"
			check_flag=0
			return 0
		fi
		if [[ $(grep --text "LAN only servers must use a port in the range of [10998, 11018]" -c "$logpath_flag") -gt 0 ]]; then
			echo -e "\r\e[1;31m$w_flag服务器开启未成功,端口冲突啦，改下端口吧,本地服务器端口范围是[10998, 11018],正在关闭服务器，请调整后重新开服！！！            \e[0m"
			close_server "$cluster_name" "$auto_flag"
			check_flag=0
			return 0
		fi
		if [[ $(grep --text "Failed to send shard broadcast message" -c "$logpath_flag") -gt 0 ]]; then
			sleep 2
			echo -e "\r\e[1;33m$w_flag服务器开启未成功,可能网络有点问题,正在自动重启。                             \e[0m"
			close_server "$cluster_name" "$auto_flag"
			start_server "$cluster_name" "$auto_flag"
		fi 
	done
}

# 依赖自动修复
start_server_check_fix() {
	echo "依赖可能出错了,尝试修复中,如果还是没有开启成功请联系作者"
	if [ "$os" == "Ubuntu" ]; then
		echo ""
		echo "##########################"
		echo "# 加载 Ubuntu Linux 环境 #"
		echo "##########################"
		echo ""
		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libcurl3-gnutls:i386
	elif
		[ "$os" == "CentOS" ]
	then
		echo ""
		echo "##########################"
		echo "# 加载 CentOS Linux 环境 #"
		echo "##########################"
		echo ""
		# 加载 32bit 库
		sudo yum -y install glibc.i686 libstdc++.i686 libcurl.i686
		# 加载 64bit 库
		sudo yum -y install glibc libstdc++ libcurl

	elif [ "$os" == "Arch" ]; then
		echo ""
		echo "########################"
		echo "# 加载 Arch Linux 环境 #"
		echo "########################"
		echo ""
		sudo pacman -Syyy
		sudo pacman -S --noconfirm wget screen
		sudo pacman -S --noconfirm lib32-gcc-libs libcurl-gnutls
	else
		echo -e "\e[31m 该系统未被本脚本支持！ \e[0m"
	fi
}

#自动添加存档所需的mod
addmod() {
	cluster_name=$1
	# mod所在目录
	modoverrides_path=$cluster_main/modoverrides.lua
	if [ -e "$modoverrides_path" ]; then
		echo "正在将开启存档所需的mod添加进服务器配置文件中..."
		cd "${gamesPath}"/mods || exit
		rm -rf dedicated_server_mods_setup.lua
		sleep 0.1
		echo "" >>dedicated_server_mods_setup.lua
		sleep 0.1
		grep --text "\"workshop" <"$modoverrides_path" | cut -d '"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line; do
			echo "ServerModSetup(\"$line\")" >>"$dedicated_server_mods_setup"
			echo "ServerModCollectionSetup(\"$line\")" >>"$dedicated_server_mods_setup"
			sleep 0.05
			echo -e "\e[92m$line Mod添加完成\e[0m"
		done
		echo -e "\e[92mMod添加完成!!!\e[0m"
	else
		echo -e "\e[1;31m未找到mod配置文件 \e[0m"
	fi
}

#主菜单
main() {
	tput setaf 2
	echo "============================================================"
	printf "%s\n" "                     脚本版本:${script_version}                            "
	echo "============================================================"
	while :; do
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
		read -r maininfo
		if [ "$maininfo" == 1 ]; then
			# 初始化环境
			PreLibrary
			prepare
		elif [ "$maininfo" == 3 ] || [ "$maininfo" == 5 ] || [ "$maininfo" == 6 ]; then
			get_cluster_name_processing
		elif [ "$maininfo" == 2 ] || [ "$maininfo" == 7 ] || [ "$maininfo" == 8 ]; then
			get_cluster_name
		fi
		(case $maininfo in
			2)
				# 开服
				start_server "$cluster_name"
				;;
			3)
				# 关服
				close_server "$cluster_name" -close
				;;
			4)
				# 查看服务器进程
				check_server "$cluster_name"
				;;
			5)
				# 控制台
				console "$cluster_name"
				;;
			6)
				# 重启服务器
				restart_server "$cluster_name"
				;;
			7)
				# 更换存档所开启的游戏版本
				change_game_version "$cluster_name"
				;;
			8)
				# 列出存档所使用的所有的mod
				list_all_mod "$cluster_name"
				;;
			9)
				# 获取最新脚本
				get_latest_version
				;;
			esac)
	done
}

# 控制台
console() {
	cluster_name=$1
	clear
	
	while :; do
		echo "==============================请输入需要进行的操作序号=============================="
		echo "                                                                                  "
		echo "	[1]服务器信息          [2]回档          [3]发布通知			"
		echo "                                                                                  "
		echo "	[4]全体复活            [5]查看玩家       [6]利用备份回档-地上"
		echo "                                                                                  "
		echo "	[7]利用备份回档-地下   [8]无人时更新配置  [9]返回上一级"
		echo "                                                                                  "
		echo "=================================================================================="
		echo "                                                                                  "
		echo -e "\e[92m请输入命令代号:\e[0m"
		read -r consoleinfo
		(case $consoleinfo in
			1) serverinfo ;;
			2)
				echo "请输入你要回档的天数(1~5):"
				read -r rollbackday
				screen -r "$process_name_main" -p 0 -X stuff "c_rollback($rollbackday)$(printf \\r)"
				echo "已回档$rollbackday 天！"
				;;
			3)
				echo "请输入你要发布的公告:"
				read -r str
				screen -r "$process_name_main" -p 0 -X stuff "c_announce(\"$str\")$(printf \\r)"
				echo "已发布通知！"
				;;
			4)
				screen -r "$process_name_main" -p 0 -X stuff "for k,v in pairs(AllPlayers) do v:PushEvent('respawnfromghost') end$(printf \\r)"
				echo "已复活全体玩家！"
				;;
			5)
				get_playerList "$cluster_name"
				;;
			6)
				get_server_save_path_master
				;;
			7)
				get_server_save_path_caves
				;;
			8) config_auto_update_anyway 
				;;
			9) main 
				;;
			esac)
	done
}

# 无人时更新的配置
config_auto_update_anyway(){
	if [ "$(grep --text auto_update_anyway  "$script_files_path/config.txt"  | awk '{print $3}')" == "true" ];then
		echo "当前为直接更新，无论服务器有没有人"
	elif [ "$(grep --text auto_update_anyway  "$script_files_path/config.txt"  | awk '{print $3}')" == "false" ];then
		echo "当前为仅在服务器有没人时更新"
	fi
	auto_update_anyway=$(grep --text auto_update_anyway  "$script_files_path/config.txt"  | awk '{print $3}')
	echo "##############################################"
	echo "############# 请选择更改到的模式 #############"
	echo "#       1.直接更新，无论服务器有没有人       #"
	echo "#       2.仅在服务器有没人时更新             #"
	echo "##############################################"
	echo "输入数字序号即可,如:1 "
	read -r auto_update_anyway_select
	if [ "$auto_update_anyway_select" == "1" ];then
		sed -i "2s/${auto_update_anyway}/true/g"  "$script_files_path/config.txt"
		echo "已修改为直接更新，无论服务器有没有人"
	elif [ "$auto_update_anyway_select" == "2" ];then
		sed -i "2s/${auto_update_anyway}/false/g"  "$script_files_path/config.txt"
		echo "已修改为仅在服务器有没人时更新"
	else 
		echo "输入有误，请重新输入"
		config_auto_update_anyway "$cluster_name"
	fi
}


# 重启服务器
restart_server() {
	cluster_name=$1
	auto_flag=$2
	check_player=$3
	close_server "$cluster_name" "$auto_flag" "$check_player"
	howtostart "$cluster_name" "$auto_flag" "$check_player"
}
# 更新游戏
update_game() {
	version_flag=$1
	cd "$HOME/steamcmd" || exit
	echo "正在更新游戏,请稍后。。。更新之后重启服务器生效哦。。。"
	if [[ ${version_flag} == "DEFAULT" ]]; then
		echo "同步最新正式版游戏本体内容中。。。"
		./steamcmd.sh +force_install_dir "$DST_DEFAULT_PATH" +login anonymous +app_update 343050 validate +quit
	else
		echo "同步最新测试版版游戏本体内容中。。。"
		./steamcmd.sh +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
	fi
}

# 关闭服务器
close_server() {
	cluster_name=$1
	close_flag=$2
	check_player=$3
	if [ "$cluster_name" == "" ]; then
		main
	elif [ -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		if [ "$close_flag" == "" ] || [ "$close_flag" == "-close" ] ;then
			close_server_autoUpdate "$cluster_name"
		fi
		# 进程名称符合就删除
		while :; do
			sleep 1
			if [[ $(screen -ls | grep --text -c "\<$process_name_master\>") -gt 0 ]]; then
				close_server_select "$process_name_master" "地上" "$close_flag" "$check_player" 
			elif [[ $(screen -ls | grep --text -c "\<$process_name_caves\>") -gt 0  ]]; then
				close_server_select "$process_name_caves" "地下" "$close_flag"  "$check_player" 
			else
				echo -e "\r\e[92m进程 $cluster_name 已关闭!!!                   \e[0m "
				break
			fi
		done
	else
		echo -e "\e[1;31m未找到这个存档 \e[0m"
	fi
}

# 关闭服务器解耦部分
close_server_select() {
	process_name_close=$1
	world_close_flag=$2
	close_flag=$3
	check_player=$4
	player_flag="false"
	if [ "$check_player" == "-NOBODY" ];then
		get_playerList "$cluster_name"
		if [ "$have_player" != false ]; then
			player_flag="true"
		fi
	fi
	if [[ "$player_flag" == "false" ]] || [ "$close_flag" == "" ] || [ "$close_flag" == "-close" ];then
		if [ "$close_flag" == "-close" ];then
			c_announce="服务器即将关闭，给您带来的不便还请谅解！！！"
		elif [ "$close_flag" == "" ];then
			c_announce="服务器需要重启,给您带来的不便还请谅解！！！"
		fi
		for i in $(screen -ls | grep --text -w "$process_name_close" | awk '/[0-9]{1,}\./ {print strtonum($1)}'); do
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r$world_close_flag服务器正在发布公告.  "
			sleep 1.5
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r$world_close_flag服务器正在发布公告.. "
			sleep 1.5
			screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
			echo -en "\r$world_close_flag服务器正在发布公告..."
			sleep 1.5
			screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
			echo -e "\r\e[92m$world_close_flag服务器公告发布完毕!!!                \e[0m"
		done
		while :; do
			sleep 1
			if [[ $(screen -ls | grep --text -c "\<$process_name_close\>") -gt 0 ]]; then
				sleep 1.5
				echo -en "\r$world_close_flag进程 $cluster_name 正在关闭,请稍后.  "
				sleep 1.5
				echo -en "\r$world_close_flag进程 $cluster_name 正在关闭,请稍后.. "
				sleep 1.5
				echo -en "\r$world_close_flag进程 $cluster_name 正在关闭,请稍后..."
			else
				echo -e "\r\e[92m$world_close_flag进程 $cluster_name 已关闭!!!                    \e[0m"
				sleep 1
				break
			fi
		done
	else
		echo "由于设置了仅在无人时更新,所以暂时不更新！"
	fi

}

# 关闭服务器自动管理部分
close_server_autoUpdate() {
	process_name_AutoUpdate="AutoUpdate $1"
	process_name_AutoUpdate_old="DST $1 AutoUpdate"
	if [ "$(screen -ls | grep --text -c "\<$process_name_AutoUpdate\>")" -gt 0 ] && [ "$process_name_AutoUpdate" != "" ]; then
		for i in $(screen -ls | grep --text -w "$process_name_AutoUpdate" | awk '/[0-9]{1,}\./ {print strtonum($1)}'); do
			kill "$i"
		done
	elif [ "$(screen -ls | grep --text -c "\<$process_name_AutoUpdate_old\>")" -gt 0 ] && [ "$process_name_AutoUpdate" != "" ]; then
		for i in $(screen -ls | grep --text -w "$process_name_AutoUpdate_old" | awk '/[0-9]{1,}\./ {print strtonum($1)}'); do
			kill "$i"
		done
	else
		echo -e "\e[1;33m$process_name_AutoUpdate 并未执行! \e[0m"
	fi
}

#查看游戏更新情况
checkupdate() {
	cluster_name=$1
	get_path_games "$cluster_name"
	# 保存buildid的位置
	buildid_version_path="$gamesPath/bin/buildid.txt"
	DST_now=$(date +%Y年%m月%d日%H:%M)
	cd "$HOME"/steamcmd || exit 
	# 判断一下对应开启的版本
	# 获取最新buildid
	echo "正在获取最新buildid。。。"
	./steamcmd.sh +login anonymous +app_info_update 1 +app_info_print 343050 +quit | sed -e '/"branches"/,/^}/!d' | sed -n "/\"$buildid_version_flag\"/,/}/p" | grep --text -m 1 buildid | sed 's/[^0-9]//g' > "$buildid_version_path"
	#查看buildid是否一致
	if [[ $(sed 's/[^0-9]//g' "$buildid_version_path") -gt $(cat "$script_files_path"/"cluster_game_buildid.txt") ]]; then
		echo " "
		echo -e "\e[31m${DST_now}:游戏服务端有更新! \e[0m"
		echo " "
		# 先检查游戏本体是不是最新的，如果是的话，那就直接重启存档就可以了,不然的话就先更新游戏本体
		if [[ $(sed 's/[^0-9]//g' "$buildid_version_path") -gt $(grep --text -m 1 buildid "$gamesPath"/steamapps/appmanifest_343050.acf | sed 's/[^0-9]//g') ]]; then
			# 更新游戏本体
			if [ "$buildid_version_flag" == "public" ];then
				echo -e "\e[33m${DST_now}:更新正式版游戏本体中。。。 \e[0m"
				update_game DEFAULT
			else
				echo -e "\e[33m${DST_now}:更新测试版游戏本体中。。。 \e[0m"
				update_game BETA
			fi
		fi
		auto_update_anyway=$(grep --text auto_update_anyway  "$script_files_path/config.txt"  | awk '{print $3}')
		if [ "$auto_update_anyway" == "true" ];then
			# 重启该存档，但不关闭当前进程
			restart_server  "$cluster_name"  -AUTO
		else
			restart_server  "$cluster_name"  -AUTO  -NOBODY
		fi
	else
		echo -e "\e[92m${DST_now}:游戏服务端没有更新!\e[0m"
	fi
}

# 查看游戏mod更新情况
checkmodupdate() {
    cluster_name=${1:?Usage: checkmodupdate [cluster_name]}
    DST_now=$(date +%Y年%m月%d日%H:%M)
    get_path_games "$cluster_name"
    get_cluster_flag "$cluster_name"

    # 保存独立存档mod文件的位置
    ugc_mods_path="${gamesPath}/ugc_mods/$cluster_name"
    get_path_server_log "$cluster_name"

    echo ""
    echo -e "\e[92m${DST_now}: 正在检查服务器mod是否有更新...\e[0m"
    cd "$dontstarve_dedicated_server_nullrenderer_path" || exit

    local has_mods_update=false
    case $cluster_flag in
        1|2) # 地上地下都有或者只有地上
            ./"$dontstarve_dedicated_server_nullrenderer" \
                -cluster "$cluster_name" \
                -shard Master \
                -only_update_server_mods \
                -ugc_directory "$ugc_mods_path/$cluster_name" > "$cluster_name".txt

            if grep --text -q -e "is out of date and needs to be updated for new users to be able to join the server" "${server_log_path_master}" \
                || grep --text -q -e "模组已过期" "${server_log_path_master}"; then
                has_mods_update=true
            fi
            ;;
        4) # 只有地下
            ./"$dontstarve_dedicated_server_nullrenderer" \
                -cluster "$cluster_name" \
                -shard Caves \
                -only_update_server_mods \
                -ugc_directory "$ugc_mods_path/$cluster_name" > "$cluster_name".txt

            if grep --text -q -e "is out of date and needs to be updated for new users to be able to join the server" "${server_log_path_caves}" \
                || grep --text -q -e "模组已过期" "${server_log_path_caves}"; then
                has_mods_update=true
            fi
            ;;
    esac

    if grep --text -q -e "DownloadPublishedFile" "${dontstarve_dedicated_server_nullrenderer_path}/$cluster_name.txt"; then
        has_mods_update=true
    fi

    if $has_mods_update; then
        if [[ "$auto_update_anyway" == "true" ]]; then
            # 重启该存档，但不关闭当前进程
            echo ""
            echo -e "\e[31m${DST_now}: Mod 有更新！\e[0m"
            echo ""

            c_announce="检测到游戏Mod有更新,需要重新加载mod,给您带来的不便还请谅解！！！"
            restart_server "$cluster_name" -AUTO
        else
            restart_server  "$cluster_name"  -AUTO  -NOBODY
        fi
    else
        echo ""
        echo -e "\e[92m${DST_now}: Mod 没有更新！\e[0m"
        echo ""
    fi
}


#查看进程执行情况
checkprocess() {
	cluster_name=$1
	flag_checkprocess=$2
	if [ -d "$master_saves_path" ]; then
		checkprocess_select "$cluster_name" "地上" "$flag_checkprocess"
	fi
	if [ -d "$caves_saves_path" ]; then
		checkprocess_select "$cluster_name" "地下" "$flag_checkprocess"
	fi
}

checkprocess_select() {
	cluster_name=$1
	world_check_flag=$2
	flag_checkprocess=$3
	log_path=$server_log_path_main
	if [ "$world_check_flag" == "地上" ]; then
		script_name="start_server_master.sh"
		process_name_check=$process_name_master
	else
		script_name="start_server_caves.sh"
		process_name_check=$process_name_caves
	fi

	if [[ $(screen -ls | grep --text -c "\<$process_name_check\>") -eq 1 ]]; then
		if [[ "$flag_checkprocess" != "no_output" ]]
		then
			echo "$world_check_flag 服务器运行正常"
		fi
	else
		echo "$world_check_flag 服务器已经关闭,自动开启中。。。"
		start_server_select "$cluster_name" "$process_name_check" "$script_name" -AUTO
		start_server_check_select "$world_check_flag" "$log_path"  -AUTO
	fi

	if [[ $(grep --text "Failed to send server broadcast message" -c "${log_path}") -gt 0 ]] || [[ $(grep --text "Failed to send server listings" -c "${log_path}") -gt 0 ]]; then
		get_playerList "$cluster_name"
		if [ "$have_player" == false ]; then
			c_announce="Failed to send server broadcast message或者Failed to send server listings,网络有点问题，且当前服务器没人，服务器需要重启,给您带来的不便还请谅解！！！"
			restart_server "$cluster_name" -AUTO
		fi
	fi
}

# 查看游戏服务器状态
check_server() {
	echo " "
	printf '=%.0s' {1..60}
	echo " "
	echo " "
	echo ""
	sessions=$(screen -ls | grep Detached | cat -n | awk '{printf "%-4s%s %s\n", $1, $2,$3}' )
	echo "$sessions"
	echo ""
	echo " "
	printf '=%.0s' {1..23}
	echo -e "输入要切换的PID\c"
	printf '=%.0s' {1..23}
	echo ""
	echo ""
	echo "PS:回车后会进入地上或地下的运行界面"
	echo "   手动输入c_shutdown(true)回车保存退出"
	echo "   进入后不想关闭请按ctrl+a+d"
	read -r folder_number
	pid1=$(echo "$sessions" | awk '{if($1 == '"$folder_number"') print $2}'  | cut -d '.' -f1)
	screen -r "$pid1"
}

# 自动更新
auto_update() {
	cluster_name=$1
	cd "$HOME" || exit
	cd "${cluster_path}" || exit
	# 配置auto_update.sh
	printf "%s" "#!/bin/bash
	# 当前脚本所在位置及名称
	script_path_name=\"$script_path/$SCRIPT_NAME\"
	# 使用脚本的方法
	script(){
		bash \$script_path_name \"\$1\" $cluster_name \"-AUTO\"
	}
	# 获取天数信息
	get_daysInfo()
	{
		datatime=\$(date +%s%3N)
		screen -r \"$process_name_main\" -p 0 -X stuff \"print(TheWorld.components.worldstate.data.cycles .. \\\" \$datatime cycles\\\")\$(printf \\\r)\"
		sleep 1
		presentday=\$(grep --text \"$server_log_path_main\" -e \"\$datatime\" | cut -d \" \" -f2 | tail -n +2 )
	}
	backup()
	{
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
					find . -maxdepth 1 -mtime +30 -name '*.zip'  | awk '{if(NR -gt 10){print \$1}}' |xargs rm -f {};
				fi
				cd \"$master_saves_path\"|| exit
				zip -r saves_bak/\"master_\${presentday}days\".zip save/ >> /dev/null 2>&1
			fi
			if [ -d \"$caves_saves_path\" ];then
				cd \"$caves_saves_path\" || exit			
				if [ ! -d \"$caves_saves_path/saves_bak\" ];then
					mkdir saves_bak
				fi
				cd \"$caves_saves_path/saves_bak\" || exit
				caves_saves_bak=\$(find . -maxdepth 1 -name '*.zip' | wc -l)
				if [ \"\$caves_saves_bak\" -gt 21 ];then
					find . -maxdepth 1 -mtime +30 -name '*.zip'  | awk '{if(NR -gt 10){print \$1}}' |xargs rm -f {};
				fi
				cd \"$caves_saves_path\" || exit
				zip -r saves_bak/\"caves_\${presentday}days\".zip save/ >> /dev/null 2>&1
			fi
			cd 	\"$script_files_path\" || exit
			if [ ! -d \"$script_files_path/Player\" ];then
				mkdir Player
			fi
			zip -r $script_files_path/Player/\"playerlist_\${presentday}days\".zip \"playerlist.txt\" >> /dev/null 2>&1
			echo \"\" > playerlist.txt
			ZipNum_Player=\$(find . -maxdepth 1 -name '*.zip' | wc -l)
			if [ \"\$ZipNum_Player\" -gt 21 ];then
				find . -maxdepth 1 -mtime +30 -name '*.zip'  | awk '{if(NR -gt 10){print \$1}}' |xargs rm -f {};
			fi
		fi
	}
	timecheck=0
	# 保持运行
	while :
			do
				script -checkprocess
				script -get_playerList
				get_daysInfo		
				echo \"当前服务器天数:\$presentday\"		
				timecheck=\$(( timecheck%750 ))
				backup
				((timecheck++))
				script -checkupdate
				script -checkmodupdate
				sleep 10
			done
	" >"$script_files_path"/auto_update.sh
	chmod 777 "$script_files_path"/auto_update.sh 
	screen -dmS "$process_name_AutoUpdate" /bin/sh -c "$script_files_path/auto_update.sh"
	echo -e "\e[92m自动更新进程 $process_name_AutoUpdate 已启动\e[0m"
	sleep 1
}

# 列出所有的mod
list_all_mod() {
	tput setaf 2
	clear
	# 各个世界模组所在的位置
	mods_path_master="$ugc_mods_path"/Master/content/322330
	mods_path_caves="$ugc_mods_path"/Caves/content/322330
	show=true
	if [ -d "$mods_path_master" ]; then
		mods_path=$mods_path_master
	elif [ -d "$mods_path_caves" ]; then
		mods_path=$mods_path_caves
	else
		show=false
		printf '=%.0s' {1..60}
		echo ""
		echo ""
		echo "当前存档没有配置或者下载mod"
		echo ""
		printf '=%.0s' {1..60}
	fi
	if [ $show == "true" ]; then
		echo "                                                                                  "
		echo "                                                                                  "
		printf '=%.0s' {1..27}
		echo -e " $cluster_name存档已下载的mod如下: \c"
		printf '=%.0s' {1..27}
		echo " "
		echo ""
	fi
	if [ "$mods_path" != "" ]; then
		for i in $(find "$mods_path" -maxdepth 1 -exec basename {} \; | awk '{print $NF}'); do
			if [[ -f "$mods_path/$i/modinfo.lua" ]]; then
				name=$(grep --text "$mods_path/$i/modinfo.lua" -e "name =" | cut -d '"' -f 2 | head -1)
				echo -e "\e[92m$i\e[0m------\e[33m$name\e[0m"
			fi
		done
		echo ""
		printf '=%.0s' {1..80}
	fi
}

# 显示存档
get_cluster_name() {
	if [ ! -d "${DST_SAVE_PATH}" ]; then
		mkdir "$HOME"/.klei
		cd "$HOME"/.klei || exit
		mkdir "${DST_SAVE_PATH}"
	fi
	# 显示搜索结果的 UI
	echo "===================================="
	echo "          文件夹搜索结果            "
	echo "===================================="
	cd "${DST_SAVE_PATH}" || exit
	# 列出所有文件夹并为它们编号
	folders=$(find . -maxdepth 1 ! -path . -type d -printf "%f\n" | cat -n )

	# 显示带有编号的文件夹列表
	echo "$folders" | awk '{printf "%-4s%s\n", $1, $2}'
	echo "输入数字选择要打开的存档      "
	echo "===================================="
	read -r folder_number
	cluster_name=$(echo "$folders" | awk '{if($1 == '"$folder_number"') print $2}')
	if [ "$cluster_name" == "" ]; then
		echo "存档名输入有误！"
		main
	elif [ ! -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		echo "存档不存在！"
		main
	else
		init "$cluster_name" 
		setconfig  "$cluster_name"
	fi
}

# 显示存档进程名
get_cluster_name_processing() {
	printf '=%.0s' {1..80}
	echo ""
	sessions=$(screen -ls | grep Detached | cat -n | awk '{printf "%s\n", $3}' | uniq | cat -n | awk '{printf "%-4s%s\n", $1, $2}')
	echo "$sessions"
	echo ""
	printf '=%.0s' {1..28}
	echo -e "请输入要选择的存档的序号\c"
	printf '=%.0s' {1..28}
	echo ""
	read -r folder_number
	cluster_name=$(echo "$sessions" | awk '{if($1 == '"$folder_number"') print $2}')
	if [ "$cluster_name" == "" ]; then
		echo "存档名输入有误！"
		main
	elif [ ! -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		echo "存档不存在！"
		main
	else
		init "$cluster_name" 
		setconfig  "$cluster_name"
	fi
}

# 获取玩家列表
get_playerList() {
	cluster_name=$1
	if [[ $(screen -ls | grep --text -c "\<$process_name_main\>") -gt 0 ]]; then
		allplayerslist=$(date +%s%3N)
		screen -r "$process_name_main" -p 0 -X stuff "for i, v in ipairs(TheNet:GetClientTable()) do  if (i~=1) then print(string.format(\"playerlist %s [%d] %s %s %s\", $allplayerslist, i-1 , v.userid, v.name, v.prefab )) end end $(printf \\r)"
		sleep 1
		list=$(grep --text "$server_log_path_main" -e "playerlist $allplayerslist" | cut -d ' ' -f 4-15)
		nowtime=$(date +'%Y-%m-%d %H:%M:%S')
		txt="-----------------------------------------------------"
		if [[ "$list" != "" ]]; then
			echo -e "\e[92m服务器玩家列表:\e[0m"
			echo -e "\e[92m================================================================================\e[0m"
			echo "$list"
			echo -e "\e[92m================================================================================\e[0m"
			have_player=true
			# 保存玩家信息
			{
				echo "$txt"
				echo "$nowtime"
				echo "$list"
			} >> "$script_files_path"/playerlist.txt
			return 1
		else
			echo -e "\e[92m服务器玩家列表:\e[0m"
			echo -e "\e[92m================================================================================\e[0m"
			echo "                                 当前服务器没有玩家"
			echo -e "\e[92m================================================================================\e[0m"
			have_player=false
			return 0
		fi
	fi
}

# 服务器信息
serverinfo() {
	echo -e "\e[92m=============================世界信息==========================================\e[0m"
	getworldstate
	echo -e "\e[33m 天数($presentcycles)($presentseason的第$presentday天)($presentphase/$presentmoonphase/$presentrain/$presentsnow/$presenttemperature°C)\e[0m"
	get_playerList 
	getmonster
	if [[ $(screen -ls | grep --text -c "\<$process_name_master\>") -gt 0 ]]; then
		echo "===========================地上世界信息========================================"
		echo -e "\e[33m海象巢:($walrus_camp_master)个  触手怪:($tentacle_master)个  蜘蛛巢:($spiderden_master)个\e[0m"
		echo -e "\e[33m高脚鸟巢:($tallbirdnest_master)个  猎犬丘:($houndmound_master)个  芦苇:($reeds_master)株  墓地:($mudi_master)个\e[0m"
	fi
	sleep 2
	if [[ $(screen -ls | grep --text -c "\<$process_name_caves\>") -gt 0 ]]; then
		echo "===========================地下世界信息========================================"
		echo -e "\e[33m触手怪:($tentacle_caves)个  蜘蛛巢:($spiderden_caves)个  芦苇:($reeds_caves)株\e[0m"
		echo -e "\e[33m损坏的发条主教:($bishop_nightmare)个  损坏的发条战车:($rook_nightmare)个  损坏的发条骑士:($knight_nightmare)个\e[0m"
	fi
	echo -e "\e[33m================================================================================\e[0m"
}

# 获取天数信息
get_daysInfo() {
	datatime=$(date +%s%3N)
	screen -r "$process_name_main" -p 0 -X stuff "print(TheWorld.components.worldstate.data.cycles ..  \" ""$datatime"" \")$(printf \\r)"
	sleep 1
	presentday=$(grep --text "$server_log_path_main" -e "$datatime" | cut -d " " -f2 | tail -n +2)
}

# 获取怪物信息
getmonster() {
	if [[ $(screen -ls | grep --text -c "\<$process_name_master\>") -gt 0 ]]; then
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
		walrus_camp_master=$(grep --text "$server_log_path_master" -e "walrus_camps in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		reeds_master=$(grep --text "$server_log_path_master" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tentacle_master=$(grep --text "$server_log_path_master" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tallbirdnest_master=$(grep --text "$server_log_path_master" -e "tallbirdnests in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		houndmound_master=$(grep --text "$server_log_path_master" -e "houndmounds in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		mound_master=$(grep --text "$server_log_path_master" -e "mounds in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		gravestone_master=$(grep --text "$server_log_path_master" -e "gravestones in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		spiderden_1_master=$(grep --text "$server_log_path_master" -e "spiderdens in the world." | awk '{print $4}')
		spiderden_2_master=$(grep --text "$server_log_path_master" -e "spiderden_2s in the world." | awk '{print $4}')
		spiderden_3_master=$(grep --text "$server_log_path_master" -e "spiderden_3s in the world." | awk '{print $4}')
		spiderden_master=$((spiderden_1_master + spiderden_2_master + spiderden_3_master))
		mudi_master=$((mound_master + gravestone_master))
		echo 
	fi
	if [[ $(screen -ls | grep --text -c "\<$process_name_caves\>") -gt 0 ]]; then
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
		reeds_caves=$(grep --text "$server_log_path_caves" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tentacle_caves=$(grep --text "$server_log_path_caves" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		spiderden_1_caves=$(grep --text "$server_log_path_caves" -e "spiderdens in the world." | awk '{print $4}')
		spiderden_2_caves=$(grep --text "$server_log_path_caves" -e "spiderden_2s in the world." | awk '{print $4}')
		spiderden_3_caves=$(grep --text "$server_log_path_caves" -e "spiderden_3s in the world." | awk '{print $4}')
		bishop_nightmare=$(grep --text "$server_log_path_caves" -e "bishop_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		rook_nightmare=$(grep --text "$server_log_path_caves" -e "rook_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		knight_nightmare=$(grep --text "$server_log_path_caves" -e "knight_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		spiderden_caves=$((spiderden_1_caves + spiderden_2_caves + spiderden_3_caves))
	fi
}

# 获取世界状态
getworldstate() {
	presentseason=""
	presentday=""
	presentcycles=""
	presentphase=""
	presentmoonphase=""
	presentrain=""
	presentsnow=""
	presenttemperature=""
	datatime=$(date +%s%3N)
	screen -r "$process_name_main" -p 0 -X stuff "print(\"\" .. TheWorld.net.components.seasons:GetDebugString() .. \" $datatime print\")$(printf \\r)"
	screen -r "$process_name_main" -p 0 -X stuff "print(\"\" .. TheWorld.components.worldstate.data.phase .. \" $datatime phase\")$(printf \\r)"
	screen -r "$process_name_main" -p 0 -X stuff "print(\"\" .. TheWorld.components.worldstate.data.moonphase .. \" $datatime moonphase\")$(printf \\r)"
	screen -r "$process_name_main" -p 0 -X stuff "print(TheWorld.components.worldstate.data.temperature .. \" $datatime temperature\")$(printf \\r)"
	screen -r "$process_name_main" -p 0 -X stuff "print(TheWorld.components.worldstate.data.cycles .. \" $datatime cycles\")$(printf \\r)"
	screen -r "$process_name_main" -p 0 -X stuff "print(\"$datatime:rain:\",TheWorld.components.worldstate.data.israining)$(printf \\r)"
	screen -r "$process_name_main" -p 0 -X stuff "print(\"$datatime:snow:\",TheWorld.components.worldstate.data.issnowing)$(printf \\r)"
	sleep 1
	presentseason=$(grep --text "$server_log_path_main" -e "$datatime print" | cut -d ' ' -f2 | tail -n +2)
	presentday=$(grep --text "$server_log_path_main" -e "$datatime print" | cut -d ' ' -f3 | tail -n +2)
	presentphase=$(grep --text "$server_log_path_main" -e "$datatime phase" | cut -d ' ' -f2 | tail -n +2)
	presentmoonphase=$(grep --text "$server_log_path_main" -e "$datatime moonphase" | cut -d ' ' -f2 | tail -n +2)
	presenttemperature=$(grep --text "$server_log_path_main" -e "$datatime temperature" | cut -d ' ' -f2 | tail -n +2)
	presentrain=$(grep --text "$server_log_path_main" -e "$datatime:rain" | cut -d ':' -f6 | tail -n +2)
	presentsnow=$(grep --text "$server_log_path_main" -e "$datatime:snow" | cut -d ':' -f6 | tail -n +2 | cut -d ' ' -f2)
	presentcycles=$(grep --text "$server_log_path_main" -e "$datatime cycles" | cut -d ' ' -f2 | tail -n +2)

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
	if [[ $(echo "$presentrain" | grep --text -c "true") -gt 0 ]]; then
		presentrain="下雨"
	fi
	if [[ $(echo "$presentrain" | grep --text -c "false") -gt 0 ]]; then
		presentrain="无雨"
	fi
	if [[ $(echo "$presentsnow" | grep --text -c "true") -gt 0 ]]; then
		presentsnow="下雪"
	fi
	if [[ $(echo "$presentsnow" | grep --text -c "false") -gt 0 ]]; then
		presentsnow="无雪"
	fi
}

# 准备环境
PreLibrary() {
	if [ "$os" == "Ubuntu" ]; then
		echo ""
		echo "##########################"
		echo "# 加载 Ubuntu Linux 环境 #"
		echo "##########################"
		echo ""
		sudo apt-get -y clean
		sudo apt-get -y update
		sudo apt-get -y wget

		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libc6-i386
		sudo apt-get -y install libcurl4-gnutls-dev:i386
		sudo apt-get -y install libcurl3-gnutls:i386
		sudo dpkg --add-architecture i386

		sudo apt-get -y install lib64gcc1
		sudo apt-get -y install lib32gcc1

		sudo apt-get -y install libcurl4-gnutls-dev

		#一些必备工具
		sudo apt-get -y install screen
		sudo apt-get -y install htop
		sudo apt-get -y install gawk
		sudo apt-get -y install zip unzip
		sudo apt-get -y install git

		if [ -f "/usr/lib/libcurl.so.4" ]; then
			ln -sf /usr/lib/libcurl.so.4 /usr/lib/libcurl-gnutls.so.4
		fi
		if [ -f "/usr/lib64/libcurl.so.4" ]; then
			ln -sf /usr/lib64/libcurl.so.4 /usr/lib64/libcurl-gnutls.so.4
		fi

	elif
		[ "$os" == "CentOS" ]
	then

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
		sudo yum -y install git

		if [ -f "/usr/lib/libcurl.so.4" ]; then
			ln -sf /usr/lib/libcurl.so.4 /usr/lib/libcurl-gnutls.so.4
		fi
		if [ -f "/usr/lib64/libcurl.so.4" ]; then
			ln -sf /usr/lib64/libcurl.so.4 /usr/lib64/libcurl-gnutls.so.4
		fi
	elif [ "$os" == "Arch" ]; then
		echo ""
		echo "########################"
		echo "# 加载 Arch Linux 环境 #"
		echo "########################"
		echo ""
		sudo pacman -Syyy
		sudo pacman -S --noconfirm wget screen
		sudo pacman -S --noconfirm lib32-gcc-libs libcurl-gnutls
	else
		echo -e "\e[1;31m 该系统未被本脚本支持！ \e[0m"
	fi
}

#前期准备
prepare() {
	cd "$HOME" || exit
	if [ -d "./dst" ]; then
		echo "新脚本的目录结构已更改，可能需要重新下载游戏本体，请稍后。。。"
		mv dst/ DST/
	fi
	if [ -d "./dst_beta" ]; then
		mv dst_beta/ DST_BETA/
	fi
	if [ ! -d "./steamcmd" ] || [ ! -d "./DST" ] || [ ! -d "./DST_BETA" ] || [ ! -d "./.klei/DoNotStarveTogether" ]; then
		PreLibrary
		mkdir "$DST_DEFAULT_PATH"
		mkdir "$DST_DEFAULT_PATH_BETA"
		mkdir "$HOME/steamcmd"
		mkdir "$HOME/.klei"
		mkdir "$HOME/.klei/DoNotStarveTogether"
		mkdir "${DST_SAVE_PATH}"
		cd "$HOME/steamcmd" || exit
		wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
		tar -xvzf steamcmd_linux.tar.gz
		sleep 1
		rm -f steamcmd_linux.tar.gz
	fi
	# 下载游戏本体
	if [ ! -f "$DST_DEFAULT_PATH/version.txt" ]; then
		echo "正在下载饥荒游戏本体！！！"
		cd "$HOME/steamcmd" || exit
		./steamcmd.sh +force_install_dir "$DST_DEFAULT_PATH" +login anonymous +app_update 343050 validate +quit
	fi
	if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
		echo "正在下载饥荒测试版游戏本体！！！"
		cd "$HOME/steamcmd" || exit
		./steamcmd.sh +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
	fi
}

# 切换游戏版本
change_game_version() {
	cluster_name=$1
	# 打印游戏版本选择菜单
	echo "###########################"
	echo "##### 请选择游戏版本: #####"
	echo "#      1.正式版32位       #"
	echo "#      2.正式版64位       #"
	echo "#      3.测试版32位       #"
	echo "#      4.测试版64位       #"
	echo "###########################"
	echo "输入数字序号即可,如:1 "
	read -r game_version
	# 获取当前游戏版本
	game_version_now=$(grep --text version "$script_files_path/config.txt" | awk '{print $3}')
	# 根据用户输入修改游戏版本，并打印提示信息
	if [ "$game_version" == "1" ]; then
		echo "更改该存档服务端版本为正式版32位!"
		sed -i "1s/${game_version_now}/正式版32位/g" "$script_files_path/config.txt"
	elif [ "$game_version" == "2" ]; then
		echo "更改该存档服务端版本为正式版64位!"
		sed -i "1s/${game_version_now}/正式版64位/g" "$script_files_path/config.txt"
	elif [ "$game_version" == "3" ]; then
		echo "更改该存档服务端版本为测试版32位!"
		sed -i "1s/${game_version_now}/测试版32位/g" "$script_files_path/config.txt"
	elif [ "$game_version" == "4" ]; then
		echo "更改该存档服务端版本为测试版64位!"
		sed -i "1s/${game_version_now}/测试版64位/g" "$script_files_path/config.txt"
	else
		# 如果用户输入的序号无效，则提示用户重新输入
		echo "输入有误,请重新输入"
		change_game_version
	fi
}

# 用地上备份回档
get_server_save_path_master() {
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Master" ]; then
		server_save_path_master="${DST_SAVE_PATH}/$cluster_name/Master"
		cd "$server_save_path_master"/saves_bak || exit
		echo "当前存档备份列表"
		ls
		echo "请选择需要进行回档的备份名称"
		read -r saves_name
		if [ -e "$saves_name" ]; then
			unzip -o "$saves_name" -d "$server_save_path_master"
		else
			echo "存档名输入有误，请重新输入"
			get_server_save_path_master
		fi
	else
		echo "当前存档没有地上的内容！"
		main
	fi
}

# 用地下备份回档
get_server_save_path_caves() {
	if [ -d "${DST_SAVE_PATH}/$cluster_name/Caves" ]; then
		server_save_path_caves="${DST_SAVE_PATH}/$cluster_name/Caves"
		cd "$server_save_path_caves"/saves_bak || exit
		echo "当前存档备份列表"
		ls
		echo "请选择需要进行回档的备份名称"
		read -r saves_name
		if [ -e "$saves_name" ]; then
			unzip -o "$saves_name" -d "$server_save_path_caves"
		else
			echo "存档名输入有误，请重新输入"
			get_server_save_path_caves
		fi
	else
		echo "当前存档没有地下的内容！"
	fi
}

# 获取最新版脚本
get_latest_version() {
	if [ -d "$HOME/clone_tamp" ]; then
		rm -rf "$HOME/clone_tamp"
		mkdir "$HOME/clone_tamp"
	else
		mkdir "$HOME/clone_tamp"
	fi
	clear
	echo "下载时间超过10s,就是网络问题,请CTRL+C强制退出,再次尝试,实在不行手动下载最新的。"
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
		get_latest_version
	fi
	cp "$HOME/clone_tamp/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$script_path/""$script_name"""
	cd "$script_path" || exit
	rm -rf "$HOME/clone_tamp"
	clear
	bash "$script_path"/"$script_name"
}

# API
if [ "$1" == "-checkprocess" ]; then
	checkprocess "$2"
elif [ "$1" == "-get_playerList" ]; then
	get_playerList "$2"
elif [ "$1" == "-checkupdate" ]; then
	checkupdate "$2"
elif [ "$1" == "-checkmodupdate" ]; then
	checkmodupdate "$2"
elif [ "$1" == "-get_playerList" ]; then
	get_playerList "$2"
elif [ "$1" == "" ] && [ "$2" == "" ]; then
	prepare
	clear
	main
fi
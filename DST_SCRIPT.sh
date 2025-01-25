#!/bin/bash

##常量区域

#测试版token
BETA_TOKEN="returnofthembeta"
# 作者提供的Token
GAME_TOKEN="pds-g^KU_iC59_53i^mrG/fM8RM3RctBmgouiK4lITydtUUbIHN30ze43MnBk="
# 饥荒存档位置
DST_SAVE_PATH="$HOME/.klei/DoNotStarveTogether"
# 默认游戏路径
DST_DEFAULT_PATH="$HOME/DST"
DST_BETA_PATH="$HOME/DST_BETA"
#脚本版本
script_version="1.8.9"
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
init() {
	cluster_name=$1
	if [ "$cluster_name" == "" ]; then
		ehco "存档名有误"
		return 0
	fi
	# 获取存档所在路径
	get_path_script_files "$cluster_name"
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
	get_process_name "$cluster_name"
	#获取存档的日志路径
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
get_path_cluster() {
	cluster_name=$1
	cluster_path="${DST_SAVE_PATH}"/"$cluster_name"
}

# 脚本文件所在路径
get_path_script_files() {
	cluster_name=$1
	get_path_cluster "$cluster_name"
	script_files_path="$cluster_path/ScriptFiles"
	# 判断是否存在这个文件夹，不存在就创建
	if [ ! -d "$script_files_path" ]; then
		mkdir "$script_files_path"
		init_config "$cluster_name"
	fi
	# 删除旧版本脚本残余文件
	if [ -f "$script_files_path/gameversion.txt" ]; then
		rm -rf "$script_files_path/gameversion.txt"
	fi
}

# 获取游戏版本和版本对应获取buildid的flag
get_path_games() {
	cluster_name=$1
	get_path_script_files "$cluster_name"
	if [[ $(grep --text -c "正式版" "$script_files_path/config.txt") -gt 0 ]]; then
		gamesPath="$DST_DEFAULT_PATH"
		buildid_version_flag="public"
	else
		gamesPath="$DST_BETA_PATH"
		buildid_version_flag="updatebeta"
	fi
}

# 获取游戏官方开服脚本所在位置和名字
get_path_dontstarve_dedicated_server_nullrenderer() {
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
get_cluster_dst_game_version() {
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
get_dedicated_server_mods_setup() {
	cluster_name=$1
	get_path_games "$cluster_name"
	dedicated_server_mods_setup="${gamesPath}"/mods/dedicated_server_mods_setup.lua
}

# 获取存档路径和主要存档，地上优先于地下，主要是用于控制台指令的选择
get_cluster_main() {
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
init_config() {
	cluster_name=$1
	config_file="$script_files_path/config.txt"

	if [ "$config_file" != "$HOME/.klei/DoNotStarveTogether/config.txt" ]; then
		if [ ! -f "$config_file" ]; then
			cat <<EOF >"$config_file"
version = 正式版32位
auto_update_anyway = true
is_auto_backup = true
is_debug_mode = false
EOF
		fi
	fi
}

# 配置文件
set_config_bool() {
	setting_name=$1
	setting_options_true=$2
	setting_options_false=$3
	setting_value_current=$(grep --text "$setting_name" "$script_files_path/config.txt" | awk '{print $3}')
	echo "##############################################"
	echo "############# 请选择更改到的设置 #############"
	echo "1. $setting_options_true"
	echo "2. $setting_options_false"
	echo "##############################################"
	echo "输入数字序号即可,如:1 "
	read -r select
	if [ "$select" == "1" ]; then
		sed -i "s/${setting_name} = ${setting_value_current}/${setting_name} = true/" "$script_files_path/config.txt"
		echo "已更改为$setting_options_true"
	elif [ "$select" == "2" ]; then
		sed -i "s/${setting_name} = ${setting_value_current}/${setting_name} = false/" "$script_files_path/config.txt"
		echo "已更改为$setting_options_false"
	else
		echo "输入有误，请重新输入"
		set_config_bool "$setting_name" "$setting_options_true" "$setting_options_false"
	fi
}

# 修复配置文件
repair_config() {
	setting_name=$1
	setting_value=$2
	setting_value_current=$(grep --text "$setting_name" "$script_files_path/config.txt" | awk '{print $3}')
	if [ "$setting_value_current" == "" ]; then
		echo "$setting_name = $setting_value" >>"$script_files_path/config.txt"
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
			# 判断ScriptFiles文件夹
			get_path_script_files "$cluster_name"
			# 判断是否有token文件
			cd "${DST_SAVE_PATH}/$cluster_name" || exit
			if [ ! -e "cluster_token.txt" ]; then
				while [ ! -e "cluster_token.txt" ]; do
					echo "该存档没有token文件,是否自动添加作者的token"
					echo "请输入 Y/y 同意 或者 N/n 拒绝并自己提供一个"
					read -r token_yes
					if [ "$token_yes" == "Y" ] || [ "$token_yes" == "y" ]; then
						echo $GAME_TOKEN >"cluster_token.txt"
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
	auto_flag=$2
	check_player=$3
	get_cluster_flag "$cluster_name"

	addmod_by_http_or_steamcmd "$cluster_name" "$auto_flag"

	get_process_name "$cluster_name"
	(case $cluster_flag in
		# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
		1)
			start_server_select "$cluster_name" "$process_name_master" "start_server_master.sh"
			start_server_select "$cluster_name" "$process_name_caves" "start_server_caves.sh"
			;;
		2)
			start_server_select "$cluster_name" "$process_name_master" "start_server_master.sh"
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
	get_path_games "$cluster_name"
	if [ "$script_start_server" == "start_server_master.sh" ]; then
		shard_name="Master"
	else
		shard_name="Caves"
	fi
	get_path_dontstarve_dedicated_server_nullrenderer "$cluster_name"
	echo "#!/bin/bash
	cd \"$dontstarve_dedicated_server_nullrenderer_path\" || exit
	run_shared=(./$dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-ugc_directory  $HOME/Steam/steamapps/workshop/)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard $shard_name" >"$script_files_path"/"$script_start_server"
	grep --text -m 1 buildid "$gamesPath"/steamapps/appmanifest_343050.acf | sed 's/[^0-9]//g' >"$script_files_path"/"cluster_game_buildid.txt"
	chmod 777 "$script_files_path"/"$script_start_server"
	screen -dmS "$process_name_select" /bin/sh -c "$script_files_path/$script_start_server"
}

#检查是否成功开启
start_server_check() {
	cluster_name=$1
	start_time=$(date +%s)
	get_process_name "$cluster_name"
	get_path_server_log "$cluster_name"
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
		get_process_name "$cluster_name"
		screen -r "$process_name_main" -p 0 -X stuff " modVersionInfo = {}  $(printf \\r)"
		return 1
	fi
}

# 判断是否成功开启
# 1代表需要执行，0代表执行完毕
start_server_check_select() {
	w_flag=$1
	logpath_flag=$2
	auto_flag=$3
	mod_flag=1
	download_flag=1
	check_flag=1
	# 该进程存在时才进行判定
	while :; do
		get_path_server_log "$cluster_name"
		if [ $mod_flag == 1 ] && [[ $(grep --text "[Workshop] OnDownloadPublishedFile" -c "$logpath_flag") -gt 0 ]] && [ $download_flag == 1 ]; then
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后.                         "
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后..                        "
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后...                       "
			sleep 1
		elif [[ $(grep --text "FinishDownloadingServerMods Complete!" -c "$logpath_flag") -gt 0 ]] || [[ $(grep --text "SUCCESS: Loaded modoverrides.lua" -c "$logpath_flag") -gt 0 ]] && [ $mod_flag == 1 ]; then
			if [[ $(grep --text "DownloadServerMods timed out with no response from Workshop..." -c "$logpath_flag") -gt 0 ]]; then
				echo -e "\r\e[31m连接创意工坊超时导致$w_flag服务器mod下载失败，将重新启动                                                                  \e[0m"
				close_server "$cluster_name" -AUTO
				start_server "$cluster_name" "$auto_flag"
				break
			else
				echo -e "\r\e[92m$w_flag服务器mod下载完成!!!                                                                  \e[0m"
				mod_flag=0
				download_flag=0
			fi
		fi

		# 检查有没有下载完成
		if [[ $(grep --text "FinishDownloadingServerMods Complete!" -c "$logpath_flag") -eq 0 ]] && [[ $(grep --text "SUCCESS: Loaded modoverrides.lua" -c "$logpath_flag") -eq 0 ]]; then
			echo -en "\r正在检测$w_flag服务器mod是否完成下载,请稍后.                    "
			sleep 1
			echo -en "\r正在检测$w_flag服务器mod是否完成下载,请稍后..                   "
			sleep 1
			echo -en "\r正在检测$w_flag服务器mod是否完成下载,请稍后...                  "
			sleep 1
		fi

		# 完成mod检测之后检测服务器有没有开启
		if [ "$check_flag" == 1 ] && [ $mod_flag == 0 ]; then
			echo -en "\r$w_flag服务器开启中,请稍后.                              "
			sleep 1
			echo -en "\r$w_flag服务器开启中,请稍后..                             "
			sleep 1
			echo -en "\r$w_flag服务器开启中,请稍后...                            "
			sleep 1
		fi

		get_process_name "$cluster_name"
		if [ -d "${DST_SAVE_PATH}/$cluster_name/Master" ]; then
			if [[ $(screen -ls | grep --text -c "\<$process_name_master\>") -eq 0 ]]; then
				echo -e "\r\e[1;31m$w_flag服务器地上服务器开启未成功,即将开启该存档。\e[0m"
				start_server_select "$cluster_name" "$process_name_master" "start_server_master.sh"
			fi
		fi

		if [ -d "${DST_SAVE_PATH}/$cluster_name/Caves" ]; then
			if [[ $(screen -ls | grep --text -c "\<$process_name_caves\>") -eq 0 ]]; then
				echo -e "\r\e[1;31m$w_flag服务器地下服务器开启未成功,即将开启该存档。\e[0m"
				start_server_select "$cluster_name" "$process_name_caves" "start_server_caves.sh"
			fi
		fi

		# mod检测和下载完成，服务器检测未完成
		if [[ $(grep --text "Sim paused" -c "$logpath_flag") -gt 0 || $(grep --text "shard LUA is now ready!" -c "$logpath_flag") -gt 0 ]] && [ $mod_flag == 0 ] && [ $download_flag == 0 ] && [ "$check_flag" == 1 ]; then
			echo -e "\r\e[92m$w_flag服务器开启成功!!!                          \e[0m"
			sleep 1
			check_flag=0
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
		sudo apt-get -y update
		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libcurl3-gnutls:i386
	elif
		[ "$os" == "DebianGNU/" ]
	then

		echo ""
		echo "##########################"
		echo "# 加载 Debian Linux 环境 #"
		echo "##########################"
		echo ""
		sudo apt-get -y update

		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libc6-i386
		sudo apt-get -y install libcurl4-gnutls-dev:i386
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

# 通过steamcmd下载mod
download_mod_by_steamcmd() {
	V2_mods=$1
	# mod所在目录
	get_cluster_main "$cluster_name"
	get_dedicated_server_mods_setup "$cluster_name"
	modoverrides_path=$cluster_main/modoverrides.lua

	if [ -e "$modoverrides_path" ]; then
		# 删除appworkshop_322330.acf
		rm -rf "$HOME/Steam/steamapps/workshop/content/322330/appworkshop_322330.acf"
		# 收集所有项目ID到字符串中
		workshop_commands="+login anonymous "
		# 统一用steamcmd下载V2_mods
		if [ ${#V2_mods[@]} -gt 0 ]; then
			for mod_id in "${V2_mods[@]}"; do
				# 如果mod_id是空的，不操作
				if [ -z "$mod_id" ]; then
					continue
				fi

				# 如果文件夹不存在，追加到命令字符串中
				if [ ! -f "$HOME/Steam/steamapps/workshop/content/322330/$mod_id/modmain.lua" ]; then
					# 如果文件夹存在，追加到命令字符串中
					workshop_commands+="+workshop_download_item 322330 $mod_id "
				else
					echo $mod_id mod已存在
				fi
			done
		fi
		workshop_commands+="+quit"
		# 检查是否只有初始命令和结束命令
		if [ "$workshop_commands" == "+login anonymous +quit" ]; then
			echo "没有需要下载的V2 Mod项目"
		else
			# 定义日志文件路径
			mkdir -p "$HOME/Steam/logs"
			log_file="$HOME/Steam/logs/stderr.txt"

			# 执行命令并将输出写入日志文件和终端
			cd $HOME/steamcmd || exit
			./steamcmd.sh +quit
			./steamcmd.sh $workshop_commands 2>&1 | tee "$log_file"
		fi
	else
		echo -e "\e[1;31m未找到mod配置文件 \e[0m"
	fi
}

#自动添加存档所需的mod
addmod_by_dst() {
	cluster_name=$1
	auto_flag=$2
	# mod所在目录
	get_cluster_main "$cluster_name"
	get_dedicated_server_mods_setup "$cluster_name"
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
			sleep 0.05
			echo -e "\e[92m$line Mod自动下载与更新添加完成\e[0m"

		done
		echo -e "\e[92mMod添加完成!!!\e[0m"
	else
		echo -e "\e[1;31m未找到mod配置文件 \e[0m"
	fi
}

# 初始化V2_mods数组
declare -a V2_mods

#自动添加存档所需的mod
addmod_by_http_or_steamcmd() {
	cluster_name=$1
	auto_flag=$2
	# mod所在目录
	get_cluster_main "$cluster_name"
	get_dedicated_server_mods_setup "$cluster_name"
	modoverrides_path=$cluster_main/modoverrides.lua
	if [ -e "$modoverrides_path" ]; then
		echo "正在将开启存档所需的mod添加进服务器配置文件中..."
		rm -rf dedicated_server_mods_setup.lua
		sleep 0.1
		echo "" >>dedicated_server_mods_setup.lua
		sleep 0.1
		V2_mods=()
		while IFS= read -r mod_num; do
			get_mod_info $mod_num
			mod_file_url=${mod_info_post[2]}
			if [ "$mod_file_url" == "" ]; then
				if [ ! -f "$HOME/Steam/steamapps/workshop/content/322330/$mod_num/modmain.lua" ]; then
					echo "${mod_info_post[0]} [${mod_info_post[1]}] 是V2 Mod 后续将使用steamcmd下载"
					V2_mods+=("$mod_num")
				else
					echo "${mod_info_post[0]} [${mod_info_post[1]}] 已存在"
				fi
			else
				# 如果文件夹不存在，追加到命令字符串中
				if [ ! -f "$HOME/DST/mods/workshop-$mod_num/modmain.lua" ]; then
					download_mod_by_http $mod_file_url $mod_num
				else
					echo "${mod_info_post[0]} [${mod_info_post[1]}] 已存在"
				fi
			fi
		done < <(grep --text "\"workshop" <"$modoverrides_path" | cut -d '"' -f 2 | cut -d '-' -f 2)

		download_mod_by_steamcmd ${V2_mods[@]}

		echo -e "\e[92mMod添加完成!!!\e[0m"
	else
		echo -e "\e[1;31m未找到mod配置文件 \e[0m"
	fi
}

#自动添加存档所需的mod
download_mod_by_http() {
	mod_file_url=$1
	mod_num=$2
	# 下载mod_file_url这个地址的文件
	wget --progress=bar:force -q -O mod_publish_data_file.zip "$mod_file_url"
	# 检查下载的文件是否是有效的zip文件
	if unzip -tq mod_publish_data_file.zip >/dev/null 2>&1; then
		unzip -oqL mod_publish_data_file.zip -d "$HOME/DST/mods/workshop-$mod_num" >/dev/null 2>&1
		echo "${mod_info_post[0]} [${mod_info_post[1]}] 下载完成"
	else
		echo "下载的文件不是有效的zip文件: $mod_file_url"
	fi
	rm mod_publish_data_file.zip
}

#主菜单
main() {
	tput setaf 2
	while :; do
		echo "============================================================"
		printf "%s\n" "                     脚本版本:${script_version}                            "
		echo "============================================================"
		echo "                                          	             "
		echo "  [1]重新载入脚本       [2]启动服务器     [3]关闭饥荒服务器 "
		echo "                                          	             "
		echo "  [4]查看服务器状态     [5]控制台         [6]重启服务器     "
		echo "                                          	             "
		echo "  [7]更改存档默认配置   [8]查看存档mod    [9]获取最新脚本   "
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
				repair_config is_auto_backup true
				repair_config is_debug_mode false
				game_version_now=$(grep --text version "$script_files_path/config.txt" | awk '{print $3}')
				auto_update_anyway=$(grep --text auto_update_anyway "$script_files_path/config.txt" | awk '{print $3}')
				is_auto_backup=$(grep --text is_auto_backup "$script_files_path/config.txt" | awk '{print $3}')

				echo "============================================================"
				echo "                                          	             "
				echo "  [1]默认游戏开启版本(当前为：$game_version_now)"
				echo "  [2]是否强制更新(当前为：$auto_update_anyway)"
				echo "  [3]是否自动备份(当前为：$is_auto_backup)"
				echo "                                          	             "
				echo "============================================================"
				echo "                                                                                  "
				echo -e "\e[92m请输入命令代号，不输返回主菜单:\e[0m"
				read -r settinginfo
				(case $settinginfo in
					1)
						# 更换存档所开启的游戏版本
						change_game_version "$cluster_name"
						;;
					2)
						set_config_bool auto_update_anyway 直接更新，无论服务器有没有人 仅在服务器有没人时更新
						;;
					3)
						set_config_bool is_auto_backup 开启自动备份 关闭自动备份
						;;
					*)
						main
						;;
					esac)

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
		echo "	[7]利用备份回档-地下   "
		echo "                                                                                  "
		echo "=================================================================================="
		echo "                                                                                  "
		echo -e "\e[92m请输入命令代号，不输返回主菜单:\e[0m"
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
			*)
				main
				;;
			esac)
	done
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
	get_process_name "$cluster_name"
	if [ "$cluster_name" == "" ]; then
		main
	elif [ -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		if [ "$close_flag" == "" ] || [ "$close_flag" == "-close" ]; then
			close_server_autoUpdate "$cluster_name"
		fi
		# 进程名称符合就删除
		while :; do
			sleep 1
			if [[ $(screen -ls | grep --text -c "\<$process_name_master\>") -gt 0 ]]; then
				close_server_select "$process_name_master" "地上" "$close_flag" "$check_player"
			elif [[ $(screen -ls | grep --text -c "\<$process_name_caves\>") -gt 0 ]]; then
				close_server_select "$process_name_caves" "地下" "$close_flag" "$check_player"
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

	if [ "$check_player" == "-NOBODY" ]; then
		get_playerList "$cluster_name"
		if [ "$have_player" != "false" ]; then
			player_flag="true"
		fi
	fi

	if [[ $player_flag == "false" ]] || [ "$close_flag" == "" ] || [ "$close_flag" == "-close" ]; then
		if [ "$close_flag" == "-close" ]; then
			c_announce="服务器即将关闭，给您带来的不便还请谅解！！！"
		elif [ "$close_flag" == "" ]; then
			c_announce="服务器需要重启,给您带来的不便还请谅解！！！"
		fi

		for i in $(screen -ls | grep --text -w "$process_name_close" | awk '/[0-9]{1,}\./ {print strtonum($1)}'); do
			for _ in {1..3}; do
				screen -S "$i" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)"
				echo -en "\r$world_close_flag服务器正在发布公告.  "
				sleep 1.5
				echo -en "\r$world_close_flag服务器正在发布公告.. "
				sleep 1.5
				echo -en "\r$world_close_flag服务器正在发布公告..."
				sleep 1.5
			done
			screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
			echo -e "\r\e[92m$world_close_flag服务器公告发布完毕!!!\e[0m"
		done

		max_attempts=3
		attempt=0

		while ((attempt < max_attempts)); do
			sleep 1
			if [[ $(screen -ls | grep --text -c "\<$process_name_close\>") -gt 0 ]]; then
				echo -en "\r$world_close_flag进程 $cluster_name 正在关闭,请稍后.  "
				sleep 1
				echo -en "\r$world_close_flag进程 $cluster_name 正在关闭,请稍后.. "
				sleep 1
				echo -en "\r$world_close_flag进程 $cluster_name 正在关闭,请稍后..."
				sleep 1
				((attempt++))
			else
				attempt=999
				echo -e "\r\e[92m$world_close_flag进程 $cluster_name 已关闭!!!                   \e[0m"
				sleep 1
				break
			fi

			if ((attempt == max_attempts)); then
				echo -e "\r\e[91m进程 $cluster_name 未能正常关闭，强制终止!!!\e[0m"
				screen -S "$process_name_close" -X quit
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

#检查游戏更新情况
checkupdate() {
    cluster_name=$1
    get_path_games "$cluster_name"
    # 保存buildid的位置
    buildid_version_path="$gamesPath/bin/buildid.txt"
    DST_now=$(date +%Y年%m月%d日%H:%M)
    # 判断一下对应开启的版本
    # 获取最新buildid
    echo "正在获取最新buildid。。。"
    export buildid_version_path=$buildid_version_path
    cd "$HOME"/steamcmd || exit

    # 修改重试次数和间隔
    local max_retries=3  # 从5改为3
    local retry_count=0
    local success=false

    # 清理旧的Steam用户数据
    echo "清理3天前的Steam用户数据..."
    find "$HOME/Steam/userdata" -type f -mtime +3 -delete 2>/dev/null
    find "$HOME/Steam/userdata" -type d -empty -delete 2>/dev/null

    # 首先尝试通过API获取
    while [ $retry_count -lt $max_retries ]; do
        response=$(curl -s --connect-timeout 10 --max-time 10 'https://api.steamcmd.net/v1/info/343050')
        curl_exit_status=$?

        if [ $curl_exit_status -eq 0 ]; then
            buildid=$(echo "$response" | jq -r '.data["343050"].depots.branches.public.buildid')
            if [ -n "$buildid" ] && [ "$buildid" != "null" ]; then
                echo "通过API成功获取buildid: $buildid"
                echo "$buildid" >"$buildid_version_path"
                success=true
                break
            fi
        fi
        echo "API请求失败，3秒后重试..."  # 从5秒改为3秒
        sleep 3  # 从5改为3
        ((retry_count++))
    done

    # 如果API获取失败，尝试通过steamcmd获取
    if [ "$success" != true ]; then
        echo "API获取失败，尝试通过steamcmd获取buildid..."
        cd "$HOME/steamcmd" || exit
        ./steamcmd.sh +login anonymous +app_info_update 1 +app_info_print 343050 +quit > steam_app_info.txt
        
        if [ -f "steam_app_info.txt" ]; then
            buildid=$(grep -A 5 "\"public\"" steam_app_info.txt | grep "buildid" | cut -d '"' -f 4)
            if [ -n "$buildid" ]; then
                echo "通过steamcmd成功获取buildid: $buildid"
                echo "$buildid" >"$buildid_version_path"
                success=true
            fi
            rm steam_app_info.txt
        fi
    fi

    if [ "$success" != true ]; then
        echo "无法获取buildid，请检查网络连接或手动更新"
        return 1
    fi

    # 显示buildid对比信息
    get_path_script_files "$cluster_name"
    local current_buildid
    current_buildid=$(cat "$script_files_path"/"cluster_game_buildid.txt")
    echo -e "\e[92m当前存档buildid: $current_buildid\e[0m"
    echo -e "\e[92m最新在线buildid: $buildid\e[0m"

    if [[ $(sed 's/[^0-9]//g' "$buildid_version_path") -gt $current_buildid ]]; then
        echo " "
        echo -e "\e[31m${DST_now}:游戏服务端有更新! \e[0m"
        echo " "
        # 先检查游戏本体是不是最新的，如果是的话，那就直接重启存档就可以了,不然的话就先更新游戏本体
        if [[ $(sed 's/[^0-9]//g' "$buildid_version_path") -gt $(grep --text -m 1 buildid "$gamesPath"/steamapps/appmanifest_343050.acf | sed 's/[^0-9]//g') ]]; then
            # 更新游戏本体
            if [ "$buildid_version_flag" == "public" ]; then
                echo -e "\e[33m${DST_now}:更新正式版游戏本体中。。。 \e[0m"
                update_game DEFAULT
            else
                echo -e "\e[33m${DST_now}:更新测试版游戏本体中。。。 \e[0m"
                update_game BETA
            fi
        fi
        auto_update_anyway=$(grep --text auto_update_anyway "$script_files_path/config.txt" | awk '{print $3}')
        c_announce="由于游戏本体有更新，服务器即将关闭，给您带来的不便还请谅解！！！"
        if [ "$auto_update_anyway" == "true" ]; then
            # 重启该存档，但不关闭当前进程
            restart_server "$cluster_name" -AUTO
        else
            restart_server "$cluster_name" -AUTO -NOBODY
        fi
    else
        echo -e "\e[92m${DST_now}:游戏服务端没有更新!\e[0m"
    fi
}

# 检查游戏mod更新情况
checkmodupdate() {
    cluster_name=${1:?Usage: checkmodupdate [cluster_name]}
    DST_now=$(date +%Y年%m月%d日%H:%M)
    get_process_name "$cluster_name"
    
    echo -e "\e[92m${DST_now}: 正在检查服务器mod是否有更新...\e[0m"
    
    # 使用时间戳标记本次查询
    local timestamp=$(date +%s%3N)
    
    # 通过控制台获取当前加载的mod信息
    screen -r "$process_name_main" -p 0 -X stuff "for k,v in pairs(KnownModIndex:GetModsToLoad()) do local modinfo = KnownModIndex:GetModInfo(v) print(string.format(\"modinfo $timestamp %s %s\", v, modinfo.version)) end$(printf \\r)"
    sleep 1
    
    # 获取日志路径
    get_path_server_log "$cluster_name"
    
    # 解析日志获取mod信息
    local has_mods_update=false
    
    # 读取并处理日志中的mod信息
    while read -r line; do
        if [[ $line =~ modinfo[[:space:]]$timestamp[[:space:]]workshop-([0-9]+)[[:space:]](.+)$ ]]; then
            local mod_id="${BASH_REMATCH[1]}"
            local current_version="${BASH_REMATCH[2]}"
            
            # 获取在线mod信息
            get_mod_info "$mod_id"
            local online_version="${mod_info_post[1]}"
            local mod_name="${mod_info_post[0]}"
            
            # 比较版本
            if [ "$current_version" != "$online_version" ]; then
                echo -e "\e[33mMod [$mod_name] 有更新:"
                echo -e "当前版本: $current_version"
                echo -e "最新版本: $online_version\e[0m"
                has_mods_update=true
                
                # 删除需要更新的mod文件
                if [ -d "$HOME/DST/mods/workshop-$mod_id" ]; then
                    echo "删除旧版本mod文件: workshop-$mod_id"
                    rm -rf "$HOME/DST/mods/workshop-$mod_id"
                fi
                if [ -d "$HOME/Steam/steamapps/workshop/content/322330/$mod_id" ]; then
                    echo "删除旧版本mod文件: $mod_id"
                    rm -rf "$HOME/Steam/steamapps/workshop/content/322330/$mod_id"
                fi
            else
                echo -e "\e[92mMod [$mod_name] 已是最新版本 ($current_version)\e[0m"
            fi
        fi
    done < <(grep --text "modinfo $timestamp" "$server_log_path_main")
    
    if [ "$has_mods_update" = true ]; then
        echo -e "\e[31m${DST_now}: 发现mod更新!\e[0m"
        
        # 获取配置
        get_path_script_files "$cluster_name"
        auto_update_anyway=$(grep --text auto_update_anyway "$script_files_path/config.txt" | awk '{print $3}')
        
        if [ "$auto_update_anyway" == "true" ]; then
            echo "准备更新mod..."
            c_announce="由于mod有更新，服务器即将重启，给您带来的不便还请谅解！！！"
            restart_server "$cluster_name" -AUTO
        else
            get_playerList "$cluster_name"
            if [ "$have_player" = false ]; then
                echo "服务器无玩家，准备更新mod..."
                c_announce="由于mod有更新，服务器即将重启，给您带来的不便还请谅解！！！"
                restart_server "$cluster_name" -AUTO
            else
                echo "服务器有玩家在线，暂不更新mod"
            fi
        fi
    else
        echo -e "\e[92m${DST_now}: 所有mod均为最新版本\e[0m"
    fi
}

# 通过API获取mod信息（请求超时为10s，超时等待2s重新请求，最多请求5次
get_mod_info() {
	local MOD_PUBLISHED_FILE_ID=$1
	local max_retries=5
	local retry_count=0
	local success=false

	while [ $retry_count -lt $max_retries ]; do
		response=$(curl -s --connect-timeout 10 --max-time 10 -X POST 'http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' \
			-H 'Content-Type: application/x-www-form-urlencoded' \
			--data "itemcount=1&publishedfileids[0]=$MOD_PUBLISHED_FILE_ID")

		curl_exit_status=$?

		if [ $curl_exit_status -eq 0 ]; then
			success=true
			break
		else
			echo "Request failed. Retrying in 2 seconds..."
			sleep 2
			((retry_count++))
		fi
	done

	if [ "$success" = true ]; then
		# 解析 JSON 响应获取mod名和版本号
		mod_name=$(echo "$response" | jq -r '.response.publishedfiledetails[0].title')
		mod_version=$(echo "$response" | jq -r '.response.publishedfiledetails[0].tags[] | select(.tag | test("version:")) | .tag')
		# 提取版本号
		mod_version_number=${mod_version#version:}
		# 提取file_url
		file_url=$(echo "$response" | jq -r '.response.publishedfiledetails[0].file_url')

		if [ "$mod_version" != "null" ]; then
			mod_info_post=("$mod_name" "$mod_version_number" "$file_url")
		else
			mod_info_post=("null" "null" "null")
		fi
	else
		echo "在尝试了 $max_retries 次后仍未能获取模组信息。"
		mod_info_post=("null" "null" "null")
	fi
}

#查看进程执行情况
checkprocess() {
	cluster_name=$1
	flag_checkprocess=$2
	get_cluster_main "$cluster_name"
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
	get_path_server_log "$cluster_name"
	get_process_name "$cluster_name"
	log_path=$server_log_path_main
	if [ "$world_check_flag" == "地上" ]; then
		script_name="start_server_master.sh"
		process_name_check=$process_name_master
		log_path=$server_log_path_master
	else
		script_name="start_server_caves.sh"
		process_name_check=$process_name_caves
		log_path=$server_log_path_caves
	fi

	if [[ $(screen -ls | grep --text -c "\<$process_name_check\>") -eq 1 ]]; then
		if [[ "$flag_checkprocess" != "no_output" ]]; then
			echo "$world_check_flag服务器运行正常"
		fi
	else
		echo "$world_check_flag服务器已经关闭,自动开启中。。。"
		start_server_select "$cluster_name" "$process_name_check" "$script_name" -AUTO
		start_server_check_select "$world_check_flag" "$log_path" -AUTO
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
	sessions=$(screen -ls | grep Detached | cat -n | awk '{printf "%-4s%s %s\n", $1, $2,$3}')
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
	pid1=$(echo "$sessions" | awk '{if($1 == '"$folder_number"') print $2}' | cut -d '.' -f1)
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
	is_auto_backup=\$(grep --text is_auto_backup \"$script_files_path/config.txt\" | awk '{print \$3}')
	# 使用脚本的方法
	script(){
		bash \$script_path_name \"\$1\" $cluster_name \"-AUTO\"
	}
	# 获取天数信息
	get_daysInfo()
	{
		datatime=\$(date +%s%3N)
		screen -r \"$process_name_main\" -p 0 -X stuff \"print(TheWorld.components.worldstate.data.cycles .. \\\" \$datatime\\\")\$(printf \\\r)\"
		sleep 1
		presentday=\$(grep --text \"$server_log_path_main\" -e \"\$datatime\" | cut -d \" \" -f2 | tail -n +2 )
	}
	backup()
	{
		# 自动备份
		if [ \"\$timecheck\" == 0 ] && [ \"\$is_auto_backup\" == true ];then
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
	# 判断$process_name_AutoUpdate是否存在,存在则不开启
	if [ "$(screen -ls | grep --text -c "\<$process_name_AutoUpdate\>")" -gt 0 ]; then
		echo -e "\e[1;33m$process_name_AutoUpdate 已经执行! \e[0m"
	else
		screen -dmS "$process_name_AutoUpdate" /bin/sh -c "$script_files_path/auto_update.sh"
		echo -e "\e[92m自动更新进程 $process_name_AutoUpdate 已启动\e[0m"
	fi
	sleep 1
}

# 列出所有的mod
list_all_mod() {
	local cluster_name=$1
	clear
	tput setaf 2
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
		for mod_num in $(find "$mods_path" -maxdepth 1 -exec basename {} \; | awk '{print $NF}'); do
			if [[ -f "$mods_path/$mod_num/modinfo.lua" ]]; then
				get_mod_info_file_details $cluster_name $mod_num
				echo "${mod_info_file[0]}" "${mod_info_file[1]}"
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
	folders=$(find . -maxdepth 1 ! -path . -type d -printf "%f\n" | cat -n)

	# 显示带有编号的文件夹列表
	echo "$folders" | awk '{printf "%-4s%s\n", $1, $2}'
	echo "输入数字选择要打开的存档      "
	echo "===================================="
	read -r folder_number
	if [ "$folder_number" == "" ]; then
		echo "存档名输入有误！"
		main
	fi
	cluster_name=$(echo "$folders" | awk '{if($1 == '"$folder_number"') print $2}')
	# 判断ScriptFiles文件夹
	if [ "$cluster_name" == "" ]; then
		echo "存档名输入有误！"
		main
	elif [ ! -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		echo "存档不存在！"
		main
	else
		get_path_script_files "$cluster_name"
		init "$cluster_name"
		init_config "$cluster_name"
	fi
}

# 显示存档进程名
get_cluster_name_processing() {
	printf '=%.0s' {1..80}
	echo ""
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
		init_config "$cluster_name"
	fi
}

# 获取玩家列表
get_playerList() {
	cluster_name=$1
	echo "当前查询存档：$1"
	get_process_name "$cluster_name"
	get_path_server_log "$cluster_name"
	if [[ $(screen -ls | grep --text -c "\<$process_name_main\>") -gt 0 ]]; then
		allplayerslist=$(date +%s%3N)
		screen -r "$process_name_main" -p 0 -X stuff "for i, v in ipairs(TheNet:GetClientTable()) do  if (i~=1) then print(string.format(\"playerlist %s [%d] %s %s %s\", $allplayerslist, i-1 , v.userid, v.name, v.prefab )) end end $(printf \\r)"
		sleep 1
		get_path_server_log "$cluster_name"
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
			} >>"$script_files_path"/playerlist.txt
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
	get_playerList "$cluster_name"
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
	get_path_server_log "$cluster_name"
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
		get_path_server_log "$cluster_name"
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

		# 如果某个变量无法解析出数值，则将其视为零
		if ! [[ "$spiderden_1_master" =~ ^[0-9]+$ ]]; then spiderden_1_master=0; fi
		if ! [[ "$spiderden_2_master" =~ ^[0-9]+$ ]]; then spiderden_2_master=0; fi
		if ! [[ "$spiderden_3_master" =~ ^[0-9]+$ ]]; then spiderden_3_master=0; fi

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
		get_path_server_log "$cluster_name"
		reeds_caves=$(grep --text "$server_log_path_caves" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tentacle_caves=$(grep --text "$server_log_path_caves" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		spiderden_1_caves=$(grep --text "$server_log_path_caves" -e "spiderdens in the world." | awk '{print $4}')
		spiderden_2_caves=$(grep --text "$server_log_path_caves" -e "spiderden_2s in the world." | awk '{print $4}')
		spiderden_3_caves=$(grep --text "$server_log_path_caves" -e "spiderden_3s in the world." | awk '{print $4}')

		# 如果某个变量无法解析出数值，则将其视为零
		if ! [[ "$spiderden_1_caves" =~ ^[0-9]+$ ]]; then spiderden_1_caves=0; fi
		if ! [[ "$spiderden_2_caves" =~ ^[0-9]+$ ]]; then spiderden_2_caves=0; fi
		if ! [[ "$spiderden_3_caves" =~ ^[0-9]+$ ]]; then spiderden_3_caves=0; fi

		spiderden_caves=$((spiderden_1_caves + spiderden_2_caves + spiderden_3_caves))
		bishop_nightmare=$(grep --text "$server_log_path_caves" -e "bishop_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		rook_nightmare=$(grep --text "$server_log_path_caves" -e "rook_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		knight_nightmare=$(grep --text "$server_log_path_caves" -e "knight_nightmares in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')

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
	get_path_server_log "$cluster_name"
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

	elif
		[ "$os" == "DebianGNU/" ]
	then

		echo ""
		echo "##########################"
		echo "# 加载 Debian Linux 环境 #"
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

#检查依赖是否安装
check_the_library() {
	local library_name=$1
	if ! which "$library_name" >/dev/null 2>&1; then
		echo "$library_name is not installed."
		install_lib "$library_name"
	fi
}

#安装依赖
install_lib() {
	local library_name=$1
	if [ "$os" == "Ubuntu" ]; then
		sudo apt-get -y install "$library_name"
	elif
		[ "$os" == "CentOS" ]
	then
		sudo yum -y install "$library_name"
	elif
		[ "$os" == "DebianGNU/" ]
	then
		sudo apt-get -y install "$library_name"
	else
		echo -e "\e[1;31m 该系统未被本脚本支持！ \e[0m"
	fi
}

#前期准备
prepare() {
	cd "$HOME" || exit
	#一些必备工具
	check_the_library screen
	check_the_library htop
	check_the_library gawk
	check_the_library zip unzip
	check_the_library git
	check_the_library jq
	if [ -d "./dst" ]; then
		echo "新脚本的目录结构已更改，可能需要重新下载游戏本体，请稍后。。。"
		mv dst/ DST/
	fi
	if [ -d "./dst_beta" ]; then
		mv dst_beta/ DST_BETA/
	fi
	if [ ! -d "./steamcmd" ] || [ ! -d "./DST" ] || [ ! -d "./.klei/DoNotStarveTogether" ]; then
		PreLibrary
		mkdir "$DST_DEFAULT_PATH"

		mkdir "$HOME/steamcmd"
		mkdir "$HOME/.klei"
		mkdir "$HOME/.klei/DoNotStarveTogether"
		mkdir "${DST_SAVE_PATH}"
		cd "$HOME/steamcmd" || exit
		curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -
	fi
	# 下载游戏本体
	if [ ! -f "$DST_DEFAULT_PATH/version.txt" ]; then
		echo "正在下载饥荒游戏本体！！！"
		cd "$HOME/steamcmd" || exit
		./steamcmd.sh +force_install_dir "$DST_DEFAULT_PATH" +login anonymous +app_update 343050 validate +quit
	fi
	# if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
	# 	echo "正在下载饥荒测试版游戏本体！！！"
	# 	cd "$HOME/steamcmd" || exit
	# 	./steamcmd.sh +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
	# fi
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
		if [ ! -d "./DST_BETA" ]; then
			mkdir "$DST_BETA_PATH"
		fi
		if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
			echo "正在下载饥荒测试版游戏本体！！！"
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
		fi
		sed -i "1s/${game_version_now}/测试版32位/g" "$script_files_path/config.txt"
	elif [ "$game_version" == "4" ]; then
		echo "更改该存档服务端版本为测试版64位!"
		if [ ! -d "./DST_BETA" ]; then
			mkdir "$DST_BETA_PATH"
		fi
		if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
			echo "正在下载饥荒测试版游戏本体！！！"
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
		fi
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
	cp "$HOME/clone_tamp/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$script_path/$SCRIPT_NAME"
	cd "$script_path" || exit
	rm -rf "$HOME/clone_tamp"
	clear
	bash "$script_path"/"$SCRIPT_NAME"
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
elif [ "$1" == "-addmod_by_http_or_steamcmd" ]; then
	addmod_by_http_or_steamcmd "$2"
elif [ "$1" == "-download_mod_by_http" ]; then
	download_mod_by_http "$2"
elif [ "$1" == "-restart_server" ]; then
	restart_server "$2" "$3"
elif [ "$1" == "-save_mod_info" ]; then
	save_mod_info "$2"
elif [ "$1" == "" ] && [ "$2" == "" ]; then
	prepare
	clear
	main
fi

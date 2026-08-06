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
script_version="1.8.21"
# 脚本更新仓库，可通过环境变量指定优先使用的镜像
DST_SCRIPT_GIT_URL="${DST_SCRIPT_GIT_URL:-}"
DST_SCRIPT_OFFICIAL_GIT_URL="https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git"
# 当前系统版本
os=$(awk -F = '/^NAME/{print $2}' /etc/os-release | sed 's/"//g' | sed 's/ //g' | sed 's/Linux//g' | sed 's/linux//g')
# 脚本实际所在目录及名称，避免从其他工作目录启动时更新到错误位置
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
script_path=$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)
SCRIPT_NAME=$(basename -- "$SCRIPT_SOURCE")

STEAMCMD_BIN=""

# 每次启动只记录对应日志在启动前的行数。不要用历史日志判断本次启动结果。
declare -A STARTUP_LOG_START_LINE
declare -A STARTUP_LOG_PREFIX_HASH
declare -A STARTUP_PROCESS_BY_LOG
declare -A STARTUP_SHARD_BY_LOG
declare -A STARTUP_RESTART_COUNTS
STARTUP_REPAIR_USED=0
STARTUP_REPAIRED_MOD_IDS=""
STARTUP_MAX_RESTARTS=2

STARTUP_FATAL_PATTERNS='Error loading main.lua|Failed mSimulation->Reset\(\)|Error during game restart!|Error during game initialization!|LUA ERROR stack traceback:'
STARTUP_READY_PATTERNS='shard LUA is now ready!|Sim paused|Server is now ready'
MOD_DOWNLOAD_MAX_ATTEMPTS="${MOD_DOWNLOAD_MAX_ATTEMPTS:-3}"
MOD_DOWNLOAD_MAX_SECONDS="${MOD_DOWNLOAD_MAX_SECONDS:-1800}"
STARTUP_MOD_REPAIR_TIMEOUT_SECONDS="${STARTUP_MOD_REPAIR_TIMEOUT_SECONDS:-600}"
SHUTDOWN_WAIT_SECONDS="${SHUTDOWN_WAIT_SECONDS:-60}"
SHUTDOWN_GRACE_SECONDS="${SHUTDOWN_GRACE_SECONDS:-10}"

manual_steamcmd_complete() {
	[ -x "$HOME/steamcmd/steamcmd.sh" ] &&
		[ -s "$HOME/steamcmd/linux32/libstdc++.so.6" ] &&
		[ -s "$HOME/steamcmd/linux32/crashhandler.so" ]
}

steamcmd_available() {
	command -v steamcmd >/dev/null 2>&1 || manual_steamcmd_complete
}

install_steamcmd_by_apt() {
	if [ "$os" != "Ubuntu" ] && [ "$os" != "DebianGNU/" ]; then
		return 1
	fi

	echo "优先通过 apt 安装 SteamCMD..."
	sudo apt-get -y update
	sudo apt-get -y install ca-certificates curl tar

	if [ "$os" == "Ubuntu" ]; then
		sudo apt-get -y install software-properties-common
		if command -v add-apt-repository >/dev/null 2>&1; then
			sudo add-apt-repository -y multiverse
		fi
	fi

	sudo dpkg --add-architecture i386
	sudo apt-get -y update
	sudo apt-get -y install steamcmd
}

install_steamcmd_manually() {
	local steamcmd_url="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
	local steamcmd_archive

	steamcmd_archive=$(mktemp) || return 1
	mkdir -p "$HOME/steamcmd"

	echo "apt 安装 SteamCMD 不可用，改用官方压缩包安装..."
	if ! curl -fL --connect-timeout 15 --max-time 180 --retry 5 --retry-delay 2 -o "$steamcmd_archive" "$steamcmd_url"; then
		echo -e "\e[1;31mSteamCMD 压缩包下载失败，请检查网络或代理。\e[0m"
		rm -f "$steamcmd_archive"
		return 1
	fi

	if ! tar -tzf "$steamcmd_archive" >/dev/null; then
		echo -e "\e[1;31mSteamCMD 压缩包校验失败，下载文件不完整。\e[0m"
		rm -f "$steamcmd_archive"
		return 1
	fi

	if ! tar -xzf "$steamcmd_archive" -C "$HOME/steamcmd"; then
		echo -e "\e[1;31mSteamCMD 解压失败，请检查目录权限和磁盘空间。\e[0m"
		rm -f "$steamcmd_archive"
		return 1
	fi
	rm -f "$steamcmd_archive"

	if [ ! -s "$HOME/steamcmd/linux32/libstdc++.so.6" ] || [ ! -s "$HOME/steamcmd/linux32/crashhandler.so" ]; then
		echo -e "\e[1;31mSteamCMD 解压不完整，缺少 linux32 下的 so 文件。\e[0m"
		return 1
	fi

	chmod +x "$HOME/steamcmd/steamcmd.sh"
}

ensure_steamcmd() {
	if command -v steamcmd >/dev/null 2>&1; then
		STEAMCMD_BIN=$(command -v steamcmd)
		return 0
	fi

	if manual_steamcmd_complete; then
		STEAMCMD_BIN="$HOME/steamcmd/steamcmd.sh"
		return 0
	fi

	if install_steamcmd_by_apt && command -v steamcmd >/dev/null 2>&1; then
		STEAMCMD_BIN=$(command -v steamcmd)
		return 0
	fi

	if install_steamcmd_manually; then
		STEAMCMD_BIN="$HOME/steamcmd/steamcmd.sh"
		return 0
	fi

	return 1
}

run_steamcmd() {
	if ! ensure_steamcmd; then
		echo -e "\e[1;31mSteamCMD 安装或定位失败，无法继续。\e[0m"
		return 1
	fi

	local timeout_seconds=${STEAMCMD_TIMEOUT_SECONDS:-0}
	local -a timeout_command=()
	if [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] && command -v timeout >/dev/null 2>&1; then
		timeout_command=(timeout --signal=TERM --kill-after=30s "$timeout_seconds")
	fi

	if [ "$STEAMCMD_BIN" == "$HOME/steamcmd/steamcmd.sh" ]; then
		(cd "$HOME/steamcmd" && "${timeout_command[@]}" "$STEAMCMD_BIN" "$@")
	else
		"${timeout_command[@]}" "$STEAMCMD_BIN" "$@"
	fi
}

steam_workshop_candidates() {
	printf '%s\n' \
		"$HOME/.steam/SteamApps/workshop" \
		"$HOME/Steam/steamapps/workshop" \
		"$HOME/.local/share/Steam/steamapps/workshop" \
		"$HOME/.steam/steam/steamapps/workshop"
}

get_workshop_path() {
	local workshop_path
	while IFS= read -r workshop_path; do
		if [ -d "$workshop_path/content/322330" ]; then
			echo "$workshop_path"
			return 0
		fi
	done < <(steam_workshop_candidates)

	if command -v steamcmd >/dev/null 2>&1; then
		echo "$HOME/.steam/SteamApps/workshop"
	else
		echo "$HOME/Steam/steamapps/workshop"
	fi
}

find_workshop_modmain() {
	local mod_id=$1
	local workshop_path
	while IFS= read -r workshop_path; do
		if [ -f "$workshop_path/content/322330/$mod_id/modmain.lua" ]; then
			echo "$workshop_path/content/322330/$mod_id/modmain.lua"
			return 0
		fi
	done < <(steam_workshop_candidates)
	return 1
}

workshop_mod_exists() {
	find_workshop_modmain "$1" >/dev/null
}

remove_workshop_mod() {
	local mod_id=$1
	local workshop_path
	while IFS= read -r workshop_path; do
		if [ -d "$workshop_path/content/322330/$mod_id" ]; then
			rm -rf "$workshop_path/content/322330/$mod_id"
		fi
	done < <(steam_workshop_candidates)
}

remove_workshop_appmanifest() {
	local workshop_path
	while IFS= read -r workshop_path; do
		rm -f "$workshop_path/appworkshop_322330.acf" "$workshop_path/content/322330/appworkshop_322330.acf"
	done < <(steam_workshop_candidates)
}

clean_steam_userdata() {
	local steam_user_path
	for steam_user_path in "$HOME/Steam/userdata" "$HOME/.steam/userdata" "$HOME/.local/share/Steam/userdata"; do
		find "$steam_user_path" -type f -mtime +3 -delete 2>/dev/null
		find "$steam_user_path" -type d -empty -delete 2>/dev/null
	done
}

##基础数据的获取
#数据统一初始化
init() {
	cluster_name=$1
	if [ "$cluster_name" == "" ]; then
		echo "存档名有误"
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
	# 每次都清空分片相关变量，避免 Master-only/Caves-only 存档复用上次调用的值。
	process_name_master=""
	process_name_caves=""
	process_name_main=""
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
	# 分片可能不存在；必须先清空，不能保留上一个存档解析出的路径。
	server_log_path_main=""
	server_log_path_master=""
	server_log_path_caves=""
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
	skip_mod_check=$4
	if [ "${5:-}" != "-KEEP_STARTUP_REPAIR" ]; then
		STARTUP_REPAIR_USED=0
		STARTUP_REPAIRED_MOD_IDS=""
	fi
	if [ "${6:-}" != "-KEEP_STARTUP_RESTART" ]; then
		STARTUP_RESTART_COUNTS=()
	fi
	get_cluster_flag "$cluster_name"

	if ! addmod_by_http_or_steamcmd "$cluster_name" "$auto_flag"; then
		echo -e "\e[1;31m存档所需 Mod 未能在有限重试内准备完成，取消本次启动。\e[0m"
		log_with_timestamp "存档所需 Mod 下载或校验失败，未启动服务器。"
		check_flag=0
		return 1
	fi

	get_process_name "$cluster_name"
	case $cluster_flag in
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
		esac
	if [ -z "$cluster_flag" ]; then
		echo "出错了,请联系作者QQ1549737287!!!"
	else
		start_server_check "$cluster_name" "$auto_flag"
		if [ "$check_flag" == 1 ] && [ "$skip_mod_check" != "-SKIP_MOD_CHECK" ]; then
			checkmodupdate "$cluster_name"
		fi
		if [ "$cluster_flag" != 5 ] && [[ $check_flag == 1 ]] && [[ $2 == "" ]]; then
			auto_update "$cluster_name"
		fi
	fi
}

#开启服务器
startup_log_begin() {
	local log_path=$1
	local process_name=$2
	local shard_name=$3
	local line_count=0
	if [ -z "$log_path" ]; then
		echo "无法记录启动日志基线：日志路径为空。" >&2
		return 1
	fi
	if [ -f "$log_path" ]; then
		line_count=$(wc -l <"$log_path")
	fi
	STARTUP_LOG_START_LINE["$log_path"]=$line_count
	if [ "$line_count" -gt 0 ]; then
		STARTUP_LOG_PREFIX_HASH["$log_path"]=$(head -n "$line_count" "$log_path" | sha256sum | awk '{print $1}')
	else
		STARTUP_LOG_PREFIX_HASH["$log_path"]=""
	fi
	STARTUP_PROCESS_BY_LOG["$log_path"]=$process_name
	STARTUP_SHARD_BY_LOG["$log_path"]=$shard_name
}

# 输出本次启动新增的日志；日志被截断时从头读取当前文件。
startup_log_delta() {
	local log_path=$1
	[ -n "$log_path" ] || return 1
	local start_line=${STARTUP_LOG_START_LINE["$log_path"]:-0}
	local original_hash=${STARTUP_LOG_PREFIX_HASH["$log_path"]:-}
	local current_hash=""
	local current_lines=0
	[ -f "$log_path" ] || return 0
	current_lines=$(wc -l <"$log_path")
	if [ "$start_line" -gt 0 ] && [ "$current_lines" -ge "$start_line" ] && [ -n "$original_hash" ]; then
		current_hash=$(head -n "$start_line" "$log_path" | sha256sum | awk '{print $1}')
	fi
	if [ "$current_lines" -lt "$start_line" ] || { [ -n "$current_hash" ] && [ "$current_hash" != "$original_hash" ]; }; then
		start_line=0
		STARTUP_LOG_START_LINE["$log_path"]=0
		STARTUP_LOG_PREFIX_HASH["$log_path"]=""
	fi
	if [ "$current_lines" -gt "$start_line" ]; then
		tail -n +$((start_line + 1)) "$log_path"
	fi
}

startup_process_exists() {
	local process_name=$1
	[ -n "$process_name" ] && screen -ls 2>/dev/null | grep --text -q "\\<$process_name\\>"
}

# screen 可能只剩一个没有游戏子进程的 shell；启动失败判断必须检查实际 DST 二进制。
startup_game_process_exists() {
	local log_path=$1
	[ -n "$log_path" ] || return 1
	local shard_name="${STARTUP_SHARD_BY_LOG["$log_path"]:-}"
	[ -n "$shard_name" ] || return 1
	startup_game_pids "$log_path" >/dev/null 2>&1
}

startup_game_pids() {
	local log_path=$1
	[ -n "$log_path" ] || return 1
	local shard_name="${STARTUP_SHARD_BY_LOG["$log_path"]:-}"
	local game_binary
	[ -n "$shard_name" ] || return 1
	get_path_games "$cluster_name"
	get_path_dontstarve_dedicated_server_nullrenderer "$cluster_name"
	game_binary="$dontstarve_dedicated_server_nullrenderer"
	ps -eo pid=,args= | awk -v binary="$game_binary" -v cluster="$cluster_name" -v shard="$shard_name" '
		{
			pid=$1
			executable=$2
			sub(/^.*\//, "", executable)
			if (executable != binary) {
				next
			}
			has_cluster=0
			has_shard=0
			for (i=3; i<=NF; i++) {
				flag=tolower($i)
				if (flag == "-cluster" && i < NF && $(i + 1) == cluster) {
					has_cluster=1
				}
				if (flag == "-shard" && i < NF && $(i + 1) == shard) {
					has_shard=1
				}
			}
			if (has_cluster && has_shard) {
				print pid
				found=1
			}
		}
		END {
			if (!found) {
				exit 1
			}
		}
	'
}

startup_stop_stale_game() {
	local log_path=$1
	local pids
	pids=$(startup_game_pids "$log_path" || true)
	[ -n "$pids" ] || return 0
	log_with_timestamp "检测到服务器已进入 Shutting down 但 DST 进程残留，先终止残留进程。"
	# 只处理匹配当前 cluster/shard 的 PID，不触碰存档或其他服务器。
	kill $pids >/dev/null 2>&1 || true
	sleep 2
	pids=$(startup_game_pids "$log_path" || true)
	if [ -n "$pids" ]; then
		kill -KILL $pids >/dev/null 2>&1 || true
	fi
}

# 仅清理“本次启动已确认致命失败并进入终止状态”的分片；正常关闭仍走独立日志基线。
startup_stop_terminal_shard() {
	local log_path=$1
	local process_name=$2
	local shard_name=$3
	local delta
	[ -n "$log_path" ] && [ -n "$process_name" ] || return 0
	STARTUP_PROCESS_BY_LOG["$log_path"]=$process_name
	STARTUP_SHARD_BY_LOG["$log_path"]=$shard_name
	delta=$(startup_log_delta "$log_path")
	if startup_delta_has_ready "$delta" || ! startup_delta_has_fatal "$delta" || ! startup_delta_has_terminal_shutdown "$delta"; then
		return 0
	fi

	if startup_game_process_exists "$log_path"; then
		startup_stop_stale_game "$log_path"
	fi
	if startup_game_process_exists "$log_path"; then
		log_with_timestamp "$shard_name 启动失败分片的 DST 进程无法终止，保留现场。"
		return 1
	fi
	if screen_session_exists_exact "$process_name"; then
		log_with_timestamp "$shard_name 分片本次启动已确认致命失败并进入 Shutting down，清理精确残留会话。"
		if ! close_exact_screen_sessions "$process_name"; then
			return 1
		fi
		sleep 1
	fi
	if screen_session_exists_exact "$process_name"; then
		log_with_timestamp "$shard_name 启动失败分片的 screen 会话仍存在，保留现场。"
		return 1
	fi
	return 0
}

startup_stop_terminal_cluster_shards() {
	local failed=0
	get_process_name "$cluster_name"
	get_path_server_log "$cluster_name"
	if ! startup_stop_terminal_shard "$server_log_path_master" "$process_name_master" "Master"; then
		failed=1
	fi
	if ! startup_stop_terminal_shard "$server_log_path_caves" "$process_name_caves" "Caves"; then
		failed=1
	fi
	return "$failed"
}

startup_delta_has_ready() {
	local delta=$1
	printf '%s\n' "$delta" | grep --text -Eq "$STARTUP_READY_PATTERNS"
}

startup_delta_has_fatal() {
	local delta=$1
	printf '%s\n' "$delta" | grep --text -Eq "$STARTUP_FATAL_PATTERNS"
}

startup_delta_has_missing_asset() {
	local delta=$1
	printf '%s\n' "$delta" | grep --text -Eq 'Could not find an asset matching [^[:space:]]+'
}

startup_delta_has_nonrepairable_lua() {
	local delta=$1
	printf '%s\n' "$delta" | grep --text -Eiq 'syntax error|unexpected symbol|attempt to (index|call|perform arithmetic)|nil value|api[[:space:]_-]*(incompat|unsupported)|incompatible api|mod[[:space:]_-]*conflict'
}

startup_delta_has_terminal_shutdown() {
	local delta=$1
	printf '%s\n' "$delta" | grep --text -Eiq 'Shutting down|Error during game restart!'
}

startup_delta_mod_ids() {
	local delta=$1
	printf '%s\n' "$delta" | grep --text -oE 'workshop-[0-9]+' | sort -u
}

# 日志统一使用 workshop-<数字>，SteamCMD 和 Workshop 目录只接受纯数字 ID。
workshop_numeric_id() {
	local mod_ref=$1
	mod_ref=${mod_ref#workshop-}
	[[ "$mod_ref" =~ ^[0-9]+$ ]] || return 1
	printf '%s\n' "$mod_ref"
}

startup_delta_missing_assets() {
	local delta=$1
	printf '%s\n' "$delta" | sed -nE 's/.*Could not find an asset matching ([^[:space:]]+).*/\1/p' | sort -u
}

# 只读取 LUA traceback 的调用栈。普通 ModIndex/modimport 日志里的 Workshop 路径不能作为故障归属。
startup_delta_traceback_mod_ids() {
	local delta=$1
	printf '%s\n' "$delta" | awk '
		function reset_block() {
			delete block_ids
		}
		function finish_block(    id) {
			for (id in block_ids) {
				all_ids[id]=1
			}
			reset_block()
		}
		function collect_ids(line,    rest, ref) {
			if (line !~ /mods\/workshop-[0-9]+\//) {
				return
			}
			rest=line
			while (match(rest, /workshop-[0-9]+/)) {
				ref=substr(rest, RSTART, RLENGTH)
				block_ids[ref]=1
				rest=substr(rest, RSTART + RLENGTH)
			}
		}
		/LUA ERROR stack traceback:/ {
			if (in_trace) {
				finish_block()
			}
			in_trace=1
			next
		}
		in_trace && /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]:/ {
			finish_block()
			in_trace=0
		}
		in_trace {
			collect_ids($0)
		}
		END {
			if (in_trace) {
				finish_block()
			}
			for (id in all_ids) {
				print id
			}
		}
	' | sort -u
}

# 同一调用栈出现多个 Workshop Mod 时无法可靠判断资源归属，必须保留现场供人工分析。
startup_delta_has_ambiguous_traceback_mods() {
	local delta=$1
	printf '%s\n' "$delta" | awk '
		function reset_block() {
			delete block_ids
			block_count=0
		}
		function finish_block() {
			if (block_count > 1) {
				ambiguous=1
			}
			reset_block()
		}
		function collect_ids(line,    rest, ref) {
			if (line !~ /mods\/workshop-[0-9]+\//) {
				return
			}
			rest=line
			while (match(rest, /workshop-[0-9]+/)) {
				ref=substr(rest, RSTART, RLENGTH)
				if (!(ref in block_ids)) {
					block_ids[ref]=1
					block_count++
				}
				rest=substr(rest, RSTART + RLENGTH)
			}
		}
		/LUA ERROR stack traceback:/ {
			if (in_trace) {
				finish_block()
			}
			in_trace=1
			next
		}
		in_trace && /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]:/ {
			finish_block()
			in_trace=0
		}
		in_trace {
			collect_ids($0)
		}
		END {
			if (in_trace) {
				finish_block()
			}
			exit ambiguous ? 0 : 1
		}
	'
}

# 缺失资源通常位于 traceback 前一行；仅在该调用栈唯一指向 wanted_mod 时建立关联。
startup_delta_traceback_mod_assets() {
	local delta=$1
	local wanted_mod=$2
	printf '%s\n' "$delta" | awk -v wanted_mod="$wanted_mod" '
		function reset_block() {
			delete block_ids
			block_count=0
			asset=""
		}
		function finish_block(    id) {
			if (block_count == 1 && asset != "") {
				for (id in block_ids) {
					if (id == wanted_mod) {
						print asset
					}
				}
			}
			reset_block()
		}
		function collect_ids(line,    rest, ref) {
			if (line !~ /mods\/workshop-[0-9]+\//) {
				return
			}
			rest=line
			while (match(rest, /workshop-[0-9]+/)) {
				ref=substr(rest, RSTART, RLENGTH)
				if (!(ref in block_ids)) {
					block_ids[ref]=1
					block_count++
				}
				rest=substr(rest, RSTART + RLENGTH)
			}
		}
		/LUA ERROR stack traceback:/ {
			if (in_trace) {
				finish_block()
			}
			reset_block()
			asset=previous
			sub(/^.*Could not find an asset matching[[:space:]]+/, "", asset)
			sub(/[[:space:]].*$/, "", asset)
			if (previous !~ /Could not find an asset matching[[:space:]]+[^[:space:]]+/) {
				asset=""
			}
			in_trace=1
			previous=$0
			next
		}
		in_trace && /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]:/ {
			finish_block()
			in_trace=0
		}
		in_trace {
			collect_ids($0)
		}
		{
			previous=$0
		}
		END {
			if (in_trace) {
				finish_block()
			}
		}
	' | sort -u
}

startup_delta_fault_mod_ids() {
	local delta=$1
	{
		printf '%s\n' "$delta" | sed -nE 's/.*error calling.*(workshop-[0-9]+).*/\1/p'
		startup_delta_traceback_mod_ids "$delta"
	} | sort -u
}

startup_delta_mod_assets() {
	local delta=$1
	local wanted_mod=$2
	{
		awk -v wanted_mod="$wanted_mod" '
			/error calling/ {
				current_mod=$0
				if (match(current_mod, /workshop-[0-9]+/)) {
					current_mod=substr(current_mod, RSTART, RLENGTH)
				} else {
					current_mod=""
				}
			}
			current_mod == wanted_mod && /Could not find an asset matching/ {
				asset=$0
				sub(/^.*Could not find an asset matching[[:space:]]+/, "", asset)
				sub(/[[:space:]].*$/, "", asset)
				print asset
			}
		' <<<"$delta"
		startup_delta_traceback_mod_assets "$delta" "$wanted_mod"
	} | sort -u
}

startup_delta_has_repairable_missing_asset() {
	local delta=$1
	local mod_ref
	while IFS= read -r mod_ref; do
		[ -n "$mod_ref" ] || continue
		if [ -n "$(startup_delta_mod_assets "$delta" "$mod_ref")" ]; then
			return 0
		fi
	done < <(startup_delta_fault_mod_ids "$delta")
	return 1
}

startup_report_nonfatal_mod_messages() {
	local delta=$1
	local warning_lines
	warning_lines=$(printf '%s\n' "$delta" | grep --text -Ei 'error calling|Could not find an asset|Disabling workshop-|Lua warning|mod[^[:space:]]* (disabled|被禁用)' || true)
	if [ -n "$warning_lines" ]; then
		echo -e "\\e[1;33m本次启动检测到模组警告/错误，但服务器已正常启动，仅记录，不自动修复：\\e[0m"
		printf '%s\n' "$warning_lines" | tail -n 20
		log_with_timestamp "本次启动检测到模组警告/错误；服务器已有正常启动标志，未执行自动修复。"
	fi
}

workshop_mod_dir() {
	local mod_id=$1
	local mod_main
	mod_main=$(find_workshop_modmain "$mod_id") || return 1
	dirname -- "$mod_main"
}

workshop_mod_existing_dir() {
	local mod_id=$1
	local workshop_path
	[[ "$mod_id" =~ ^[0-9]+$ ]] || return 1
	while IFS= read -r workshop_path; do
		if [ -d "$workshop_path/content/322330/$mod_id" ]; then
			printf '%s\n' "$workshop_path/content/322330/$mod_id"
			return 0
		fi
	done < <(steam_workshop_candidates)
	return 1
}

workshop_mod_required_files_ok() {
	local mod_dir=$1
	[ -d "$mod_dir" ] && [ -f "$mod_dir/modmain.lua" ] && [ -f "$mod_dir/modinfo.lua" ]
}

repair_restore_workshop_mod() {
	local mod_id=$1
	local backup_dir=$2
	local target_file="$backup_dir/target-$mod_id"
	local original_backup="$backup_dir/original-$mod_id"
	local absent_marker="$backup_dir/original-$mod_id.absent"
	local target current_dir
	[[ "$mod_id" =~ ^[0-9]+$ ]] || return 1
	[ -f "$target_file" ] || return 0
	target=$(<"$target_file")
	case "$target" in
		*/content/322330/"$mod_id") ;;
		*)
			log_with_timestamp "拒绝从无效备份目标恢复 workshop-$mod_id: $target"
			return 1
			;;
	esac

	current_dir=$(workshop_mod_existing_dir "$mod_id" 2>/dev/null || true)
	if [ -n "$current_dir" ] && [ "$current_dir" != "$target" ]; then
		rm -rf -- "$current_dir" || return 1
	fi
	if [ -d "$target" ]; then
		rm -rf -- "$target" || return 1
	fi
	if [ -d "$original_backup" ]; then
		mkdir -p "$(dirname -- "$target")" || return 1
		cp -a "$original_backup" "$target"
	elif [ ! -f "$absent_marker" ]; then
		log_with_timestamp "workshop-$mod_id 的原始备份状态不完整，无法恢复。"
		return 1
	fi
}

# 备份后下载并校验一个 Workshop mod。失败时恢复原目录。
repair_one_workshop_mod() {
	local mod_id=$1
	local assets=$2
	local mod_dir=""
	local workshop_path target backup_dir existing_dir
	local target_file original_backup absent_marker
	local steam_status asset
	local STEAMCMD_TIMEOUT_SECONDS=${STARTUP_MOD_REPAIR_TIMEOUT_SECONDS:-600}
	if ! [[ "$STEAMCMD_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
		STEAMCMD_TIMEOUT_SECONDS=600
	fi
	[[ "$mod_id" =~ ^[0-9]+$ ]] || return 1
	backup_dir=$3
	[ -d "$backup_dir" ] || return 1
	workshop_path=$(get_workshop_path)
	target="$workshop_path/content/322330/$mod_id"
	existing_dir=$(workshop_mod_existing_dir "$mod_id" 2>/dev/null || true)
	[ -n "$existing_dir" ] && target="$existing_dir"
	target_file="$backup_dir/target-$mod_id"
	original_backup="$backup_dir/original-$mod_id"
	absent_marker="$backup_dir/original-$mod_id.absent"

	# 第一次尝试时保存不可变的原始快照；后续重试不能覆盖该快照。
	if [ ! -f "$target_file" ]; then
		printf '%s\n' "$target" >"$target_file" || return 1
		if [ -d "$target" ]; then
			if ! cp -a "$target" "$original_backup"; then
				log_with_timestamp "无法备份 workshop-$mod_id，跳过自动修复。"
				return 1
			fi
		else
			: >"$absent_marker" || return 1
		fi
	fi

	# 原始快照已经成功保存，才清理本次待替换目录。
	if [ -d "$target" ]; then
		if ! rm -rf -- "$target"; then
			log_with_timestamp "无法备份 workshop-$mod_id，跳过自动修复。"
			return 1
		fi
	fi

	log_with_timestamp "开始强制重新下载并校验 workshop-$mod_id。"
	run_steamcmd +login anonymous +workshop_download_item 322330 "$mod_id" validate +quit
	steam_status=$?
	mod_dir=$(workshop_mod_existing_dir "$mod_id" 2>/dev/null || true)
	if [ "$steam_status" -eq 0 ] && workshop_mod_required_files_ok "$mod_dir"; then
		while IFS= read -r asset; do
			[ -n "$asset" ] || continue
			if [[ "$asset" = /* || "$asset" == *..* ]] || [ ! -e "$mod_dir/$asset" ]; then
				log_with_timestamp "workshop-$mod_id 下载后仍缺少资源: $asset"
				steam_status=1
			fi
		done <<<"$assets"
	else
		log_with_timestamp "workshop-$mod_id 下载或基础文件校验失败。"
		steam_status=1
	fi

	if [ "$steam_status" -ne 0 ]; then
		if ! repair_restore_workshop_mod "$mod_id" "$backup_dir"; then
			log_with_timestamp "workshop-$mod_id 修复失败，且原目录恢复失败，请保留备份目录: $backup_dir"
			return 2
		fi
		return 1
	fi
	return 0
}

repair_startup_mods() {
	local delta=$1
	local attempt=1
	local mod_ids pending_mod_ids next_pending backup_root mod_ref mod_id mod_assets
	local hard_failure=0 repair_status=0 restore_failed=0
	if startup_delta_has_ambiguous_traceback_mods "$delta"; then
		log_with_timestamp "同一 LUA traceback 涉及多个 Workshop mod，无法可靠判断资源归属，停止自动修复并保留现场。"
		return 1
	fi
	mod_ids=$(startup_delta_fault_mod_ids "$delta")
	[ -n "$mod_ids" ] || { log_with_timestamp "致命启动错误未关联到 Workshop mod，停止自动修复。"; return 1; }
	backup_root=$(mktemp -d "${TMPDIR:-/tmp}/dst-mod-repair.XXXXXX") || return 1
	pending_mod_ids=$mod_ids

	while [ "$attempt" -le 3 ] && [ -n "$pending_mod_ids" ]; do
		log_with_timestamp "第 $attempt/3 次尝试修复 Workshop mod: $(printf '%s\n' "$pending_mod_ids" | tr '\n' ' ')"
		next_pending=""
		while IFS= read -r mod_ref; do
			[ -n "$mod_ref" ] || continue
			if ! mod_id=$(workshop_numeric_id "$mod_ref"); then
				log_with_timestamp "日志中提取到无效的 Workshop mod 标识: $mod_ref"
				hard_failure=1
				continue
			fi
			mod_assets=$(startup_delta_mod_assets "$delta" "workshop-$mod_id")
			if [ -z "$mod_assets" ]; then
				log_with_timestamp "无法将缺失资源对应到 $mod_ref，停止自动修复以避免误替换。"
				hard_failure=1
				continue
			fi
			repair_status=0
			repair_one_workshop_mod "$mod_id" "$mod_assets" "$backup_root" || repair_status=$?
			if [ "$repair_status" -eq 2 ]; then
				hard_failure=1
				break
			elif [ "$repair_status" -ne 0 ]; then
				next_pending+="$mod_ref"$'\n'
			fi
		done <<<"$pending_mod_ids"
		if [ "$hard_failure" -ne 0 ]; then
			break
		fi
		pending_mod_ids=$(printf '%s' "$next_pending" | sed '/^[[:space:]]*$/d')
		if [ -z "$pending_mod_ids" ]; then
			STARTUP_REPAIRED_MOD_IDS=$(printf '%s\n' "$mod_ids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
			log_with_timestamp "Workshop mod 自动修复下载及资源校验完成: $STARTUP_REPAIRED_MOD_IDS"
			rm -rf -- "$backup_root"
			return 0
		fi
		attempt=$((attempt + 1))
	done

	while IFS= read -r mod_ref; do
		[ -n "$mod_ref" ] || continue
		if mod_id=$(workshop_numeric_id "$mod_ref"); then
			if ! repair_restore_workshop_mod "$mod_id" "$backup_root"; then
				log_with_timestamp "无法从事务备份恢复 $mod_ref，备份目录: $backup_root"
				restore_failed=1
			fi
		fi
	done <<<"$mod_ids"
	if [ "$restore_failed" -ne 0 ]; then
		log_with_timestamp "Workshop mod 自动修复失败且自动恢复不完整，已保留事务备份: $backup_root"
		return 1
	fi
	log_with_timestamp "Workshop mod 自动修复失败，已恢复原模组并停止重试。"
	rm -rf -- "$backup_root"
	return 1
}

start_server_select() {
	cluster_name=$1
	process_name_select=$2
	script_start_server=$3
	local log_path=""
	get_path_games "$cluster_name"
	if [ "$script_start_server" == "start_server_master.sh" ]; then
		shard_name="Master"
	else
		shard_name="Caves"
	fi
	get_path_dontstarve_dedicated_server_nullrenderer "$cluster_name"
	get_path_server_log "$cluster_name"
	if [ "$shard_name" == "Master" ]; then
		log_path=$server_log_path_master
	else
		log_path=$server_log_path_caves
	fi
	if [ -z "$log_path" ]; then
		echo "无法启动 $cluster_name/$shard_name：未解析到对应日志路径。" >&2
		return 1
	fi
	local workshop_path
	workshop_path=$(get_workshop_path)
	echo "#!/bin/bash
	cd \"$dontstarve_dedicated_server_nullrenderer_path\" || exit
	run_shared=(./$dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-ugc_directory \"$workshop_path/\")
	run_shared+=(-monitor_parent_process \$\$)
	\"\${run_shared[@]}\" -shard $shard_name" >"$script_files_path"/"$script_start_server"
	grep --text -m 1 buildid "$gamesPath"/steamapps/appmanifest_343050.acf | sed 's/[^0-9]//g' >"$script_files_path"/"cluster_game_buildid.txt"
	chmod 777 "$script_files_path"/"$script_start_server"
	if ! startup_log_begin "$log_path" "$process_name_select" "$shard_name"; then
		echo "无法启动 $cluster_name/$shard_name：启动日志基线记录失败。" >&2
		return 1
	fi
	screen -dmS "$process_name_select" /bin/sh -c "$script_files_path/$script_start_server"
}

#检查是否成功开启
start_server_check() {
	cluster_name=$1
	local start_auto_flag=$2
	start_time=$(date +%s)
	# 设定超时时间为 300 秒（5 分钟）
	TIMEOUT=300 
	get_process_name "$cluster_name"
	get_path_server_log "$cluster_name"
	local startup_ok=1
	if [ -n "$server_log_path_master" ]; then
		if start_server_check_select "地上" "$server_log_path_master" "$start_auto_flag" $start_time $TIMEOUT; then
			startup_ok=0
		fi
	fi
	if [ "$startup_ok" -eq 1 ] && [ -n "$server_log_path_caves" ]; then
		if start_server_check_select "地下" "$server_log_path_caves" "$start_auto_flag" $start_time $TIMEOUT; then
			startup_ok=0
		fi
	fi
	end_time=$(date +%s)
	cost_time=$((end_time - start_time))
	cost_minutes=$((cost_time / 60))
	cost_seconds=$((cost_time % 60))
	cost_echo="$cost_minutes分$cost_seconds秒"
	if [ "$startup_ok" -eq 0 ] || [ "$cost_echo" == "00分00秒" ] || [ "$cost_echo" == "0分0秒" ]; then
		echo -e "\\e[1;31m本次服务器启动失败，停止后续 Mod 更新检查和自动更新。\\e[0m"
		check_flag=0
		return 0
	else
		echo -e "\r\e[92m本次开服花费时间$cost_echo:\e[0m"
		check_flag=1
		sleep 1
		get_process_name "$cluster_name"
		if startup_process_exists "$process_name_main"; then
			screen -S "$process_name_main" -p 0 -X stuff " modVersionInfo = {}  $(printf \\r)" >/dev/null 2>&1 || true
		fi
		return 1
	fi
}

startup_restart_cluster_limited() {
	local reason=$1
	local restart_auto_flag=$2
	local close_mode=${3:-$restart_auto_flag}
	local key="$cluster_name:$reason"
	local count=${STARTUP_RESTART_COUNTS["$key"]:-0}
	if [ "$count" -ge "$STARTUP_MAX_RESTARTS" ]; then
		log_with_timestamp "$reason 已达到最多 $STARTUP_MAX_RESTARTS 次自动重启，停止重启。"
		close_server "$cluster_name" "$close_mode"
		check_flag=0
		return 1
	fi
	count=$((count + 1))
	STARTUP_RESTART_COUNTS["$key"]=$count
	log_with_timestamp "$reason 将执行有限重试 ($count/$STARTUP_MAX_RESTARTS)。"
	if ! close_server "$cluster_name" "$close_mode"; then
		log_with_timestamp "$reason 自动重启已取消：服务器关闭未得到安全确认。"
		check_flag=0
		return 1
	fi
	howtostart "$cluster_name" "$restart_auto_flag" "" "-SKIP_MOD_CHECK" "-KEEP_STARTUP_REPAIR" "-KEEP_STARTUP_RESTART"
	[ "$check_flag" -eq 1 ]
}

# 判断是否成功开启
# 1代表需要执行，0代表执行完毕
start_server_check_select() {
	w_flag=$1
	logpath_flag=$2
	auto_flag=$3
	start_time=${4:-$(date +%s)}
	TIMEOUT=${5:-300}
	mod_flag=1
	download_flag=1
	check_flag=1
	if [ -z "$logpath_flag" ]; then
		echo "$w_flag服务器启动检测已停止：未解析到日志路径。" >&2
		check_flag=0
		return 0
	fi
	# 兼容监控脚本等直接调用路径：缺少上下文时按当前分片补齐。
	if [ "$w_flag" == "地上" ]; then
		STARTUP_PROCESS_BY_LOG["$logpath_flag"]="${STARTUP_PROCESS_BY_LOG["$logpath_flag"]:-$process_name_master}"
		STARTUP_SHARD_BY_LOG["$logpath_flag"]="Master"
	else
		STARTUP_PROCESS_BY_LOG["$logpath_flag"]="${STARTUP_PROCESS_BY_LOG["$logpath_flag"]:-$process_name_caves}"
		STARTUP_SHARD_BY_LOG["$logpath_flag"]="Caves"
	fi
	if [ -z "${STARTUP_LOG_START_LINE["$logpath_flag"]+set}" ]; then
		STARTUP_LOG_START_LINE["$logpath_flag"]=0
	fi
	local startup_process="${STARTUP_PROCESS_BY_LOG["$logpath_flag"]}"
	local delta=""
	local fatal_seen=0
	local ready_seen=0
	# 只检查本次 start_server_select 之后新增的日志。
	while :; do
		current_time=$(date +%s)
		elapsed_time=$((current_time - start_time))
		if [ "$elapsed_time" -gt "$TIMEOUT" ]; then
			log_with_timestamp "\r\e[1;31m$w_flag服务器启动超时，请检查网络或配置。正在关闭服务器。\e[0m"
			close_server "$cluster_name" "$auto_flag"
			return 0
		fi
		get_path_server_log "$cluster_name"
		delta=$(startup_log_delta "$logpath_flag")
		if startup_delta_has_ready "$delta"; then
			ready_seen=1
		fi
		if startup_delta_has_fatal "$delta"; then
			fatal_seen=1
		fi

		# 正常启动标志优先级最高：即使同一轮日志有模组警告，也绝不修复。
		if [ "$ready_seen" -eq 1 ]; then
			startup_report_nonfatal_mod_messages "$delta"
			echo -e "\r\e[92m$w_flag服务器开启成功!!!                          \e[0m"
			check_flag=0
			return 1
		fi

		# 已知错误必须先于通用“进程已退出”处理，否则进程先退出时会丢失错误分类。
		if printf '%s\n' "$delta" | grep --text -Fq "Your Server Will Not Start !!!"; then
			echo -e "\r\e[1;31m$w_flag服务器开启失败：请检查令牌是否存在且有效；该错误不会自动重启，请修正后手动启动。\e[0m"
			close_server "$cluster_name" "$auto_flag"
			return 0
		fi
		if printf '%s\n' "$delta" | grep --text -Fq 'PushNetworkDisconnectEvent With Reason: "ID_DST_INITIALIZATION_FAILED", reset: false'; then
			echo -e "\r\e[1;31m$w_flag服务器开启未成功,端口冲突啦，改下端口吧,正在关闭服务器，请调整后重新开服！！！            \e[0m"
			close_server "$cluster_name" "$auto_flag"
			check_flag=0
			return 0
		fi
		if printf '%s\n' "$delta" | grep --text -Fq "LAN only servers must use a port in the range of [10998, 11018]"; then
			echo -e "\r\e[1;31m$w_flag服务器开启未成功,端口冲突啦，改下端口吧,本地服务器端口范围是[10998, 11018],正在关闭服务器，请调整后重新开服！！！            \e[0m"
			close_server "$cluster_name" "$auto_flag"
			check_flag=0
			return 0
		fi
		if printf '%s\n' "$delta" | grep --text -Fq "DownloadServerMods timed out with no response from Workshop..."; then
			echo -e "\r\e[31m连接创意工坊超时导致$w_flag服务器 Mod 下载失败，将进行有限重试。\e[0m"
			if startup_restart_cluster_limited "Workshop 下载超时" "$auto_flag" -AUTO; then
				return 1
			fi
			return 0
		fi
		if printf '%s\n' "$delta" | grep --text -Fq "Failed to send shard broadcast message"; then
			echo -e "\r\e[1;33m$w_flag分片广播失败，可能是临时网络问题，将进行有限重试。\e[0m"
			if startup_restart_cluster_limited "分片广播失败" "$auto_flag"; then
				return 1
			fi
			return 0
		fi

		# 先判断服务器是否已经失败，不能让“等待 Mod 下载”遮住启动失败。
		if [ "$fatal_seen" -eq 1 ] && { ! startup_game_process_exists "$logpath_flag" || startup_delta_has_terminal_shutdown "$delta"; }; then
			mod_flag=0
			download_flag=0
			check_flag=0
		elif [ "$elapsed_time" -ge 10 ] && ! startup_game_process_exists "$logpath_flag"; then
			echo -e "\r\e[1;31m$w_flag服务器实际进程已退出，但未出现正常启动标志，停止等待 Mod 下载。\e[0m"
			log_with_timestamp "$w_flag服务器实际进程已退出且没有正常启动标志，停止启动检测。"
			check_flag=0
			close_server "$cluster_name" "$auto_flag"
			return 0
		fi

		if [ "$mod_flag" == 1 ] && printf '%s\n' "$delta" | grep --text -Eq 'FinishDownloadingServerMods Complete!'; then
			echo -e "\r\e[92m$w_flag服务器mod下载完成!!!                                                                  \e[0m"
			mod_flag=0
			download_flag=0
		elif [ "$mod_flag" == 1 ] && printf '%s\n' "$delta" | grep --text -Eq 'Registering Mods:|Mods registered\.|ModIndex: Load sequence finished successfully\.|Starting Dedicated Server Game'; then
			# 这些标志只表示本次启动已越过 Workshop 下载阶段，不代表服务器启动成功。
			echo -e "\r\e[92m$w_flag服务器已完成 Workshop 下载检测，正在加载模组和世界...\e[0m"
			mod_flag=0
			download_flag=0
		elif [ "$mod_flag" == 1 ] && printf '%s\n' "$delta" | grep --text -Fq "[Workshop] OnDownloadPublishedFile" && [ "$download_flag" == 1 ]; then
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后.                         "
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后..                        "
			sleep 1
			echo -en "\r$w_flag服务器mod正在下载中,请稍后...                       "
			sleep 1
		fi

		# 检查有没有下载完成
		if [ "$mod_flag" -eq 1 ]; then
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

		# 只有“致命错误 + 对应会话已退出 + 没有正常标志”才可进入模组修复。
		if [ "$fatal_seen" -eq 1 ] && [ -n "$startup_process" ] && { ! startup_game_process_exists "$logpath_flag" || startup_delta_has_terminal_shutdown "$delta"; }; then
			if ! startup_stop_terminal_cluster_shards; then
				echo -e "\\e[1;31m启动失败分片无法安全结束，停止自动修复并保留现场。\\e[0m"
				log_with_timestamp "启动失败分片清理未完成，无法安全自动修复。"
				check_flag=0
				return 0
			fi
			if startup_game_process_exists "$logpath_flag"; then
				echo -e "\\e[1;31m$w_flag服务器已进入终止状态但进程无法退出，停止自动修复并保留现场。\\e[0m"
				log_with_timestamp "服务器终止状态检测到残留 DST 进程，无法安全自动修复。"
				check_flag=0
				return 0
			fi
			if startup_delta_has_repairable_missing_asset "$delta" && ! startup_delta_has_nonrepairable_lua "$delta"; then
				if [ "$STARTUP_REPAIR_USED" -ne 0 ]; then
					echo -e "\e[1;31m$w_flag服务器在模组修复后仍启动失败，已停止自动修复。\e[0m"
					log_with_timestamp "模组修复后的再次启动仍失败，停止自动修复。"
					check_flag=0
				else
					STARTUP_REPAIR_USED=1
					echo -e "\r\e[1;31m$w_flag服务器已确认启动失败，检测到模组资源缺失，开始有限次自动修复。\e[0m"
					if ! close_server "$cluster_name" "$auto_flag"; then
						echo -e "\e[1;31m服务器关闭未得到安全确认，取消 Mod 自动修复并保留现场。\e[0m"
						log_with_timestamp "Mod 自动修复已取消：服务器关闭未得到安全确认。"
						check_flag=0
						return 0
					fi
					if repair_startup_mods "$delta"; then
						echo -e "\e[92m模组修复完成，重新启动服务器并重新执行启动检测。\e[0m"
						howtostart "$cluster_name" "$auto_flag" "" "-SKIP_MOD_CHECK" "-KEEP_STARTUP_REPAIR" "-KEEP_STARTUP_RESTART"
						if [ "$check_flag" -eq 1 ]; then
							echo -e "\e[92m模组修复后服务器启动成功: $STARTUP_REPAIRED_MOD_IDS\e[0m"
							log_with_timestamp "模组修复后服务器启动成功: $STARTUP_REPAIRED_MOD_IDS"
							return 1
						fi
						echo -e "\e[1;31m模组修复后服务器仍启动失败，已停止自动修复和自动重启。\e[0m"
						log_with_timestamp "模组修复后的完整启动检测失败，停止自动修复和自动重启。"
					else
						echo -e "\e[1;31m模组自动修复失败，已停止重试；请检查本次启动日志或手动处理模组。\e[0m"
						check_flag=0
					fi
				fi
			else
				echo -e "\e[1;31m$w_flag服务器启动失败，但不是可确认的资源缺失；可能是 Lua 语法/API 不兼容或模组冲突，停止自动修复。\e[0m"
				printf '%s\n' "$delta" | grep --text -Ei 'lua|stack traceback|error calling|api|conflict' | tail -n 30 || true
				log_with_timestamp "服务器致命启动失败，但未发现可自动修复的模组资源缺失。"
				check_flag=0
			fi
			return 0
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
		sudo dpkg --add-architecture i386
		sudo apt-get -y update
		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libcurl3-gnutls:i386 || sudo apt-get -y install libcurl4-gnutls-dev:i386 || true
	elif
		[ "$os" == "DebianGNU/" ]
	then

		echo ""
		echo "##########################"
		echo "# 加载 Debian Linux 环境 #"
		echo "##########################"
		echo ""
		sudo apt-get -y update
		sudo dpkg --add-architecture i386
		sudo apt-get -y update

		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libc6-i386
		sudo apt-get -y install libcurl3-gnutls:i386 || sudo apt-get -y install libcurl4-gnutls-dev:i386 || true

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
	local V2_mods=("$@")
	# mod所在目录
	get_cluster_main "$cluster_name"
	get_dedicated_server_mods_setup "$cluster_name"
	modoverrides_path=$cluster_main/modoverrides.lua

	if [ -e "$modoverrides_path" ]; then
		# 删除appworkshop_322330.acf
		remove_workshop_appmanifest
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
				if ! workshop_mod_exists "$mod_id"; then
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
			run_steamcmd $workshop_commands 2>&1 | tee "$log_file"
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
		rm -rf "$dedicated_server_mods_setup"
		sleep 0.1
		touch "$dedicated_server_mods_setup"
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
	local download_failed=0
	# mod所在目录
	get_cluster_main "$cluster_name"
	get_dedicated_server_mods_setup "$cluster_name"
	modoverrides_path=$cluster_main/modoverrides.lua
	if [ -e "$modoverrides_path" ]; then
		echo "正在将开启存档所需的mod添加进服务器配置文件中..."
		rm -rf "$dedicated_server_mods_setup"
		sleep 0.1
		touch "$dedicated_server_mods_setup"
		V2_mods=()
		while IFS= read -r mod_num; do
			get_mod_info "$mod_num"
			mod_file_url=${mod_info_post[2]}
			if [ -z "$mod_file_url" ] || [ "$mod_file_url" == "null" ]; then
				if ! workshop_mod_exists "$mod_num"; then
					echo "${mod_info_post[0]} [${mod_info_post[1]}] 是V2 Mod 后续将使用steamcmd下载"
					V2_mods+=("$mod_num")
				else
					echo -e "\e[92m${mod_info_post[0]} [${mod_info_post[1]}]-V2 已存在\e[0m"
				fi
			else
				# 如果文件夹不存在，追加到命令字符串中
				if [ ! -f "$HOME/DST/mods/workshop-$mod_num/modmain.lua" ]; then
					if ! download_mod_by_http "$mod_file_url" "$mod_num"; then
						log_with_timestamp "Mod $mod_num HTTP 下载失败。"
						download_failed=1
					fi
				else
					echo -e "\e[92m${mod_info_post[0]} [${mod_info_post[1]}]-V1 已存在\e[0m"
				fi
			fi
		done < <(grep --text "\"workshop" <"$modoverrides_path" | cut -d '"' -f 2 | cut -d '-' -f 2)

		# 重新写入ServerModSetup配置
		while IFS= read -r mod_num; do
			echo "ServerModSetup(\"$mod_num\")" >>"$dedicated_server_mods_setup"
		done < <(grep --text "\"workshop" <"$modoverrides_path" | cut -d '"' -f 2 | cut -d '-' -f 2)

		if ! download_ensure_all_success "${V2_mods[@]}"; then
			download_failed=1
		fi

		if [ "$download_failed" -ne 0 ]; then
			echo -e "\e[1;31m部分 Mod 下载或校验失败，已停止本次启动。\e[0m"
			return 1
		fi
		echo -e "\e[92mMod添加完成!!!\e[0m"
		return 0
	else
		echo -e "\e[1;31m未找到mod配置文件 \e[0m"
		return 0
	fi
}

# 下载指定 Mod 列表，并在有限次数和总时长内确认全部存在。
download_ensure_all_success() {
	local mods_to_download=("$@")
	local try_count=1
	local max_attempts=${MOD_DOWNLOAD_MAX_ATTEMPTS:-3}
	local max_seconds=${MOD_DOWNLOAD_MAX_SECONDS:-1800}
	local start_seconds current_seconds elapsed_seconds remaining_seconds
	local STEAMCMD_TIMEOUT_SECONDS
	if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
		max_attempts=3
	fi
	if ! [[ "$max_seconds" =~ ^[1-9][0-9]*$ ]]; then
		max_seconds=1800
	fi
	if [ ${#mods_to_download[@]} -eq 0 ]; then
		return 0
	fi
	start_seconds=$(date +%s)

	while [ ${#mods_to_download[@]} -gt 0 ] && [ "$try_count" -le "$max_attempts" ]; do
		current_seconds=$(date +%s)
		elapsed_seconds=$((current_seconds - start_seconds))
		if [ "$elapsed_seconds" -ge "$max_seconds" ]; then
			break
		fi
		remaining_seconds=$((max_seconds - elapsed_seconds))
		STEAMCMD_TIMEOUT_SECONDS=$remaining_seconds
		log_with_timestamp "\n🎯 第 $try_count/$max_attempts 次尝试下载以下Mod：${mods_to_download[*]}"

		# 调用steamcmd进行下载
		if ! download_mod_by_steamcmd "${mods_to_download[@]}"; then
			log_with_timestamp "\e[33m本次 SteamCMD 调用返回失败，将根据文件校验结果决定是否重试。\e[0m"
		fi
		sleep 1

		# 检查哪些仍未下载成功
		local failed_mods=()
		for mod_num in "${mods_to_download[@]}"; do
			mod_path=$(find_workshop_modmain "$mod_num")
			if [ -z "$mod_path" ]; then
				log_with_timestamp "\e[33m[仍未成功] Mod $mod_num 未找到modmain.lua\e[0m"
				failed_mods+=("$mod_num")
			else
				log_with_timestamp "\e[92m[成功] Mod $mod_num 下载完成\e[0m"
			fi
		done

		# 更新待下载列表
		mods_to_download=("${failed_mods[@]}")
		if [ ${#mods_to_download[@]} -gt 0 ]; then
			current_seconds=$(date +%s)
			elapsed_seconds=$((current_seconds - start_seconds))
			if [ "$try_count" -ge "$max_attempts" ] || [ "$elapsed_seconds" -ge "$max_seconds" ]; then
				break
			fi
			log_with_timestamp "\e[33m部分Mod仍未下载成功，准备重新尝试...\e[0m"
			sleep 2
		fi
		try_count=$((try_count + 1))
	done

	if [ ${#mods_to_download[@]} -gt 0 ]; then
		current_seconds=$(date +%s)
		elapsed_seconds=$((current_seconds - start_seconds))
		log_with_timestamp "\e[1;31mSteamCMD Mod 下载在 $try_count 次尝试、${elapsed_seconds} 秒后仍失败：${mods_to_download[*]}\e[0m"
		return 1
	fi

	log_with_timestamp "\e[92m✅ 所有Steamcmd Mod已成功下载完毕！\e[0m"
	return 0
}


#自动添加存档所需的mod
download_mod_by_http() {
    local mod_file_url=$1
    local mod_num=$2
    local temp_dir
    local mods_path="$HOME/DST/mods/workshop-$mod_num"
    temp_dir=$(mktemp -d "/tmp/mod_${mod_num}.XXXXXX") || { echo "无法创建临时目录"; return 1; }
    
    # 下载到临时目录
    wget -q -O "$temp_dir/mod.zip" "$mod_file_url" || { echo "下载失败，保留旧 Mod"; rm -rf "$temp_dir"; return 1; }
    
    # 静默测试压缩包（不输出任何信息）
    unzip -tq "$temp_dir/mod.zip" >/dev/null 2>&1 || { 
        echo "文件损坏，保留旧 Mod"; 
        rm -rf "$temp_dir"; 
        return 1; 
    }
    
    # 解压失败时恢复旧 Mod，避免更新失败后丢失可用版本
    local mod_path="$mods_path"
    local old_mod_path="$temp_dir/old_mod"
    if [ -d "$mod_path" ]; then
        mv "$mod_path" "$old_mod_path" || { echo "无法备份旧 Mod，取消更新"; rm -rf "$temp_dir"; return 1; }
    fi
    if ! unzip -oq "$temp_dir/mod.zip" -d "$mods_path" >/dev/null 2>&1 || [ ! -d "$mod_path" ]; then
        rm -rf "$mod_path"
        if [ -d "$old_mod_path" ]; then
            mv "$old_mod_path" "$mod_path"
        fi
        echo "解压失败，已恢复旧 Mod"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
    echo -e "\e[92m${mod_info_post[0]} [${mod_info_post[1]}]-V1 下载完成\e[0m"
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
				screen -S "$process_name_main" -p 0 -X stuff "c_rollback($rollbackday)$(printf \\r)"
				echo "已回档$rollbackday 天！"
				;;
			3)
				echo "请输入你要发布的公告:"
				read -r str
				screen -S "$process_name_main" -p 0 -X stuff "c_announce(\"$str\")$(printf \\r)"
				echo "已发布通知！"
				;;
			4)
				screen -S "$process_name_main" -p 0 -X stuff "for k,v in pairs(AllPlayers) do v:PushEvent('respawnfromghost') end$(printf \\r)"
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
	if ! close_server "$cluster_name" "$auto_flag" "$check_player"; then
		log_with_timestamp "服务器关闭未得到安全确认，取消本次重启。"
		return 1
	fi
	howtostart "$cluster_name" "$auto_flag" "$check_player"
}

# 更新游戏
update_game() {
	local version_flag=$1
	local steamcmd_log
	local steamcmd_status
	steamcmd_log=$(mktemp) || return 1
	echo "正在更新游戏,请稍后。。。更新之后重启服务器生效哦。。。"
	if [[ ${version_flag} == "DEFAULT" ]]; then
		echo "同步最新正式版游戏本体内容中。。。"
		run_steamcmd +force_install_dir "$DST_DEFAULT_PATH" +login anonymous +app_update 343050 validate +quit 2>&1 | tee "$steamcmd_log"
	else
		echo "同步最新测试版版游戏本体内容中。。。"
		run_steamcmd +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta "$BETA_TOKEN" validate +quit 2>&1 | tee "$steamcmd_log"
	fi
	steamcmd_status=${PIPESTATUS[0]}

	if [ "$steamcmd_status" -ne 0 ]; then
		echo -e "\e[1;31mSteamCMD 进程执行失败，退出码: $steamcmd_status\e[0m"
		rm -f "$steamcmd_log"
		return 1
	fi
	if ! grep --text -Fq "Success! App '343050' fully installed." "$steamcmd_log"; then
		echo -e "\e[1;31mSteamCMD 未返回游戏本体安装成功标志，本次更新按失败处理。\e[0m"
		grep --text -E 'ERROR!|Error!|FAILED|Failure' "$steamcmd_log" | tail -n 10 || true
		rm -f "$steamcmd_log"
		return 1
	fi

	rm -f "$steamcmd_log"
	return 0
}

get_game_version_value() {
	local game_path=$1
	local version_file="$game_path/version.txt"
	if [ -f "$version_file" ]; then
		tr -d '[:space:]' <"$version_file"
	fi
}

get_game_buildid_value() {
	local game_path=$1
	local manifest_file="$game_path/steamapps/appmanifest_343050.acf"
	if [ -f "$manifest_file" ]; then
		grep --text -m 1 '"buildid"' "$manifest_file" 2>/dev/null | sed 's/[^0-9]//g'
	fi
}

# Klei 官方构建列表中的 release/updatebeta 版本与游戏目录 version.txt 一致。
get_remote_game_version() {
	local steam_branch=$1
	local builds_branch
	local response
	local remote_version

	case "$steam_branch" in
		public)
			builds_branch="release"
			;;
		updatebeta)
			builds_branch="updatebeta"
			;;
		*)
			return 1
			;;
	esac
	if ! response=$(curl -fsS --connect-timeout 10 --max-time 20 \
		"https://s3.amazonaws.com/dstbuilds/builds.json"); then
		return 1
	fi
	if ! remote_version=$(jq -er --arg branch "$builds_branch" '
		.[$branch]
		| select(type == "array" and length > 0)
		| last
		| tostring
	' <<<"$response" 2>/dev/null); then
		return 1
	fi

	[[ "$remote_version" =~ ^[0-9]+$ ]] || return 1
	printf '%s\n' "$remote_version"
}

screen_session_ids_exact() {
	local wanted_name=$1
	[ -n "$wanted_name" ] || return 1
	screen -ls 2>/dev/null | awk -v wanted="$wanted_name" '
		{
			line=$0
			sub(/^[[:space:]]*/, "", line)
			if (line !~ /^[0-9]+\./) {
				next
			}
			pid=line
			sub(/\..*$/, "", pid)
			session=line
			sub(/^[0-9]+\./, "", session)
			metadata=index(session, "\t")
			if (metadata > 0) {
				session=substr(session, 1, metadata - 1)
			} else {
				sub(/[[:space:]]+\([^()]*\)[[:space:]]*$/, "", session)
			}
			if (session == wanted) {
				print pid
			}
		}
	'
}

screen_session_exists_exact() {
	local session_ids
	session_ids=$(screen_session_ids_exact "$1")
	[ -n "$session_ids" ]
}

close_exact_screen_sessions() {
	local process_name=$1
	local session_id
	local failed=0
	while IFS= read -r session_id; do
		[ -n "$session_id" ] || continue
		if ! screen -S "$session_id" -X quit >/dev/null 2>&1; then
			failed=1
		fi
	done < <(screen_session_ids_exact "$process_name")
	return "$failed"
}

# 输出基线之后的新日志；文件被截断或替换时改为读取当前完整文件。
shutdown_log_delta() {
	local log_path=$1
	local start_line=$2
	local original_hash=$3
	local current_lines=0
	local current_hash=""
	[ -n "$log_path" ] && [ -f "$log_path" ] || return 0
	current_lines=$(wc -l <"$log_path")
	if [ "$start_line" -gt 0 ] && [ "$current_lines" -ge "$start_line" ] && [ -n "$original_hash" ]; then
		current_hash=$(head -n "$start_line" "$log_path" | sha256sum | awk '{print $1}')
	fi
	if [ "$current_lines" -lt "$start_line" ] || { [ -n "$current_hash" ] && [ "$current_hash" != "$original_hash" ]; }; then
		start_line=0
	fi
	if [ "$current_lines" -gt "$start_line" ]; then
		tail -n +$((start_line + 1)) "$log_path"
	fi
}

# 关闭服务器
close_server() {
	cluster_name=$1
	close_flag=$2
	check_player=$3
	local close_failed=0
	local close_status=0
	get_process_name "$cluster_name"
	if [ -z "$cluster_name" ]; then
		main
		return 1
	elif [ -d "${DST_SAVE_PATH}/$cluster_name" ]; then
		get_path_server_log "$cluster_name"
		[ -n "$server_log_path_master" ] && STARTUP_SHARD_BY_LOG["$server_log_path_master"]="Master"
		[ -n "$server_log_path_caves" ] && STARTUP_SHARD_BY_LOG["$server_log_path_caves"]="Caves"
		if [ "$close_flag" == "" ] || [ "$close_flag" == "-close" ]; then
			close_server_autoUpdate "$cluster_name"
		fi

		if [ -n "$process_name_master" ] && screen_session_exists_exact "$process_name_master"; then
			close_server_select "$process_name_master" "地上" "$close_flag" "$check_player" "$server_log_path_master"
			close_status=$?
			if [ "$close_status" -eq 2 ]; then
				return 2
			elif [ "$close_status" -ne 0 ]; then
				close_failed=1
			fi
		fi
		if [ -n "$process_name_caves" ] && screen_session_exists_exact "$process_name_caves"; then
			close_server_select "$process_name_caves" "地下" "$close_flag" "$check_player" "$server_log_path_caves"
			close_status=$?
			if [ "$close_status" -eq 2 ]; then
				return 2
			elif [ "$close_status" -ne 0 ]; then
				close_failed=1
			fi
		fi

		if [ -n "$server_log_path_master" ] && startup_game_process_exists "$server_log_path_master"; then
			echo -e "\e[1;31m地上 DST 进程仍存在且未得到安全关闭确认，已保留现场。\e[0m"
			close_failed=1
		fi
		if [ -n "$server_log_path_caves" ] && startup_game_process_exists "$server_log_path_caves"; then
			echo -e "\e[1;31m地下 DST 进程仍存在且未得到安全关闭确认，已保留现场。\e[0m"
			close_failed=1
		fi
		if [ "$close_failed" -ne 0 ]; then
			log_with_timestamp "进程 $cluster_name 关闭未得到安全确认，未继续强制终止。"
			return 1
		fi
		echo -e "\r\e[92m进程 $cluster_name 已关闭!!!                   \e[0m "
		return 0
	else
		echo -e "\e[1;31m未找到这个存档 \e[0m"
		return 1
	fi
}

# 关闭服务器解耦部分
close_server_select() {
	local process_name_close=$1
	local world_close_flag=$2
	local close_flag=$3
	local check_player=$4
	local server_log_path_close=$5
	local player_flag="false"
	local baseline_lines=0
	local baseline_hash=""
	local wait_seconds=${SHUTDOWN_WAIT_SECONDS:-60}
	local grace_seconds=${SHUTDOWN_GRACE_SECONDS:-10}
	local elapsed=0
	local terminal_elapsed=0
	local serialized_seen=0
	local shutting_down_seen=0
	local shutdown_sent=0
	local delta=""
	local session_id
	local -a session_ids=()

	if [ "$check_player" == "-NOBODY" ]; then
		get_playerList "$cluster_name"
		if [ "$have_player" != "false" ]; then
			player_flag="true"
		fi
	fi
	if [[ "$player_flag" != "false" ]] && [ "$close_flag" != "" ] && [ "$close_flag" != "-close" ]; then
		echo "由于设置了仅在无人时更新,所以暂时不更新！"
		return 2
	fi

	if ! [[ "$wait_seconds" =~ ^[1-9][0-9]*$ ]]; then
		wait_seconds=60
	fi
	if ! [[ "$grace_seconds" =~ ^[0-9]+$ ]]; then
		grace_seconds=10
	fi
	if [ -z "$server_log_path_close" ]; then
		if [ "$world_close_flag" == "地上" ]; then
			server_log_path_close=$server_log_path_master
		else
			server_log_path_close=$server_log_path_caves
		fi
	fi
	if [ -n "$server_log_path_close" ] && [ -f "$server_log_path_close" ]; then
		baseline_lines=$(wc -l <"$server_log_path_close")
		if [ "$baseline_lines" -gt 0 ]; then
			baseline_hash=$(head -n "$baseline_lines" "$server_log_path_close" | sha256sum | awk '{print $1}')
		fi
	fi

	mapfile -t session_ids < <(screen_session_ids_exact "$process_name_close")
	if [ ${#session_ids[@]} -eq 0 ]; then
		return 0
	fi
	if [ "$close_flag" == "-close" ]; then
		c_announce="服务器即将关闭，给您带来的不便还请谅解！！！"
	elif [ "$close_flag" == "" ]; then
		c_announce="服务器需要重启,给您带来的不便还请谅解！！！"
	fi

	for session_id in "${session_ids[@]}"; do
		if ! screen -S "$session_id" -Q select . >/dev/null 2>&1; then
			continue
		fi
		for _ in {1..3}; do
			if ! screen -S "$session_id" -Q select . >/dev/null 2>&1; then
				break
			fi
			screen -S "$session_id" -p 0 -X stuff "c_announce(\"$c_announce\") $(printf \\r)" >/dev/null 2>&1 || break
			echo -en "\r$world_close_flag服务器正在发布公告.  "
			sleep 1.5
			echo -en "\r$world_close_flag服务器正在发布公告.. "
			sleep 1.5
			echo -en "\r$world_close_flag服务器正在发布公告..."
			sleep 1.5
		done
		if screen -S "$session_id" -Q select . >/dev/null 2>&1; then
			echo -e "\r\e[92m$world_close_flag服务器公告发布完毕!!!\e[0m"
			if screen -S "$session_id" -p 0 -X stuff "c_shutdown(true) $(printf \\r)" >/dev/null 2>&1; then
				shutdown_sent=1
			fi
			sleep 5
			if screen -S "$session_id" -Q select . >/dev/null 2>&1; then
				screen -S "$session_id" -p 0 -X stuff "c_shutdown(true) $(printf \\r)" >/dev/null 2>&1 || true
			fi
		fi
	done

	while [ "$elapsed" -lt "$wait_seconds" ]; do
		sleep 1
		elapsed=$((elapsed + 1))
		delta=$(shutdown_log_delta "$server_log_path_close" "$baseline_lines" "$baseline_hash")
		if printf '%s\n' "$delta" | grep --text -Fq 'Serializing world'; then
			serialized_seen=1
		fi
		if printf '%s\n' "$delta" | grep --text -Fq 'Shutting down'; then
			shutting_down_seen=1
		fi

		if ! screen_session_exists_exact "$process_name_close"; then
			if [ "$serialized_seen" -eq 1 ] && [ "$shutting_down_seen" -eq 1 ]; then
				echo -e "\r\e[92m$world_close_flag进程 $cluster_name 已保存并正常关闭!!!                   \e[0m"
				return 0
			fi
			echo -e "\r\e[1;31m$world_close_flag会话已退出，但本次关闭日志未同时出现保存和终止标志。\e[0m"
			log_with_timestamp "$world_close_flag会话退出，但无法从本次新增日志确认 Serializing world 和 Shutting down。"
			return 1
		fi

		if [ "$serialized_seen" -eq 1 ] && [ "$shutting_down_seen" -eq 1 ]; then
			terminal_elapsed=$((terminal_elapsed + 1))
			if [ "$terminal_elapsed" -ge "$grace_seconds" ]; then
				log_with_timestamp "$world_close_flag服务器已完成保存并进入 Shutting down，但会话仍挂起；清理精确匹配会话 $process_name_close。"
				if ! close_exact_screen_sessions "$process_name_close"; then
					log_with_timestamp "$world_close_flag精确 screen 会话清理命令执行失败。"
					return 1
				fi
				sleep 1
				if screen_session_exists_exact "$process_name_close"; then
					log_with_timestamp "$world_close_flag精确 screen 会话清理后仍存在，保留现场。"
					return 1
				fi
				echo -e "\r\e[92m$world_close_flag服务器已完成保存和终止日志，挂起会话已清理。\e[0m"
				return 0
			fi
		fi
		echo -en "\r$world_close_flag进程 $cluster_name 正在关闭，已等待 ${elapsed}/${wait_seconds} 秒..."
	done

	echo -e "\r\e[1;31m$world_close_flag服务器未在等待时间内产生本次完整的保存和终止标志，未强制结束，已保留现场。\e[0m"
	if [ "$shutdown_sent" -eq 0 ]; then
		log_with_timestamp "$world_close_flag关闭命令未成功发送，未强制结束会话。"
	else
		log_with_timestamp "$world_close_flag本次关闭未同时确认 Serializing world 和 Shutting down，未强制结束会话。"
	fi
	return 1
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
	fi
}

#检查游戏更新情况
checkupdate() {
    cluster_name=$1
    get_path_games "$cluster_name"
    get_path_script_files "$cluster_name"
    DST_now=$(date +%Y年%m月%d日%H:%M)

    local local_version=""
    local local_buildid=""
    local new_version=""
    local new_buildid=""
    local update_version_flag="BETA"
	local remote_version=""
	local update_required=false

    if [ "$buildid_version_flag" == "public" ]; then
        update_version_flag="DEFAULT"
    fi

    local_version=$(get_game_version_value "$gamesPath")
    local_buildid=$(get_game_buildid_value "$gamesPath")

    update_game_and_restart_if_changed() {
        local old_version=$1
        local old_buildid=$2
        local update_flag=$3

        if [ "$update_flag" == "DEFAULT" ]; then
            echo -e "\e[33m${DST_now}:更新正式版游戏本体中。。。 \e[0m"
            if ! update_game DEFAULT; then
                echo -e "\e[1;31m${DST_now}:SteamCMD 更新正式版游戏本体失败，跳过重启\e[0m"
                return 1
            fi
        else
            echo -e "\e[33m${DST_now}:更新测试版游戏本体中。。。 \e[0m"
            if ! update_game BETA; then
                echo -e "\e[1;31m${DST_now}:SteamCMD 更新测试版游戏本体失败，跳过重启\e[0m"
                return 1
            fi
        fi

        new_version=$(get_game_version_value "$gamesPath")
        new_buildid=$(get_game_buildid_value "$gamesPath")

        echo -e "\e[92m更新前版本号: ${old_version:-未知}\e[0m"
        echo -e "\e[92m更新后版本号: ${new_version:-未知}\e[0m"
        echo -e "\e[92m更新前buildid: ${old_buildid:-未知}\e[0m"
        echo -e "\e[92m更新后buildid: ${new_buildid:-未知}\e[0m"

        if [ "$new_version" != "$old_version" ] || [ "$new_buildid" != "$old_buildid" ]; then
            auto_update_anyway=$(grep --text auto_update_anyway "$script_files_path/config.txt" | awk '{print $3}')
            c_announce="由于游戏本体有更新，服务器即将关闭，给您带来的不便还请谅解！！！"
            if [ "$auto_update_anyway" == "true" ]; then
                restart_server "$cluster_name" -AUTO
            else
                restart_server "$cluster_name" -AUTO -NOBODY
            fi
        else
            echo -e "\e[92m${DST_now}:已执行SteamCMD同步，游戏版本号和buildid均未变化，不重启\e[0m"
        fi
    }

    # 清理旧的Steam用户数据
    echo "清理3天前的Steam用户数据..."
    clean_steam_userdata

	if ! [[ "$local_version" =~ ^[0-9]+$ ]]; then
		echo -e "\e[33m${DST_now}:未找到有效的version.txt，直接执行一次游戏更新以修复安装...\e[0m"
		update_required=true
    else
		echo -e "\e[92m当前游戏服务端版本号: $local_version\e[0m"
        echo -e "\e[92m当前游戏服务端buildid: ${local_buildid:-未知}\e[0m"
    fi

	if [ "$update_required" != true ]; then
		echo "正在通过Klei官方构建列表检查 ${buildid_version_flag} 分支版本号（不执行app_update/validate）。。。"
		if ! remote_version=$(get_remote_game_version "$buildid_version_flag"); then
			echo -e "\e[33m${DST_now}:无法获取Klei官方最新版本号，本次跳过更新并等待下次检查。\e[0m"
			return 1
		fi
		echo -e "\e[92mKlei官方${buildid_version_flag}分支版本号: $remote_version\e[0m"
		if [ "$remote_version" == "$local_version" ]; then
			echo -e "\e[92m${DST_now}:游戏服务端没有更新!\e[0m"
			return 0
		fi
		if [ "$remote_version" -lt "$local_version" ]; then
			echo -e "\e[33m${DST_now}:本地版本号 $local_version 高于Klei官方记录 $remote_version，本次跳过更新以避免回退。\e[0m"
			return 1
		fi
		update_required=true
	fi

	if [ -n "$remote_version" ]; then
		echo " "
		echo -e "\e[31m${DST_now}:Klei官方版本号 $remote_version 高于本地版本号 $local_version，确认游戏服务端有更新! \e[0m"
		echo " "
	fi
	update_game_and_restart_if_changed "$local_version" "$local_buildid" "$update_version_flag"
}

# 检查游戏mod更新情况
checkmodupdate() {
    cluster_name=${1:?Usage: checkmodupdate [cluster_name]}
    DST_now=$(date +%Y年%m月%d日%H:%M)
    get_process_name "$cluster_name"
	get_path_server_log "$cluster_name"
	local active_log=""
	if [ -n "$server_log_path_master" ]; then
		active_log=$server_log_path_master
		STARTUP_SHARD_BY_LOG["$active_log"]="Master"
	elif [ -n "$server_log_path_caves" ]; then
		active_log=$server_log_path_caves
		STARTUP_SHARD_BY_LOG["$active_log"]="Caves"
	else
		echo -e "\e[33m${DST_now}: 未解析到服务器日志路径，跳过 Mod 更新检查。\e[0m"
		return 0
	fi
	if ! startup_game_process_exists "$active_log"; then
		echo -e "\e[33m${DST_now}: 服务器实际进程未运行，跳过 Mod 更新检查。\e[0m"
		return 0
	fi
	if ! startup_process_exists "$process_name_main"; then
		echo -e "\e[33m${DST_now}: DST 进程存在但 screen 会话不存在，无法安全发送 Mod 查询，跳过本次检查。\e[0m"
		return 0
	fi
    
    echo -e "\e[92m${DST_now}: 正在检查服务器mod是否有更新...\e[0m"
    
    local timestamp=$(date +%s%3N)
    
    if ! screen -S "$process_name_main" -p 0 -X stuff "for k,v in pairs(KnownModIndex:GetModsToLoad()) do local modinfo = KnownModIndex:GetModInfo(v) print(string.format(\"modinfo $timestamp %s %s\", v, modinfo.version)) end$(printf \\r)"; then
		echo -e "\e[33m${DST_now}: Mod 查询命令发送失败，跳过本次检查。\e[0m"
		return 0
	fi
    sleep 1
    
    get_path_server_log "$cluster_name"
    
    local has_mods_update=false
    declare -A updated_mods
    declare -A current_mod_versions

    while read -r line; do
        if [[ $line =~ modinfo[[:space:]]$timestamp[[:space:]]workshop-([0-9]+)[[:space:]](.+)$ ]]; then
            local mod_id="${BASH_REMATCH[1]}"
            local current_version="${BASH_REMATCH[2]}"
            current_mod_versions["$mod_id"]="$current_version"
        fi
    done < <(grep --text "modinfo $timestamp" "$server_log_path_main")

    if [ "${#current_mod_versions[@]}" -eq 0 ]; then
        echo -e "\e[92m${DST_now}: 当前服务器没有启用 Workshop mod\e[0m"
        return 0
    fi

    local mod_info_tmp
    mod_info_tmp=$(mktemp -d)
    local parallel_limit=8
    local running=0
    for mod_id in "${!current_mod_versions[@]}"; do
        (
            get_mod_info "$mod_id"
            printf '%s\t%s\t%s\n' "$mod_id" "${mod_info_post[0]}" "${mod_info_post[1]}" > "$mod_info_tmp/$mod_id.tsv"
        ) &
        running=$((running + 1))
        if [ "$running" -ge "$parallel_limit" ]; then
            wait -n || true
            running=$((running - 1))
        fi
    done
    wait || true

    for mod_id in "${!current_mod_versions[@]}"; do
        local current_version="${current_mod_versions[$mod_id]}"
        local mod_name="null"
        local online_version="null"
        if [ -s "$mod_info_tmp/$mod_id.tsv" ]; then
            IFS=$'\t' read -r _ mod_name online_version < "$mod_info_tmp/$mod_id.tsv"
        fi

        # 转换为小写进行比较
        current_version_lower=$(echo "$current_version" | tr '[:upper:]' '[:lower:]')
        online_version_lower=$(echo "$online_version" | tr '[:upper:]' '[:lower:]')

        if [ -n "$online_version_lower" ] && [ "$online_version_lower" != "null" ] && [ "$current_version_lower" != "$online_version_lower" ]; then
            log_with_timestamp "\e[33mMod [$mod_name] 有更新:"
            log_with_timestamp "当前版本: $current_version"
            log_with_timestamp "最新版本: $online_version\e[0m"
            has_mods_update=true
			updated_mods["$mod_id"]="$mod_name"
        else
            echo -e "\e[92mMod [$mod_name] [$mod_id] 已是最新版本 ($current_version)\e[0m"
        fi
    done
    rm -rf "$mod_info_tmp"
    
    if [ "$has_mods_update" = true ]; then
        echo -e "\e[31m${DST_now}: 发现mod更新!\e[0m"
        
        get_path_script_files "$cluster_name"
        auto_update_anyway=$(grep --text auto_update_anyway "$script_files_path/config.txt" | awk '{print $3}')
        
        # 定义日志文件路径
        log_file="$script_files_path/mod_update.log"

        # 记录更新的mod到配置文件
        local updated_mods_file="$script_files_path/last_updated_mods.txt"
        > "$updated_mods_file"  # 清空文件
        for mod_id in "${!updated_mods[@]}"; do
            echo "$mod_id" >> "$updated_mods_file"
        done

        if [ "$auto_update_anyway" == "true" ]; then
            echo "准备更新mod..."
            c_announce="由于mod有更新，服务器即将重启，给您带来的不便还请谅解！！！"
			if ! close_server "$cluster_name" -AUTO; then
				log_with_timestamp "Mod 更新已取消：服务器关闭未得到安全确认。"
				return 1
			fi

			# 服务器已关闭，删除旧版本 mod 文件
			for mod_id in "${!updated_mods[@]}"; do
				mod_name="${updated_mods[$mod_id]}"
				if [ -d "$HOME/DST/mods/workshop-$mod_id" ]; then
					log_with_timestamp "删除旧版本mod文件: workshop-$mod_id    $mod_name"
					rm -rf "$HOME/DST/mods/workshop-$mod_id"
				fi
				if workshop_mod_exists "$mod_id"; then
					log_with_timestamp "删除旧版本mod文件: $mod_id   $mod_name"
					remove_workshop_mod "$mod_id"
				fi
			done

			howtostart "$cluster_name" -AUTO "" -SKIP_MOD_CHECK
        else
            get_playerList "$cluster_name"
            if [ "$have_player" = false ]; then
                echo "服务器无玩家，准备更新mod..."
				c_announce="由于mod有更新，服务器即将重启，给您带来的不便还请谅解！！！"
				if ! close_server "$cluster_name" -AUTO; then
					log_with_timestamp "Mod 更新已取消：服务器关闭未得到安全确认。"
					return 1
				fi

				# 服务器已关闭，删除旧版本 mod 文件
				for mod_id in "${!updated_mods[@]}"; do
					mod_name="${updated_mods[$mod_id]}"
					if [ -d "$HOME/DST/mods/workshop-$mod_id" ]; then
						log_with_timestamp "删除旧版本mod文件: workshop-$mod_id   $mod_name"
						rm -rf "$HOME/DST/mods/workshop-$mod_id"
					fi
					if workshop_mod_exists "$mod_id"; then
						log_with_timestamp "删除旧版本mod文件: $mod_id   $mod_name"
						remove_workshop_mod "$mod_id"
					fi
				done

				howtostart "$cluster_name" -AUTO "" -SKIP_MOD_CHECK
            else
                echo "服务器有玩家在线，暂不更新mod"
            fi
        fi
    else
        echo -e "\e[92m${DST_now}: 所有mod均为最新版本\e[0m"
    fi
}

log_with_timestamp() {
	# 获取脚本文件所在路径
	get_path_script_files "$cluster_name"
	# 定义日志文件路径
	log_file="$script_files_path/mod_update.log"
	echo -e $1
    echo "$(date +%Y-%m-%d\ %H:%M:%S) $1" >> "$log_file"
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
		startup_shard_check="Master"
	else
		script_name="start_server_caves.sh"
		process_name_check=$process_name_caves
		log_path=$server_log_path_caves
		startup_shard_check="Caves"
	fi
	if [ -z "$log_path" ] || [ -z "$process_name_check" ]; then
		log_with_timestamp "$world_check_flag服务器路径或进程名解析失败，跳过自动巡检。"
		return 0
	fi
	STARTUP_SHARD_BY_LOG["$log_path"]=$startup_shard_check

	local process_count game_running=0
	process_count=$(screen -ls | grep --text -c "\<$process_name_check\>")
	if startup_game_process_exists "$log_path"; then
		game_running=1
	fi
	if [ "$game_running" -eq 1 ]; then
		if [ "$process_count" -gt 1 ]; then
			log_with_timestamp "$world_check_flag服务器检测到 $process_count 个同名会话，请检查并清理重复进程。"
		fi
		if [ "$process_count" -eq 0 ]; then
			log_with_timestamp "$world_check_flag实际 DST 进程仍在运行，但 screen 会话不存在；为避免重复进程，本次不自动启动。"
		fi
		if [[ "$flag_checkprocess" != "no_output" ]]; then
			echo "$world_check_flag服务器运行正常"
		fi
	else
		if [ "$process_count" -gt 0 ]; then
			log_with_timestamp "$world_check_flag检测到 screen 会话存在但实际 DST 进程已退出，清理残留会话。"
			screen -S "$process_name_check" -X quit >/dev/null 2>&1 || true
			sleep 1
		fi
		log_with_timestamp  "$world_check_flag服务器已经关闭,自动开启中。。。"
		STARTUP_REPAIR_USED=0
		start_server_select "$cluster_name" "$process_name_check" "$script_name" -AUTO
		start_server_check_select "$world_check_flag" "$log_path" -AUTO
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
		screen -S \"$process_name_main\" -p 0 -X stuff \"print(TheWorld.components.worldstate.data.cycles .. \\\" \$datatime\\\")\$(printf \\\r)\"
		sleep 1
		presentday=\$(grep --text \"$server_log_path_main\" -e \"\$datatime\" | cut -d \" \" -f2 | tail -n +2 )
	}
	backup()
	{
		# 自动备份
		backup_zip()
		{
			local backup_path=\$1
			local source_path=\$2
			local temp_backup_path="\${backup_path}.tmp.\$\$"
			local zip_status
			if command -v ionice >/dev/null 2>&1; then
				ionice -c 3 nice -n 19 zip -q -1 -r "\$temp_backup_path" "\$source_path" >> /dev/null 2>&1
				zip_status=\$?
			else
				nice -n 19 zip -q -1 -r "\$temp_backup_path" "\$source_path" >> /dev/null 2>&1
				zip_status=\$?
			fi
			if [ "\$zip_status" -eq 0 ]; then
				mv -f "\$temp_backup_path" "\$backup_path"
			else
				rm -f "\$temp_backup_path"
				return 1
			fi
		}
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
				backup_zip \"saves_bak/master_\${presentday}days.zip\" \"save/\"
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
				backup_zip \"saves_bak/caves_\${presentday}days.zip\" \"save/\"
			fi
			cd 	\"$script_files_path\" || exit
			if [ ! -d \"$script_files_path/Player\" ];then
				mkdir Player
			fi
			backup_zip \"$script_files_path/Player/playerlist_\${presentday}days.zip\" \"playerlist.txt\"
			echo \"\" > playerlist.txt
			ZipNum_Player=\$(find \"$script_files_path/Player\" -maxdepth 1 -name '*.zip' | wc -l)
			if [ \"\$ZipNum_Player\" -gt 21 ];then
				find \"$script_files_path/Player\" -maxdepth 1 -mtime +30 -name '*.zip' | awk '{if(NR -gt 10){print \$1}}' | xargs -r rm -f
			fi
		fi
	}
	timecheck=0
	maintenance_interval=750
	last_game_check=0
	last_mod_check=0
	game_check_interval_seconds=600
	mod_check_interval_seconds=60
	# 保持运行
	while :
			do
				script -checkprocess
				get_daysInfo		
				echo \"当前服务器天数:\$presentday\"		
				timecheck=\$(( timecheck%maintenance_interval ))
				current_time=\$(date +%s)
				if script -get_playerList; then
					backup
				else
					echo \"检测到玩家在线，跳过本次自动备份\"
				fi
				if [ \$(( current_time - last_game_check )) -ge \$game_check_interval_seconds ]; then
					script -checkupdate
					last_game_check=\$(date +%s)
				fi
				if [ \$(( current_time - last_mod_check )) -ge \$mod_check_interval_seconds ]; then
					script -checkmodupdate
					last_mod_check=\$(date +%s)
				fi
				((timecheck++))
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
		screen -S "$process_name_main" -p 0 -X stuff "for i, v in ipairs(TheNet:GetClientTable()) do  if (i~=1) then print(string.format(\"playerlist %s [%d] %s %s %s\", $allplayerslist, i-1 , v.userid, v.name, v.prefab )) end end $(printf \\r)"
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
	screen -S "$process_name_main" -p 0 -X stuff "print(TheWorld.components.worldstate.data.cycles ..  \" ""$datatime"" \")$(printf \\r)"
	sleep 1
	get_path_server_log "$cluster_name"
	presentday=$(grep --text "$server_log_path_main" -e "$datatime" | cut -d " " -f2 | tail -n +2)
}

# 获取怪物信息
getmonster() {
	if [[ $(screen -ls | grep --text -c "\<$process_name_master\>") -gt 0 ]]; then
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"walrus_camp\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"bishop\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"knight\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"rook\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"tallbirdnest\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"mound\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"houndmound\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"tentacle\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"reeds\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"pigtorch\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"gravestone\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"spiderden\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"spiderden_2\")$(printf \\r)"
		screen -S "$process_name_master" -p 0 -X stuff "c_countprefabs(\"spiderden_3\")$(printf \\r)"
		sleep 1
		get_path_server_log "$cluster_name"
		walrus_camp_master=$(grep --text "$server_log_path_master" -e "walrus_camps in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		reeds_master=$(grep --text "$server_log_path_master" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tentacle_master=$(grep --text "$server_log_path_master" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tallbirdnest_master=$(grep --text "$server_log_path_master" -e "tallbirdnests in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		houndmound_master=$(grep --text "$server_log_path_master" -e "houndmounds in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		mound_master=$(grep --text "$server_log_path_master" -e "mounds in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		gravestone_master=$(grep --text "$server_log_path_master" -e "gravestones in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		spiderden_1_master=$(grep --text "$server_log_path_master" -e "spiderdens in the world." | awk '{print $4}' | tail -n 1)
		spiderden_2_master=$(grep --text "$server_log_path_master" -e "spiderden_2s in the world." | awk '{print $4}' | tail -n 1)
		spiderden_3_master=$(grep --text "$server_log_path_master" -e "spiderden_3s in the world." | awk '{print $4}' | tail -n 1)

		# 如果某个变量无法解析出数值，则将其视为零
		if ! [[ "$spiderden_1_master" =~ ^[0-9]+$ ]]; then spiderden_1_master=0; fi
		if ! [[ "$spiderden_2_master" =~ ^[0-9]+$ ]]; then spiderden_2_master=0; fi
		if ! [[ "$spiderden_3_master" =~ ^[0-9]+$ ]]; then spiderden_3_master=0; fi

		spiderden_master=$((spiderden_1_master + spiderden_2_master + spiderden_3_master))
		mudi_master=$((mound_master + gravestone_master))
		echo
	fi
	if [[ $(screen -ls | grep --text -c "\<$process_name_caves\>") -gt 0 ]]; then
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"walrus_camp\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"bishop\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"knight\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"rook\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"tallbirdnest\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"mound\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"houndmound\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"tentacle\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"reeds\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"pigtorch\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"gravestone\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"spiderden\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"spiderden_2\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"spiderden_3\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"bishop_nightmare\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"rook_nightmare\")$(printf \\r)"
		screen -S "$process_name_caves" -p 0 -X stuff "c_countprefabs(\"knight_nightmare\")$(printf \\r)"
		sleep 1
		get_path_server_log "$cluster_name"
		reeds_caves=$(grep --text "$server_log_path_caves" -e "reedss in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		tentacle_caves=$(grep --text "$server_log_path_caves" -e "tentacles in the world." | cut -d ':' -f4 | tail -n 1 | sed 's/[^0-9\]//g')
		spiderden_1_caves=$(grep --text "$server_log_path_caves" -e "spiderdens in the world." | awk '{print $4}' | tail -n 1)
		spiderden_2_caves=$(grep --text "$server_log_path_caves" -e "spiderden_2s in the world." | awk '{print $4}' | tail -n 1)
		spiderden_3_caves=$(grep --text "$server_log_path_caves" -e "spiderden_3s in the world." | awk '{print $4}' | tail -n 1)

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
	screen -S "$process_name_main" -p 0 -X stuff "print(\"\" .. TheWorld.net.components.seasons:GetDebugString() .. \" $datatime print\")$(printf \\r)"
	screen -S "$process_name_main" -p 0 -X stuff "print(\"\" .. TheWorld.components.worldstate.data.phase .. \" $datatime phase\")$(printf \\r)"
	screen -S "$process_name_main" -p 0 -X stuff "print(\"\" .. TheWorld.components.worldstate.data.moonphase .. \" $datatime moonphase\")$(printf \\r)"
	screen -S "$process_name_main" -p 0 -X stuff "print(TheWorld.components.worldstate.data.temperature .. \" $datatime temperature\")$(printf \\r)"
	screen -S "$process_name_main" -p 0 -X stuff "print(TheWorld.components.worldstate.data.cycles .. \" $datatime cycles\")$(printf \\r)"
	screen -S "$process_name_main" -p 0 -X stuff "print(\"$datatime:rain:\",TheWorld.components.worldstate.data.israining)$(printf \\r)"
	screen -S "$process_name_main" -p 0 -X stuff "print(\"$datatime:snow:\",TheWorld.components.worldstate.data.issnowing)$(printf \\r)"
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
		sudo apt-get -y install wget curl ca-certificates tar

		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libc6-i386
		sudo dpkg --add-architecture i386

		sudo apt-get -y update
		sudo apt-get -y install libcurl3-gnutls:i386 || sudo apt-get -y install libcurl4-gnutls-dev:i386 || true
		sudo apt-get -y install lib32gcc-s1 || sudo apt-get -y install lib32gcc1

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
		sudo yum -y install wget curl tar

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
		sudo apt-get -y install wget curl ca-certificates tar

		sudo apt-get -y install libstdc++6
		sudo apt-get -y install lib32stdc++6
		sudo apt-get -y install libc6-i386
		sudo dpkg --add-architecture i386

		sudo apt-get -y update
		sudo apt-get -y install libcurl3-gnutls:i386 || sudo apt-get -y install libcurl4-gnutls-dev:i386 || true
		sudo apt-get -y install lib32gcc-s1 || sudo apt-get -y install lib32gcc1

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
	check_the_library curl
	if [ -d "./dst" ]; then
		echo "新脚本的目录结构已更改，可能需要重新下载游戏本体，请稍后。。。"
		mv dst/ DST/
	fi
	if [ -d "./dst_beta" ]; then
		mv dst_beta/ DST_BETA/
	fi
	if [ ! -d "$DST_DEFAULT_PATH" ] || [ ! -d "$DST_SAVE_PATH" ] || ! steamcmd_available; then
		PreLibrary
		mkdir -p "$DST_DEFAULT_PATH" "$HOME/.klei" "$DST_SAVE_PATH"
		if ! ensure_steamcmd; then
			exit 1
		fi
	fi
	# 下载游戏本体
	if [ ! -f "$DST_DEFAULT_PATH/version.txt" ]; then
		echo "正在下载饥荒游戏本体！！！"
		run_steamcmd +force_install_dir "$DST_DEFAULT_PATH" +login anonymous +app_update 343050 validate +quit
	fi
	# if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
	# 	echo "正在下载饥荒测试版游戏本体！！！"
	# 	run_steamcmd +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
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
			mkdir -p "$DST_BETA_PATH"
		fi
		if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
			echo "正在下载饥荒测试版游戏本体！！！"
			run_steamcmd +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
		fi
		sed -i "1s/${game_version_now}/测试版32位/g" "$script_files_path/config.txt"
	elif [ "$game_version" == "4" ]; then
		echo "更改该存档服务端版本为测试版64位!"
		if [ ! -d "./DST_BETA" ]; then
			mkdir -p "$DST_BETA_PATH"
		fi
		if [ ! -f "$DST_BETA_PATH/version.txt" ]; then
			echo "正在下载饥荒测试版游戏本体！！！"
			run_steamcmd +force_install_dir "$DST_BETA_PATH" +login anonymous +app_update 343050 -beta $BETA_TOKEN validate +quit
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
	local git_url
	local clone_succeeded=false
	local git_urls=()
	if [ -n "$DST_SCRIPT_GIT_URL" ]; then
		git_urls+=("$DST_SCRIPT_GIT_URL")
	fi
	git_urls+=(
		"$DST_SCRIPT_OFFICIAL_GIT_URL"
		"https://ghfast.top/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git"
		"https://gh-proxy.com/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git"
		"https://ghproxy.net/https://github.com/ChengTu-Lazy/Linux_DST_SCRIPT.git"
	)

	if [ -d "$HOME/clone_tamp" ]; then
		rm -rf "$HOME/clone_tamp"
		mkdir "$HOME/clone_tamp"
	else
		mkdir "$HOME/clone_tamp"
	fi
	clear
	cd "$HOME/clone_tamp" || exit
	for git_url in "${git_urls[@]}"; do
		echo "正在从 ${git_url} 获取最新版脚本..."
		rm -rf "$HOME/clone_tamp/Linux_DST_SCRIPT"
		if command -v timeout >/dev/null 2>&1; then
			timeout 45 git clone --depth 1 "$git_url" Linux_DST_SCRIPT
		else
			git clone --depth 1 "$git_url" Linux_DST_SCRIPT
		fi
		if [ $? -eq 0 ]; then
			if bash -n "$HOME/clone_tamp/Linux_DST_SCRIPT/DST_SCRIPT.sh"; then
				clone_succeeded=true
				break
			fi
			echo -e "\e[33m当前下载源中的脚本未通过语法检查，正在尝试下一个地址...\e[0m"
		fi
		echo -e "\e[33m当前下载源不可用，正在尝试下一个地址...\e[0m"
	done
	if [ "$clone_succeeded" != true ]; then
		echo -e "\e[1;31m所有内置下载源均不可用，请检查网络，或通过 DST_SCRIPT_GIT_URL 指定其他镜像。\e[0m"
		cd "$script_path" || exit
		rm -rf "$HOME/clone_tamp"
		return 1
	fi
	local update_temp
	update_temp=$(mktemp "$script_path/.${SCRIPT_NAME}.update.XXXXXX") || {
		echo -e "\e[1;31m无法在脚本目录创建更新临时文件，本次更新已取消。\e[0m"
		cd "$script_path" || exit
		rm -rf "$HOME/clone_tamp"
		return 1
	}
	if ! install -m 755 "$HOME/clone_tamp/Linux_DST_SCRIPT/DST_SCRIPT.sh" "$update_temp" || ! bash -n "$update_temp"; then
		echo -e "\e[1;31m新脚本写入或语法校验失败，原脚本保持不变。\e[0m"
		rm -f "$update_temp"
		cd "$script_path" || exit
		rm -rf "$HOME/clone_tamp"
		return 1
	fi
	if ! mv -f "$update_temp" "$script_path/$SCRIPT_NAME"; then
		echo -e "\e[1;31m替换脚本失败，原脚本保持不变。\e[0m"
		rm -f "$update_temp"
		cd "$script_path" || exit
		rm -rf "$HOME/clone_tamp"
		return 1
	fi
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

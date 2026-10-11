#!/bin/bash

set -o pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script_under_test="$repo_dir/DST_SCRIPT.sh"
test_root=$(mktemp -d)
result_file="$test_root/results"
: >"$result_file"

cleanup() {
	rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
	echo "[PASS] $1"
	echo PASS >>"$result_file"
}

fail() {
	echo "[FAIL] $1"
	echo FAIL >>"$result_file"
}

assert_contains() {
	local file=$1
	local expected=$2
	local name=$3
	if grep -Fq -- "$expected" "$file"; then
		pass "$name"
	else
		fail "$name"
		echo "  未找到: $expected"
	fi
}

assert_not_contains() {
	local file=$1
	local unexpected=$2
	local name=$3
	if grep -Fq -- "$unexpected" "$file"; then
		fail "$name"
		echo "  意外找到: $unexpected"
	else
		pass "$name"
	fi
}

source "$script_under_test" __test__

test_generated_start_script() (
	local sandbox="$test_root/start-script"
	mkdir -p "$sandbox/scripts" "$sandbox/game/steamapps" "$sandbox/bin" "$sandbox/saves/fixture/Master"
	echo '"buildid" "123456"' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	: >"$sandbox/saves/fixture/Master/server_log.txt"
	cat >"$sandbox/bin/dontstarve_dedicated_server_nullrenderer" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_GAME_ARGS"
EOF
	chmod +x "$sandbox/bin/dontstarve_dedicated_server_nullrenderer"

	get_path_games() { gamesPath="$sandbox/game"; }
	get_path_dontstarve_dedicated_server_nullrenderer() {
		dontstarve_dedicated_server_nullrenderer_path="$sandbox/bin"
		dontstarve_dedicated_server_nullrenderer="dontstarve_dedicated_server_nullrenderer"
		script_files_path="$sandbox/scripts"
	}
	get_workshop_path() { echo "$sandbox/workshop"; }
	get_path_server_log() {
		server_log_path_master="$sandbox/saves/fixture/Master/server_log.txt"
		server_log_path_caves=""
	}
	screen() { :; }

	start_server_select "fixture" "DST_Master fixture" "start_server_master.sh"
	local generated="$sandbox/scripts/start_server_master.sh"
	assert_contains "$generated" 'run_shared+=(-monitor_parent_process $$)' "生成脚本保留运行时父进程 PID"

	export TEST_GAME_ARGS="$sandbox/game-args.log"
	bash "$generated"
	assert_contains "$TEST_GAME_ARGS" '-monitor_parent_process' "游戏启动参数包含父进程监控选项"
	if awk '/^-monitor_parent_process$/{getline; if ($0 ~ /^[0-9]+$/) found=1} END{exit !found}' "$TEST_GAME_ARGS"; then
		pass "父进程监控参数展开为数字 PID"
	else
		fail "父进程监控参数展开为数字 PID"
	fi
)

test_start_check_logs_and_returns() (
	local sandbox="$test_root/start-check"
	mkdir -p "$sandbox"
	local log_file="$sandbox/server.log"
	local output="$sandbox/output.log"
	printf '%s\n' '[Workshop] OnDownloadPublishedFile' >"$log_file"
	cluster_name="fixture"
	DST_SAVE_PATH="$sandbox/saves"
	mkdir -p "$DST_SAVE_PATH/fixture/Master"
	get_path_server_log() { :; }
	get_process_name() {
		process_name_master="DST_Master fixture"
		process_name_caves="DST_Caves fixture"
	}
	screen() { printf '%s\n' '1.DST_Master fixture' '2.DST_Caves fixture'; }
	local sleep_calls=0
	sleep() {
		sleep_calls=$((sleep_calls + 1))
		if [ "$sleep_calls" -eq 4 ]; then
			printf '%s\n' 'FinishDownloadingServerMods Complete!' 'Sim paused' >>"$log_file"
		fi
	}
	close_server() { echo close >>"$sandbox/actions.log"; }
	start_server() { echo start >>"$sandbox/actions.log"; }
	log_with_timestamp() { echo "$1" >>"$output"; }

	start_server_check_select "地上" "$log_file" -AUTO >"$output" 2>&1
	assert_contains "$output" 'mod正在下载中' "Workshop 字面量日志能进入下载分支"
	assert_contains "$output" '服务器开启成功' "启动检查能从下载状态进入成功状态"
	assert_not_contains "$output" 'integer expression expected' "缺省超时参数不再产生整数错误"
)

test_restart_branches_return() (
	local sandbox="$test_root/restart-branches"
	mkdir -p "$sandbox/saves/fixture/Master"
	cluster_name="fixture"
	DST_SAVE_PATH="$sandbox/saves"
	get_path_server_log() { :; }
	get_process_name() { process_name_master="DST_Master fixture"; process_name_caves="DST_Caves fixture"; }
	screen() { printf '%s\n' '1.DST_Master fixture'; }
	sleep() { :; }
	log_with_timestamp() { :; }
	close_server() { echo close >>"$sandbox/actions.log"; }
	howtostart() { echo start >>"$sandbox/actions.log"; check_flag=1; }

	printf '%s\n' 'Your Server Will Not Start !!!' >"$sandbox/token.log"
	start_server_check_select "地上" "$sandbox/token.log" -AUTO 1 9999999999 >/dev/null 2>&1
	if [ "$(grep -c '^close$' "$sandbox/actions.log")" -eq 1 ] && [ "$(grep -c '^start$' "$sandbox/actions.log")" -eq 0 ]; then
		pass "令牌错误分支关闭后不自动重启"
	else
		fail "令牌错误分支关闭后不自动重启"
	fi

	: >"$sandbox/actions.log"
	printf '%s\n' 'Failed to send shard broadcast message' >"$sandbox/network.log"
	start_server_check_select "地上" "$sandbox/network.log" -AUTO 1 9999999999 >/dev/null 2>&1
	if [ "$(grep -c '^close$' "$sandbox/actions.log")" -eq 1 ] && [ "$(grep -c '^start$' "$sandbox/actions.log")" -eq 1 ]; then
		pass "网络错误分支只执行一次重启后返回"
	else
		fail "网络错误分支只执行一次重启后返回"
	fi
)

test_mod_restore_and_replace() (
	local sandbox="$test_root/mod-update"
	export HOME="$sandbox/home"
	mkdir -p "$HOME/DST/mods/workshop-123"
	echo old >"$HOME/DST/mods/workshop-123/old.txt"
	mod_info_post=(Fixture 1.0 unused)
	wget() {
		local output
		while [ $# -gt 0 ]; do
			if [ "$1" = "-O" ]; then output=$2; shift 2; else shift; fi
		done
		: >"$output"
	}
	unzip() {
		if [ "$1" = "-tq" ]; then return 0; fi
		return 1
	}
	local output="$sandbox/failure.log"
	if download_mod_by_http fixture 123 >"$output" 2>&1; then
		fail "Mod 解压失败返回非零"
	else
		pass "Mod 解压失败返回非零"
	fi
	assert_contains "$HOME/DST/mods/workshop-123/old.txt" old "Mod 解压失败后恢复旧版本"
	assert_contains "$output" '已恢复旧 Mod' "Mod 恢复路径输出明确日志"

	unzip() {
		if [ "$1" = "-tq" ]; then return 0; fi
		local destination="${@: -1}"
		mkdir -p "$destination"
		echo new >"$destination/new.txt"
	}
	if download_mod_by_http fixture 123 >"$sandbox/success.log" 2>&1; then
		pass "Mod 解压成功返回零"
	else
		fail "Mod 解压成功返回零"
	fi
	assert_contains "$HOME/DST/mods/workshop-123/new.txt" new "Mod 成功更新写入新版本"
	if [ ! -e "$HOME/DST/mods/workshop-123/old.txt" ]; then
		pass "Mod 成功更新后移除旧版本内容"
	else
		fail "Mod 成功更新后移除旧版本内容"
	fi
)

test_duplicate_screen_detection() (
	local sandbox="$test_root/process-check"
	mkdir -p "$sandbox"
	: >"$sandbox/server.log"
	get_cluster_main() { master_saves_path="$sandbox/master"; caves_saves_path="$sandbox/caves"; }
	get_path_server_log() {
		server_log_path_main="$sandbox/server.log"
		server_log_path_master="$sandbox/server.log"
		server_log_path_caves="$sandbox/server.log"
	}
	get_process_name() {
		process_name_master="DST_Master fixture"
		process_name_caves="DST_Caves fixture"
	}
	screen() { printf '%s\n' '1.DST_Master fixture' '2.DST_Master fixture'; }
	log_with_timestamp() { echo "$1"; }
	start_server_select() { echo started >>"$sandbox/actions.log"; }
	start_server_check_select() { echo checked >>"$sandbox/actions.log"; }
	startup_game_process_exists() { return 0; }
	get_playerList() { have_player=true; }

	checkprocess_select fixture 地上 normal >"$sandbox/output.log" 2>&1
	assert_contains "$sandbox/output.log" '检测到 2 个同名会话' "重复 screen 会话输出告警"
	if [ ! -e "$sandbox/actions.log" ]; then
		pass "重复 screen 会话不会再次启动服务器"
	else
		fail "重复 screen 会话不会再次启动服务器"
	fi
)

test_startup_mod_check() (
	local sandbox="$test_root/startup-mod-check"
	mkdir -p "$sandbox"
	cluster_name="fixture"
	local actions="$sandbox/actions.log"

	get_cluster_flag() { cluster_flag=2; }
	addmod_by_http_or_steamcmd() { echo addmod >>"$actions"; }
	get_process_name() { process_name_master="DST_Master fixture"; }
	start_server_select() { echo start >>"$actions"; }
	start_server_check() { check_flag=1; echo "ready:${2:-manual}" >>"$actions"; }
	checkmodupdate() { echo mod-check >>"$actions"; }
	auto_update() { echo auto-update >>"$actions"; }

	howtostart fixture
	if [ "$(tr '\n' ' ' <"$actions")" = "addmod start ready:manual mod-check auto-update " ]; then
		pass "服务器启动成功后执行一次Mod检查"
	else
		fail "服务器启动成功后执行一次Mod检查"
	fi

	: >"$actions"
	howtostart fixture -AUTO "" -SKIP_MOD_CHECK
	assert_not_contains "$actions" mod-check "Mod更新重启路径跳过重复启动检查"
	assert_contains "$actions" 'ready:-AUTO' "自动启动标志传递到完整启动检查"
)

test_repair_does_not_leak_asset_variable() (
	local sandbox="$test_root/repair-scope"
	local backup_root="$sandbox/backup"
	local target="$sandbox/workshop/content/322330/222"
	mkdir -p "$target" "$backup_root"
	printf '%s\n' old >"$target/modmain.lua"
	printf '%s\n' old >"$target/modinfo.lua"
	asset=sentinel
	get_workshop_path() { echo "$sandbox/workshop"; }
	workshop_mod_existing_dir() {
		[ -d "$target" ] && echo "$target"
	}
	run_steamcmd() {
		mkdir -p "$target/images"
		printf '%s\n' new >"$target/modmain.lua"
		printf '%s\n' new >"$target/modinfo.lua"
		printf '%s\n' data >"$target/images/example.xml"
	}
	log_with_timestamp() { :; }

	if repair_one_workshop_mod 222 images/example.xml "$backup_root"; then
		pass "事务式 Mod 修复夹具执行成功"
	else
		fail "事务式 Mod 修复夹具执行成功"
	fi
	if [ "$asset" = sentinel ]; then
		pass "Mod 资源校验循环不泄漏 asset 变量"
	else
		fail "Mod 资源校验循环不泄漏 asset 变量"
	fi
)

test_generic_lua_traceback_detection() (
	local sandbox="$test_root/lua-traceback"
	local output="$sandbox/output.log"
	local delta ids assets
	mkdir -p "$sandbox"
	delta=$(cat <<'EOF'
[00:00:14]: ModIndex:GetModsToLoad inserting forcedmoddir, workshop-111
[00:00:14]: [string "scripts/util.lua"]:641: Could not find an asset matching images/example.xml in any of the search paths.
[00:00:14]: LUA ERROR stack traceback:
        =[C] in function 'assert'
        scripts/util.lua(641,1) in function 'resolvefilepath'
        ../mods/workshop-222/scripts/tool.lua(4,1) in function 'RegisterAsset'
        ../mods/workshop-222/modmain.lua(88,1) in main chunk
[00:00:14]: Shutting down
EOF
)

	if startup_delta_has_fatal "$delta"; then
		pass "通用 LUA traceback 被识别为启动致命错误"
	else
		fail "通用 LUA traceback 被识别为启动致命错误"
	fi

	ids=$(startup_delta_fault_mod_ids "$delta")
	if [ "$ids" = "workshop-222" ]; then
		pass "只从 traceback 错误块提取故障 Mod"
	else
		fail "只从 traceback 错误块提取故障 Mod"
		echo "  实际提取: $ids"
	fi

	assets=$(startup_delta_mod_assets "$delta" "workshop-222")
	if [ "$assets" = "images/example.xml" ]; then
		pass "缺失资源与唯一 traceback Mod 建立关联"
	else
		fail "缺失资源与唯一 traceback Mod 建立关联"
		echo "  实际提取: $assets"
	fi

	repair_one_workshop_mod() { echo "$1" >>"$output"; }
	log_with_timestamp() { echo "$1" >>"$output"; }
	local normal_delta='[00:00:10]: ModIndex:GetModsToLoad inserting forcedmoddir, workshop-111'
	if repair_startup_mods "$normal_delta" >/dev/null 2>&1; then
		fail "正常 ModIndex 日志不会触发自动替换"
	else
		pass "正常 ModIndex 日志不会触发自动替换"
	fi
	if [ ! -s "$output" ] || ! grep -Eq '^[0-9]+$' "$output"; then
		pass "正常 ModIndex 日志未调用 Mod 修复"
	else
		fail "正常 ModIndex 日志未调用 Mod 修复"
	fi
)

test_ambiguous_lua_traceback_is_not_repaired() (
	local sandbox="$test_root/ambiguous-traceback"
	local actions="$sandbox/actions.log"
	local delta
	mkdir -p "$sandbox"
	delta=$(cat <<'EOF'
[00:00:14]: Could not find an asset matching images/example.xml in any of the search paths.
[00:00:14]: LUA ERROR stack traceback:
        ../mods/workshop-222/scripts/tool.lua(4,1) in function 'RegisterAsset'
        ../mods/workshop-333/scripts/compat.lua(8,1) in function 'ApplyPatch'
        ../mods/workshop-222/modmain.lua(88,1) in main chunk
[00:00:14]: Shutting down
EOF
)

	repair_one_workshop_mod() { echo "$1" >>"$actions"; }
	log_with_timestamp() { echo "$1" >>"$actions"; }

	if startup_delta_has_ambiguous_traceback_mods "$delta"; then
		pass "同一 traceback 含多个 Mod 时识别为归属歧义"
	else
		fail "同一 traceback 含多个 Mod 时识别为归属歧义"
	fi
	if repair_startup_mods "$delta" >/dev/null 2>&1; then
		fail "归属歧义时拒绝自动修复"
	else
		pass "归属歧义时拒绝自动修复"
	fi
	if [ ! -e "$actions" ] || ! grep -Eq '^[0-9]+$' "$actions"; then
		pass "归属歧义时未替换任何 Mod"
	else
		fail "归属歧义时未替换任何 Mod"
	fi
)

test_startup_terminal_shard_cleanup() (
	local sandbox="$test_root/startup-terminal-cleanup"
	local actions="$sandbox/actions.log"
	local master_active=true
	mkdir -p "$sandbox"
	cluster_name=fixture
	cat >"$sandbox/master.log" <<'EOF'
[00:00:14]: Could not find an asset matching images/example.xml in any of the search paths.
[00:00:14]: LUA ERROR stack traceback:
        ../mods/workshop-222/modmain.lua(1,1) in main chunk
[00:00:15]: Shutting down
EOF
	cat >"$sandbox/caves.log" <<'EOF'
[00:00:14]: LUA ERROR stack traceback:
        ../mods/workshop-333/modmain.lua(1,1) in main chunk
[00:00:15]: Server is now ready
[00:00:16]: Shutting down
EOF
	get_process_name() {
		process_name_master="DST_Master fixture"
		process_name_caves="DST_Caves fixture"
	}
	get_path_server_log() {
		server_log_path_master="$sandbox/master.log"
		server_log_path_caves="$sandbox/caves.log"
	}
	startup_log_delta() { cat "$1"; }
	startup_game_process_exists() { return 1; }
	screen_session_exists_exact() { [ "$1" = "DST_Master fixture" ] && $master_active; }
	close_exact_screen_sessions() { echo "$1" >>"$actions"; master_active=false; }
	log_with_timestamp() { echo "$1" >>"$actions"; }
	sleep() { :; }

	if startup_stop_terminal_cluster_shards; then
		pass "只清理本次启动已确认 fatal 和 terminal 的分片"
	else
		fail "只清理本次启动已确认 fatal 和 terminal 的分片"
	fi
	assert_contains "$actions" 'DST_Master fixture' "启动失败分片使用精确会话名清理"
	assert_not_contains "$actions" 'DST_Caves fixture' "已出现 ready 标志的分片不按启动失败清理"
)

test_download_retry_boundary_and_propagation() (
	local sandbox="$test_root/download-boundary"
	local output="$sandbox/output.log"
	local attempts=0
	mkdir -p "$sandbox"
	MOD_DOWNLOAD_MAX_ATTEMPTS=2
	MOD_DOWNLOAD_MAX_SECONDS=300
	download_mod_by_steamcmd() { attempts=$((attempts + 1)); }
	find_workshop_modmain() { return 1; }
	log_with_timestamp() { echo "$1" >>"$output"; }
	sleep() { :; }

	if download_ensure_all_success 111 222; then
		fail "SteamCMD Mod 达到重试上限后返回失败"
	else
		pass "SteamCMD Mod 达到重试上限后返回失败"
	fi
	if [ "$attempts" -eq 2 ]; then
		pass "SteamCMD Mod 下载严格遵守最大尝试次数"
	else
		fail "SteamCMD Mod 下载严格遵守最大尝试次数"
		echo "  实际尝试: $attempts"
	fi

	attempts=0
	MOD_DOWNLOAD_MAX_ATTEMPTS=10
	MOD_DOWNLOAD_MAX_SECONDS=2
	echo 0 >"$sandbox/clock"
	date() { cat "$sandbox/clock"; }
	sleep() { echo 2 >"$sandbox/clock"; }
	if download_ensure_all_success 111; then
		fail "SteamCMD Mod 达到总时长边界后返回失败"
	else
		pass "SteamCMD Mod 达到总时长边界后返回失败"
	fi
	if [ "$attempts" -eq 1 ]; then
		pass "SteamCMD Mod 总时长边界阻止后续尝试"
	else
		fail "SteamCMD Mod 总时长边界阻止后续尝试"
	fi

	local actions="$sandbox/start-actions.log"
	get_cluster_flag() { cluster_flag=2; }
	addmod_by_http_or_steamcmd() { return 1; }
	get_process_name() { process_name_master="DST_Master fixture"; }
	start_server_select() { echo start >>"$actions"; }
	start_server_check() { echo check >>"$actions"; }
	check_flag=1
	if howtostart fixture >"$sandbox/start-output.log" 2>&1; then
		fail "Mod 下载失败时 howtostart 返回失败"
	else
		pass "Mod 下载失败时 howtostart 返回失败"
	fi
	if [ ! -e "$actions" ]; then
		pass "Mod 下载失败后不会启动服务器"
	else
		fail "Mod 下载失败后不会启动服务器"
	fi
)

test_shutdown_log_safety() (
	local sandbox="$test_root/shutdown-safety"
	local log_file="$sandbox/server.log"
	local actions="$sandbox/actions.log"
	local output="$sandbox/output.log"
	local process_name="DST_Master fixture"
	local active=true
	local shutdown_logged=false
	local emit_current_markers=true
	mkdir -p "$sandbox"
	printf '%s\n' '[00:00:01]: Serializing world: old-session' '[00:00:02]: Shutting down' >"$log_file"
	cluster_name=fixture
	SHUTDOWN_WAIT_SECONDS=2
	SHUTDOWN_GRACE_SECONDS=1
	sleep() { :; }
	log_with_timestamp() { echo "$1" >>"$output"; }
	screen() {
		if [ "$1" = "-ls" ]; then
			if $active; then
				printf '\t101.%s\t(08/05/26 20:55:12)\t(Detached)\n' "$process_name"
				printf '\t102.%s-extra\t(08/05/26 20:55:12)\t(Detached)\n' "$process_name"
			fi
			return 0
		fi
		if [ "$1" = "-S" ] && [ "$3" = "-Q" ]; then
			$active
			return
		fi
		if [ "$1" = "-S" ] && [ "$3" = "-X" ] && [ "$4" = "quit" ]; then
			echo "$*" >>"$actions"
			active=false
			return 0
		fi
		if [[ "$*" == *c_shutdown* ]] && $emit_current_markers && ! $shutdown_logged; then
			printf '%s\n' '[00:01:01]: Serializing world: current-session' '[00:01:02]: Shutting down' >>"$log_file"
			shutdown_logged=true
		fi
		return 0
	}

	if close_server_select "$process_name" "地上" "" "" "$log_file" >"$output" 2>&1; then
		pass "本次保存和关闭标志齐全时可清理挂起会话"
	else
		fail "本次保存和关闭标志齐全时可清理挂起会话"
	fi
	assert_contains "$actions" '-S 101 -X quit' "只终止精确匹配的挂起 screen 会话"

	active=true
	shutdown_logged=false
	emit_current_markers=false
	: >"$actions"
	: >"$output"
	printf '%s\n' '[00:00:01]: Serializing world: old-session' '[00:00:02]: Shutting down' >"$log_file"
	if close_server_select "$process_name" "地上" "" "" "$log_file" >"$output" 2>&1; then
		fail "只有历史关闭标志时返回失败并保留现场"
	else
		pass "只有历史关闭标志时返回失败并保留现场"
	fi
	if [ ! -s "$actions" ]; then
		pass "未发现本次保存和关闭标志时不强制终止"
	else
		fail "未发现本次保存和关闭标志时不强制终止"
	fi
)

test_close_server_propagates_failure() (
	local sandbox="$test_root/close-propagation"
	local calls="$sandbox/calls.log"
	mkdir -p "$sandbox/saves/fixture/Master"
	cluster_name=fixture
	DST_SAVE_PATH="$sandbox/saves"
	get_process_name() {
		process_name_master="DST_Master fixture"
		process_name_caves=""
	}
	get_path_server_log() {
		server_log_path_master="$sandbox/saves/fixture/Master/server_log.txt"
		server_log_path_caves=""
	}
	close_server_autoUpdate() { :; }
	screen_session_exists_exact() { [ "$1" = "DST_Master fixture" ]; }
	close_server_select() { echo call >>"$calls"; return 1; }

	if close_server fixture -AUTO >/dev/null 2>&1; then
		fail "分片关闭失败会传播到 close_server"
	else
		pass "分片关闭失败会传播到 close_server"
	fi
	if [ "$(wc -l <"$calls")" -eq 1 ]; then
		pass "分片关闭失败不会触发外层无限循环"
	else
		fail "分片关闭失败不会触发外层无限循环"
	fi
)

test_generated_backup_path() (
	local sandbox="$test_root/auto-update"
	export HOME="$sandbox/home"
	cluster_path="$sandbox/cluster"
	script_files_path="$cluster_path/ScriptFiles"
	master_saves_path="$cluster_path/Master"
	caves_saves_path="$cluster_path/Caves"
	server_log_path_main="$master_saves_path/server_log.txt"
	process_name_main="DST_Master fixture"
	process_name_AutoUpdate="AutoUpdate fixture"
	mkdir -p "$script_files_path" "$master_saves_path" "$caves_saves_path" "$HOME"
	echo 'is_auto_backup = true' >"$script_files_path/config.txt"
	screen() { :; }
	sleep() { :; }

	auto_update fixture >/dev/null 2>&1
	local generated="$script_files_path/auto_update.sh"
	if bash -n "$generated"; then
		pass "生成的自动维护脚本语法有效"
	else
		fail "生成的自动维护脚本语法有效"
	fi
	assert_contains "$generated" "find \"$script_files_path/Player\"" "玩家备份从真实 Player 目录统计"
	assert_contains "$generated" 'xargs -r rm -f' "玩家备份清理在空输入时不调用 rm"
	assert_contains "$generated" 'mod_check_interval_seconds=60' "自动维护脚本每分钟检查Mod"
	assert_contains "$generated" 'last_mod_check' "Mod检查使用独立计时器"
	assert_contains "$generated" 'game_check_interval_seconds=600' "自动维护脚本每十分钟检查游戏本体"
	assert_contains "$generated" 'script -rebuild_player_stats' "自动更新启动时重建历史玩家统计"
	assert_contains "$script_under_test" 'auto_update_anyway = true' "保留有人在线时允许强制更新的默认配置"
)

test_player_history_permissions() (
	local sandbox="$test_root/player-management"
	local save_root="$sandbox/saves"
	local cluster_root="$save_root/fixture"
	local scripts="$cluster_root/ScriptFiles"
	local archive_source="$sandbox/archive-source"
	local records_output="$sandbox/records.log"
	export HOME="$sandbox/home"
	DST_SAVE_PATH="$save_root"
	mkdir -p "$scripts/Player" "$archive_source" "$HOME"
	echo 'version = 正式版32位' >"$scripts/config.txt"
	cat >"$archive_source/playerlist.txt" <<'EOF'
-----------------------------------------------------
2026-08-06 10:00:00
[1] KU_history Old Name willow
EOF
	(
		cd "$archive_source" || exit 1
		zip -q "$scripts/Player/history.zip" playerlist.txt
	)
	cat >"$scripts/playerlist.txt" <<'EOF'
-----------------------------------------------------
2026-08-06 10:10:00
[1] KU_history New Name wendy
[2] KU_current Current Player wx78
EOF

	get_historical_player_records fixture >"$records_output"
	assert_contains "$records_output" $'KU_history\tNew Name\twendy' "当前玩家记录覆盖历史昵称和角色"
	assert_contains "$records_output" $'KU_current\tCurrent Player\twx78' "历史玩家列表合并当前玩家"

	send_player_console_command() { return 1; }
	if grant_player_admin fixture KU_history >/dev/null; then
		assert_contains "$cluster_root/adminlist.txt" 'KU_history' "玩家可加入管理员名单"
	else
		fail "玩家可加入管理员名单"
	fi
	if ban_player fixture KU_history >/dev/null; then
		assert_contains "$cluster_root/blocklist.txt" 'KU_history' "历史玩家可写入黑名单"
	else
		fail "历史玩家可写入黑名单"
	fi
	if unban_player fixture KU_history >/dev/null; then
		if grep -Fq -- 'KU_history' "$cluster_root/blocklist.txt"; then
			fail "玩家可从黑名单移除"
		else
			pass "玩家可从黑名单移除"
		fi
	else
		fail "玩家可从黑名单移除"
	fi
	if revoke_player_admin fixture KU_history >/dev/null; then
		if grep -Fq -- 'KU_history' "$cluster_root/adminlist.txt"; then
			fail "玩家可从管理员名单移除"
		else
			pass "玩家可从管理员名单移除"
		fi
	else
		fail "玩家可从管理员名单移除"
	fi
	local sent_command
	send_player_console_command() { sent_command=$1; return 0; }
	ban_player fixture KU_history >/dev/null
	if [ "$sent_command" = 'TheNet:Ban("KU_history")' ]; then
		pass "在线Ban使用DST控制台命令"
	else
		fail "在线Ban使用DST控制台命令"
	fi
	unban_player fixture KU_history >/dev/null
	if [ "$sent_command" = 'TheNet:Unban("KU_history")' ]; then
		pass "在线解除Ban使用DST控制台命令"
	else
		fail "在线解除Ban使用DST控制台命令"
	fi
)

test_player_statistics() (
	local sandbox="$test_root/player-statistics"
	local save_root="$sandbox/saves"
	local scripts="$save_root/fixture/ScriptFiles"
	local stats_file="$scripts/player_statistics.txt"
	local base_epoch
	local stats_line
	DST_SAVE_PATH="$save_root"
	mkdir -p "$scripts"
	echo 'version = 正式版32位' >"$scripts/config.txt"
	cat >"$scripts/playerlist.txt" <<'EOF'
-----------------------------------------------------
2026-08-06 10:00:00
[1] KU_stats Stats Player willow
-----------------------------------------------------
2026-08-06 10:00:10
[1] KU_stats Stats Player wendy
EOF

	if rebuild_player_statistics fixture; then
		stats_line=$(grep -F -- 'KU_stats' "$stats_file")
		if [ "$(printf '%s\n' "$stats_line" | awk -F '\t' '{print $6}')" = 2 ] && [ "$(printf '%s\n' "$stats_line" | awk -F '\t' '{print $7}')" = 10 ]; then
			pass "历史快照重建玩家采样和游玩时长"
		else
			fail "历史快照重建玩家采样和游玩时长"
			echo "  实际统计: $stats_line"
		fi
	else
		fail "历史快照重建玩家采样和游玩时长"
	fi

	base_epoch=$(date -d '2026-08-06 10:00:00' +%s)
	update_player_statistics_from_list '[1] KU_stats Stats Player wx78' fixture "$((base_epoch + 20))"
	stats_line=$(grep -F -- 'KU_stats' "$stats_file")
	if [ "$(printf '%s\n' "$stats_line" | awk -F '\t' '{print $6}')" = 3 ] && [ "$(printf '%s\n' "$stats_line" | awk -F '\t' '{print $7}')" = 20 ]; then
		pass "在线快照增量更新玩家游玩统计"
	else
		fail "在线快照增量更新玩家游玩统计"
		echo "  实际统计: $stats_line"
	fi
	show_player_statistics fixture >"$sandbox/output.log"
	assert_contains "$sandbox/output.log" $'玩家名\tUserID\t最近角色' "历史统计表头输出真实制表符"
	assert_not_contains "$sandbox/output.log" '\\tUserID' "历史统计表头不输出字面量反斜杠"
)

test_update_game_result_validation() (
	local sandbox="$test_root/game-update-result"
	local calls="$sandbox/calls.log"
	local steam_mode=success
	mkdir -p "$sandbox/game"
	export TMPDIR="$sandbox"
	DST_DEFAULT_PATH="$sandbox/game"

	run_steamcmd() {
		printf '%s\n' "$*" >>"$calls"
		case "$steam_mode" in
			success)
				printf "Success! App '343050' fully installed.\n"
				return 0
				;;
			missing_marker)
				printf 'ERROR! mock failure without success marker\n'
				return 0
				;;
			nonzero)
				printf 'mock steamcmd exited nonzero\n'
				return 7
				;;
		esac
	}

	if update_game DEFAULT >"$sandbox/success.log" 2>&1; then
		pass "SteamCMD退出码和固定成功标志齐全时更新成功"
	else
		fail "SteamCMD退出码和固定成功标志齐全时更新成功"
	fi
	assert_contains "$calls" '+app_update 343050 validate +quit' "真实游戏更新仍保留SteamCMD完整校验"

	steam_mode=missing_marker
	if update_game DEFAULT >"$sandbox/missing-marker.log" 2>&1; then
		fail "SteamCMD退出码为零但缺少成功标志时更新失败"
	else
		pass "SteamCMD退出码为零但缺少成功标志时更新失败"
	fi

	steam_mode=nonzero
	if update_game DEFAULT >"$sandbox/nonzero.log" 2>&1; then
		fail "SteamCMD非零退出时更新失败"
	else
		pass "SteamCMD非零退出时更新失败"
	fi
)

test_remote_game_version() (
	local sandbox="$test_root/remote-game-version"
	local calls="$sandbox/calls.log"
	local response_mode=success
	mkdir -p "$sandbox"
	: >"$calls"
	curl() {
		printf '%s\n' "$*" >>"$calls"
		case "$response_mode" in
			success)
				printf '%s\n' '{"release":["740256","740477"],"updatebeta":["735978","735984"]}'
				;;
			malformed)
				printf '%s\n' '{"release":[],"updatebeta":["invalid"]}'
				;;
			request_failure)
				return 7
				;;
		esac
	}

	if [ "$(get_remote_game_version public)" == "740477" ]; then
		pass "Klei构建列表解析正式版最新版本号"
	else
		fail "Klei构建列表解析正式版最新版本号"
	fi
	if [ "$(get_remote_game_version updatebeta)" == "735984" ]; then
		pass "Klei构建列表解析测试版最新版本号"
	else
		fail "Klei构建列表解析测试版最新版本号"
	fi
	assert_contains "$calls" 'https://s3.amazonaws.com/dstbuilds/builds.json' "版本查询使用Klei官方构建列表"

	response_mode=malformed
	if get_remote_game_version public >/dev/null 2>&1; then
		fail "Klei构建列表正式版数组为空时返回失败"
	else
		pass "Klei构建列表正式版数组为空时返回失败"
	fi
	if get_remote_game_version updatebeta >/dev/null 2>&1; then
		fail "Klei构建列表版本号无效时返回失败"
	else
		pass "Klei构建列表版本号无效时返回失败"
	fi

	response_mode=request_failure
	if get_remote_game_version public >/dev/null 2>&1; then
		fail "Klei构建列表请求失败时返回失败"
	else
		pass "Klei构建列表请求失败时返回失败"
	fi

	: >"$calls"
	if get_remote_game_version invalid >/dev/null 2>&1; then
		fail "未知Steam分支不会请求Klei构建列表"
	else
		pass "未知Steam分支不会请求Klei构建列表"
	fi
	if [ ! -s "$calls" ]; then
		pass "未知Steam分支未产生网络请求"
	else
		fail "未知Steam分支未产生网络请求"
	fi
)

test_game_update_precheck() (
	local sandbox="$test_root/game-update-precheck"
	local calls="$sandbox/calls.log"
	local output="$sandbox/output.log"
	mkdir -p "$sandbox/game/steamapps" "$sandbox/scripts"
	echo 740477 >"$sandbox/game/version.txt"
	echo '"buildid" "24080846"' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	echo 'auto_update_anyway = true' >"$sandbox/scripts/config.txt"
	: >"$calls"

	get_path_games() {
		gamesPath="$sandbox/game"
		buildid_version_flag=public
	}
	get_path_script_files() { script_files_path="$sandbox/scripts"; }
	clean_steam_userdata() { :; }
	get_remote_game_version() { echo "query:$1" >>"$calls"; printf '%s\n' 740477; }
	update_game() { echo "update:$1" >>"$calls"; }
	restart_server() { echo "restart:$*" >>"$calls"; }

	checkupdate fixture >"$output" 2>&1
	assert_contains "$output" '游戏服务端没有更新' "Klei官方版本与本地一致时直接结束检查"
	assert_contains "$calls" 'query:public' "正式版查询Klei release分支对应版本"
	assert_not_contains "$calls" 'update:' "正式版已是最新时不执行SteamCMD更新"

	: >"$calls"
	echo 740476 >"$sandbox/game/version.txt"
	get_remote_game_version() { echo "query:$1" >>"$calls"; printf '%s\n' 740477; }
	update_game() {
		echo "update:$1" >>"$calls"
		echo 740477 >"$sandbox/game/version.txt"
		echo '"buildid" "24080847"' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	}
	checkupdate fixture >"$output" 2>&1
	assert_contains "$output" 'Klei官方版本号 740477 高于本地版本号 740476' "手动降低version.txt后能确认正式版更新"
	assert_contains "$calls" 'update:DEFAULT' "远端版本号高于本地后才执行SteamCMD"
	assert_contains "$calls" 'restart:fixture -AUTO' "正式版实际更新后保留强制重启配置"

	: >"$calls"
	echo 740477 >"$sandbox/game/version.txt"
	echo '"buildid" "24080846"' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	get_remote_game_version() { echo "query:$1" >>"$calls"; return 1; }
	if checkupdate fixture >"$output" 2>&1; then
		fail "Klei构建列表查询失败时返回失败并等待重试"
	else
		pass "Klei构建列表查询失败时返回失败并等待重试"
	fi
	assert_not_contains "$calls" 'update:' "Klei构建列表查询失败不降级为完整游戏校验"

	: >"$calls"
	get_remote_game_version() { echo "query:$1" >>"$calls"; printf '%s\n' 740476; }
	if checkupdate fixture >"$output" 2>&1; then
		fail "官方版本低于本地时返回失败并保留现场"
	else
		pass "官方版本低于本地时返回失败并保留现场"
	fi
	assert_contains "$output" '本地版本号 740477 高于Klei官方记录 740476' "官方列表滞后时输出具体跳过原因"
	assert_not_contains "$calls" 'update:' "官方列表滞后时不执行完整游戏校验"

	: >"$calls"
	rm -f "$sandbox/game/version.txt"
	get_remote_game_version() { echo "query:$1" >>"$calls"; printf '%s\n' 740477; }
	update_game() {
		echo "update:$1" >>"$calls"
		echo 740477 >"$sandbox/game/version.txt"
	}
	checkupdate fixture >"$output" 2>&1
	assert_contains "$calls" 'update:DEFAULT' "version.txt缺失时执行一次SteamCMD修复安装"
	assert_not_contains "$calls" 'query:' "version.txt缺失时不发送远端版本查询"
	assert_not_contains "$output" '确认游戏服务端有更新' "version.txt缺失时不误报已确认存在更新"

	: >"$calls"
	echo 735983 >"$sandbox/game/version.txt"
	get_path_games() {
		gamesPath="$sandbox/game"
		buildid_version_flag=updatebeta
	}
	get_remote_game_version() { echo "query:$1" >>"$calls"; printf '%s\n' 735984; }
	update_game() {
		echo "update:$1" >>"$calls"
		echo 735984 >"$sandbox/game/version.txt"
		echo '"buildid" "24090000"' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	}
	checkupdate fixture >"$output" 2>&1
	assert_contains "$calls" 'query:updatebeta' "测试版查询Klei updatebeta分支最新版本"
	assert_contains "$calls" 'update:BETA' "测试版远端版本高于本地后执行更新"
)

test_game_update_restart_recovery() (
	local sandbox="$test_root/game-restart-recovery"
	local calls="$sandbox/calls.log"
	local pending="$sandbox/fixture/game_update_pending_restart"
	local restart_ok=false
	local players_online=false
	mkdir -p "$sandbox/game/steamapps" "$sandbox/fixture" "$sandbox/other"
	printf '100\n' >"$sandbox/game/version.txt"
	printf '"buildid" "1000"\n' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	printf '1000\n' >"$sandbox/fixture/cluster_game_buildid.txt"
	printf '1000\n' >"$sandbox/other/cluster_game_buildid.txt"
	printf 'auto_update_anyway = false\n' | tee "$sandbox/fixture/config.txt" >"$sandbox/other/config.txt"
	get_path_games() { gamesPath="$sandbox/game"; buildid_version_flag=public; }
	get_path_script_files() { script_files_path="$sandbox/$1"; }
	clean_steam_userdata() { :; }
	get_remote_game_version() { echo query >>"$calls"; printf '101\n'; }
	get_playerList() { have_player=$players_online; }
	update_game() {
		echo "update:timeout=$STEAMCMD_TIMEOUT_SECONDS" >>"$calls"
		printf '101\n' >"$sandbox/game/version.txt"
		printf '"buildid" "1001"\n' >"$sandbox/game/steamapps/appmanifest_343050.acf"
	}
	restart_server() {
		echo "restart:$*" >>"$calls"
		[ "$restart_ok" == true ] || return 1
		printf '1001\n' >"$sandbox/$1/cluster_game_buildid.txt"
	}

	players_online=true
	checkupdate fixture >"$sandbox/online.log" 2>&1
	assert_not_contains "$calls" 'update:' "仅无人更新配置在有人在线时不下载游戏本体"
	players_online=false
	if checkupdate fixture >"$sandbox/first.log" 2>&1; then
		fail "更新后重启失败返回非零"
	else
		pass "更新后重启失败返回非零"
	fi
	if [ -f "$pending" ]; then pass "重启失败保留待重启标记"; else fail "重启失败保留待重启标记"; fi
	assert_contains "$calls" 'update:timeout=600' "自动游戏更新使用默认600秒超时"
	: >"$calls"
	checkupdate fixture >"$sandbox/retry.log" 2>&1
	assert_contains "$calls" 'restart:fixture -AUTO -NOBODY' "磁盘已最新仍重试受无人配置限制的重启"
	assert_not_contains "$calls" 'update:' "待重启时不重复下载"
	assert_not_contains "$calls" query "待重启恢复不依赖远端查询"

	restart_ok=true
	checkupdate fixture >"$sandbox/recovered.log" 2>&1
	if [ ! -f "$pending" ]; then pass "重启成功清除待重启标记"; else fail "重启成功清除待重启标记"; fi
	: >"$calls"
	checkupdate fixture >"$sandbox/current.log" 2>&1
	assert_not_contains "$calls" restart "运行buildid与磁盘一致时不重复重启"
	: >"$calls"
	checkupdate other >"$sandbox/shared.log" 2>&1
	assert_contains "$calls" 'restart:other -AUTO -NOBODY' "共用本体的另一个存档独立重启"
	assert_not_contains "$calls" 'update:' "共用本体已更新时无需重新下载"
)

test_auto_game_update_timeout() (
	local sandbox="$test_root/game-update-timeout"
	mkdir -p "$sandbox/game/steamapps" "$sandbox/scripts"
	printf '100\n' >"$sandbox/game/version.txt"
	printf 'auto_update_anyway = true\n' >"$sandbox/scripts/config.txt"
	cat >"$sandbox/steamcmd" <<'EOF'
#!/bin/bash
exec sleep 20
EOF
	chmod +x "$sandbox/steamcmd"
	DST_DEFAULT_PATH="$sandbox/game"
	get_path_games() { gamesPath="$sandbox/game"; buildid_version_flag=public; }
	get_path_script_files() { script_files_path="$sandbox/scripts"; }
	clean_steam_userdata() { :; }
	get_remote_game_version() { printf '101\n'; }
	ensure_steamcmd() { STEAMCMD_BIN="$sandbox/steamcmd"; }
	restart_server() { echo restart >>"$sandbox/calls"; }
	AUTO_UPDATE_GAME_TIMEOUT_SECONDS=1
	local started=$SECONDS
	if checkupdate fixture >"$sandbox/output.log" 2>&1; then
		fail "自动游戏更新超时返回失败"
	else
		pass "自动游戏更新超时返回失败"
	fi
	if [ $((SECONDS - started)) -lt 10 ]; then pass "SteamCMD超时后控制权返回调用方"; else fail "SteamCMD超时后控制权返回调用方"; fi
	assert_contains "$sandbox/output.log" '退出码: 124' "真实timeout命令终止隔离SteamCMD桩进程"
	if [ ! -e "$sandbox/calls" ]; then pass "下载超时不重启服务器"; else fail "下载超时不重启服务器"; fi
)

test_restart_requires_successful_start() (
	close_server() { return 0; }
	log_with_timestamp() { :; }
	howtostart() { check_flag=0; return 0; }
	if restart_server fixture -AUTO; then fail "开服检查失败时重启返回失败"; else pass "开服检查失败时重启返回失败"; fi
	howtostart() { check_flag=1; return 0; }
	if restart_server fixture -AUTO; then pass "开服检查成功时重启返回成功"; else fail "开服检查成功时重启返回成功"; fi
)

test_beta_steamcmd_args_and_install_check() (
	local sandbox="$test_root/beta-steamcmd"
	local calls="$sandbox/calls.log"
	mkdir -p "$sandbox/beta/steamapps" "$sandbox/beta/bin64" "$sandbox/beta/bin"
	: >"$calls"
	export TMPDIR="$sandbox"
	DST_BETA_PATH="$sandbox/beta"

	run_steamcmd() {
		printf '%s\n' "$*" >>"$calls"
		printf "Success! App '343050' fully installed.\n"
		return 0
	}

	printf '755194\n' >"$sandbox/beta/version.txt"
	printf '"buildid" "25540104"\n' >"$sandbox/beta/steamapps/appmanifest_343050.acf"
	: >"$sandbox/beta/bin64/dontstarve_dedicated_server_nullrenderer_x64"
	chmod +x "$sandbox/beta/bin64/dontstarve_dedicated_server_nullrenderer_x64"

	if download_game_body BETA >"$sandbox/beta-update.log" 2>&1; then
		pass "测试版本体下载按成功标志通过"
	else
		fail "测试版本体下载按成功标志通过"
	fi
	assert_contains "$calls" "-beta updatebeta" "测试版下载使用分支名 updatebeta"
	assert_not_contains "$calls" "returnofthembeta" "测试版下载不再把分支密码当分支名"

	: >"$calls"
	DST_SCRIPT_BETA_PASSWORD="s3cret"
	download_game_body BETA >"$sandbox/beta-password.log" 2>&1 || true
	assert_contains "$calls" "-betapassword s3cret" "配置分支密码时额外传递 -betapassword"
	DST_SCRIPT_BETA_PASSWORD=""

	if dst_install_complete "$sandbox/beta"; then
		pass "版本号、清单与主程序齐全时视为安装完整"
	else
		fail "版本号、清单与主程序齐全时视为安装完整"
	fi

	rm -f "$sandbox/beta/bin64/dontstarve_dedicated_server_nullrenderer_x64"
	if dst_install_complete "$sandbox/beta"; then
		fail "缺少服务端主程序时视为安装不完整"
	else
		pass "缺少服务端主程序时视为安装不完整"
	fi

	: >"$sandbox/beta/bin/dontstarve_dedicated_server_nullrenderer"
	chmod +x "$sandbox/beta/bin/dontstarve_dedicated_server_nullrenderer"
	if dst_install_complete "$sandbox/beta"; then
		pass "仅存在32位主程序时仍视为安装完整"
	else
		fail "仅存在32位主程序时仍视为安装完整"
	fi

	printf '\n' >"$sandbox/beta/version.txt"
	if dst_install_complete "$sandbox/beta"; then
		pass "version.txt只有空白字符时仍视为安装完整"
	else
		fail "version.txt只有空白字符时仍视为安装完整"
	fi

	: >"$sandbox/beta/version.txt"
	if dst_install_complete "$sandbox/beta"; then
		fail "version.txt为空时视为安装不完整"
	else
		pass "version.txt为空时视为安装不完整"
	fi

	printf '"buildid" "25540104"\n\t\t"BetaKey"\t\t"updatebeta"\n' >"$sandbox/beta/steamapps/appmanifest_343050.acf"
	# 前面的断言把 version.txt 清空了，这里恢复成"已装好测试版"的现场。
	printf '755194\n' >"$sandbox/beta/version.txt"
	printf '"buildid" "25540104"\n\t\t"BetaKey"\t\t"updatebeta"\n' >"$sandbox/beta/steamapps/appmanifest_343050.acf"

	if dst_beta_body_ready "$sandbox/beta"; then
		pass "清单标记测试分支且本体完整时视为已装好测试版"
	else
		fail "清单标记测试分支且本体完整时视为已装好测试版"
	fi

	printf '"buildid" "24080846"\n' >"$sandbox/beta/steamapps/appmanifest_343050.acf"
	if dst_beta_body_ready "$sandbox/beta"; then
		fail "正式版清单不会被误判为测试版本体"
	else
		pass "正式版清单不会被误判为测试版本体"
	fi

	printf '"buildid" "25540104"\n\t\t"BetaKey"\t\t"updatebeta"\n' >"$sandbox/beta/steamapps/appmanifest_343050.acf"
	printf '740477\n' >"$sandbox/beta/version.txt"
	if dst_beta_body_ready "$sandbox/beta"; then
		pass "版本号落后但分支正确时不重复下载，交给自动更新处理"
	else
		fail "版本号落后但分支正确时不重复下载，交给自动更新处理"
	fi

	# 目录里是完整正式版本体：应触发一次测试版重新下载，而不是直接跳过。
	run_steamcmd() {
		printf '%s\n' "$*" >>"$calls"
		printf '%s\n' "$*"
		return 1
	}
	printf '"buildid" "24080846"\n' >"$sandbox/beta/steamapps/appmanifest_343050.acf"
	echo 4 | change_game_version fixture >"$sandbox/ensure-only.log" 2>&1
	assert_contains "$sandbox/ensure-only.log" "测试版游戏本体下载失败" "本体不完整时切换版本执行下载并给出失败原因"
	assert_contains "$sandbox/ensure-only.log" "-beta updatebeta" "本体不完整时的下载命令使用测试分支名"
	assert_contains "$sandbox/ensure-only.log" "当前不是测试版本体" "正式版本体在位时提示需要重新下载测试版"
)

test_beta_version_switch_requires_install() (
	local sandbox="$test_root/beta-switch"
	local calls="$sandbox/calls.log"
	local config="$sandbox/scripts/config.txt"
	mkdir -p "$sandbox/scripts" "$sandbox/beta"
	printf 'version = 正式版32位\nauto_update_anyway = true\n' >"$config"
	: >"$calls"
	export TMPDIR="$sandbox"
	DST_BETA_PATH="$sandbox/beta"
	script_files_path="$sandbox/scripts"

	run_steamcmd() {
		printf '%s\n' "$*" >>"$calls"
		printf '%s\n' "$*"
		return 1
	}
	log_with_timestamp() { :; }
	get_remote_game_version() {
		printf '%s\n' 755194
	}

	if echo 4 | change_game_version fixture >"$sandbox/switch-fail.log" 2>&1; then
		fail "测试版本体下载失败时切换版本失败"
	else
		pass "测试版本体下载失败时切换版本失败"
	fi
	assert_contains "$config" "version = 正式版32位" "测试版下载失败时保留原正式版配置"
	assert_contains "$sandbox/switch-fail.log" "-beta updatebeta" "失败路径同样使用正确的测试分支"

	run_steamcmd() {
		printf '%s\n' "$*" >>"$calls"
		printf "Success! App '343050' fully installed.\n"
		mkdir -p "$DST_BETA_PATH/steamapps" "$DST_BETA_PATH/bin64"
		printf '755194\n' >"$DST_BETA_PATH/version.txt"
		printf '"buildid" "25540104"\n\t\t"BetaKey"\t\t"updatebeta"\n' >"$DST_BETA_PATH/steamapps/appmanifest_343050.acf"
		: >"$DST_BETA_PATH/bin64/dontstarve_dedicated_server_nullrenderer_x64"
		chmod +x "$DST_BETA_PATH/bin64/dontstarve_dedicated_server_nullrenderer_x64"
		return 0
	}

	if echo 4 | change_game_version fixture >"$sandbox/switch-ok.log" 2>&1; then
		pass "测试版本体下载成功后切换版本成功"
	else
		fail "测试版本体下载成功后切换版本成功"
	fi
	assert_contains "$config" "version = 测试版64位" "测试版本体下载成功后写入测试版配置"
)

test_missing_beta_body_blocks_start() (
	local sandbox="$test_root/beta-missing-body"
	mkdir -p "$sandbox/saves" "$sandbox/beta-saves/fixture/Master" \
		"$sandbox/beta-saves/fixture/ScriptFiles" "$sandbox/beta"
	printf 'version = 测试版64位\n' >"$sandbox/beta-saves/fixture/ScriptFiles/config.txt"
	: >"$sandbox/beta-saves/fixture/Master/server_log.txt"
	DST_SAVE_PATH="$sandbox/saves"
	DST_BETA_SAVE_PATH="$sandbox/beta-saves"
	DST_BETA_PATH="$sandbox/beta"
	DST_DEFAULT_PATH="$sandbox/official"

	if start_server_select fixture "DST_Master_beta fixture" "start_server_master.sh" \
		>"$sandbox/blocked.log" 2>&1; then
		fail "测试版本体缺失时阻止启动分片"
	else
		pass "测试版本体缺失时阻止启动分片"
	fi
	assert_contains "$sandbox/blocked.log" "测试版本体不存在或不完整" "测试版本体缺失时给出明确提示"
	if compgen -G "$sandbox/beta-saves/fixture/ScriptFiles/start_server_master.sh" >/dev/null; then
		fail "测试版本体缺失时不生成启动脚本"
	else
		pass "测试版本体缺失时不生成启动脚本"
	fi
)

test_beta_save_path_resolution() (
	local sandbox="$test_root/beta-save-path"
	mkdir -p "$sandbox/saves/stable_only/ScriptFiles" "$sandbox/saves/beta_cluster/ScriptFiles" \
		"$sandbox/saves/beta_cluster/Master" "$sandbox/beta-saves/beta_cluster/ScriptFiles" \
		"$sandbox/beta-saves/beta_cluster/Master" "$sandbox/beta-saves/beta_cluster/Caves"
	printf 'version = 正式版64位\n' >"$sandbox/saves/stable_only/ScriptFiles/config.txt"
	printf 'version = 正式版64位\n' >"$sandbox/saves/beta_cluster/ScriptFiles/config.txt"
	printf 'version = 测试版64位\nauto_update_anyway = true\n' >"$sandbox/beta-saves/beta_cluster/ScriptFiles/config.txt"
	echo token >"$sandbox/saves/beta_cluster/cluster_token.txt"

	DST_SAVE_PATH="$sandbox/saves"
	DST_BETA_SAVE_PATH="$sandbox/beta-saves"

	get_path_cluster stable_only
	if [ "$cluster_path" == "$sandbox/saves/stable_only" ]; then
		pass "正式版存档解析到正式版存档目录"
	else
		fail "正式版存档解析到正式版存档目录"
	fi

	# 正式版目录里还留着旧的“正式版”配置，但测试版目录已是测试版配置：应以测试版为准。
	get_path_cluster beta_cluster
	if [ "$cluster_path" == "$sandbox/beta-saves/beta_cluster" ]; then
		pass "切换到测试版的存档解析到测试版存档目录"
	else
		fail "切换到测试版的存档解析到测试版存档目录"
		echo "  实际路径: $cluster_path"
	fi

	# 从正式版切测试版时，应把世界和 token 复制到测试版存档目录
	rm -rf "$sandbox/beta-saves/beta_cluster"
	migrate_cluster_to_beta_save beta_cluster
	if [ -f "$sandbox/beta-saves/beta_cluster/cluster_token.txt" ] &&
		[ -d "$sandbox/beta-saves/beta_cluster/Master" ]; then
		pass "切换测试版时复制正式版存档与token"
	else
		fail "切换测试版时复制正式版存档与token"
		command ls -la "$sandbox/beta-saves/beta_cluster" >&2
	fi

	# 已经在测试版目录里的存档不会被再次覆盖
	printf 'modified\n' >"$sandbox/beta-saves/beta_cluster/ScriptFiles/config.txt"
	migrate_cluster_to_beta_save beta_cluster
	if [ "$(cat "$sandbox/beta-saves/beta_cluster/ScriptFiles/config.txt")" == "modified" ]; then
		pass "测试版目录已存在时不重复覆盖"
	else
		fail "测试版目录已存在时不重复覆盖"
	fi
)

test_self_update_validation() (
	local sandbox="$test_root/self-update"
	export HOME="$sandbox/home"
	mkdir -p "$HOME" "$sandbox/target"
	script_path="$sandbox/target"
	SCRIPT_NAME="DST_SCRIPT.sh"
	echo original >"$script_path/$SCRIPT_NAME"
	DST_SCRIPT_GIT_URL="mock-invalid"
	DST_SCRIPT_OFFICIAL_GIT_URL="mock-valid"
	local clone_attempt=0
	clear() { :; }
	timeout() { shift; "$@"; }
	git() {
		clone_attempt=$((clone_attempt + 1))
		mkdir -p Linux_DST_SCRIPT
		if [ "$clone_attempt" -eq 1 ]; then
			printf '%s\n' '#!/bin/bash' 'if then' >Linux_DST_SCRIPT/DST_SCRIPT.sh
		else
			printf '%s\n' '#!/bin/bash' 'echo updated' >Linux_DST_SCRIPT/DST_SCRIPT.sh
		fi
		return 0
	}
	bash() {
		if [ "$1" = "-n" ]; then
			command /bin/bash "$@"
		else
			echo "$*" >>"$sandbox/restart.log"
		fi
	}

	get_latest_version >"$sandbox/output.log" 2>&1
	assert_contains "$sandbox/output.log" '未通过语法检查' "自更新拒绝语法错误候选脚本"
	assert_contains "$script_path/$SCRIPT_NAME" 'echo updated' "自更新使用后续有效来源原子替换脚本"
	if compgen -G "$script_path/.${SCRIPT_NAME}.update.*" >/dev/null; then
		fail "自更新完成后清理临时文件"
	else
		pass "自更新完成后清理临时文件"
	fi
)

test_generated_start_script
test_start_check_logs_and_returns
test_restart_branches_return
test_mod_restore_and_replace
test_duplicate_screen_detection
test_startup_mod_check
test_repair_does_not_leak_asset_variable
test_generic_lua_traceback_detection
test_ambiguous_lua_traceback_is_not_repaired
test_startup_terminal_shard_cleanup
test_download_retry_boundary_and_propagation
test_shutdown_log_safety
test_close_server_propagates_failure
test_generated_backup_path
test_player_history_permissions
test_player_statistics
test_update_game_result_validation
test_remote_game_version
test_game_update_precheck
test_game_update_restart_recovery
test_auto_game_update_timeout
test_restart_requires_successful_start
test_beta_steamcmd_args_and_install_check
test_beta_version_switch_requires_install
test_missing_beta_body_blocks_start
test_beta_save_path_resolution
test_self_update_validation

passed=$(grep -c '^PASS$' "$result_file" || true)
failed=$(grep -c '^FAIL$' "$result_file" || true)
echo "[SUMMARY] passed=$passed failed=$failed"
[ "$failed" -eq 0 ]

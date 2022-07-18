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

: "
功能如下：
不需要手动添加mod文件了,自动添加mod(使用的是klei提供dedicated_server_mods_setup.lua)
自动更新服务器mod
自动更新服务器
崩档自动重启服务器
"

##全局默认变量
#脚本版本
DST_SCRIPT_version="1.3.7"
# git加速链接
use_acceleration_url="hub.fastgit.xyz/"
# 饥荒存档位置
DST_save_path="$HOME/.klei/DoNotStarveTogether"
# 脚本开启的服务器版本
DST_game_version="正式版"
DST_game_version_reverse="测试版"
# 当前游戏位置
DST_game_path="$HOME/dst"
# 当前游戏的分支位置
DST_temp_path="$HOME/DST_Updatecheck/branch_DST"
# 当前系统版本
os=$(awk -F = '/^NAME/{print $2}' /etc/os-release | sed 's/"//g' | sed 's/ //g' | sed 's/Linux//g' | sed 's/linux//g')
# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
flag=1

#通知内容
c_announce="服务器需要重启,给您带来的不便还请谅解！！！"

#主菜单
function Main()
{
	clear
	tput setaf 2 
	echo "==========================================================================================================="
	echo -e "                                            \c"
	printf "%-40s\n"  "服务器版本为${DST_game_version}"
	echo -e "                                             \c"
	tput setaf 3 
	printf "%-40s\n" "脚本版本为${DST_SCRIPT_version}"
	tput setaf 2 
    echo "==========================================================================================================="
	while :
	do
		echo "                                                                                  "
		echo "	[1]更新服务器                             [2]启动服务器                     [3]关闭饥荒服务器			"
		echo "                                                                                  "
		echo "	[4]查看服务器状态                         [5]控制台                         [6]重启服务器"
		echo "                                                                                  "
		echo "	[7]更换服务器版本为${DST_game_version_reverse}                 [8]查看存档mod                    [9]获取最新脚本			   "
		echo "                                                                                  "
		echo "==========================================================================================================="
		echo "                                                                                  "
		echo -e "\e[92m请输入命令代号：\e[0m"
		read -r main1
		case $main1 in
			1)update_game break;;
			2)start_server break;;
			3)close_server break;;
			4)check_server break;;
			5)console break;;
			6)restart_server break;;
			7)change_game_version break;;
			8)list_all_mod break;;
			9)get_mew_version break;;
		esac
    done
}

# 获取最新版脚本
function console()
{
	echo "没写好,请过段时间更新脚本"
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
		git clone "https://${use_acceleration_url}/ChengTu-Lazy/Linux_DST_SCRIPT.git"
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
	Cluster_bath="${DST_save_path}"/"$cluster_name"
	ugc_mods_path="${DST_game_path}/ugc_mods"
	dontstarve_dedicated_server_nullrenderer_path="${DST_game_path}/bin"
	masterlog_path="${DST_save_path}/$cluster_name/Master/server_log.txt"
	caveslog_path="${DST_save_path}/$cluster_name/Caves/server_log.txt"
	cd "$HOME" || exit
	cd "${Cluster_bath}" || exit
	# 配置auto_update.sh
	printf "%s" "#!/bin/bash
	##配置常量
	DST_now=\$(date +\"%D %T\")
	# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
	flag=$flag
	# 游戏版本
	DST_game_version=\"${DST_game_version}\"
	#查看进程执行情况
	function CheckProcess()
	{
		# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
		if [ \"\$flag\" == 1 ]; then
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -ne 1 || \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -ne 1 ]]; then
				c_announce=\"检测到游戏存档未完整开启,服务器需要重启,给您带来的不便还请谅解！！！\"
				restart_server
			fi
			if [[ \$(grep -c \"Operation too slow. Less than 5 bytes/sec transferred the last 60 seconds\" \"${masterlog_path}\") -gt 0 ]]; then
				c_announce=\"检测到游戏数据链接延迟较大,服务器需要重启,给您带来的不便还请谅解！！！\"
				restart_server
			fi
		elif [ \"\$flag\" == 4 ]; then
			if [[ \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -ne 1 ]]; then
				c_announce=\"检测到游戏存档未完整开启,服务器需要重启,给您带来的不便还请谅解！！！\"
				restart_server
			fi
			if [[ \$(grep -c \"Operation too slow. Less than 5 bytes/sec transferred the last 60 seconds\" \"${caveslog_path}\") -gt 0 ]]; then
				c_announce=\"检测到游戏数据链接延迟较大,服务器需要重启,给您带来的不便还请谅解！！！\"
				restart_server
			fi
		elif [ \"\$flag\" == 2 ]; then
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -ne 1 ]]; then
				c_announce=\"检测到游戏存档未完整开启,服务器需要重启,给您带来的不便还请谅解！！！\"
				restart_server
			fi
			if [[ \$(grep -c \"Operation too slow. Less than 5 bytes/sec transferred the last 60 seconds\" \"${caveslog_path}\") -gt 0 ]]; then
				c_announce=\"检测到游戏数据链接延迟较大,服务器需要重启,给您带来的不便还请谅解！！！\"
				restart_server
			fi
		fi
	}
	#查看游戏更新情况
	function CheckUpdate()
	{
		#先更新服务器副本文件
		cd $HOME/steamcmd || exit
		if [[ \"\${DST_game_version}\" == \"测试版\" ]]; then
			echo \"正在同步测试版游戏服务端。\"	
			./steamcmd.sh  +force_install_dir \"$HOME/DST_Updatecheck/branch_DST_Beta\" +login anonymous +app_update 343050 -beta anewreignbeta validate +quit
			rm \"$HOME/DST_Updatecheck/branch_DST_Beta/version_copy.txt\"
			chmod 777 \"$HOME/DST_Updatecheck/branch_DST_Beta/version.txt\"
			cp \"$HOME/DST_Updatecheck/branch_DST_Beta/version.txt\" \"$HOME/DST_Updatecheck/branch_DST_Beta/version_copy.txt\"
		else
			echo \"正在同步正式版游戏服务端。\"	
			./steamcmd.sh  +force_install_dir \"$HOME/DST_Updatecheck/branch_DST\"  +login anonymous +app_update 343050 validate +quit 
			rm \"$HOME/DST_Updatecheck/branch_DST/version_copy.txt\"
			chmod 777 \"$HOME/DST_Updatecheck/branch_DST/version.txt\"
			cp \"$HOME/DST_Updatecheck/branch_DST/version.txt\" \"$HOME/DST_Updatecheck/branch_DST/version_copy.txt\"
		fi
		#查看副本文件中的版本号和当前游戏的版本号是否一致
		if flock \"${DST_temp_path}/version_copy.txt\" -c \"! diff -q ${DST_temp_path}/version_copy.txt ${DST_game_path}/version.txt > /dev/null\" ; then
			echo -e \"\e[93m\"\"\${DST_now}\"\": 游戏服务端有更新!\e[0m\"	
			c_announce=\"检测到游戏服务端有更新,服务器需要重启,给您带来的不便还请谅解！！！\"
			UpdateServer
		else
			echo -e \"\e[93m\"\"\${DST_now}\"\": 游戏服务端没有更新!\e[0m\"	
		fi
	}
	#查看游戏mod更新情况
	function CheckModUpdate()
	{
		echo \"\"\"\${DST_now}\"\": 同步服务端更新进程正在运行。。。\"
		cd $dontstarve_dedicated_server_nullrenderer_path || exit
		./dontstarve_dedicated_server_nullrenderer -only_update_server_mods -ugc_directory \"$cluster_name\" > $cluster_name.txt 
		# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
		if [ \"\$flag\" == 1 ] || [ \"\$flag\" == 2 ]; then
			# NeedsUpdate=\$(awk '/NeedsUpdate/{print \$2}' \"${ugc_mods_path}\"/\"$cluster_name\"/Master/appworkshop_322330.acf | sed 's/\"//g')
			if [[ \$(grep \"is out of date and needs to be updated for new users to be able to join the server\" -c \"${masterlog_path}\") -gt  0 ]]; then
				DST_has_mods_update=true
				DST_now=\$(date +\"%D %T\")
			fi
		elif [ \"\$flag\" == 4 ]; then
			if [[ \$(grep \"is out of date and needs to be updated for new users to be able to join the server\" -c \"${caveslog_path}\") -gt  0 ]]; then
				DST_has_mods_update=true
				DST_now=\$(date +\"%D %T\")
			fi
		else
			DST_has_mods_update=false
			DST_now=\$(date +\"%D %T\")
		fi
		if [[ \$(grep \"DownloadPublishedFile\" -c \"${dontstarve_dedicated_server_nullrenderer_path}/$cluster_name.txt\") -gt  0 ]]; then
			DST_has_mods_update=true
			DST_now=\$(date +\"%D %T\")
		else
			DST_has_mods_update=false
			DST_now=\$(date +\"%D %T\")
		fi
		if [  \${DST_has_mods_update} == true ]; then
			echo -e \"\e[93m\"\"\${DST_now}\"\": Mod 有更新！\e[0m\"
			c_announce=\"检测到游戏Mod有更新,服务器需要重启,给您带来的不便还请谅解！！！\"
			restart_server
		elif [  \${DST_has_mods_update} == false ]; then
			echo -e \"\e[92m\${DST_now}: Mod 没有更新!\e[0m\"
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
		if [[ \"\${DST_game_version}\" == \"测试版\" ]]; then
			echo \"正在同步测试版游戏服务端。\"
			./steamcmd.sh +force_install_dir \"$HOME/dst_beta\" +login anonymous +app_update 343050 -beta anewreignbeta validate +quit
		else
			echo \"正在同步正式版游戏服务端。\"
			./steamcmd.sh +force_install_dir \"$HOME/dst\" +login anonymous +app_update 343050 validate +quit 
		fi
		start_server
	}

	# 关闭服务器
	function Shutdown()
	{
		if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -gt 0 || \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -gt 0 || \$(screen -ls | grep -c \"DST $cluster_name AutoUpdate\") -gt 0 ]]; then
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -gt 0  ]]; then
				for i in \$(screen -ls | grep -w \"DST_Master $cluster_name\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')
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
			else
				echo \"$cluster_name 这个存档没有开启地上服务器！！！！！！\"
			fi

			if [[ \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -gt 0  ]]; then
				for i in \$(screen -ls | grep -w \"DST_Caves $cluster_name\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')
				do
					screen -S \"\$i\" -p 0 -X stuff \"c_shutdown(true) \$(printf \\\\r)\"
					sleep 1
				done
			else
				echo \"$cluster_name 这个存档没有开启地下服务器！！！！！！\"
			fi
			while :
			do
				sleep 1
				if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -gt 0 || \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -gt 0 ]]; then
					echo -e \"服务器 $cluster_name 正在关闭,请稍后。。。\"
				else
					echo -e \"服务器 $cluster_name 已关闭!!!\"
					break
				fi
			done
		fi
	}
	# 开启服务器
	function start_server()
	{
		Addmod
		# 1:地上地下都有 2:只有地上 5:啥也没有 4:只有地下
		if [ \$flag == 1 ];then
			screen -dmS  \"DST_Master $cluster_name\" /bin/sh -c \"${DST_save_path}/$cluster_name/startmaster.sh\" 
			screen -dmS  \"DST_Caves $cluster_name\" /bin/sh -c \"${DST_save_path}/$cluster_name/startcaves.sh\"
			if [ \"\$(screen -ls | grep -c \"DST_Master $cluster_name\")\" -gt 0 ];then
			while :
			do
				sleep 2
				echo \"地上服务器开启中,请稍后。。。\"
				if [[ \$(grep \"Sim paused\" -c \"$masterlog_path\") -gt 0 || \$(grep \"shard LUA is now ready!\" -c \"$masterlog_path\") -gt 0 ]];then
				echo \"地上服务器开启成功!!!\"
				break
				fi
			done
			fi
			if [ \"\$(screen -ls | grep -c \"DST_Caves $cluster_name\")\" -gt 0 ];then
				while :
				do
					sleep 1
					echo \"地下服务器开启中,请稍后。。。\"
					if [[ \$(grep \"Sim paused\" -c \"$caveslog_path\") -gt 0 || \$(grep \"shard LUA is now ready!\" -c \"$caveslog_path\") -gt 0 ]];then
						echo \"地下服务器开启成功!!!\"
						break
					fi
				done
			fi
		elif [ \$flag == 2 ];then
			screen -dmS  \"DST_Master $cluster_name\" /bin/sh -c \"${DST_save_path}/$cluster_name/startmaster.sh\" 
			if [ \"\$(screen -ls | grep -c \"DST_Master $cluster_name\")\" -gt 0 ];then
				while :
				do
					sleep 2
					echo \"地上服务器开启中,请稍后。。。\"
					if [[ \$(grep \"Sim paused\" -c \"$masterlog_path\") -gt 0 || \$(grep \"shard LUA is now ready!\" -c \"$masterlog_path\") -gt 0 ]];then
						echo \"地上服务器开启成功!!!\"
						break
					fi
				done
			fi
		elif [ \$flag == 4 ];then
			screen -dmS  \"DST_Caves $cluster_name\" /bin/sh -c \"${DST_save_path}/$cluster_name/startcaves.sh\"
			if [ \"\$(screen -ls | grep -c \"DST_Caves $cluster_name\")\" -gt 0 ];then
				while :
				do
					sleep 1
					echo \"地下服务器开启中,请稍后。。。\"
					if [[ \$(grep \"Sim paused\" -c \"$caveslog_path\") -gt 0 || \$(grep \"shard LUA is now ready!\" -c \"$caveslog_path\") -gt 0 ]];then
						echo \"地下服务器开启成功!!!\"
						break
					fi
				done
			fi
		fi
	}
	#自动添加存档所需的mod
	function Addmod()
	{
		echo \"正在将开启存档所需的mod添加进服务器配置文件中。。。\"
		cd \"${DST_game_path}\"/mods || exit
		rm -rf dedicated_server_mods_setup.lua
		sleep 0.1
		if [ -e \"${DST_save_path}/$cluster_name/Master/modoverrides.lua\" ]; then
			grep \"\\\"workshop\" < \"${DST_save_path}/$cluster_name/Master/modoverrides.lua\" | cut -d '\"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
			do
				echo \"ServerModSetup(\"\"\$line\"\")\">>${DST_game_path}/mods/dedicated_server_mods_setup.lua
				echo \"ServerModCollectionSetup(\"\"\$line\"\")\">>${DST_game_path}/mods/dedicated_server_mods_setup.lua
				sleep 0.5
				echo \"\$line Mod添加完成\"
			done
		elif [ -e \"${DST_save_path}/$cluster_name/Caves/modoverrides.lua\" ]; then
			grep \"\\\"workshop\" < \"${DST_save_path}/$cluster_name/Caves/modoverrides.lua\" | cut -d '\"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
			do
				echo \"ServerModSetup(\"\"\$line\"\")\">>${DST_game_path}/mods/dedicated_server_mods_setup.lua
				echo \"ServerModCollectionSetup(\"\"\$line\"\")\">>${DST_game_path}/mods/dedicated_server_mods_setup.lua
				sleep 0.5
				echo \"\$line Mod添加完成\"
			done
		fi
	}
	
	# 保持运行
	while :
			do
				DST_now=\$(date +\"%D %T\")
				CheckProcess
				CheckUpdate
				CheckModUpdate
				sleep 1
			done
	" > "${Cluster_bath}"/auto_update.sh
	chmod 777 "${Cluster_bath}"/auto_update.sh
	screen -dmS  "DST $cluster_name AutoUpdate" /bin/sh -c "${DST_save_path}/$cluster_name/auto_update.sh"
	echo -e "\e[92m自动更新进程 DST $cluster_name AutoUpdate 已启动\e[0m"
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
		if [ -e "${DST_save_path}/$cluster_name/Master/modoverrides.lua" ]; then
			grep "\"workshop" < "${DST_save_path}/$cluster_name/Master/modoverrides.lua" | cut -d '"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
			do
				echo "ServerModSetup(\"$line\")">>"${DST_game_path}"/mods/dedicated_server_mods_setup.lua
				echo "ServerModCollectionSetup(\"$line\")">>"${DST_game_path}"/mods/dedicated_server_mods_setup.lua
				sleep 0.05
				echo -e "\e[92m$line Mod添加完成\e[0m"
			done
		elif [ -e "${DST_save_path}/$cluster_name/Caves/modoverrides.lua" ]; then 
			grep "\"workshop" < "${DST_save_path}/$cluster_name/Caves/modoverrides.lua" | cut -d '"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
			do
				echo "ServerModSetup(\"$line\")">>"${DST_game_path}"/mods/dedicated_server_mods_setup.lua
				echo "ServerModCollectionSetup(\"$line\")">>"${DST_game_path}"/mods/dedicated_server_mods_setup.lua
				sleep 0.05
				echo -e "\e[92m$line Mod添加完成\e[0m"
			done
		fi
}
# 开启服务器
function start_server()
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
	echo ""
	echo "请输入存档代码"
	read -r cluster_name
		if [ "$cluster_name" == "" ]; then
			 Main
		else
			if [ "$(screen -ls | grep -c "DST_Caves $cluster_name")" -gt 0 ] ;then
			echo "该服务器已开启地上服务器,请先关闭再启动！！"
			elif [ "$(screen -ls | grep -c "DST_Master $cluster_name")" -gt 0 ];then
				echo "该服务器已开启地下服务器,请先关闭再启动！！"
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
				if [ -d "${DST_save_path}/$cluster_name" ];then
					Filechose
				fi
			fi
		fi
		
		
}
# 选择开启的存档
function Filechose()
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
	case $flag in
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
	esac
}
#开启地下服务器
function StartCaves()
{
	rm -rf "${DST_save_path}"/"$cluster_name"/startcaves.sh
	echo   "#!/bin/bash
	gamesPath=\"$DST_game_path/bin\"
	cd "\"\$gamesPath\" \|\| exit"
	run_shared=(./dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard Caves" > "${DST_save_path}"/"$cluster_name"/startcaves.sh
	cd "${DST_save_path}"/"$cluster_name" || exit
	chmod u+x ./startcaves.sh
	cd "$HOME" || exit
	screen -dmS  "DST_Caves $cluster_name" /bin/sh -c "${DST_save_path}/$cluster_name/startcaves.sh" 
}
#开启地面服务器
function StartMaster()
{
	rm -rf "${DST_save_path}"/"$cluster_name"/startmaster.sh
	echo   "#!/bin/bash
	gamesPath=\"$DST_game_path/bin\"
	cd "\"\$gamesPath\" \|\| exit"
	run_shared=(./dontstarve_dedicated_server_nullrenderer)
	run_shared+=(-console)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard Master " > "${DST_save_path}"/"$cluster_name"/startmaster.sh
	cd "${DST_save_path}"/"$cluster_name" || exit
	chmod u+x ./startmaster.sh
	cd "$HOME" || exit
	screen -dmS  "DST_Master $cluster_name" /bin/sh -c "${DST_save_path}/$cluster_name/startmaster.sh" 
}
#检查是否成功开启
function start_serverCheck()
{
	masterchatlog_path="${DST_save_path}/$cluster_name/Master/server_log.txt"
	caveslog_path="${DST_save_path}/$cluster_name/Caves/server_log.txt"
	start_time=$(date +%s);
	if [ "$(screen -ls | grep -c "DST_Master $cluster_name")" -gt 0 ];then
		while :
		do
			sleep 1
			echo -en "\r地上服务器开启中,请稍后.  "
			sleep 1
			echo -en "\r地上服务器开启中,请稍后.. "
			sleep 1
			echo -en "\r地上服务器开启中,请稍后..."
			if [[ $(grep "Sim paused" -c "$masterchatlog_path") -gt 0 ||  $(grep "shard LUA is now ready!" -c "$masterchatlog_path") -gt 0 ]];then
				NeedsDownload=$(awk '/NeedsDownload/{print $2}' "${ugc_mods_path}"/"$cluster_name"/Master/appworkshop_322330.acf | sed 's/"//g')
				if [ "${NeedsDownload}" -ne 0 ]; then
					close_server_
					start_server
				else
					echo -e "\n\e[92m地上服务器开启成功!!!                \e[0m"
					break
				fi
			fi
			if  [[ $(grep "Your Server Will Not Start !!!" -c "$masterchatlog_path") -gt 0  ]]; then
				echo "服务器开启未成功,请执注意令牌是否成功设置且有效。"
				break
			elif [[ $(grep "Failed to send shard broadcast message" -c "$masterchatlog_path") -gt 0 ]]; then
				echo "服务器开启未成功,可能网络有点问题,正在自动重启。"
				sleep 3
				close_server_
				start_server
			fi
		done
	fi
	if [ "$(screen -ls | grep -c "DST_Caves $cluster_name")" -gt 0 ];then
		while :
		do
			sleep 1
			echo -en "\r地下服务器开启中,请稍后.  "
			sleep 1
			echo -en "\r地下服务器开启中,请稍后.. "
			sleep 1
			echo -en "\r地下服务器开启中,请稍后..."
			if [[ $(grep "Sim paused" -c "$caveslog_path") -gt 0 || $(grep "shard LUA is now ready!" -c "$caveslog_path") -gt 0 ]];then
				NeedsDownload=$(awk '/NeedsDownload/{print $2}' "${ugc_mods_path}"/"$cluster_name"/Caves/appworkshop_322330.acf | sed 's/"//g')
				if [ "${NeedsDownload}" -ne 0 ]; then
					close_server_
					start_server
				else
					echo -e "\n\e[92m地下服务器开启成功!!!                \e[0m"
					break
				fi
			fi
			if [[ $(grep "Your Server Will Not Start !!!" -c "$caveslog_path") -gt 0 || $(grep "Failed to send shard broadcast message" -c "$caveslog_path") -gt 0 ]]; then
				echo "服务器开启未成功,请注意令牌是否成功设置且有效。"
				break
			elif [[ $(grep "Failed to send shard broadcast message" -c "$caveslog_path") -gt 0 ]]; then
				echo "服务器开启未成功,可能网络有点问题,正在自动重启。"
				sleep 3
				close_server_
				start_server
			fi
		done
	fi
	end_time=$(date +%s)
	cost_time=$((end_time-start_time))
	echo -e "\r\e[92m本次开服花费时间:$((cost_time/60))分$((cost_time%60))秒\e[0m"
}
# 关闭服务器
function close_server()
{
	printf  '=%.0s' {1..76}
	echo ""
	screen -ls
	printf  '=%.0s' {1..28}
	echo -e "请输入要关闭的存档名\c"
	printf  '=%.0s' {1..28}
	echo ""
	read -r cluster_name
	if [ "$cluster_name" == "" ]; then
			 Main
	else
		echo ""
		close_server_
	fi
	
}
# 关闭服务器解耦部分
function close_server_()
{
	if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0 || $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0 || $(screen -ls | grep -c "DST $cluster_name AutoUpdate") -gt 0 ]]; then
		if [[ $(screen -ls | grep -c "DST $cluster_name AutoUpdate") -gt 0  ]]; then
			for i in $(screen -ls | grep -w "DST $cluster_name AutoUpdate" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				kill "$i"
			done
		fi
		if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0  ]]; then
			for i in $(screen -ls | grep -w "DST_Master $cluster_name" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
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
				echo -e "\n\e[92m地上服务器已关闭!!!                \e[0m"
				
				sleep 1
			done
		fi

		if [[ $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0  ]]; then

			for i in $(screen -ls | grep -w "DST_Caves $cluster_name" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
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
				echo -e "\n\e[92m地下服务器已关闭!!!                \e[0m"
				sleep 1
			done
		fi
			
			while :
			do
				sleep 1
				if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0 || $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0 ]]; then
					echo -e "\e[92m进程 $cluster_name 正在关闭,请稍后。。。\e[0m"
				else
				 	echo -e "\r\e[92m进程 $cluster_name 已关闭!!!                   \e[0m "
					clear
					break
				fi
			done
		else
			printf  '=%.0s' {1..80}
			echo ""
			echo ""
			echo "当前游戏服务器未开启！！！"
			echo ""
			printf  '=%.0s' {1..80}
			echo ""
		fi
}
# 重启服务器
function restart_server()
{
	close_server
	Filechose
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
	echo ""
	echo "请输入存档代码"
	read -r cluster_name
	echo "                                                                                  "
    echo "                                                                                  "
	printf  '=%.0s' {1..27}
    echo -e " $cluster_name存档已下载的mod如下： \c"
	printf  '=%.0s' {1..27}
	echo ""
	temp_mods_path="$DST_game_path"/ugc_mods/"$cluster_name"/Master/content/322330
	if [ -d "$temp_mods_path" ]; then
		for i in $( find "/home/ubuntu/dst/ugc_mods/bh/Master/content/322330" -maxdepth 1   -exec basename {} \; | awk '{print $NF}' )
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
	sudo apt-get -y install screen
	sudo apt-get -y install htop
	sudo apt-get -y install gawk
	# 加载 32bit 库
	sudo apt-get -y install lib32gcc1
	sudo apt-get -y install lib32stdc++6
	sudo apt-get -y install libcurl4-gnutls-dev:i386
	sudo dpkg --add-architecture i386
	# 加载 64bit库
	sudo apt-get -y install lib64gcc1
	sudo apt-get -y install lib64stdc++6
	sudo apt-get -y install libcurl4-gnutls-dev

	elif [ "$os" == "CentOS" ];then

		echo ""
		echo "##########################"
		echo "# 加载 CentOS Linux 环境 #"
		echo "##########################"
		echo ""
		sudo yum -y update
		sudo yum -y install tar wget screen
		# 加载 32bit 库
		sudo yum -y install glibc.i686 libstdc++.i686 libcurl.i686
		# 加载 64bit 库
		sudo yum -y install glibc libstdc++ libcurl
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
	if [ ! -d "./steamcmd" ] ||[ ! -d "./DST_Updatecheck"  ] || [ ! -d "./DST_Updatecheck/branch_DST"  ] || [ ! -d "./DST_Updatecheck/branch_DST_Beta"  ] || [ ! -d "./.klei/DoNotStarveTogether"  ] ;then
		PreLibrary
		mkdir "$HOME/dst"
		mkdir "$HOME/dst_beta"
		mkdir "$HOME/DST_Updatecheck"
		mkdir "$HOME/DST_Updatecheck/branch_DST"
		mkdir "$HOME/DST_Updatecheck/branch_DST_Beta"
		mkdir "$HOME/steamcmd"
		mkdir "$HOME/.klei"
		mkdir "${DST_save_path}"
		cd "$HOME/steamcmd" || exit 
		wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
		tar -xvzf steamcmd_linux.tar.gz
		sleep 1
		rm -f steamcmd_linux.tar.gz
	fi
	if [[ ${DST_game_version} == "正式版" ]]; then
		echo "游当前服务端版本为正式版！"
		cd "$HOME/dst" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
		fi
	else
		echo "当前服务端版本为测试版！"
		cd "$HOME/dst_beta" || exit
		if [ ! -e "version.txt" ] ; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 -beta anewreignbeta validate +quit
		fi
	fi
	
	cd "$HOME" || exit 
	Main
}
# 切换游戏版本
function change_game_version()
{
	if [[ ${DST_game_version} == "正式版" ]]; then
	    echo "更改服务端版本为测试版！"	
	    DST_game_version="测试版"
		DST_game_version_reverse="正式版"
		DST_temp_path="$HOME/DST_Updatecheck/branch_DST_Beta"
		DST_game_path="$HOME/dst_beta"
		cd "$HOME/dst_beta" || exit
		if [ ! -e "version.txt" ] ; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 -beta anewreignbeta validate +quit
		fi
    else
        echo "更改服务端版本为正式版！"	
	    DST_game_version="正式版"
		DST_game_version_reverse="测试版"
		DST_temp_path="$HOME/DST_Updatecheck/branch_DST"
		DST_game_path="$HOME/dst"
		cd "$HOME/dst" || exit
		if [ ! -e "version.txt" ]; then
			cd "$HOME/steamcmd" || exit
			./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
		fi
    fi
    Main
}
# 更新游戏
function update_game()
{
	cd "$HOME/steamcmd" || exit
    echo "正在更新游戏,请稍后。。。更新之后重启服务器生效哦。。。"
    if [[ ${DST_game_version} == "正式版" ]]; then
	    echo "游当前服务端版本为正式版！"
	    ./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
	else
        echo "当前服务端版本为测试版！"
	    ./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 -beta anewreignbeta validate +quit
    fi
}
prepare
Main column -t
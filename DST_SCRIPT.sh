#!/bin/bash
#Program:
#	饥荒linux系统服务器开服脚本 测试
#History:
# 2022/04/12 诚徒
# 2022/04/22 适配更多的服务器
# 2022/04/22 新增更新服务器mod功能
# 2022/06/13 修复自动添加mod功能被干扰的bug
# 2022/06/14 完善开服，新增手动更新服务器功能
# 2022/06/15 自动更新mod
# 2022/06/30 自动更新服务器
# 2022/07/04 崩档自动重启服务器

##全局默认变量
DST_conf_dirname="DoNotStarveTogether"   
DST_conf_basedir="$HOME/.klei" 
DST_save_path="$HOME/.klei/DoNotStarveTogether"
DST_game_version="正式版"
DST_game_path="$HOME/dst"
DST_temp_path="$HOME/DST_Updatecheck/branch_DST"
# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
flag=1

#主菜单
function Main()
{
    clear
    echo "                                                                                  "
    echo "                                                                                  "
	printf  '=%.0s' {1..27}
    echo -e "  当前服务器版本为${DST_game_version}  \c"
    printf  '=%.0s' {1..27}
	while :
	do
		echo "                                                                                  "
		echo "     [1]更新服务器                [2]启动服务器         [3]关闭饥荒服务器"
		echo "                                                                                  "
		echo "     [4]查看游戏服务器状态         [5]控制台             [6]手动重启服务器"
		echo "                                                                                  "
		echo "     [7]更换服务器版本            [8]开启swap分区       [9]查看所有已下载mod"
		echo "                                                                                  "
		printf  '=%.0s' {1..80}
		echo "                                                                                  "
		echo -e "\e[92m请输入命令代号：\e[0m"
		read -r main1
		case $main1 in
			1)update_game break;;
			2)Startserver break;;
			3)CloseServer;;
			4)CheckServer break;;
			5)console ;;
			6)RestartServer ;;
			7)change_game_version ;;
			8)Openswapchoose ;;
			9)listallmod break;;
		esac
    done
}

# 自动更新
function auto_update()
{
	Cluster_bath="${DST_save_path}"/"$cluster_name"
	cd "$HOME" || exit
	cd "${Cluster_bath}" || exit
	# 配置auto_update.sh
	printf "%s" "#!/bin/bash
	##配置常量
	DST_has_game_update=false
	DST_now=\$(date +\"%D %T\")
	# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
	flag=$flag
	#查看进程执行情况
	function CheckProcess()
	{
		# 1:地上地下都有 2:只有地上 3:啥也没有 4:只有地下
		if [ \"\$flag\" == 1 ]; then
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -lt 1 || \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -lt 1 ]]; then
				RestartServer
			fi
		elif [ \"\$flag\" == 2 ]; then
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -lt 1 ]]; then
				RestartServer
			fi
		elif [ \"\$flag\" == 4 ]; then
			if [[ \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -lt 1 ]]; then
				RestartServer
			fi
		fi
	}
	#查看游戏更新情况
	function CheckUpdate()
	{
		#先更新服务器副本文件
		cd $HOME/steamcmd || exit
		if [[ \"${DST_game_version}\" == \"测试版\" ]]; then
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
		if flock \"${DST_temp_path}/version_copy.txt\" -c \"! diff -q \"${DST_temp_path}/version_copy.txt\" \"${DST_game_path}/version.txt\" > /dev/null\" ; then
		    DST_has_game_update=true
			echo -e \"\e[93m\"\"\${DST_now}\"\": 游戏服务端有更新!\e[0m\"	
			UpdateServer
		else
		    DST_has_game_update=false
			echo -e \"\e[93m\"\"\${DST_now}\"\": 游戏服务端没有更新!\e[0m\"	
		fi
	}
	#查看游戏mod更新情况
	function CheckModUpdate()
	{
		echo \"\"\"\${DST_now}\"\": 同步服务端更新进程正在运行。。。\"
		if [[ \$(grep \"is out of date and needs to be updated for new users to be able to join the server\" -c \"\"${masterchatlog_path}\"\") -gt  0 ]]; then
		DST_has_mods_update=true
		DST_now=\$(date +\"%D %T\")
		echo -e \"\e[93m\"\"\${DST_now}\"\": Mod 有更新！\e[0m\"
		else
			DST_has_mods_update=false
			echo -e \"\e[92m\${DST_now}: Mod 没有更新!\e[0m\"
		fi
		if [  \${DST_has_mods_update} == true ]; then
			RestartServer
		fi
	}
	# 重启服务器
	function RestartServer()
	{
		Shutdown
		StartServer
	}
	# 更新服务器
	function UpdateServer()
	{
		Shutdown
		cd $HOME/steamcmd || exit
		if [[ \"${DST_game_version}\" == \"测试版\" ]]; then
			echo \"正在同步测试版游戏服务端。\"
			./steamcmd.sh +force_install_dir \"$HOME/dst_beta\" +login anonymous +app_update 343050 -beta anewreignbeta validate +quit
		else
			echo \"正在同步正式版游戏服务端。\"
			./steamcmd.sh +force_install_dir \"$HOME/dst\" +login anonymous +app_update 343050 validate +quit 
		fi
		DST_has_game_update=false
		StartServer
	}

	# 关闭服务器
	function Shutdown()
	{
		if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -gt 0 || \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -gt 0 || \$(screen -ls | grep -c \"DST $cluster_name AutoUpdate\") -gt 0 ]]; then
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -gt 0  ]]; then
				for i in \$(screen -ls | grep -w \"DST_Master $cluster_name\" | awk '/[0-9]{1,}\./ {print strtonum(\$1)}')
				do
					screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"服务器需要重启，给您带来的不便还请谅解！！！\\\") \$(printf \\\\r)\"
					sleep 2
					screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"服务器需要重启，给您带来的不便还请谅解！！！\\\") \$(printf \\\\r)\"
					sleep 2
					screen -S \"\$i\" -p 0 -X stuff \"c_announce(\\\"服务器需要重启，给您带来的不便还请谅解！！！\\\") \$(printf \\\\r)\"
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
	function StartServer()
	{
		Addmod
		screen -dmS  \"DST_Master $cluster_name\" /bin/sh -c \"${DST_save_path}/$cluster_name/startmaster.sh\"
		screen -dmS  \"DST_Caves $cluster_name\" /bin/sh -c \"${DST_save_path}/$cluster_name/startcaves.sh\"
		while :
		do
			sleep 1
			if [[ \$(screen -ls | grep -c \"DST_Master $cluster_name\") -gt 0 || \$(screen -ls | grep -c \"DST_Caves $cluster_name\") -lt 0 ]]; then
				break
			fi
		done
	}
	#自动添加存档所需的mod
	function Addmod()
	{
		echo \"正在将开启存档所需的mod添加进服务器配置文件中。。。\"
		cd \"${DST_game_path}\"/mods || exit
		rm -rf dedicated_server_mods_setup.lua
		sleep 0.1
			grep \"\\\"workshop\" < \"${DST_conf_basedir}/${DST_conf_dirname}/$cluster_name/Master/modoverrides.lua\" | cut -d '\"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
			do
				echo \"ServerModSetup(\"\"\$line\"\")\">>${DST_game_path}/mods/dedicated_server_mods_setup.lua
				echo \"ServerModCollectionSetup(\"\"\$line\"\")\">>${DST_game_path}/mods/dedicated_server_mods_setup.lua
				sleep 0.5
				echo \"\$line Mod添加完成\"
			done
	}
	
	# 保持运行
	while :
			do
				DST_now=\$(date +\"%D %T\")
				CheckProcess
				CheckUpdate
				CheckModUpdate
				echo -e \"\\e[31m\"\"\${DST_now}\"\": 半小时后进行下一次循环检查！\\e\\ \"
				sleep 1
			done
	" > "${Cluster_bath}"/auto_update.sh
	chmod 777 "${Cluster_bath}"/auto_update.sh
	screen -dmS  "DST $cluster_name AutoUpdate" /bin/sh -c "${DST_save_path}/$cluster_name/auto_update.sh"
	echo "自动更新进程 DST $cluster_name AutoUpdate 已启动"
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
		grep "\"workshop" < "${DST_conf_basedir}/${DST_conf_dirname}/$cluster_name/Master/modoverrides.lua" | cut -d '"' -f 2 | cut -d '-' -f 2 | while IFS= read -r line
		do
			echo "ServerModSetup(\"$line\")">>"${DST_game_path}"/mods/dedicated_server_mods_setup.lua
			echo "ServerModCollectionSetup(\"$line\")">>"${DST_game_path}"/mods/dedicated_server_mods_setup.lua
			sleep 0.05
			echo "$line Mod添加完成"
		done
}
# 开启服务器
function Startserver()
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
		if [ -d "${DST_save_path}/$cluster_name" ]
		then 
			if [ -d "${DST_save_path}/$cluster_name/Master" ]; then
				flag=4
			else
				flag=5
			fi
			if [ -d "${DST_save_path}/$cluster_name/Caves" ] ; then
				flag=$((flag - 3))
			else
				flag=$((flag - 2))
			fi
			case $flag in
				1)addmod;StartMaster;StartCaves;auto_update;StartServerCheck;
				;;
				2)addmod;StartMaster;auto_update;StartServerCheck;
				;;
				3)echo "存档没有内容，请自行创建！！！"
				;;
				4)addmod;StartCaves;auto_update;StartServerCheck;
				;;
			esac
		else
			echo "存档不存在，请自行创建！！！" 
		fi
}
# 选择开启的存档
function Filechose()
{ 
	if [ -d "${DST_save_path}/$cluster_name/Master" ]; then
		flag=4
	else
		flag=5
	fi
	if [ -d "${DST_save_path}/$cluster_name/Caves" ] ; then
		flag=$((flag - 3))
	else
		flag=$((flag - 2))
	fi
	case $flag in
		1)addmod;StartMaster;StartCaves;auto_update;StartServerCheck;
		;;
		2)addmod;StartMaster;auto_update;StartServerCheck;
		;;
		3)echo "存档没有内容，请自行创建！！！"
		;;
		4)addmod;StartCaves;auto_update;StartServerCheck;
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
	run_shared+=(-persistent_storage_root ~/.klei -conf_dir DoNotStarveTogether)
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
	run_shared+=(-persistent_storage_root ~/.klei -conf_dir DoNotStarveTogether)
	run_shared+=(-cluster $cluster_name)
	run_shared+=(-monitor_parent_process $)
	\"\${run_shared[@]}\" -shard Master " > "${DST_save_path}"/"$cluster_name"/startmaster.sh
	cd "${DST_save_path}"/"$cluster_name" || exit
	chmod u+x ./startmaster.sh
	cd "$HOME" || exit
	screen -dmS  "DST_Master $cluster_name" /bin/sh -c "${DST_save_path}/$cluster_name/startmaster.sh"
}
#检查是否成功开启
function StartServerCheck()
{
	masterchatlog_path="${DST_conf_basedir}/${DST_conf_dirname}/$cluster_name/Master/server_log.txt"
	caveschatlog_path="${DST_conf_basedir}/${DST_conf_dirname}/$cluster_name/Caves/server_log.txt"
	
	if [ "$(screen -ls | grep -c "DST_Master $cluster_name")" -gt 0 ];then
		while :
		do
			sleep 2
			echo "地上服务器开启中，请稍后。。。"
			if [[ $(grep "Sim paused" -c "$masterchatlog_path") -gt 0 ]];then
				echo "地上服务器开启成功！！！"
				break
			fi
			if [[ $(grep "Your Server Will Not Start !!!" -c "$masterchatlog_path") -gt 0 ]]; then
				echo "服务器开启未成功，请执行关闭服务器命令后再次尝试，并注意令牌是否成功设置且有效。"
				break
			fi
		done
		echo 
	fi
	if [ "$(screen -ls | grep -c "DST_Caves $cluster_name")" -gt 0 ];then
		while :
		do
			sleep 1
			echo "地下服务器开启中，请稍后。。。"
			if [[ $(grep "Sim paused" -c "$caveschatlog_path") -gt 0 ]];then
				echo "地下服务器开启成功!!"
				break
			fi
			if [[ $(grep "Your Server Will Not Start !!!" -c "$caveschatlog_path") -gt 0 ]]; then
				echo "服务器开启未成功，请执行关闭服务器命令后再次尝试，并注意令牌是否成功设置且有效。"
				break
			fi
		done
	fi
	echo "服务器开启成功，和小伙伴尽情玩耍吧！！！"
}
# 关闭服务器
function CloseServer()
{
	screen -ls
	echo ""
	printf  '=%.0s' {1..28}
	echo -e "请输入要关闭的存档名\c"
	printf  '=%.0s' {1..28}
	echo ""
	read -r cluster_name
	echo ""
	if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0 || $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0 || $(screen -ls | grep -c "DST $cluster_name AutoUpdate") -gt 0 ]]; then
		if [[ $(screen -ls | grep -c "DST $cluster_name AutoUpdate") -gt 0  ]]; then
			for i in $(screen -ls | grep -w "DST $cluster_name AutoUpdate" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				kill "$i"
			done
		else
			echo "$cluster_name 这个存档没有开启自动更新！！！"
		fi
		if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0  ]]; then
			for i in $(screen -ls | grep -w "DST_Master $cluster_name" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地上服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地上服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地上服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
				echo "地上服务器已关闭！！！"
				sleep 1
			done
		else
			echo "$cluster_name 这个存档没有开启地上服务器！！！！！！"
		fi

		if [[ $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0  ]]; then

			for i in $(screen -ls | grep -w "DST_Caves $cluster_name" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地下服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地下服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地下服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
				echo "地下服务器已关闭！！！"
				sleep 1
			done
		else
			echo "$cluster_name 这个存档没有开启地下服务器！！！！！！"
		fi
			
			while :
			do
				sleep 1
				if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0 || $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0 ]]; then
					echo -e "\e[92m服务器 $cluster_name 正在关闭,请稍后。。。\e[0m"
				else
				 	echo -e "\e[92m服务器 $cluster_name 已关闭!!!\e[0m"
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
function RestartServer()
{
	screen -ls
	echo ""
	printf  '=%.0s' {1..28}
	echo -e "请输入要关闭的存档名\c"
	printf  '=%.0s' {1..28}
	echo ""
	read -r cluster_name
	echo ""
	if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0 || $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0 || $(screen -ls | grep -c "DST $cluster_name AutoUpdate") -gt 0 ]]; then
		if [[ $(screen -ls | grep -c "DST $cluster_name AutoUpdate") -gt 0  ]]; then
			for i in $(screen -ls | grep -w "DST $cluster_name AutoUpdate" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				kill "$i"
			done
			else
				echo "$cluster_name 这个存档没有开启自动更新！！！"
		fi
		if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0  ]]; then
			for i in $(screen -ls | grep -w "DST_Master $cluster_name" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地上服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地上服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地上服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
				echo "地上服务器已关闭！！！"
				sleep 1
			done
		else
			echo "$cluster_name 这个存档没有开启地上服务器！！！！！！"
		fi

		if [[ $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0  ]]; then

			for i in $(screen -ls | grep -w "DST_Caves $cluster_name" | awk '/[0-9]{1,}\./ {print strtonum($1)}')
			do
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地下服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地下服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_announce(\"服务器需要重启，给您带来的不便还请谅解！！！\") $(printf \\r)"
				echo "地下服务器关服中！！！"
				sleep 2
				screen -S "$i" -p 0 -X stuff "c_shutdown(true) $(printf \\r)"
				echo "地下服务器已关闭！！！"
				sleep 1
			done
		else
			echo "$cluster_name 这个存档没有开启地下服务器！！！！！！"
		fi
			
			while :
			do
				sleep 1
				if [[ $(screen -ls | grep -c "DST_Master $cluster_name") -gt 0 || $(screen -ls | grep -c "DST_Caves $cluster_name") -gt 0 ]]; then
					echo -e "\e[92m服务器 $cluster_name 正在关闭,请稍后。。。\e[0m"
				else
				 	echo -e "\e[92m服务器 $cluster_name 已关闭!!!\e[0m"
					break
				fi
			done
			Filechose "$cluster_name"
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
# 查看游戏服务器状态
function CheckServer()
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
function listallmod()
{
	clear 
	echo "                                                                                  "
    echo "                                                                                  "
	printf  '=%.0s' {1..27}
    echo -e "  当前服务器已下载的mod如下： \c"
	printf  '=%.0s' {1..27}
	echo ""
	
	for i in $( ls -l "${DST_game_path}/mods"| awk '/^d/ {print $NF}' | cut -d '-' -f 2 )
    do
        if [[ -f "${DST_game_path}/mods/workshop-$i/modinfo.lua" ]]; then
	        name=$(grep "${DST_game_path}/mods/workshop-$i/modinfo.lua" -e "name =" | cut -d '"' -f 2 | head -1)	
	        echo -e "\e[92m$i\e[0m------\e[33m$name\e[0m" 
	    fi
    done
	echo ""
    printf  '=%.0s' {1..80}
}
# 准备环境
function PreLibrary()
{
	sudo dpkg --add-architecture i386
	sudo apt-get update -y
	sudo apt-get install lib32gcc1 -y
	sudo apt-get install lib32stdc++6 -y
	sudo apt-get install libcurl4-gnutls-dev:i386 -y
}
#前期准备
function prepare()
{
	
	if [[ ${DST_game_version} == "正式版" ]]; then
	 	DST_game_path="$HOME/dst"
		DST_temp_path="$HOME/DST_Updatecheck/branch_DST"
	elif [ ${DST_game_version} == "测试版" ]; then
		DST_game_path="$HOME/dst_beta"
		DST_temp_path="$HOME/DST_Updatecheck/branch_DST_Beta"
	fi
	if [ ! -d "./dst" ] || [ ! -d "./dst_beta"  ] || [ ! -d "./DST_Updatecheck"  ] || [ ! -d "./DST_Updatecheck/branch_DST"  ] || [ ! -d "./DST_Updatecheck/branch_DST_Beta"  ] ;then
	mkdir "$HOME/dst"
	mkdir "$HOME/dst_beta"
	mkdir "$HOME/DST_Updatecheck"
	mkdir "$HOME/DST_Updatecheck/branch_DST"
	mkdir "$HOME/DST_Updatecheck/branch_DST_Beta"
	fi
   	if [ ! -d "./steamcmd" ]
	then
	PreLibrary
	mkdir ./steamcmd
	mkdir "$HOME/.klei/DoNotStarveTogether"
	cd ./steamcmd || exit
	wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
	tar -xvzf steamcmd_linux.tar.gz
	spleep 1
	rm -f steamcmd_linux.tar.gz
	echo "正在下载游戏，请稍后。。。"
	if [[ ${DST_game_version} == "正式版" ]]; then
	    echo "游当前服务端版本为正式版！"
	    ./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
	else
        echo "当前服务端版本为测试版！"
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
		DST_temp_path="$HOME/DST_Updatecheck/branch_DST_Beta"
    else
        echo "更改服务端版本为正式版！"	
	    DST_game_version="正式版"
		DST_temp_path="$HOME/DST_Updatecheck/branch_DST"
    fi
    Main
}
# 更新游戏
function update_game()
{
	cd "$HOME" || exit
    echo "正在更新游戏，请稍后。。。更新之后重启服务器生效哦。。。"
	cd ./steamcmd || exit
    if [[ ${DST_game_version} == "正式版" ]]; then
	    echo "游当前服务端版本为正式版！"
	    ./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 validate +quit 
	else
        echo "当前服务端版本为测试版！"
	    ./steamcmd.sh  +force_install_dir "${DST_game_path}" +login anonymous  +app_update 343050 -beta anewreignbeta validate +quit
    fi
}
prepare
Main


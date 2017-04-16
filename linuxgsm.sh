#!/bin/bash
# Project: Game Server Managers - LinuxGSM
# Author: Daniel Gibbs
# License: MIT License, Copyright (c) 2017 Daniel Gibbs
# Purpose: Counter-Strike: Global Offensive | Server Management Script
# Contributors: https://github.com/GameServerManagers/LinuxGSM/graphs/contributors
# Documentation: https://github.com/GameServerManagers/LinuxGSM/wiki
# Website: https://gameservermanagers.com

# Debugging
if [ -f ".dev-debug" ]; then
	exec 5>dev-debug.log
	BASH_XTRACEFD="5"
	set -x
fi

version="170305"
rootdir="$(dirname $(readlink -f "${BASH_SOURCE[0]}"))"
selfname="$(basename $(readlink -f "${BASH_SOURCE[0]}"))"
servicename="${selfname}"
shortname="core"
servername="core"
gamename="core"
lockselfname=".${servicename}.lock"
steamcmddir="${rootdir}/steamcmd"
lgsmdir="${rootdir}/lgsm"
functionsdir="${lgsmdir}/functions"
libdir="${lgsmdir}/lib"
tmpdir="${lgsmdir}/tmp"
serverfiles="${rootdir}/serverfiles"
configdir="${lgsmdir}/config-lgsm"
configdirserver="${configdir}/${servername}"
configdirdefault="${lgsmdir}/config-default"


## GitHub Branch Select
# Allows for the use of different function files
# from a different repo and/or branch.
githubuser="GameServerManagers"
githubrepo="LinuxGSM"
githubbranch="feature/config"

# Core Function that is required first
core_functions.sh(){
	functionfile="${FUNCNAME}"
	fn_bootstrap_fetch_file_github "lgsm/functions" "core_functions.sh" "${functionsdir}" "chmodx" "run" "noforcedl" "nomd5"
}

# Bootstrap
# Fetches the core functions required before passed off to core_dl.sh

# Fetches core functions
fn_bootstrap_fetch_file(){
	remote_fileurl="${1}"
	local_filedir="${2}"
	local_filename="${3}"
	chmodx="${4:-0}"
	run="${5:-0}"
	forcedl="${6:-0}"
	md5="${7:-0}"
	# If the file is missing, then download
	if [ ! -f "${local_filedir}/${local_filename}" ]; then
		if [ ! -d "${local_filedir}" ]; then
			mkdir -p "${local_filedir}"
		fi
		# Defines curl path
		curl_paths_array=($(command -v curl 2>/dev/null) $(which curl >/dev/null 2>&1) /usr/bin/curl /bin/curl /usr/sbin/curl /sbin/curl)
		for curlpath in "${curl_paths_array}"
		do
			if [ -x "${curlpath}" ]; then
				break
			fi
		done
		# If curl exists download file
		if [ "$(basename ${curlpath})" == "curl" ]; then
			# trap to remove part downloaded files
			echo -ne "    fetching ${local_filename}...\c"
			curlcmd=$(${curlpath} -s --fail -L -o "${local_filedir}/${local_filename}" "${remote_fileurl}" 2>&1)
			local exitcode=$?
			if [ ${exitcode} -ne 0 ]; then
				echo -e "\e[0;31mFAIL\e[0m\n"
				echo -e "${remote_fileurl}" | tee -a "${scriptlog}"
				echo "${curlcmd}" | tee -a "${scriptlog}"
				exit 1
			else
				echo -e "\e[0;32mOK\e[0m"
			fi
		else
			echo "[ FAIL ] Curl is not installed"
			exit 1
		fi
		# make file chmodx if chmodx is set
		if [ "${chmodx}" == "chmodx" ]; then
			chmod +x "${local_filedir}/${local_filename}"
		fi
	fi

	if [ -f "${local_filedir}/${local_filename}" ]; then
		# run file if run is set
		if [ "${run}" == "run" ]; then
			source "${local_filedir}/${local_filename}"
		fi
	fi
}

fn_bootstrap_fetch_file_github(){
	github_file_url_dir="${1}"
	github_file_url_name="${2}"
	githuburl="https://raw.githubusercontent.com/${githubuser}/${githubrepo}/${githubbranch}/${github_file_url_dir}/${github_file_url_name}"

	remote_remote_fileurl="${githuburl}"
	local_local_filedir="${3}"
	local_local_filename="${github_file_url_name}"
	chmodx="${4:-0}"
	run="${5:-0}"
	forcedldl="${6:-0}"
	md5="${7:-0}"
	# Passes vars to the file download function
	fn_bootstrap_fetch_file "${remote_remote_fileurl}" "${local_local_filedir}" "${local_local_filename}" "${chmodx}" "${run}" "${forcedldl}" "${md5}"
}

# Installer menu

fn_print_center() {
	columns="$(tput cols)"
	line="$@"
	printf "%*s\n" $(( (${#line} + columns) / 2)) "${line}"
}

fn_print_horizontal(){
	char="${1:-=}"
	printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' "${char}"
}

# Bash Menu
fn_install_menu_bash() {
	local resultvar=$1
	title=$2
	caption=$3
	options=$4
	fn_print_horizontal
	fn_print_center $title
	fn_print_center $caption
	fn_print_horizontal
	menu_options=()
	while read -r line || [[ -n "${line}" ]]; do
		var=$(echo "${line}" | awk -F "," '{print $2 " - " $3}')
		menu_options+=( "${var}" )
	done <  $options
	menu_options+=( "Cancel" )
	select option in "${menu_options[@]}"; do
		if [ -n "${option}" ] && [ "${option}" != "Cancel" ]; then
			eval "$resultvar=\"${option/%\ */}\""
		fi
		break
	done
}

# Whiptail/Dialog Menu
fn_install_menu_whiptail() {
	local menucmd=$1
	local resultvar=$2
	title=$3
	caption=$4
	options=$5
	height=${6:-40}
	width=${7:-80}
	menuheight=${8:-30}
	IFS=","
	menu_options=()
	while read -r line; do
		key=$(echo "${line}" | awk -F "," '{print $3}')
		val=$(echo "${line}" | awk -F "," '{print $2}')
		menu_options+=( ${val//\"} "${key//\"}" )
	done < $options
	OPTION=$(${menucmd} --title "${title}" --menu "${caption}" ${height} ${width} ${menuheight} "${menu_options[@]}" 3>&1 1>&2 2>&3)
	if [ $? == 0 ]; then
		eval "$resultvar=\"${OPTION}\""
	else
		eval "$resultvar="
	fi
}

# Menu selector
fn_install_menu() {
	local resultvar=$1
	local selection=""
	title=$2
	caption=$3
	options=$4
	# Get menu command
	for menucmd in whiptail dialog bash; do
		if [ -x $(which ${menucmd}) ]; then
			menucmd=$(which ${menucmd})
			break
		fi
	done
	case "$(basename ${menucmd})" in
		whiptail|dialog)
			fn_install_menu_whiptail "${menucmd}" selection "${title}" "${caption}" "${options}" 40 80 30;;
		*)
			fn_install_menu_bash selection "${title}" "${caption}" "${options}";;
	esac
	eval "$resultvar=\"${selection}\""
}

# Gets server info from serverlist.csv and puts in to array
fn_server_info(){
	IFS=","
	server_info_array=($(grep -a "${userinput}" "${serverlist}"))
	shortname="${server_info_array[0]}" # csgo
	servername="${server_info_array[1]}" # csgoserver
	gamename="${server_info_array[2]}" # Counter Strike: Global Offensive
}

fn_install_getopt(){
	userinput="empty"
	echo "Usage: $0 [option]"
	echo -e ""
	echo "Installer - Linux Game Server Managers - Version ${version}"
	echo "https://gameservermanagers.com"
	echo -e ""
	echo -e "Commands"
	echo -e "install |Select server to install."
	echo -e "servername |e.g $0 csgoserver. Enter the required servername will install it."
	echo -e "list |List all servers available for install."
	exit
}

fn_install_file(){
	local_filename="${servername}"
	if [ -e "${local_filename}" ]; then
		i=2
	while [ -e "${local_filename}-${i}" ] ; do
		let i++
	done
		local_filename="${local_filename}-${i}"
	fi
	cp -R "${selfname}" "${local_filename}"
	sed -i -e "s/shortname=\"core\"/shortname=\"${shortname}\"/g" "${local_filename}"
	sed -i -e "s/servername=\"core\"/servername=\"${servername}\"/g" "${local_filename}"
	sed -i -e "s/gamename=\"core\"/gamename=\"${gamename}\"/g" "${local_filename}"
	echo "Installed ${gamename} server as ${local_filename}"
	echo "./${local_filename} install"
	exit
}

# Prevent from running this script as root.
if [ "$(whoami)" == "root" ]; then
	if [ ! -f "${functionsdir}/core_functions.sh" ]||[ ! -f "${functionsdir}/check_root.sh" ]||[ ! -f "${functionsdir}/core_messages.sh" ]; then
		echo "[ FAIL ] Do NOT run this script as root!"
		exit 1
	else
		core_functions.sh
		check_root.sh
	fi
fi

# LinuxGSM installer mode
if [ "${shortname}" == "core" ]; then
	userinput=$1
	datadir="${lgsmdir}/data"
	serverlist="${datadir}/serverlist.csv"
	serverlist_tmp="${tmpdir}/data/serverlist.csv"

	# Download the serverlist. This is the complete list of all supported servers.
	# Download to tmp dir
	fn_bootstrap_fetch_file_github "lgsm/data" "serverlist.csv" "${tmpdir}/data" "serverlist.csv" "nochmodx" "norun" "noforcedl" "nomd5"
	# if missing in lgsm dir copy it accross
	if [ ! -f "${serverlist}" ]; then
		mkdir -p "${datadir}"
		cp -R "${serverlist_tmp}" "${serverlist}"
	# check if the files are different.
	else
		file_diff=$(diff -q "${serverlist_tmp}" "${serverlist}")
		if [ "${file_diff}" != "" ]; then
			cp -Rf "${serverlist_tmp}" "${serverlist}"
		fi
	fi

	if [ ! -f "${serverlist}" ];then
		echo "[ FAIL ] serverlist.csv could not be loaded."
		exit 1
	fi

	if [ "${userinput}" == "list" ]; then
		{
			awk -F "," '{print $2 "\t" $3}' "${serverlist}"
		} | column -s $'\t' -t | more
		exit
	elif [ "${userinput}" == "install" ]; then
		fn_install_menu result "LinuxGSM" "Select game to install" "lgsm/data/serverlist.csv"
		userinput="${result}"
		fn_server_info
		if [ "${result}" == "${servername}" ]; then
			fn_install_file
		elif [ "${result}" == "" ]; then
			echo "Install canceled"
		else
			echo "[ FAIL ] menu result does not match servername"
		fi
	elif [ -n "${userinput}" ]; then
		fn_server_info
		if [ "${userinput}" == "${servername}" ]; then
			fn_install_file
		fi
	else
		fn_install_getopt
	fi

# LinuxGSM Server Mode
else
	core_functions.sh

	# Load LinuxGSM configs
	# These are required to get all the default variables for the specific server.
	# Load the default config. If missing download it. If changed reload it.
	if [ ! -f "${configdirdefault}/config-lgsm/${servername}/_default.cfg" ];then
		mkdir -p "${configdirdefault}/config-lgsm/${servername}"
		fn_fetch_config "lgsm/config-default/config-lgsm/${servername}" "_default.cfg" "${configdirdefault}/config-lgsm/${servername}" "_default.cfg" "nochmodx" "norun" "noforcedl" "nomd5"
	fi
	if [ ! -f "${configdirserver}/_default.cfg" ];then
		mkdir -p "${configdirserver}"
		cp -R "${configdirdefault}/config-lgsm/${servername}/_default.cfg" "${configdirserver}/_default.cfg"
	else
		function_file_diff=$(diff -q ${configdirdefault}/config-lgsm/${servername}/_default.cfg ${configdirserver}/_default.cfg)
		if [ "${function_file_diff}" != "" ]; then
			echo "_default.cfg has been altered. Reloading config."
			cp -R "${configdirdefault}/config-lgsm/${servername}/_default.cfg" "${configdirserver}/_default.cfg"
		fi
	fi
	source "${configdirserver}/_default.cfg"
	# Load the common.cfg config. If missing download it
	if [ ! -f "${configdirserver}/common.cfg" ];then
		fn_fetch_config "lgsm/config-default/config-lgsm" "common-template.cfg" "${configdirserver}" "common.cfg" "${chmodx}" "nochmodx" "norun" "noforcedl" "nomd5"
		source "${configdirserver}/common.cfg"
	else
		source "${configdirserver}/common.cfg"
	fi
	# Load the instance.cfg config. If missing download it
	if [ ! -f "${configdirserver}/${servicename}.cfg" ];then
		fn_fetch_config "lgsm/config-default/config-lgsm" "instance-template.cfg" "${configdirserver}" "${servicename}.cfg" "nochmodx" "norun" "noforcedl" "nomd5"
		source "${configdirserver}/${servicename}.cfg"
	else
		source "${configdirserver}/${servicename}.cfg"
	fi
	getopt=$1
	core_getopt.sh
fi
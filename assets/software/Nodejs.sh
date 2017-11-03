#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://nodejs.org
#Target: Automatically Install & Update Node.js On GNU/Linux
#Writer: MaxdSre
#Date: Aug 23, 2017 11:46 Wed +0800
#Update Time:
# - May 22, 2017 02:34 Mon +0800
# - June 07, 2017 13:08 Wed +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'NJTemp_XXXXX'}
# trap '' HUP	#overlook SIGHUP when internet interrupted or terminal shell closed
# trap '' INT   #overlook SIGINT when enter Ctrl+C, QUIT is triggered by Ctrl+\
trap funcTrapINTQUIT INT QUIT

funcTrapINTQUIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    printf "Detect $(tput setaf 1)%s$(tput sgr0) or $(tput setaf 1)%s$(tput sgr0), begin to exit shell\n" "CTRL+C" "CTRL+\\"
    exit
}

#########  0-2. Variables Setting  #########
# term_cols=$(tput cols)   # term_lines=$(tput lines)
readonly c_bold="$(tput bold)"
readonly c_normal="$(tput sgr0)"     # c_normal='\e[0m'
# black 0, red 1, green 2, yellow 3, blue 4, magenta 5, cyan 6, gray 7
readonly c_red="${c_bold}$(tput setaf 1)"     # c_red='\e[31;1m'
readonly c_blue="$(tput setaf 4)"    # c_blue='\e[34m'
readonly official_site='https://nodejs.org'   #Node.js Official Site
readonly download_stable_page="${official_site}/en/download/"
readonly download_edge_page="${download_stable_page}current/"
readonly release_note_page="${official_site}/en/download/releases/"
readonly os_type='linux-x64'
software_fullname=${software_fullname:-'Nodejs'}
application_name=${application_name:-'Nodejs'}
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup
readonly temp_save_path='/tmp'      # Save Path Of Downloaded Packages
installation_path="/opt/${application_name}"      # Decompression & Installation Path Of Package
is_existed=${is_existed:-0}   # Default value is 0， check if system has installed Node.js

include_path="/usr/local/include/${application_name}"
ld_so_conf_path="/etc/ld.so.conf.d/${application_name}.conf"
profile_d_path="/etc/profile.d/${application_name}.sh"

version_check=${version_check:-0}
is_edge=${is_edge:-0}
is_uninstall=${is_uninstall:-0}
proxy_server=${proxy_server:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Installing / Updating Node.js (default stable) On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check current stable release version
    -e    --edge, choose edge version (default stable version)
    -p [protocol:]ip:port    --proxy host (http|https|socks4|socks5), default protocol is http
    -u    --uninstall, uninstall software installed
${c_normal}
EOF
}

funcExitStatement(){
    local str="$*"
    [[ -n "$str" ]] && printf "%s\n" "$str"
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    exit
}

funcCommandExistCheck(){
    # $? -- 0 is find, 1 is not find
    local name="$1"
    if [[ -n "$name" ]]; then
        local executing_path=${executing_path:-}
        executing_path=$(which "$name" 2> /dev/null || command -v "$name" 2> /dev/null)
        [[ -n "${executing_path}" ]] && return 0 || return 1
    else
        return 1
    fi
}

funcInitializationCheck(){
    # 1 - Check root or sudo privilege
    [[ "$UID" -ne 0 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script requires superuser privileges (eg. root, su)."
    # 2 - OS support check
    [[ -s /etc/os-release || -s /etc/SuSE-release || -s /etc/redhat-release || (-s /etc/debian_version && -s /etc/issue.net) ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script doesn't support your system!"

    # 3 - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && now_user="$USER" || now_user="$SUDO_USER"
    [[ "${now_user}" == 'root' ]] && user_home='/root' || user_home="/home/${now_user}"

    # CentOS/Fedora/OpenSUSE: xz   Debian/Ubuntu: xz-utils
    funcCommandExistCheck 'xz' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}xz${c_normal} command found, please install it (CentOS/OpenSUSE: xz   Debian/Ubuntu: xz-utils)!"

    funcCommandExistCheck 'tar' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}tar${c_normal} command found to decompress .tar.xz file!"

    funcCommandExistCheck 'sha256sum' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}sha256sum${c_normal} or ${c_blue}openssl${c_normal} command found, please install it!"
}

funcInternetConnectionCheck(){
    local gateway_ip=${gateway_ip:-}
    # CentOS: iproute Debian/OpenSUSE: iproute2
    if funcCommandExistCheck 'ip'; then
        gateway_ip=$(ip route | awk 'match($1,/^default/){print $3}')
    elif funcCommandExistCheck 'netstat'; then
        gateway_ip=$(netstat -rn | awk 'match($1,/^Destination/){getline;print $2;exit}')
    else
        funcExitStatement "${c_red}Error${c_normal}: No ${c_blue}ip${c_normal} or ${c_blue}netstat${c_normal} command found, please install it!"
    fi

    ! ping -q -w 1 -c 1 "$gateway_ip" &> /dev/null && funcExitStatement "${c_red}Error${c_normal}: No internet connection detected, disable ICMP? please check it!"   # Check Internet Connection
}

funcDownloadToolCheck(){
    local proxy_pattern="^((http|https|socks4|socks5):)?([0-9]{1,3}.){3}[0-9]{1,3}:[0-9]{1,5}$"
    proxy_server=${proxy_server:-}
    if [[ -n "${proxy_server}" ]]; then
        if [[ "${proxy_server}" =~ $proxy_pattern ]]; then
            local proxy_proto_pattern="^((http|https|socks4|socks5):)"
            if [[ "${proxy_server}" =~ $proxy_proto_pattern ]]; then
                local p_proto="${proxy_server%%:*}"
                local p_host="${proxy_server#*:}"
            else
                local p_proto='http'
                local p_host="${proxy_server}"
            fi
        else
            funcExitStatement "${c_red}Error${c_normal}: please specify right proxy host addr like ${c_blue}[protocol:]ip:port${c_normal}!"
        fi
    fi

    local retry_times=${retry_times:-5}
    local retry_delay_time=${retry_delay_time:-1}
    local connect_timeout_time=${connect_timeout_time:-2}
    local referrer_page=${referrer_page:-'https://duckduckgo.com/?q=github'}
    # local user_agent=${user_agent:-'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6.4) AppleWebKit/537.29.20 (KHTML, like Gecko) Chrome/60.0.3030.92 Safari/537.29.20'}

    if funcCommandExistCheck 'curl'; then
        download_tool="curl -fsL --retry ${retry_times} --retry-delay ${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-keepalive --referer ${referrer_page}"   # curl -s URL -o /PATH/FILE； -fsSL
        # --user-agent ${user_agent}

        if [[ -n "${proxy_server}" ]]; then
            local curl_version_no=${curl_version_no:-}
            curl_version_no=$(curl --version | sed -r -n '1s@.* ([[:digit:].]*) .*@\1@p')
            case "$p_proto" in
                http ) export http_proxy="${p_host}" ;;
                https ) export HTTPS_PROXY="${p_host}" ;;
                socks4 ) [[ "${curl_version_no}" > '7.21.7' ]] && download_tool="${download_tool} -x ${p_proto}a://${p_host}" || download_tool="${download_tool} --socks4a ${p_host}" ;;
                socks5 ) [[ "${curl_version_no}" > '7.21.7' ]] && download_tool="${download_tool} -x ${p_proto}h://${p_host}" || download_tool="${download_tool} --socks5-hostname ${p_host}" ;;
                * ) export http_proxy="${p_host}" ;;
            esac
        fi

    elif funcCommandExistCheck 'wget'; then
        download_tool="wget -qO- --tries=${retry_times} --waitretry=${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-http-keep-alive --referer=${referrer_page}" # wget -q URL -O /PATH/FILE
        # --user-agent=${user_agent}

        # local version_no=$(wget --version | sed -r -n '1s@.* ([[:digit:].]*) .*@\1@p')
        if [[ -n "$proxy_server" ]]; then
            if [[ "$p_proto" == 'https' ]]; then
                export https_proxy="${p_host}"
            else
                export http_proxy="${p_host}"
            fi
        fi
    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal} or ${c_blue}wget${c_normal}!"
    fi
}


#########  1-2 getopts Operation  #########
start_time=$(date +'%s')    # Start Time Of Operation

while getopts "hceup:" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        e ) is_edge=1 ;;
        u ) is_uninstall=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. Latest & Local Version Check  #########
funcVersionLocalCheck(){
    if [[ -f "${installation_path}/bin/node" ]]; then
        is_existed=1
        current_version_local=$("${installation_path}/bin/node" --version | sed -r -n 's@v([[:digit:].]*)@\1@p')
    fi
}

funcVersionOnlineCheck(){
    local release_type
    release_type=${release_type:-'Current'}
    declare -a latest_version_online_arr
    if [[ "${is_edge}" -eq 1 ]]; then
        release_type='LTS'
        latest_version_online_arr=($($download_tool "${download_edge_page}" | sed -r -n '/Latest Current Version/{s@.*Version:[[:space:]]*<[^>]*>([^<]+)<.*npm[[:space:]]*([[:digit:].]+).*@\1 \2@g;p}'))
    else
        latest_version_online_arr=($($download_tool "${download_stable_page}" | sed -r -n '/Latest LTS Version/{s@.*Version:[[:space:]]*<[^>]*>([^<]+)<.*npm[[:space:]]*([[:digit:].]+).*@\1 \2@g;p}'))
    fi

    [[ ${#latest_version_online_arr[*]} -eq 0 ]] && funcExitStatement "${c_red}Fatal error${c_normal}, fail to get online version on official site!"

    latest_version_online=${latest_version_online:-}
    latest_version_online=${latest_version_online_arr[0]}
    # latest_npm_version=${latest_version_online_arr[1]}

    [[ -z "${latest_version_online}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest online version on official site!"

    release_date=$($download_tool "${release_note_page}" | sed -r -n '/Version.*'"${latest_version_online}"'/,/Date/{/Date/{s@[[:space:]]*<[^>]*>[[:space:]]*@@g;p}}')

    if [[ "${version_check}" -eq 1 ]]; then
        if [[ "${is_existed}" -eq 1 ]]; then
            funcExitStatement "Local existed version is ${c_red}${current_version_local}${c_normal}, Latest ${c_blue}${release_type}${c_normal} version online is ${c_red}${latest_version_online}${c_normal} (${c_blue}${release_date}${c_normal})!"
        else
            funcExitStatement "Latest ${c_blue}${release_type}${c_normal} version online (${c_red}${latest_version_online}${c_normal}), Release date ($c_red${release_date}$c_normal)!"
        fi
    fi

    if [[ "${is_existed}" -eq 1 ]]; then
        if [[ "${latest_version_online}" == "${current_version_local}" ]]; then
            funcExitStatement "Latest ${c_blue}${release_type}${c_normal} version (${c_red}${latest_version_online}${c_normal}) has been existed in your system!"

        elif [[ "${latest_version_online}" < "${current_version_local}" ]]; then
            funcExitStatement "Existed version local (${c_red}${current_version_local}${c_normal}) > Latest ${c_blue}${release_type}${c_normal} version online (${c_red}${latest_version_online}${c_normal})!"

        elif [[ "${latest_version_online}" > "${current_version_local}" && -n "$current_version_local"  ]]; then
            printf "Existed version local (${c_red}%s${c_normal}) < Latest ${c_blue}%s${c_normal} version online (${c_red}%s${c_normal})!\n" "${current_version_local}" "${release_type}" "${latest_version_online}"
        fi
    else
        printf "No %s find in your system!\n" "${software_fullname}"
    fi
}


#########  2-2. Uninstall  #########
funcUninstallOperation(){
    [[ "${is_existed}" -eq 1 ]] || funcExitStatement "${c_blue}Note${c_normal}: no ${software_fullname} is found in your system!"

    [[ -d "${installation_path}" ]] && rm -rf "${installation_path}"
    [[ -d "${installation_path}${bak_suffix}" ]] && rm -rf "${installation_path}${bak_suffix}"

    local npm_path="${user_home}/.npm"
    [[ -d "${npm_path}" ]] && rm -rf "${npm_path}"    # ~/.npm/
    local node_repl_history_path="${user_home}/.node_repl_history"
    [[ -d "${node_repl_history_path}" ]] && rm -rf "${node_repl_history_path}"   # ~/.node_repl_history

    [[ -d "${include_path}" ]] && rm -rf "${include_path}"
    [[ -f "${ld_so_conf_path}" ]] && rm -rf "${ld_so_conf_path}"
    [[ -f "${profile_d_path}" ]] && rm -rf "${profile_d_path}"

    [[ -d "${installation_path}" ]] || funcExitStatement "${software_fullname} (v ${c_red}${current_version_local}${c_normal}) is successfully removed from your system!"

}


#########  2-3. Download & Decompress Latest Software  #########
funcDownloadAndDecompressOperation(){
    printf "Begin to download latest version ${c_red}%s${c_normal}, just be patient!\n" "${latest_version_online}"

    # Download the latest version while two versions compared different
    local pack_save_path="${temp_save_path}/node-v${latest_version_online}-${os_type}.tar.xz"
    local sha256_save_path="${temp_save_path}/SHASUMS256.txt"
    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
    [[ -f "${sha256_save_path}" ]] && rm -f "${sha256_save_path}"

    # https://nodejs.org/dist/v7.10.0/node-v7.10.0-linux-x64.tar.xz
    # https://nodejs.org/dist/v7.10.0/SHASUMS256.txt

    $download_tool "${official_site}/dist/v${latest_version_online}/node-v${latest_version_online}-${os_type}.tar.xz" > "$pack_save_path"

    $download_tool "${official_site}/dist/v${latest_version_online}/SHASUMS256.txt" > "$sha256_save_path"

    # grep node-vx.y.z.tar.gz SHASUMS256.txt | sha256sum -c -
    if [[ -f "${pack_save_path}" && -f "${sha256_save_path}" ]]; then
        cd "${temp_save_path}"
        grep "${pack_save_path##*/}" "${sha256_save_path##*/}" | sha256sum -c -- 1> /dev/null
        if [[ $? -eq 0 ]]; then
            printf "Package $c_blue%s$c_normal approves SHA-256 check!\n" "${pack_save_path##*/}"
        else
            funcExitStatement "${c_red}Error${c_normal}, package ${c_blue}${pack_save_path##*/}${c_normal} SHA-256 check inconsistency! The package may not be integrated!"
        fi

    else
        funcExitStatement "${c_red}Sorry${c_normal}: package download operation is faily!"
    fi

    local application_backup_path="${installation_path}${bak_suffix}"
    [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"

    [[ -d "${installation_path}" ]] && mv "${installation_path}" "${application_backup_path}"    # Backup Installation Directory
    [[ -d "${installation_path}" ]] || mkdir -p "${installation_path}"     # Create Installation Directory
    tar xf "${pack_save_path}" -C "${installation_path}" --strip-components=1    # Decompress To Target Directory

    local new_installed_version=${new_installed_version:-}
    new_installed_version=$("${installation_path}/bin/node" --version | sed -r -n 's@v([[:digit:].]*)@\1@p')    # Just Installed Version In System

    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
    [[ -f "${sha256_save_path}" ]] && rm -f "${sha256_save_path}"

    if [[ "${latest_version_online}" != "${new_installed_version}" ]]; then
        [[ -d "${installation_path}" ]] && rm -rf "${installation_path}"

        if [[ "${is_existed}" -eq 1 ]]; then
            mv "${application_backup_path}" "${installation_path}"
            funcExitStatement "${c_red}Sorry${c_normal}: ${c_blue}update${c_normal} operation is faily. ${software_fullname} has been rolled back to the former version!"
        else
            funcExitStatement "${c_red}Sorry${c_normal}: ${c_blue}install${c_normal} operation is faily!"
        fi

    else
        [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"
    fi
}



#########  2-4. Export include/lib/bin Path  #########
funcPostInstallationConfiguration(){
    # - include files
    ln -sv "${installation_path}/include" "${include_path}" 1> /dev/null
    # - lib files
    echo -e "${installation_path}/lib" > "${ld_so_conf_path}"
    ldconfig -v &> /dev/null    ##讓系統重新生成緩存
    # - bin path
    echo "export PATH=\$PATH:${installation_path}/bin" > "${profile_d_path}"
    # shellcheck source=/dev/null
    source "${profile_d_path}" 2> /dev/null

    if [[ "$is_existed" -eq 1 ]]; then
        printf "%s was updated to version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${latest_version_online}"
    else
        printf "Installing %s version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${latest_version_online}"
    fi

    printf "${c_bold}$c_blue%s$c_normal: You need to relogin to make Node.js effort!\n" 'Notice'
}


#########  2-5. Operation Time Cost  #########
funcTotalTimeCosting(){
    finish_time=$(date +'%s')        # End Time Of Operation
    total_time_cost=$((finish_time-start_time))   # Total Time Of Operation
    funcExitStatement "Total time cost is ${c_red}${total_time_cost}${c_normal} seconds!"
}


#########  3. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck

funcVersionLocalCheck
if [[ "${is_uninstall}" -eq 1 ]]; then
    funcUninstallOperation
else
    funcVersionOnlineCheck
    funcDownloadAndDecompressOperation
    funcPostInstallationConfiguration
    funcTotalTimeCosting
fi


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset software_fullname
    unset application_name
    unset bak_suffix
    unset installation_path
    unset is_existed
    unset include_path
    unset ld_so_conf_path
    unset profile_d_path
    unset version_check
    unset is_edge
    unset is_uninstall
    unset proxy_server
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

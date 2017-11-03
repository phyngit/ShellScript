#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://www.torproject.org/projects/torbrowser.html
#Verify Signature: https://www.torproject.org/docs/verifying-signatures.html
#Target: Automatically Install & Update Tor Browser On GNU/Linux
#Writer: MaxdSre
#Date: July 25, 2017 09:42 Tue +0800
#Update Time:
# - Feb 16, 2017 11:43 +0800
# - May 16, 2017 17:20 Tue -0400
# - June 07, 2017 17:23 Wed +0800


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'TBTemp_XXXXX'}
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
readonly official_site='https://www.torproject.org'
readonly download_page="${official_site}/projects/torbrowser.html"  # Download Page
readonly download_redirect_page='https://dist.torproject.org'           #安装包真实下载地址
readonly download_version="linux64"  # linux64
download_language='en-US' #英文 en-US, 中文 zh-TW
readonly key_server='pgp.mit.edu'     # pgp.mit.edu pool.sks-keyservers.net
readonly gnupg_key='0x4E2C6E8793298290'
software_fullname=${software_fullname:-'Tor Browser'}
application_name=${application_name:-'TorBrowser'}
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup
readonly temp_save_path='/tmp'      # Save Path Of Downloaded Packages
installation_path="/opt/${application_name}"      # Decompression & Installation Path Of Package
readonly pixmaps_png_path="/usr/share/pixmaps/${application_name}.png"
readonly application_desktop_path="/usr/share/applications/${application_name}.desktop"
is_existed=${is_existed:-0}   # Default value is 0， check if system has installed Mozilla Thunderbird

version_check=${version_check:-0}
is_uninstall=${is_uninstall:-0}
proxy_server=${proxy_server:-}

#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Installing / Updating Tor Browser On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check current stable release version
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

    # CentOS/Fedora/Debian/Ubuntu: gnupg2, OpenSUSE: gpg2
    if funcCommandExistCheck 'gpg2'; then
        gpg_tool='gpg2'
    elif funcCommandExistCheck 'gpg'; then
        gpg_tool='gpg'
    else
        funcExitStatement "${c_red}Error${c_normal}, no ${c_blue}gpg${c_normal} or ${c_blue}gpg2${c_normal} command found to verify GnuPG digit signature!"
    fi

    if [[ -s /etc/debian_version ]]; then
        funcCommandExistCheck 'dirmngr' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}dirmngr${c_normal} command found"
    fi

    # CentOS/Fedora/OpenSUSE: xz   Debian/Ubuntu: xz-utils
    funcCommandExistCheck 'xz' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}xz${c_normal} command found, please install it (CentOS/OpenSUSE: xz   Debian/Ubuntu: xz-utils)!"

    funcCommandExistCheck 'tar' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}tar${c_normal} command found to decompress .tar.xz file!"
}

funcInternetConnectionCheck(){
    # CentOS: iproute Debian/OpenSUSE: iproute2
    local gateway_ip=${gateway_ip:-}
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

while getopts "hcup:" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        u ) is_uninstall=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. Latest & Local Version Check  #########
funcVersionLocalCheck(){
    if [[ -f "${installation_path}/start-tor-browser.desktop" ]]; then
        is_existed=1
        current_version_local=$(sed -n -r '1,/^$/s@^Tor Browser (.*) --.*@\1@p' "${installation_path}/Browser/TorBrowser/Docs/ChangeLog.txt")
    fi
}

funcVersionOnlineCheck(){
    download_link_arr=($($download_tool "${download_page}" | sed -r -n '/Stable Tor/,/Experimental Tor/{/'"${download_language}"'/,/<\/tr>/{/'"${download_version}"'/s@.*href="../dist/(.*)".*@\1@pg}}'))  # pack file & sign file

    pack_download_link="${download_redirect_page}/${download_link_arr[0]}"    # 安装包真实下载链接
    pack_name=${pack_download_link##*/}   # 安装包名称
    sign_file_download_link="${download_redirect_page}/${download_link_arr[1]}"    # GnuPG签名文件真实下载链接
    sign_file_name=${sign_file_download_link##*/}    # 签名文件名称

    # https://dist.torproject.org/torbrowser/6.5.2/tor-browser-linux64-6.5.2_en-US.tar.xz
    # https://dist.torproject.org/torbrowser/6.5.2/tor-browser-linux64-6.5.2_en-US.tar.xz.asc

    latest_version_online=$(echo "${pack_download_link}" | sed -r -n 's@.*-(.*)_.*@\1@p')

    [[ -z "${latest_version_online}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest online version on official site!"

    if [[ "${version_check}" -eq 1 ]]; then
        if [[ "${is_existed}" -eq 1 ]]; then
            funcExitStatement "Local existed version is ${c_red}${current_version_local}${c_normal}, Latest version online is ${c_red}${latest_version_online}${c_normal}!"
        else
            funcExitStatement "Latest version online (${c_red}${latest_version_online}${c_normal})!"
        fi
    fi

    if [[ "${is_existed}" -eq 1 ]]; then
        if [[ "${latest_version_online}" == "${current_version_local}" ]]; then
            funcExitStatement "Latest version (${c_red}${latest_version_online}${c_normal}) has been existed in your system!"
        else
            printf "Existed version local (${c_red}%s${c_normal}) < Latest version online (${c_red}%s${c_normal})!\n" "${current_version_local}" "${latest_version_online}"
        fi
    else
        printf "No %s find in your system!\n" "${software_fullname}"
    fi
}


#########  2-2. Uninstall  #########
funcUninstallOperation(){
    [[ "${is_existed}" -eq 1 ]] || funcExitStatement "${c_blue}Note${c_normal}: no ${software_fullname} is found in your system!"

    [[ -f "${pixmaps_png_path}" ]] && rm -f "${pixmaps_png_path}"
    [[ -f "${application_desktop_path}" ]] && rm -f "${application_desktop_path}"

    [[ -d "${installation_path}" ]] && rm -rf "${installation_path}"
    [[ -d "${installation_path}${bak_suffix}" ]] && rm -rf "${installation_path}${bak_suffix}"

    [[ -d "${installation_path}" ]] || funcExitStatement "${software_fullname} (v ${c_red}${current_version_local}${c_normal}) is successfully removed from your system!"
}


#########  2-3. Download & Decompress Latest Software  #########
funcDownloadAndDecompressOperation(){
    printf "Begin to download latest version ${c_red}%s${c_normal}, just be patient!\n" "${latest_version_online}"
    # Download the latest version while two versions compared different
    pack_save_path="${temp_save_path}/${pack_name}"
    sign_file_save_path="${temp_save_path}/${sign_file_name}"

    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
    [[ -f "${sign_file_save_path}" ]] && rm -f "${sign_file_save_path}"

    $download_tool "${pack_download_link}" > "${pack_save_path}"     # 下載.tar.xz安裝包

    $download_tool "${sign_file_download_link}" > "${sign_file_save_path}"    # 下載GnuPG签名文件.tar.xz.asc

    # - Verify Signature
    $gpg_tool --list-key "${gnupg_key}" &> /dev/null      # 检查GnuPG Key是否安装，如未安装，则安装key
    if [[ $? -gt 0 ]]; then
        $gpg_tool --keyserver "${key_server}" --recv-keys "${gnupg_key}" &> /dev/null
    fi

    temp_signinfo_file=$(mktemp -t "${mktemp_format}")     #创建临时文件，用于保存文件校验信息
    $gpg_tool --verify "${sign_file_save_path}" "${pack_save_path}" 2> "${temp_signinfo_file}"

    local verify_result=${verify_result:-}
    verify_result=$(sed -n '/Good signature /p' "${temp_signinfo_file}")

    [[ -f "${temp_signinfo_file}" ]] && rm -f "${temp_signinfo_file}"

    if [[ "${verify_result}" == '' ]]; then
        [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
        [[ -f "${sign_file_save_path}" ]] && rm -f "${sign_file_save_path}"
        funcExitStatement "${c_red}Sorry${c_normal}: package GnuPG signature verified faily, please try it later again!"
    else
        printf "GnuPG signature verified info:\n${c_blue}%s${c_normal}\n" "$verify_result"
    fi

    # - Decompress
    local application_backup_path="${installation_path}${bak_suffix}"
    [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"

    [[ -d "${installation_path}" ]] && mv "${installation_path}" "${application_backup_path}"    # Backup Installation Directory
    [[ -d "${installation_path}" ]] || mkdir -p "${installation_path}"     # Create Installation Directory
    tar xf "${pack_save_path}" -C "${installation_path}" --strip-components=1    # Decompress To Target Directory

    local new_installed_version=${new_installed_version:-}
    local version_file="${installation_path}/Browser/TorBrowser/Docs/ChangeLog.txt"
    [[ -s "${version_file}" ]] && new_installed_version=$(sed -n -r '1,/^$/s@^Tor Browser[[:space:]]*([[:digit:].]+)[[:space:]]*.*@\1@gp' "${version_file}")   # Just Installed Version In System

    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"     #刪除安裝包
    [[ -f "${sign_file_save_path}" ]] && rm -f "${sign_file_save_path}"   #删除签名文件

    if [[ "${latest_version_online}" != "${new_installed_version}" ]]; then
        [[ -d "${installation_path}" ]] && rm -rf "${installation_path}"

        if [[ "${is_existed}" -eq 1 ]]; then
            mv "${application_backup_path}" "${installation_path}"
            funcExitStatement "${c_red}Sorry${c_normal}: ${c_blue}update${c_normal} operation is faily. ${software_fullname} has been rolled back to the former version!"
        else
            funcExitStatement "${c_red}Sorry${c_normal}: ${c_blue}install${c_normal} operation is faily!"
        fi

    else
        [[ -f "${pixmaps_png_path}" ]] && rm -f "${pixmaps_png_path}"
        [[ -f "${application_desktop_path}" ]] && rm -f "${application_desktop_path}"
        [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"
    fi
}


#########  2-4. Desktop Configuration  #########
funcDesktopFileConfiguration(){
tee "${application_desktop_path}" &> /dev/null <<-'EOF'
[Desktop Entry]
Encoding=UTF-8
Name=Tor Browser
GenericName[en]=Web Browser
Comment=Tor Browser is +1 for privacy and -1 for mass surveillance
Type=Application
Categories=Network;WebBrowser;Security;
Exec=installation_path/Browser/start-tor-browser %u
Icon=application_name.png
Terminal=false
StartupWMClass=Tor Browser
MimeType=text/html;text/xml;application/xhtml+xml;application/vnd.mozilla.xul+xml;text/mml;
EOF
sed -i -r 's@application_name@'"$application_name"'@g' "${application_desktop_path}"
sed -i -r 's@installation_path@'"$installation_path"'@g' "${application_desktop_path}"
}

funcDesktopConfiguration(){
    if [[ -d '/usr/share/applications' ]]; then
        [[ -f "${installation_path}/Browser/browser/chrome/icons/default/default48.png" ]] && ln -sf "${installation_path}/Browser/browser/chrome/icons/default/default48.png" "${pixmaps_png_path}"
        funcDesktopFileConfiguration
    fi

    if [[ "$is_existed" -eq 1 ]]; then
        printf "%s was updated to version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${latest_version_online}"
    else
        printf "Installing %s version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${latest_version_online}"
    fi

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
    funcDesktopConfiguration
    funcTotalTimeCosting
fi


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset download_language
    unset software_fullname
    unset application_name
    unset bak_suffix
    unset installation_path
    unset is_existed
    unset version_check
    unset is_uninstall
    unset proxy_server
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

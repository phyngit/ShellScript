#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://www.mozilla.org/en-US/firefox
#Target: Automatically Install & Update Mozilla Firefox On GNU/Linux
#Writer: MaxdSre
#Date: June 07, 2017 14:19 Wed +0800
#Update Time:
# - Feb 15, 2017 14:38 Wed +0800
# - May 15, 2017 09:30 Mon -0400


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'MFTemp_XXXXX'}
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
readonly official_site='https://www.mozilla.org/en-US/firefox/'   #Mozilla Firefox Official Site
readonly download_page="${official_site}all/"        # Download Page
readonly release_note_page="${official_site}notes/"
software_fullname=${software_fullname:-'Mozilla Firefox'}
lang=${lang:-'en-US'}  #英文 en-US, 中文 zh-TW
readonly os_type='linux-x86_64'
application_name=${application_name:-'mozillaFirefox'}
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup
readonly temp_save_path='/tmp'      # Save Path Of Downloaded Packages
installation_path="/opt/${application_name}"      # Decompression & Installation Path Of Package
readonly pixmaps_png_path="/usr/share/pixmaps/${application_name}.png"
readonly application_desktop_path="/usr/share/applications/${application_name}.desktop"
is_existed=${is_existed:-0}   # Default value is 0， check if system has installed Mozilla Thunderbird

version_check=${version_check:-0}
change_language=${change_language:-0}
is_uninstall=${is_uninstall:-0}
proxy_server=${proxy_server:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Installing / Updating Mozilla Firefox Web Browser On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check current stable release version
    -l    --change language to 'zh-TW', default is 'en-US'
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

    # CentOS/Debian/OpenSUSE: bzip2
    funcCommandExistCheck 'bzip2' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}bzip2${c_normal} command found, please install it (CentOS/Debian/OpenSUSE: bzip2)!"

    funcCommandExistCheck 'tar' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}tar${c_normal} command found to decompress .tar.bz2 file!"
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

while getopts "hclup:" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        l ) change_language=1 ;;
        u ) is_uninstall=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. Latest & Local Version Check  #########
# latest_version_online=$($download_tool $download_page | sed -n -r '/'"$download_version"' in '"$download_language"'/s@.*product=thunderbird-(.*)-SSL.*@\1@p')

funcVersionLocalCheck(){
    if [[ -f "${installation_path}/firefox" ]]; then
        is_existed=1
        current_version_local=$("${installation_path}/firefox" --version | awk '{print $NF}')
    fi
}

funcVersionOnlineCheck(){
    # latest_version_online=$($download_tool $download_page | sed -n -r '/'"$download_version"' in '"$download_language"'/s@.*product=firefox-(.*)-SSL.*@\1@p')
    latest_version_online=$($download_tool "${release_note_page}" | sed -r -n '/Firefox Release/{x;s@^[[:space:]]*@@g;s@<[^>]*>@@g;p};h')
    release_date=$($download_tool "${release_note_page}" | sed -r -n '/Firefox Release/{n;s@^[[:space:]]*@@;s@<[^>]*>@@g;p}')

    [[ -z "${latest_version_online}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest online version on official site!"

    if [[ "${version_check}" -eq 1 ]]; then
        if [[ "${is_existed}" -eq 1 ]]; then
            funcExitStatement "Local existed version is ${c_red}${current_version_local}${c_normal}, Latest version online is ${c_red}${latest_version_online}${c_normal} (${c_blue}${release_date}${c_normal})!"
        else
            funcExitStatement "Latest version online (${c_red}${latest_version_online}${c_normal}), Release date ($c_red${release_date}$c_normal)!"
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

    local config_path="${user_home}/.mozilla"
    [[ -d "${config_path}" ]] && rm -rf "${config_path}"    # ~/.mozilla
    local cache_path="${user_home}/.cache/mozilla"
    [[ -d "${cache_path}" ]] && rm -rf "${cache_path}"   # ~/.cache/mozilla

    [[ -d "${installation_path}" ]] || funcExitStatement "${software_fullname} (v ${c_red}${current_version_local}${c_normal}) is successfully removed from your system!"
}


#########  2-3. Download & Decompress Latest Software  #########
funcDownloadAndDecompressOperation(){
    printf "Begin to download latest version ${c_red}%s${c_normal}, just be patient!\n" "${latest_version_online}"

    # Download the latest version while two versions compared different
    local pack_save_path="${temp_save_path}/firefox-${latest_version_online}.tar.bz2"
    [[ -f "$pack_save_path" ]] && rm -f "$pack_save_path"

    [[ "${change_language}" -eq 1 ]] && lang='zh-TW'
    $download_tool "https://download-installer.cdn.mozilla.net/pub/firefox/releases/$latest_version_online/${os_type}/${lang}/firefox-${latest_version_online}.tar.bz2" > "${pack_save_path}"     # Download .tar.bz2 Installation Package

    local application_backup_path="${installation_path}${bak_suffix}"
    [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"

    [[ -d "${installation_path}" ]] && mv "${installation_path}" "${application_backup_path}"    # Backup Installation Directory
    [[ -d "${installation_path}" ]] || mkdir -p "${installation_path}"     # Create Installation Directory
    tar xf "${pack_save_path}" -C "${installation_path}" --strip-components=1    # Decompress To Target Directory

    local new_installed_version=${new_installed_version:-}
    new_installed_version=$("${installation_path}/firefox" --version | awk '{print $NF}')    # Just Installed Version In System

    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"

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
Name=Firefox Web Browser
GenericName[en]= firefox
Comment=Firefox web browser
Exec=installation_path/firefox %u
Icon=application_name.png
Terminal=false
Type=Application
StartupWMClass=Firefox-bin
MimeType=text/html;text/xml;application/xhtml+xml;application/vnd.mozilla.xul+xml;text/mml;application/x-xpinstall;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;
Categories=Network;WebBrowser;Application;
EOF
sed -i -r 's@application_name@'"$application_name"'@g' "${application_desktop_path}"
sed -i -r 's@installation_path@'"$installation_path"'@g' "${application_desktop_path}"
}

funcDesktopConfiguration(){
    if [[ -d '/usr/share/applications' ]]; then
        [[ -f "${installation_path}/browser/icons/mozicon128.png" ]] && ln -sf "${installation_path}/browser/icons/mozicon128.png" "${pixmaps_png_path}"
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
    unset software_fullname
    unset lang
    unset application_name
    unset bak_suffix
    unset installation_path
    unset is_existed
    unset version_check
    unset change_language
    unset is_uninstall
    unset proxy_server
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

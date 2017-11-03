#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://www.libreoffice.org
#Target: Automatically Install & Update LibreOffice On GNU/Linux
#Writer: MaxdSre
#Date: Oct 27, 2017 11:42 Fri +0800
#Update Time:
# - Mar 01, 2017 14:01~20:15 Wed +0800
# - May 19, 2017 15:12 Fri -0400
# - June 08, 2017 09:24 Thu +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'LOTemp_XXXXX'}
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

readonly official_site='https://www.libreoffice.org'   #LibreOffice Official Site
readonly download_page="${official_site}/download/download/"   # Download Page
readonly download_link='http://download.documentfoundation.org'   #真實下載鏈接(proximateVersion)
readonly old_archive_page='https://downloadarchive.documentfoundation.org/libreoffice/old/' #真實下載地址(preciseVersion)
software_fullname=${software_fullname:-'Libre Office'}
version_type=${version_type:-'still'}   # still, fresh
lang=${lang:-'en-US'}  #英文 en-US, 中文 zh-TW
lang_pack_existed=${lang_pack_existed:-0}   # 語言包是否存在

readonly arch=$(uname -m)    # hardware arch
readonly temp_save_path='/tmp'  # Save Path Of Downloaded Packages
is_existed=${is_existed:-0}  #判斷LibreOffice是否安裝，默認爲0 未安裝， 1 已安裝有

version_check=${version_check:-0}
fresh_version=${fresh_version:-0}
change_language=${change_language:-0}
is_uninstall=${is_uninstall:-0}
proxy_server=${proxy_server:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Installing / Updating Libre Office - Free Office Suite On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check current stable('still') release version
    -f    --choose latest 'fresh' version, default is mature 'still' version
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

    # CentOS/Debian/OpenSUSE: gzip
    funcCommandExistCheck 'gzip' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gzip${c_normal} command found, please install it (CentOS/Debian/OpenSUSE: gzip)!"

    funcCommandExistCheck 'tar' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}tar${c_normal} command found to decompress .tar.gz file!"

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

funcPackManagerCommandCheck(){
    if funcCommandExistCheck 'zypper'; then
        zypper ref -f &> /dev/null
        package_type='rpm'
        install_command='zypper in -ly'
        remove_command='zypper rm -y'
    elif funcCommandExistCheck 'yum'; then
        yum makecache fast 1> /dev/null
        package_type='rpm'
        install_command='yum localinstall -y'
        remove_command='yum erase -y'
    elif funcCommandExistCheck 'dnf'; then
        package_type='rpm'
        install_command='dnf install -y'
        remove_command='dnf remove -y'
    elif funcCommandExistCheck 'rpm'; then
        package_type='rpm'
        remove_command='rpm -e'
    elif funcCommandExistCheck 'apt-get'; then
        apt-get -yq update &> /dev/null
        package_type='deb'
        install_command='dpkg -i'
        remove_command='apt-get purge -y'
    elif funcCommandExistCheck 'dpkg'; then
        package_type='deb'
        install_command='dpkg -i'
        remove_command='dpkg -r'
    fi
}


#########  1-2 getopts Operation  #########
start_time=$(date +'%s')    # Start Time Of Operation

while getopts "hcflup:" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        f ) fresh_version=1 ;;
        l ) change_language=1 ;;
        u ) is_uninstall=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. Latest & Local Version Check  #########
funcVersionLocalCheck(){
    ls /usr/bin/libreoffice* &> /dev/null   # check binary program exists or not
    if [[ $? -eq 0 ]]; then
        is_existed=1
        for i in /usr/bin/libreoffice*;do
            [[ -e "${i}" ]] || break
            current_version_local=$($i --version | awk '{print $2;exit}')
            if [[ -n "${current_version_local}" ]]; then
                break
            fi
        done    # Endo for
    fi  #End if
}

funcVersionOnlineCheck(){
    [[ "${fresh_version}" -eq 1 ]] && version_type='fresh'

    # - Via Release Note Page, But Not Update In Time
    # https://www.libreoffice.org/download/release-notes

    # - Proximate Latest Version
    proximate_latest_version_list=$($download_tool "${download_page}" | sed -r -n '/released/{s@^.*<ul[^>]*>@@g;s@<\/a>@ @g;s@<[^>]*>@@g;s@[[:space:]]*$@@g;p}')
    [[ -z "${proximate_latest_version_list}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest ${c_blue}${version_type}${c_normal} proximate version on official site!"
    # 5.4.2 5.3.6
    fresh_proximate_version=${proximate_latest_version_list%% *}
    still_proximate_version=${proximate_latest_version_list##* }

    proximate_latest_version=${proximate_latest_version:-}
    case "${version_type,,}" in
        fresh ) proximate_latest_version="${fresh_proximate_version}" ;;
        still ) proximate_latest_version="${still_proximate_version}" ;;
    esac

    # - Precise Latest Version
    precise_latest_version_arr=($($download_tool "${old_archive_page}" | sed -r -n '/>'"${proximate_latest_version}"'/{s@.*<a href="([^"]*)">([^\/]*)\/<.*@\2'" ${old_archive_page}"'\1@g;p}' | sed -n '$p'))
    # 5.4.2.2 https://downloadarchive.documentfoundation.org/libreoffice/old/5.4.2.2/

    latest_version_online=${latest_version_online:-}

    if [[ $(echo ${#precise_latest_version_arr[@]}) -ne 0 ]]; then
        latest_version_online=${precise_latest_version_arr[0]}
    else
        funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest ${c_blue}${version_type}${c_normal} precise version on official site!"
    fi

    if [[ "${version_check}" -eq 1 ]]; then
        if [[ "${is_existed}" -eq 1 ]]; then
            funcExitStatement "Local existed version is ${c_red}${current_version_local}${c_normal}, Latest ${c_blue}${version_type}${c_normal} version online is ${c_red}${latest_version_online}${c_normal}!"
        else
            funcExitStatement "Latest ${c_blue}${version_type}${c_normal} version online (${c_red}${latest_version_online}${c_normal})!"
        fi
    fi

    if [[ "${is_existed}" -eq 1 ]]; then
        if [[ "${latest_version_online}" == "${current_version_local}" ]]; then
            funcExitStatement "Latest ${c_blue}${version_type}${c_normal} version (${c_red}${latest_version_online}${c_normal}) has been existed in your system!"
        elif [[ "${latest_version_online}" > "${current_version_local}" && -n "${current_version_local}" ]]; then
            printf "Existed version local ($c_red%s$c_normal) < Latest ${c_blue}${version_type}${c_normal} online version!\n" "$current_version_local" "$latest_version_online"
        fi

    else
        printf "No %s find in your system!\n" "${software_fullname}"
    fi
}


#########  2-2. Uninstall  #########
funcUninstallOperation(){
    [[ "${is_existed}" -eq 1 ]] || funcExitStatement "${c_blue}Note${c_normal}: no ${software_fullname} is found in your system!"

    ${remove_command} libreoffice* &> /dev/null

    local config_path="${user_home}/.config/libreoffice"
    [[ -d "${config_path}" ]] && rm -rf "${config_path}"    # ~/.config/libreoffice

    ls /usr/bin/libreoffice* &> /dev/null   # check binary program exists or not
    if [[ $? -gt 0 ]]; then
        funcExitStatement "${software_fullname} (v ${c_red}${current_version_local}${c_normal}) is successfully removed from your system!"
    fi
}


#########  2-3. Download & Decompress Latest Software  #########
# Custom function - sha256 verify
sha256VerifyFunc(){
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        if funcCommandExistCheck 'sha256sum'; then
            result=$(sha256sum "${file_path}" | awk '{print $1}')
        elif funcCommandExistCheck 'openssl'; then
            result=$(openssl dgst -sha256 "${file_path}" | awk '{print $NF}')
        fi  # End if
    else
        result=0    # file not exists
    fi  # End if
    echo $result
}

# Custom Function - Package Download & SHA-256 Verify
packDownloadFunc(){
    local pack_list="$1"
    local pack_save_name="$2"

    $download_tool "${pack_list}" > "${pack_save_name}"

    if [[ -f "${pack_save_name}" ]]; then
        local pack_sha256=${pack_sha256:-}
        pack_sha256=$(sha256VerifyFunc "${pack_save_name}")
        # echo "$pack_sha256"

        if [[ "${pack_sha256}" == 0 ]]; then
            [[ -f "${pack_save_name}" ]] && rm -f "${pack_save_name}"
            funcExitStatement "${c_red}Sorry${c_normal}: package ${c_blue}${pack_save_name}${c_normal} not exists!"
        else
            local pack_sha256_origin=${pack_sha256_origin:-}
            pack_sha256_origin=$($download_tool "${pack_list}.mirrorlist" | sed -n -r '/SHA-256/s@<[^>]*>@@g;s@.*Hash: (.*)@\1@gp')

            if [[ "${pack_sha256}" == "${pack_sha256_origin}" ]]; then
                printf "Package $c_blue%s$c_normal approves SHA-256 check!\n" "${pack_save_name##*/}"
            else
                [[ -f "${pack_save_name}" ]] && rm -f "${pack_save_name}"
                funcExitStatement "${c_red}Error${c_normal}, package ${c_blue}${pack_save_name##*/}${c_normal} SHA-256 check inconsistency! The package may not be integrated!"
            fi  # End if

        fi  # End if

    fi  # End if
}

decompressInstallationFileFunc(){
    local pack_save_name="$1"
    local pack_extrect_path="$2"
    local pack_type="$3"

    if [[ -f "${pack_save_name}" ]]; then
        [[ -d "${pack_extrect_path}" ]] && rm -rf "${pack_extrect_path}"
        mkdir -p "${pack_extrect_path}"
        tar xf "${pack_save_name}" -C "${pack_extrect_path}" --strip-components=1
        local pack_path="${pack_extrect_path}/${pack_type^^}S"
        if [[ -d "${pack_path}" ]]; then
            $install_command "${pack_path}"/*."${pack_type}" 1> /dev/null
        fi
    fi
}

funcRemoveTemporaryFiles(){
    if [[ -d "${temp_save_path}" ]]; then
        rm -rf "${temp_save_path}"/LibreOffice* &> /dev/null
    fi
}

funcInstallationOperation(){
    printf "Begin to download latest ${c_blue}%s${c_normal} version ${c_red}%s${c_normal}, just be patient!\n" "${version_type}" "${latest_version_online}"

    if [[ "${change_language}" -eq 1 ]]; then
        lang='zh-TW'
        lang_pack_existed=1
    fi

    # - Precise Version Link
    main_pack_link="${old_archive_page}${latest_version_online}/${package_type}/${arch}/LibreOffice_${latest_version_online}_Linux_${arch//_/-}_${package_type}.tar.gz"

    help_pack_link="${old_archive_page}${latest_version_online}/${package_type}/${arch}/LibreOffice_${latest_version_online}_Linux_${arch//_/-}_${package_type}_helppack_$lang.tar.gz"

    [[ "${lang_pack_existed}" -eq 1 ]] && lang_pack_link="${old_archive_page}${latest_version_online}/${package_type}/${arch}/LibreOffice_${latest_version_online}_Linux_${arch//_/-}_${package_type}_langpack_$lang.tar.gz"

    # - Temp Save Path
    main_pack_save_name="${temp_save_path}/LibreOffice_${latest_version_online}.${lang}.tar.gz"
    help_pack_save_name="${temp_save_path}/LibreOffice_helppack_${latest_version_online}.${lang}.tar.gz"
    [[ "${lang_pack_existed}" -eq 1 ]] && lang_pack_save_name="${temp_save_path}/LibreOffice_langpack_${latest_version_online}.${lang}.tar.gz"

    funcRemoveTemporaryFiles

    ### - Docnload & Verify Controller (Very Important) - ###
    packDownloadFunc "${main_pack_link}" "${main_pack_save_name}"
    packDownloadFunc "${help_pack_link}" "${help_pack_save_name}"
    [[ "${lang_pack_existed}" -eq 1 ]] &&  packDownloadFunc "${lang_pack_link}" "${lang_pack_save_name}"

    ###  - Decompression & Installation -  ###
    $remove_command libreoffice* &> /dev/null
    main_pack_extract_path="${temp_save_path}/LibreOffice"
    help_pack_extract_path="${temp_save_path}/LibreOffice_helppack"
    [[ "$lang_pack_existed" -eq 1 ]] &&  lang_pack_extract_path="${temp_save_path}/LibreOffice_langpack"
    # 不能放在同一個目錄中安裝，help的pack依賴mian中的pack

    if [[ "${is_existed}" -eq 1 ]]; then
        printf "Begin to ${c_red}%s${c_normal} ${software_fullname}!\n" "update"
    else
        printf "Begin to ${c_red}%s${c_normal} ${software_fullname}!\n" "install"
    fi

    ### - Decompression & Extraction & Installation Controller (Very Important) - ###
    decompressInstallationFileFunc "${main_pack_save_name}" "${main_pack_extract_path}" "${package_type}"
    decompressInstallationFileFunc "${help_pack_save_name}" "${help_pack_extract_path}" "${package_type}"
    [[ "${lang_pack_existed}" -eq 1 ]] && decompressInstallationFileFunc "${lang_pack_save_name}" "${lang_pack_extract_path}" "${package_type}"

    funcRemoveTemporaryFiles

    ls /usr/bin/libreoffice* &> /dev/null   # check binary program exists or not
    if [[ $? -eq 0 ]]; then
        for i in /usr/bin/libreoffice*;do
            [[ -e "${i}" ]] || break
            local new_installed_version=${new_installed_version:-}
            new_installed_version=$("$i" --version | awk '{print $2;exit}')    # Just Installed Version In System

            if [[ "${latest_version_online}" == "${new_installed_version}" ]]; then
                funcRemoveTemporaryFiles

                if [[ "$is_existed" -eq 1 ]]; then
                    printf "Successfully update %s to ${c_blue}%s${c_normal} version ${c_red}%s${c_normal}!\n" "${software_fullname}" "${version_type}" "${latest_version_online}"
                else
                    printf "Successfully install %s ${c_blue}%s${c_normal} version ${c_red}%s${c_normal}!\n" "${software_fullname}" "${version_type}" "${latest_version_online}"
                fi

            fi  # End if

            break
        done    # Endo for

    else
        funcExitStatement "${c_red}Sorry${c_normal}: fail to install ${software_fullname} , please try later again!"
    fi  #End if
}


#########  2-4. Operation Time Cost  #########
funcTotalTimeCosting(){
    finish_time=$(date +'%s')        # End Time Of Operation
    total_time_cost=$((finish_time-start_time))   # Total Time Of Operation
    funcExitStatement "Total time cost is ${c_red}${total_time_cost}${c_normal} seconds!"
}


#########  3. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
funcPackManagerCommandCheck

funcVersionLocalCheck
if [[ "${is_uninstall}" -eq 1 ]]; then
    funcUninstallOperation
else
    funcVersionOnlineCheck
    funcInstallationOperation
    funcTotalTimeCosting
fi


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset software_fullname
    unset version_type
    unset lang
    unset lang_pack_existed
    unset is_existed
    unset version_check
    unset is_uninstall
    unset proxy_server
    unset fresh_version
    unset change_language
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

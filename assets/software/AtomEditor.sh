#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://atom.io/
#Target: Automatically Install & Update Atom Text Editor On GNU/Linux
#Writer: MaxdSre
#Date: Sep 21, 2017 17:45 Thu +0800
#Update Time:


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'ATETemp_XXXXX'}
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
readonly official_site='https://atom.io/'   #Mozilla Thunderbird Official Site
software_fullname=${software_fullname:-'Atom Text Editor'}

application_name=${application_name:-'AtomTextEditor'}
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup
readonly temp_save_path='/tmp'      # Save Path Of Downloaded Packages
installation_path="/opt/${application_name}"      # Decompression & Installation Path Of Package
readonly pixmaps_png_path="/usr/share/pixmaps/${application_name}.png"
readonly application_desktop_path="/usr/share/applications/${application_name}.desktop"
is_existed=${is_existed:-1}   # Default value is 1， assume system has installed Atom Text Editor

version_check=${version_check:-0}
package_path=${package_path:-}
is_uninstall=${is_uninstall:-0}
proxy_server=${proxy_server:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Installing / Updating Atom Text Editor On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check current stable release version
    -f package_path    --specify Atom installation package path (e.g. /tmp/atom-amd64)
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

    # funcCommandExistCheck 'gawk' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gawk${c_normal} command found!"

    # error while loading shared libraries: libgconf-2.so.4: cannot open shared object file: No such file or directory
    # apt|libgconf2-4|/usr/lib/x86_64-linux-gnu/libgconf-2.so.4
    # zypper|gconf2|/usr/lib64/libgconf-2.so.4
    # yum|GConf2|/usr/lib64/libgconf-2.so.4
    if [[ -z $(find /usr -name 'libgconf-2.so.4' -print 2>/dev/null) ]]; then
        funcExitStatement "${c_red}Fatal Error${c_normal}: atom need shared libraries ${c_blue}libgconf-2.so.4${c_normal}, please install it first. (apt: libgconf2-4, zypper: gconf2, yum: GConf2)!"
    fi
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
    local referrer_page=${referrer_page:-'https://duckduckgo.com/?q=atom'}
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
start_time=$(date +'%s')    # processing start time

while getopts "hcf:p:u" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        f ) package_path="$OPTARG" ;;
        u ) is_uninstall=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. Latest & Local Version Check  #########
funcVersionLocalCheck(){
    if [[ -s "${installation_path}/atom" ]]; then
        current_version_local=$("${installation_path}/atom" --version 2>/dev/null | sed -r -n '/^Atom/{s@[^[:digit:]]*(.*)$@\1@g;p}')
    elif funcCommandExistCheck 'atom'; then
        current_version_local=$(atom --version 2>/dev/null | sed -r -n '/^Atom/{s@[^[:digit:]]*(.*)$@\1@g;p}')
    else
        is_existed=0
    fi
}

funcVersionOnlineCheck(){
    # https://developer.github.com/v3/repos/releases/#get-the-latest-release
    local release_info=${release_info:-}
    # relese version | release date | .tar.gz package download link
    release_info=$($download_tool https://api.github.com/repos/atom/atom/releases/latest | sed -r -n '/(tag_name|published_at|browser_download_url)/{/browser_download_url/{/.tar.gz/!d;/amd64/!d};s@[^:]*:[[:space:]]*"([^"]*)".*@\1@g;p}' | sed ':a;N;$!ba;s@\n@|@g;')

    latest_version_online=$(echo "${release_info}" | awk -F\| '{print gensub(/^[^[:digit:]]*(.*)/,"\\1","g",$1)}')
    [[ -z "${latest_version_online}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest online version!"

    release_date=$(echo "${release_info}" | awk -F\| '{print $2}' | date -f - +"%F" 2>/dev/null)

    pack_download_link=$(echo "${release_info}" | awk -F\| '{print $NF}')
    [[ -z "${pack_download_link}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get package download link!"

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

    local config_path="${user_home}/.atom"
    [[ -d "${config_path}" ]] && rm -rf "${config_path}"    # ~/.atom

    [[ -d "${installation_path}" ]] || funcExitStatement "${software_fullname} (v ${c_red}${current_version_local}${c_normal}) is successfully removed from your system!"
}


#########  2-3. Download & Decompress Latest Software  #########
funcDownloadAndDecompressOperation(){
    local l_package_path=${l_package_path:-}
    local pack_save_path=${pack_save_path:-}

    if [[ -n "${package_path}" && -s "${package_path}" ]]; then
        [[ "${package_path}" =~ .tar.gz$ ]] || funcExitStatement "${c_red}Sorry${c_normal}: package path (${c_blue}${package_path}${c_normal}) you specified is not actual and legal!"
        l_package_path="${package_path}"
    else
        printf "Begin to download latest version ${c_red}%s${c_normal}, just be patient!\n" "${latest_version_online}"
        # Download the latest version while two versions compared different
        [[ -z "${pack_download_link}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get package download link!"

        pack_save_path="${temp_save_path}/${pack_download_link##*/}"
        [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
        $download_tool "${pack_download_link}" > "${pack_save_path}"
        l_package_path="${pack_save_path}"
    fi

    printf "Begin to decompress package, just be patient!\n"

    local application_backup_path="${installation_path}${bak_suffix}"
    [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"

    [[ -d "${installation_path}" ]] && mv "${installation_path}" "${application_backup_path}"    # Backup Installation Directory

    [[ -d "${installation_path}" ]] || mkdir -p "${installation_path}"     # Create Installation Directory
    tar xf "${l_package_path}" -C "${installation_path}" --strip-components=1    # Decompress To Target Directory

    # Just Installed Version In System
    local new_installed_version=${new_installed_version:-}

    if [[ -s "${installation_path}/atom" ]]; then
        new_installed_version=$("${installation_path}/atom" --version 2>/dev/null | sed -r -n '/^Atom/{s@[^[:digit:]]*(.*)$@\1@g;p}')
    fi

    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"

    if [[ "${latest_version_online}" != "${new_installed_version}" ]]; then
        [[ -d "${installation_path}" ]] && rm -rf "${installation_path}"

        if [[ "${is_existed}" -eq 1 ]]; then
            mv "${application_backup_path}" "${installation_path}"
            funcExitStatement "${c_red}Sorry${c_normal}, ${c_blue}update${c_normal} operation is faily. ${software_fullname} has been rolled back to the former version!"
        else
            funcExitStatement "${c_red}Sorry${c_normal}, ${c_blue}install${c_normal} operation is faily!"
        fi

    else
        [[ -f "${pixmaps_png_path}" ]] && rm -f "${pixmaps_png_path}"
        [[ -f "${application_desktop_path}" ]] && rm -f "${application_desktop_path}"
        [[ -d "${application_backup_path}" ]] && rm -rf "${application_backup_path}"
    fi
}


#########  2-4. Executaion PATH Configuration  #########
funcExecuationPathConfiguration(){
    # add to PATH execution path
    local execute_path=${execute_path:-"/etc/profile.d/${application_name}.sh"}
    echo "export PATH=${installation_path}/atom:\$PATH" > "${execute_path}"

    apm_path=${apm_path:-"${installation_path}/resources/app/apm/bin/apm"}
    [[ -s "${apm_path}" ]] && echo "export PATH=${apm_path}:\$PATH" >> "${execute_path}"
    source "${execute_path}" 1> /dev/null
}


#########  2-5. Plug-in Installation & User References  #########
funcPluginsInstallation(){
    local config_path=${config_path:-"${user_home}/.atom"}
    [[ -d "${config_path}" ]] || mkdir -p "${config_path}"

tee "${config_path}/package.txt" &> /dev/null <<-'EOF'
atom-autocomplete-php
atom-bootstrap4
atom-runner
autocomplete-php
autocomplete-python
emmet
file-icons
go-plus
highlight-selected
markdown-preview-plus
minimap
php-twig
platformio-ide-terminal
python-autopep8
python-tools
EOF

# export packages info
# apm list --installed --bare > ~/.atom/package.txt
# import packages info
# apm install --packages-file ~/.atom/package.txt

    if [[ -s "${apm_path}" ]]; then
        printf "${c_red}Attention${c_normal}: if you wanna install plug-in, run the follow command in terminal:\n${c_blue}%s${c_normal}\n\n" "${apm_path} install --packages-file ${config_path}/package.txt"
        chown -R "${now_user}":"${now_user}" "${config_path}/package.txt"
    fi
}


funcUserReferenceConfiguration(){
    local config_path=${config_path:-"${user_home}/.atom"}
    [[ -d "${config_path}" ]] || mkdir -p "${config_path}"

tee "${config_path}/config.cson" &> /dev/null <<-'EOF'
"*":
  "autocomplete-python":
    showTooltips: true
    useSnippets: "all"
  core:
    autoHideMenuBar: true
    disabledPackages: [
      "github"
      "wrap-guide"
      "php-twig"
      "atom-autocomplete-php"
      "autocomplete-php"
      "markdown-preview"
    ]
    telemetryConsent: "no"
  editor:
    fontSize: 18
    softWrap: true
    tabLength: 4
  "exception-reporting":
    userId: "816448ac-4595-40c1-82f8-840b23b640df"
  "markdown-preview-plus":
    enableLatexRenderingByDefault: true
  "platformio-ide-terminal":
    core:
      mapTerminalsTo: "File"
      workingDirectory: "Active File"
    style:
      fontSize: "18"
      theme: "novel"
    toggles:
      autoClose: true
  welcome:
    showOnStartup: false
EOF

    chown -R "${now_user}":"${now_user}" "${config_path}"
}


#########  2-6. Desktop Configuration  #########
funcDesktopFileConfiguration(){
tee "${application_desktop_path}" &> /dev/null <<-'EOF'
[Desktop Entry]
Name=Atom
Comment=A hackable text editor for the 21st Century.
GenericName=Text Editor
Exec=installation_path/atom %F
Icon=application_name.png
Type=Application
StartupNotify=true
Categories=GNOME;GTK;Utility;TextEditor;Development;
MimeType=text/plain;
EOF
sed -i -r 's@application_name@'"$application_name"'@g' "${application_desktop_path}"
sed -i -r 's@installation_path@'"$installation_path"'@g' "${application_desktop_path}"
}

funcDesktopConfiguration(){
    if [[ -d '/usr/share/applications' ]]; then
        [[ -f "${installation_path}/atom.png" ]] && ln -sf "${installation_path}/atom.png" "${pixmaps_png_path}"
        funcDesktopFileConfiguration
    fi

    if [[ "$is_existed" -eq 1 ]]; then
        printf "%s was updated to version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${latest_version_online}"
    else
        printf "Installing %s version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${latest_version_online}"
    fi
}


#########  2-7. Operation Time Cost  #########
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
    funcExecuationPathConfiguration
    funcUserReferenceConfiguration
    funcDesktopConfiguration
    [[ "${is_existed}" -eq 1 ]] || funcPluginsInstallation
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
    unset version_check
    unset package_path
    unset is_uninstall
    unset proxy_server
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

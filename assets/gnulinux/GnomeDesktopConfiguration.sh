#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #IFS  Internal Field Separator


#Official Site: https://www.gnome.org/
#Documentation:
# - https://www.gnome.org/technologies/

#Target: Configuration GNOME 3 Desktop Enviroment In GNU/Linux
#Writer: MaxdSre
#Date: Sep 25, 2017 14:03 +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'G3CTemp_XXXXX'}

# trap '' HUP	#overlook SIGHUP when internet interrupted or terminal shell closed
# trap '' INT   #overlook SIGINT when enter Ctrl+C, QUIT is triggered by Ctrl+\
trap funcTrapINTQUIT INT QUIT

funcTrapINTQUIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    printf "Detect $(tput setaf 1)%s$(tput sgr0) or $(tput setaf 1)%s$(tput sgr0), begin to exit shell\n" "CTRL+C" "CTRL+\\"
    exit
}

#########  0-2. Variables Setting  #########
readonly c_bold="$(tput bold)"
readonly c_normal="$(tput sgr0)"
# black 0, red 1, green 2, yellow 3, blue 4, magenta 5, cyan 6, gray 7
readonly c_red="${c_bold}$(tput setaf 1)"
readonly c_blue="$(tput setaf 4)"

readonly temp_save_path='/tmp'      # Save Path Of Downloaded Packages

proxy_server=${proxy_server:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

GNOME 3 Desktop Enviroment Configuration In GNU/Linux (RHEL/SUSE/Debian)
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -p [protocol:]ip:port    --proxy host (http|https|socks4|socks5), default protocol is http
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
    # [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    # 4 - current login user detection
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && login_user="$USER" || login_user="$SUDO_USER"
    login_user_home=${login_user_home:-}
    login_user_home=$(awk -F: 'match($1,/^'"${login_user}"'$/){print $(NF-1)}' /etc/passwd)

    # 5 -  Check essential command    # CentOS/Debian/OpenSUSE: gzip
    # CentOS/Debian/OpenSUSE: gzip
    funcCommandExistCheck 'gzip' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gzip${c_normal} command found, please install it (CentOS/Debian/OpenSUSE: gzip)!"

    funcCommandExistCheck 'tar' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}tar${c_normal} command found to decompress .tar.gz file!"

    funcCommandExistCheck 'unzip' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}unzip${c_normal} command found!"

    funcCommandExistCheck 'curl' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}curl${c_normal} command found!"

    funcCommandExistCheck 'gawk' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gawk${c_normal} command found!"

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
    local referrer_page=${referrer_page:-'https://duckduckgo.com/?q=gnome'}
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

    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal}!"
    fi
}

funcPackageManagerDetection(){
    # OpenSUSE has utility apt-get, aptitude. Amazing
    if funcCommandExistCheck 'zypper'; then
        pack_manager='zypper'
    elif funcCommandExistCheck 'apt-get'; then
        pack_manager='apt-get'
    elif funcCommandExistCheck 'dnf'; then
        pack_manager='dnf'
    elif funcCommandExistCheck 'yum'; then
        pack_manager='yum'
    else
        funcExitStatement "${c_red}Sorry${c_normal}: can't find command ${c_blue}apt-get|yum|dnf|zypper${c_normal}."
    fi
}

funcPackageManagerOperation(){
    local action="${1:-'update'}"
    local package_lists=(${2:-})

    case "${pack_manager}" in
        apt-get )
            # disable dialog prompt
            export DEBIAN_FRONTEND=noninteractive
            # apt-get [options] command
            case "${action}" in
                install|in )
                    apt-get -yq install "${package_lists[@]}" &> /dev/null
                    ;;
                remove|rm )
                    apt-get -yq purge "${package_lists[@]}" &> /dev/null
                    apt-get -yq autoremove 1> /dev/null
                    ;;
                upgrade|up )
                    # https://askubuntu.com/questions/165676/how-do-i-fix-a-e-the-method-driver-usr-lib-apt-methods-http-could-not-be-foun#211531
                    # https://github.com/koalaman/shellcheck/wiki/SC2143
                    if ! dpkg --list | grep -q 'apt-transport-https'; then
                        apt-get -yq install apt-transport-https &> /dev/null
                    fi

                    apt-get -yq clean all 1> /dev/null
                    apt-get -yq update 1> /dev/null
                    apt-get -yq upgrade &> /dev/null
                    apt-get -yq dist-upgrade &> /dev/null
                    apt-get -yq autoremove 1> /dev/null
                    ;;
                * )
                    apt-get -yq clean all 1> /dev/null
                    apt-get -yq update 1> /dev/null
                    ;;
            esac

            unset DEBIAN_FRONTEND
            ;;
        dnf )
            # dnf [options] COMMAND
            case "${action}" in
                install|in )
                    dnf -yq install "${package_lists[@]}" &> /dev/null
                    ;;
                remove|rm )
                    dnf -yq remove "${package_lists[@]}" &> /dev/null
                    dnf -yq autoremove 2> /dev/null
                    ;;
                upgrade|up )
                    dnf -yq makecache &> /dev/null
                    dnf -yq upgrade &> /dev/null    #dnf has no command update
                    dnf -yq autoremove 2> /dev/null
                    ;;
                * )
                    dnf -yq clean all &> /dev/null
                    dnf -yq makecache fast &> /dev/null
                    ;;
            esac
            ;;
        yum )
            funcCommandExistCheck 'yum-complete-transaction' && yum-complete-transaction --cleanup-only &> /dev/null
            # yum [options] COMMAND
            case "${action}" in
                install|in )
                    yum -y -q install "${package_lists[@]}" &> /dev/null
                    ;;
                remove|rm )
                    yum -y -q erase "${package_lists[@]}" &> /dev/null
                    # yum -y -q remove "${package_lists[@]}" &> /dev/null
                    ;;
                upgrade|up )
                    yum -y -q makecache fast &> /dev/null
                    # https://www.blackmoreops.com/2014/12/01/fixing-there-are-unfinished-transactions-remaining-you-might-consider-running-yum-complete-transaction-first-to-finish-them-in-centos/
                    funcCommandExistCheck 'yum-complete-transaction' || yum -y -q install yum-utils &> /dev/null
                    yum -y -q update &> /dev/null
                    yum -y -q upgrade &> /dev/null
                    ;;
                * )
                    yum -y -q clean all &> /dev/null
                    yum -y -q makecache fast &> /dev/null
                    ;;
            esac
            ;;
        zypper )
            # zypper [--global-opts] command [--command-opts] [command-arguments]
            case "${action}" in
                install|in )
                    zypper in -yl "${package_lists[@]}" &> /dev/null
                    ;;
                remove|rm )
                    zypper rm -yu "${package_lists[@]}" &> /dev/null
                    zypper rm -yu $(zypper packages --unneeded | awk 'match($1,/^i/){ORS=" ";print $(NF-4)}') &> /dev/null  # remove unneeded packages
                    ;;
                upgrade|up )
                    zypper clean -a 1> /dev/null
                    zypper ref -f &> /dev/null
                    zypper up -yl 1> /dev/null
                    zypper dup -yl 1> /dev/null
                    zypper patch -yl 1> /dev/null
                    ;;
                * )
                    zypper clean -a 1> /dev/null
                    zypper ref -f &> /dev/null
                    ;;
            esac
            ;;
    esac
}


#########  1-2 getopts Operation  #########
while getopts "hp:" option "$@"; do
    case "$option" in
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. GNOME Extension Installation  #########
# - CustomCorner
funcCustomCornerInstallation(){
    local download_link=${download_link:-'https://gitlab.com/eccheng/customcorner/repository/master/archive.tar.gz'}
    local pack_save_path=${pack_save_path:="${temp_save_path}/${download_link##*/}"}
    $download_tool "${download_link}" > "${pack_save_path}"

    local gnome_extension_dir=${gnome_extension_dir:-"${login_user_home}/.local/share/gnome-shell/extensions/customcorner@eccheng.gitlab.com"}
    [[ -d "${gnome_extension_dir}" ]] && rm -rf "${gnome_extension_dir}"
    mkdir -p "${gnome_extension_dir}"
    tar xf "${pack_save_path}" -C "${gnome_extension_dir}" --strip-components=1

    local gnome_shell_version=${gnome_shell_version:-}
    gnome_shell_version=$(gnome-shell --version 2>/dev/null | sed -r -n '/GNOME Shell/{s@[^[:digit:]]*(.*)$@\1@g;p}')
    [[ -f "${gnome_extension_dir}/metadata.json" ]] && sed -i -r '/shell-version/s@("shell-version": \[\").*(\"\],)@\1'"${gnome_shell_version}"'\2@' "${gnome_extension_dir}/metadata.json"

    chown -R "${login_user}":"${login_user}" "${gnome_extension_dir}"
    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
}

# - Proxy Switcher
funcProxySwitcherInstattation(){
    local download_link=${download_link:-'https://github.com/tomflannaghan/proxy-switcher/archive/master.zip'}
    local pack_save_path=${pack_save_path:="${temp_save_path}/${download_link##*/}"}
    $download_tool "${download_link}" > "${pack_save_path}"

    local gnome_extension_dir=${gnome_extension_dir:-"${login_user_home}/.local/share/gnome-shell/extensions/ProxySwitcher@flannaghan.com"}
    [[ -d "${gnome_extension_dir}" ]] && rm -rf "${gnome_extension_dir}"
    mkdir -p "${gnome_extension_dir}"

    local temp_decompress_dir=${temp_decompress_dir:-"${temp_save_path}/proxy-switcher"}
    [[ -d "${temp_decompress_dir}" ]] && rm -rf "${temp_decompress_dir}"
    mkdir -p "${temp_decompress_dir}"

    unzip -q -d "${temp_decompress_dir}" "${pack_save_path}"
    local extract_dir_src=${extract_dir_src:-}
    extract_dir_src=$(find "${temp_decompress_dir}" -type d -name 'src' -print)
    [[ -d "${extract_dir_src}" ]] && cp -R "${extract_dir_src}"/* "${gnome_extension_dir}"
    # extension.js, messages.pot, metadata.json

    chown -R "${login_user}":"${login_user}" "${gnome_extension_dir}"
    [[ -f "${pack_save_path}" ]] && rm -f "${pack_save_path}"
    [[ -d "${temp_decompress_dir}" ]] && rm -rf "${temp_decompress_dir}"
}


#########  2-2. GNOME Tweak Tool Configuration  #########
# gsettings list-schemas
# gsettings list-keys
# gsettings list-schemas | sort | while IFS="" read -r schema; do gsettings list-keys "${schema}" | sort | while IFS="" read -r key; do echo "${schema}|${key}|$(gsettings get ${schema} ${key} 2>/dev/null)"; done; done

funcTweakToolConfiguration(){
    # - Desktop
    # Icons on Desktop
    gsettings set org.gnome.desktop.background show-desktop-icons false

    # centered|none|scaled|spanned|stretched|wallpater|zoom
    # Background - Mode (default: zoom)
    # gsettings set org.gnome.desktop.background picture-options 'zoom'
    # Lock Screen - Mode (default: zoom)
    # gsettings set org.gnome.desktop.screensaver picture-options|'zoom'

    # - Extensions
    # Applications menu|apps-menu@gnome-shell-extensions.gcampax.github.com
    # Place status indicator|places-menu@gnome-shell-extensions.gcampax.github.com
    # Window list|window-list@gnome-shell-extensions.gcampax.github.com
    # Removeable drive menu|drive-menu@gnome-shell-extensions.gcampax.github.com
    # Windownavigator|windowsNavigator@gnome-shell-extensions.gcampax.github.com
    # ProxySwitcher|ProxySwitcher@flannaghan.com
    # Customcorner|customcorner@eccheng.gitlab.com

    # gsettings get org.gnome.shell enabled-extensions

    # - Top Bar
    # gsettings get org.gnome.settings-daemon.plugins.xsettings overrides
    # "{'Gtk/ShellShowsAppMenu': <1>}"
    # show date (default false)
    gsettings set org.gnome.desktop.interface clock-show-date true
    # show seconds
    gsettings set org.gnome.desktop.interface clock-show-seconds false
    # Calendar - Show week numbers (default false)
    gsettings set org.gnome.desktop.calendar show-weekdate true

    # Date & Time
    gsettings set org.gnome.desktop.interface clock-format '24h'

    # - Windows
    # Titlebar Buttons (default close)
    gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'

    # - Workspaces
    # gsettings set org.gnome.desktop.wm.preferences num-workspaces 4
    gsettings set org.gnome.shell.overrides dynamic-workspaces true
    gsettings set org.gnome.shell.overrides workspaces-only-on-primary true

}


funcCommonReferencesConfiguration(){
    # - Desktop Privacy
    [[ -f "${login_user_home}/.local/share/recently-used.xbel" ]] && rm -f "${login_user_home}/.local/share/recently-used.xbel"

    # disappear recent button
    gsettings set org.gnome.desktop.privacy remember-recent-files false
    # disable record files opened recently, default is -1
    gsettings set org.gnome.desktop.privacy recent-files-max-age 0
    gsettings set org.gnome.desktop.privacy remember-app-usage false
    gsettings set org.gnome.desktop.privacy remove-old-temp-files true
    gsettings set org.gnome.desktop.privacy remove-old-trash-files true
    gsettings set org.gnome.desktop.privacy send-software-usage-stats false
    gsettings set org.gnome.desktop.privacy show-full-name-in-top-bar true

    # - Login Screen
    gsettings set org.gnome.login-screen disable-restart-buttons false
    gsettings set org.gnome.login-screen disable-user-list false
    gsettings set org.gnome.login-screen allowed-failures 3
    gsettings set org.gnome.login-screen banner-message-enable false
    gsettings set org.gnome.login-screen banner-message-text ''
    gsettings set org.gnome.login-screen enable-fingerprint-authentication true
    gsettings set org.gnome.login-screen enable-password-authentication true
    gsettings set org.gnome.login-screen enable-smartcard-authentication true
    gsettings set org.gnome.login-screen fallback-logo ''
    gsettings set org.gnome.login-screen logo ''

    # - Network Proxy
    # 'none'|'manual'|'auto'
    # org.gnome.system.proxy|mode|'none'
    # automatic
    # org.gnome.system.proxy|autoconfig-url|''
    # Manually
    # org.gnome.system.proxy|ignore-hosts|['localhost', '127.0.0.0/8', '::1']
    # org.gnome.system.proxy|use-same-proxy|true
    # org.gnome.system.proxy.ftp|host|''
    # org.gnome.system.proxy.ftp|port|0
    # org.gnome.system.proxy.http|authentication-password|''
    # org.gnome.system.proxy.http|authentication-user|''
    # org.gnome.system.proxy.http|enabled|false
    # org.gnome.system.proxy.http|host|''
    # org.gnome.system.proxy.http|port|0
    # org.gnome.system.proxy.http|use-authentication|false
    # org.gnome.system.proxy.https|host|''
    # org.gnome.system.proxy.https|port|0
    # org.gnome.system.proxy.socks|host|''
    # org.gnome.system.proxy.socks|port|0

    # - Terminal
    # gsettings set org.gnome.desktop.default-applications.terminal exec 'x-terminal-emulator'

    gsettings set org.gnome.Terminal.Legacy.Settings confirm-close true
    gsettings set org.gnome.Terminal.Legacy.Settings default-show-menubar false
    # gsettings set org.gnome.Terminal.Legacy.Settings encodings ['UTF-8']
    gsettings set org.gnome.Terminal.Legacy.Settings menu-accelerator-enabled true
    gsettings set org.gnome.Terminal.Legacy.Settings mnemonics-enabled false
    gsettings set org.gnome.Terminal.Legacy.Settings new-terminal-mode 'tab'
    # gsettings set org.gnome.Terminal.Legacy.Settings schema-version uint32 3
    gsettings set org.gnome.Terminal.Legacy.Settings shell-integration-enabled true
    gsettings set org.gnome.Terminal.Legacy.Settings shortcuts-enabled true
    gsettings set org.gnome.Terminal.Legacy.Settings tab-policy 'automatic'
    gsettings set org.gnome.Terminal.Legacy.Settings tab-position 'top'
    gsettings set org.gnome.Terminal.Legacy.Settings theme-variant 'system'
}


#########  2-3. Unneeded GNOME Utility  #########
funcUnneededGNOMEUtility(){
    # - Game
    local game_pack_list=${game_pack_list:-}
    game_pack_list=$(grep Game /usr/share/applications/*.desktop | awk -F: '{!a[$1]++}END{for(i in a) print i}' | while read -r line; do sed -r -n '/Exec/{s@.*=([^[:space:]]+).*@\1@g;p}' "${line}" | awk '{!a[$0]++}END{print}'; done | sed ':a;N;s@\n@ @g;t a;')
    [[ -z "${game_pack_list}" ]] || funcPackageManagerOperation 'remove' "${game_pack_list}"

    # grep Game /usr/share/applications/*.desktop | awk -F: '{!a[$1]++}END{for(i in a) print i}' | while read -r line;do sed -r -n '/Exec/{s@.*=([^[:space:]]+).*@\1@g;p}' "${line}" | awk '{if($0=="sol"){$0="aisleriot"};!a[$0]++}END{print}'; done | xargs -- sudo zypper rm -yu

    funcPackageManagerOperation 'remove' "evolution totem empathy brasero bijiben gnome-maps gnome-music gnome-clocks gnome-contacts gnome-weather"
}


#########  3. Executing Process  #########
if funcCommandExistCheck 'gnome-shell'; then
    funcInitializationCheck
    funcInternetConnectionCheck
    funcDownloadToolCheck
    funcPackageManagerDetection

    funcCustomCornerInstallation
    funcProxySwitcherInstattation
    funcCommandExistCheck 'gsettings' && funcTweakToolConfiguration
    funcCommonReferencesConfiguration
    funcUnneededGNOMEUtility
fi


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset mktemp_format
    unset proxy_server
    unset download_tool
    unset pack_manager
}

trap funcTrapEXIT EXIT

# Script End

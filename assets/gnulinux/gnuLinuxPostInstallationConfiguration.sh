#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #IFS  Internal Field Separator

#Target: Post Initialization Setting On Freshly Installed GNU Linux (RHEL/CentOS/Fedora/Debian/Ubuntu/OpenSUSE and variants)
#Writer: MaxdSre
#Date: Oct 26, 2017 19:10 Thu +0800
#Reconfiguration Date:
# - July 11, 2017 13:12 Tue ~ July 12, 2017 16:33 Wed +0800
# - July 27, 2017 17:26 Thu +0800
# - Aug 16, 2017 18:25 Wed +0800
# - Sep 05, 2017 13:49 Tue +0800
# - Oct 17, 2017 11:50 Tue +0800

#Docker Script https://get.docker.com/
#Gitlab Script https://packages.gitlab.com/gitlab/gitlab-ce/install


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'PICTemp_XXXXX'}
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
readonly c_normal="$(tput sgr0)"     # c_normal='\e[0m'
# black 0, red 1, green 2, yellow 3, blue 4, magenta 5, cyan 6, gray 7
readonly c_red="${c_bold}$(tput setaf 1)"     # c_red='\e[31;1m'
readonly c_blue="$(tput setaf 4)"    # c_blue='\e[34m'
str_len=${str_len:-16}               # printf str width
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup
pass_change_minday=${pass_change_minday:-0}    # minimum days need for a password change
pass_change_maxday=${pass_change_maxday:-90}   # maximum days the password is valid
pass_change_warnningday=${pass_change_warnningday:-10}  # password expiry advanced warning days
readonly github_raw_url='https://raw.githubusercontent.com'
readonly vim_url="${github_raw_url}/MaxdSre/ShellScript/master/configs/vimrc"
readonly sysctl_url="${github_raw_url}/MaxdSre/ShellScript/master/configs/sysctl.conf"
readonly os_check_script="${github_raw_url}/MaxdSre/ShellScript/master/assets/gnulinux/gnuLinuxDistroVersionDetection.sh"
readonly default_timezone=${default_timezone:-'Asia/Singapore'}
readonly default_grub_timeout=${default_grub_timeout:-2}
disable_ssh_root=${disable_ssh_root:-0}
enable_sshd=${enable_sshd:-0}
change_repository=${change_repository:-0}
just_keygen=${just_keygen:-0}
restrict_remote_login=${restrict_remote_login:-0}
grub_timeout=${grub_timeout:-2}
new_hostname=${new_hostname:-}
new_username=${new_username:-}
new_timezone=${new_timezone:-}
grant_sudo=${grant_sudo:-0}
proxy_server=${proxy_server:-}
flag=1    # used for funcFinishStatement

#########  1-1 Initialization Prepatation  #########
funcInfoPrintf(){
    local item="$1"
    local value="$2"
    [[ -n "$1" && -n "$2" ]] && printf "%${str_len}s $c_red%s$c_normal\n" "$item:" "$value"
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
    # 2 - specified for RHEL/Debian/SLES
    [[ -f '/etc/redhat-release' || -f '/etc/debian_version' || -f '/etc/SuSE-release' ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script just support RHEL/CentOS/Debian/Ubuntu/OpenSUSE derivates!"
    # 3 - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    funcCommandExistCheck 'curl' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}curl${c_normal} command found!"

    funcCommandExistCheck 'gawk' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gawk${c_normal} command found!"

    # used for SSH configuration
    funcCommandExistCheck 'man' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}man${c_normal} command found!"

    # 4 - current login user detection
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && login_user="$USER" || login_user="$SUDO_USER"
    login_user_home=${login_user_home:-}
    login_user_home=$(awk -F: 'match($1,/^'"${login_user}"'$/){print $(NF-1)}' /etc/passwd)

    login_user_ip=${login_user_ip:-}
    if [[ -n "${SSH_CLIENT:-}" ]]; then
        login_user_ip=$(echo "${SSH_CLIENT}" | awk '{print $1}')
    elif [[ -n "${SSH_CONNECTION:-}" ]]; then
        login_user_ip=$(echo "${SSH_CONNECTION}" | awk '{print $1}')
    else
        login_user_ip=$(who | sed -r -n 's@.*\(([^\)]+)\).*@\1@gp')
        # [[ "${login_user_ip}" == ":0" ]] && login_user_ip='127.0.0.1'
    fi

}

funcInternetConnectionCheck(){
    # CentOS: iproute Debian/OpenSUSE: iproute2
    local gateway_ip
    if funcCommandExistCheck 'ip'; then
        gateway_ip=$(ip route | awk 'match($1,/^default/){print $3}')
    elif funcCommandExistCheck 'netstat'; then
        gateway_ip=$(netstat -rn | awk 'match($1,/^Destination/){getline;print $2;exit}')
    else
        funcExitStatement "${c_red}Error${c_normal}: No ${c_blue}ip${c_normal} or ${c_blue}netstat${c_normal} command finds, please install it!"
    fi

    # Check Internet Connection
    ! ping -q -w 1 -c 1 "$gateway_ip" &> /dev/null && funcExitStatement "${c_red}Error${c_normal}: No internet connection detected, disable ICMP? please check it!"
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
    local referrer_page=${referrer_page:-'https://duckduckgo.com/?q=gnulinux'}
    # local user_agent=${user_agent:-'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6.4) AppleWebKit/537.29.20 (KHTML, like Gecko) Chrome/60.0.3030.92 Safari/537.29.20'}

    if funcCommandExistCheck 'curl'; then
        download_tool_origin="curl -fsL"
        download_tool="${download_tool_origin} --retry ${retry_times} --retry-delay ${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-keepalive --referer ${referrer_page}"   # curl -s URL -o /PATH/FILE； -fsSL
        # --user-agent ${user_agent}

        if [[ -n "${proxy_server}" ]]; then
            local curl_version_no=${curl_version_no:-}
            curl_version_no=$(curl --version | sed -r -n '1s@^[^[:digit:]]*([[:digit:].]*).*@\1@p')
            case "${p_proto}" in
                http ) export http_proxy="${p_host}" ;;
                https ) export HTTPS_PROXY="${p_host}" ;;
                socks4 ) [[ "${curl_version_no}" > '7.21.7' ]] && download_tool="${download_tool} -x ${p_proto}a://${p_host}" || download_tool="${download_tool} --socks4a ${p_host}" ;;
                socks5 ) [[ "${curl_version_no}" > '7.21.7' ]] && download_tool="${download_tool} -x ${p_proto}h://${p_host}" || download_tool="${download_tool} --socks5-hostname ${p_host}" ;;
                * ) export http_proxy="${p_host}" ;;
            esac
        fi

    elif funcCommandExistCheck 'wget'; then
        download_tool_origin="wget -qO-"
        download_tool="${download_tool_origin} --tries=${retry_times} --waitretry=${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-http-keep-alive --referer=${referrer_page}" # wget -q URL -O /PATH/FILE
        # --user-agent=${user_agent}

        # local version_no=$(wget --version | sed -r -n '1s@^[^[:digit:]]*([[:digit:].]*).*@\1@p')
        if [[ -n "${proxy_server}" ]]; then
            if [[ "${p_proto}" == 'https' ]]; then
                export https_proxy="${p_host}"
            else
                export http_proxy="${p_host}"
            fi
        fi
    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal} or ${c_blue}wget${c_normal}!"
    fi

    country=${country:-}
    # if [[ -d '/dev/' ]]; then
    #     # https://major.io/icanhazip-com-faq/
    #     exec 5<> /dev/tcp/icanhazip.com/80
    #     echo -e 'GET / HTTP/1.0\r\nHost: icanhazip.com\r\n\r' >&5
    #     while read -r i; do [[ -n "$i" ]] && country="$i" ; done <&5
    #     exec 5>&-
    #
    #     if [[ -z "${country}" ]]; then
    #         exec 6<> /dev/tcp/ipinfo.io/80
    #         echo -e 'GET / HTTP/1.0\r\nHost: ipinfo.io\r\n\r' >&6
    #         country=$(cat 0<&6 | sed -r -n '/^\{/,/^\}/{/\"country\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}}')
    #         exec 6>&-
    #     fi
    #
    # fi
    [[ -n "${country}" ]] || country=$($download_tool_origin ipinfo.io/country)

}

funcSystemServiceManager(){
    # systemctl / service & chkconfig
    local service_name="$1"
    local action="$2"
    if funcCommandExistCheck 'systemctl'; then
        case "${action}" in
            start|stop|reload|restart|status|enable|disable )
                systemctl unmask "${service_name}" &> /dev/null
                [[ "${action}" == 'start' ]] && systemctl enable "${service_name}" &> /dev/null
                systemctl "$action" "${service_name}" &> /dev/null
                ;;
            * ) systemctl status "${service_name}" 1> /dev/null ;;
        esac
    else
        case "$action" in
            start|stop|restart|status )

                if funcCommandExistCheck 'chkconfig'; then
                    local sysv_command='chkconfig'  # for RedHat/OpenSUSE
                elif funcCommandExistCheck 'sysv-rc-conf'; then
                    local sysv_command='sysv-rc-conf'   # for Debian
                fi

                [[ "${action}" == 'start' ]] && $sysv_command "${service_name}" on &> /dev/null
                service "${service_name}" "$action" &> /dev/null
                ;;
            * ) service status "${service_name}" 1> /dev/null ;;
        esac
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

    # case "${pack_manager}" in
    #     zypper|dnf|yum|rpm ) pack_suffix='rpm' ;;
    #     apt-get|apt|dpkg ) pack_suffix='deb' ;;
    # esac
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

funcOperationBar(){
cat <<EOF

=========================================
  Operation Processing, Just Be Patient
=========================================

EOF
}


funcFinishStatement(){
    local string="$*"
    local str="$1"
    string=${string/"$str"}
    [[ -n "$string" ]] && string=" ($c_red$string$c_normal )"
    printf "Step $flag - ${c_bold}$c_blue%s$c_normal is finished$string;\n" "$str"
    (( flag++ ))
    # let flag++
    # flag=$((flag+1))
}

funcOSInfoDetection(){
    local osinfo=${osinfo:-}
    osinfo=$($download_tool "${os_check_script}" | bash -s -- -j | sed -r -n 's@[{}]@@g;s@","@\n@g;s@":"@|@g;s@(^"|"$)@@g;p')

    if [[ -z "${osinfo}" ]]; then
        funcExitStatement "${c_red}Fatal${c_normal}, fail to extract os info!"
    elif [[ -n $(echo "${osinfo}" | sed -n -r '/^error\|/p') ]]; then
        funcExitStatement "${c_red}Fatal${c_normal}, this script doesn't support your system!"
    fi

    distro_name=${distro_name:-}
    if [[ -n $(echo "${osinfo}" | sed -n -r '/^distro_name\|/p') ]]; then
        distro_name=$(echo "${osinfo}" | awk -F\| 'match($1,/^distro_name$/){print $NF}')
        distro_name=${distro_name%%-*}    # rhel/centos/fedora/debian/ubuntu/sles/opensuse
    fi

    codename=${codename:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^codename\|/p') ]] && codename=$(echo "${osinfo}" | awk -F\| 'match($1,/^codename$/){print $NF}')

    distro_fullname=${distro_fullname:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^pretty_name\|/p') ]] && distro_fullname=$(echo "${osinfo}" | awk -F\| 'match($1,/^pretty_name$/){print $NF}')

    version_id=${version_id:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^version_id\|/p') ]] && version_id=$(echo "${osinfo}" | awk -F\| 'match($1,/^version_id$/){print $NF}')

    ip_local=${ip_local:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^ip_local\|/p') ]] && ip_local=$(echo "${osinfo}" | awk -F\| 'match($1,/^ip_local$/){print $NF}')

    ip_public=${ip_public:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^ip_public\|/p') ]] && ip_public=$(echo "${osinfo}" | awk -F\| 'match($1,/^ip_public$/){print $NF}')

    ip_public_region=${ip_public_region:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^ip_public_region\|/p') ]] && ip_public_region=$(echo "${osinfo}" | awk -F\| 'match($1,/^ip_public_region$/){print $NF}')

    case "${distro_name,,}" in
        rhel|centos )
            [[ "${version_id%%.*}" -le 5 ]] && funcExitStatement "${c_red}Sorry${c_normal}: your system ${c_blue}${distro_fullname}${c_normal} is obsoleted!"
            ;;
    esac

echo "
=========================================
    GNU/Linux Distribution Information
=========================================
"

    [[ -z "${distro_name}" ]] || funcInfoPrintf 'Distro Name' "${distro_name}"
    [[ -z "${version_id}" ]] || funcInfoPrintf 'Version ID' "${version_id}"
    [[ -z "${codename}" ]] || funcInfoPrintf "Code Name" "${codename}"
    [[ -z "${distro_fullname}" ]] || funcInfoPrintf 'Full Name' "${distro_fullname}"

    if [[ -n "${ip_public}" ]]; then
        [[ "${ip_public}" == "${ip_local}" ]] || funcInfoPrintf 'Internal IP' "${ip_local}"
        funcInfoPrintf 'External IP' "${ip_public} (${ip_public_region})"
    fi

    version_id=${version_id%%.*}
}


#########  1-2 getopts Operation  #########
start_time=$(date +'%s')    # Start Time Of Operation

funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Post Installation Configuring RHEL/CentOS/Fedora/Debian/Ubuntu/OpenSUSE!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -r    --replace repository source, for China mainland only
    -u username    --add user, create new user, password same to username
    -S    --sudo, grant user sudo privilege which is specified by '-u'
    -H hostname    --hostname, set hostname
    -T timezone    --timezone, set timezone (eg. America/New_York, Asia/Hong_Kong)
    -s    --ssh, enable sshd service (server side), default start on system startup
    -d    --disable root user remoting login (eg: via ssh)
    -k    --keygen, sshd service only allow ssh keygen, disable password, along with '-s'
    -R    --restrict remote login from specific ip (current login host), use with caution
    -g time    --grub timeout, set timeout num (second)
    -p [protocol:]ip:port    --proxy host (http|https|socks4|socks5), default protocol is http
${c_normal}
EOF
exit
}

while getopts "ru:SH:T:sdkRg:p:h  ru:Sg:H:T:skdp:h" option "$@"; do
    case "$option" in
        r ) change_repository=1 ;;
        u ) new_username="$OPTARG" ;;
        S ) grant_sudo=1 ;;
        H ) new_hostname="$OPTARG" ;;
        T ) new_timezone="$OPTARG" ;;
        s ) enable_sshd=1 ;;
        d ) disable_ssh_root=1 ;;
        k ) just_keygen=1 ;;
        R ) restrict_remote_login=1 ;;
        g ) grub_timeout="$OPTARG" ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo ;;
    esac
done


#########  2-1. Disable SELinux  #########
# SELinux Installation
# - yum -y -q/dnf -yq install selinux-policy
# - zypper in -yl libselinux1 libselinux-devel
# - apt-get install selinux-basics

# Disable SELinux default currently
funcDisableSELinux(){
    local selinux_config=${selinux_config:-'/etc/selinux/config'}
    if [[ -f "${selinux_config}" ]]; then
        [[ -f "${selinux_config}${bak_suffix}" ]] || cp -fp "${selinux_config}" "${selinux_config}${bak_suffix}"
        sed -i -r 's@(SELINUX=)enforcing@\1disabled@g;s@#*(SELINUXTYPE=.*)@#\1@g' "${selinux_config}"
        funcFinishStatement "Disable SELinux"
    fi
}


#########  2-2. Package Repository Setting & System Update  #########
funcRepositoryYUM(){
    local repo_dir=${repo_dir:-'/etc/yum.repos.d/'}
    if [[ "${change_repository}" -eq 1 && "${distro_name}" == 'centos' && "${country^^}" == 'CN' ]]; then
        local repo_dir_backup="${repo_dir}${bak_suffix}"
        if [[ ! -d "${repo_dir_backup}" ]]; then
            mkdir -p "${repo_dir_backup}"
            mv -f ${repo_dir}CentOS*.repo "${repo_dir_backup}"
        fi

        # http://mirrors.163.com/.help/centos.html
        local repo_savename="${repo_dir}CentOS-Base.repo"
        [[ -f "${repo_savename}" ]] || $download_tool "http://mirrors.163.com/.help/CentOS${version_id}-Base-163.repo" > "$repo_savename"
    fi

    # Installing EPEL Repository
    if [[ ! -f "${repo_dir}epel.repo" ]]; then
        local rpm_gpg_dir='/etc/pki/rpm-gpg/'
        [[ -f "${rpm_gpg_dir}RPM-GPG-KEY-EPEL-${version_id}" ]] || $download_tool "https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-${version_id}" > "${rpm_gpg_dir}RPM-GPG-KEY-EPEL-${version_id}"
        funcPackageManagerOperation 'install' "epel-release"
        [[ -f "${repo_dir}epel-testing.repo" ]] && rm -f "${repo_dir}epel-testing.repo"
    fi
}

funcRepositoryDNF(){
    if [[ "${change_repository}" -eq 1 && "${distro_name}" == 'fedora' && "${country^^}" == 'CN' ]]; then
        local repo_dir=${repo_dir:-'/etc/yum.repos.d/'}
        local repo_dir_backup="${repo_dir}${bak_suffix}"
        if [[ ! -d "${repo_dir_backup}" ]]; then
            mkdir -p "${repo_dir_backup}"
            mv -f "${repo_dir}*.repo" "${repo_dir_backup}"
        fi

        # http://mirrors.163.com/.help/fedora.html
        local repo_fedora_savename="${repo_dir}Fedora.repo"
        [[ -f "${repo_fedora_savename}" ]] || $download_tool "http://mirrors.163.com/.help/fedora-163.repo" > "$repo_fedora_savename"

        local repo_fedora_updates_savename="${repo_dir}Fedora-Updates.repo"
        [[ -f "${repo_fedora_updates_savename}" ]] || $download_tool "http://mirrors.163.com/.help/fedora-updates-163.repo" > "$repo_fedora_updates_savename"
    fi
}

funcSourceUbuntu(){
tee /etc/apt/sources.list 1> /dev/null <<-EOF
deb $repo_site/$distro_name/ $codename main restricted universe multiverse
deb-src $repo_site/$distro_name/ $codename main restricted universe multiverse

deb $repo_site/$distro_name/ $codename-security main restricted universe multiverse
deb-src $repo_site/$distro_name/ $codename-security main restricted universe multiverse

deb $repo_site/$distro_name/ $codename-updates main restricted universe multiverse
deb-src $repo_site/$distro_name/ $codename-updates main restricted universe multiverse

deb $repo_site/$distro_name/ $codename-proposed main restricted universe multiverse
deb-src $repo_site/$distro_name/ $codename-proposed main restricted universe multiverse

deb $repo_site/$distro_name/ $codename-backports main restricted universe multiverse
deb-src $repo_site/$distro_name/ $codename-backports main restricted universe multiverse
EOF
}

# custom function for Debian
funcSourceDebian(){
tee /etc/apt/sources.list 1> /dev/null <<-EOF
deb $repo_site/$distro_name/ $codename main non-free contrib
deb-src $repo_site/$distro_name/ $codename main non-free contrib

deb $repo_site/$distro_name/ $codename-updates main non-free contrib
deb-src $repo_site/$distro_name/ $codename-updates main non-free contrib

deb $repo_site/$distro_name/ $codename-backports main non-free contrib
deb-src $repo_site/$distro_name/ $codename-backports main non-free contrib

deb $repo_site/$distro_name-security/ $codename/updates main non-free contrib
deb-src $repo_site/$distro_name-security/ $codename/updates main non-free contrib
EOF
}

funcRepositoryAPT(){
    if [[ "${change_repository}" -eq 1 && "${country}" == 'CN'  ]]; then
        local repo_path=${repo_path:-'/etc/apt/sources.list'}
        [[ -f "${repo_path}${bak_suffix}" ]] || cp -fp "${repo_path}" "${repo_path}${bak_suffix}"
        local repo_site='http://mirrors.163.com'
        funcSource"${distro_name^}"
    fi
}

funcRepositoryZYPPER(){
    if [[ "${change_repository}" -eq 1 && "${distro_name}" == 'opensuse' ]]; then
        for i in $(zypper lr | awk -F\| 'match($1,/[[:digit:]]/)&&match($0,/OSS/){print gensub(/[[:blank:]]/,"","g",$1)}'); do zypper rr "$i" &> /dev/null ; done

        [[ "${version_id%%.*}" -ge 42 ]] && repo_keyword="leap/${version_id}" || repo_keyword="${version_id}"

        local repo_url=${repo_url:'http://download.opensuse.org'}
        local repo_alias=${repo_alias:-'OpenSUSE'}
        if [[ "${country}" == 'CN' ]]; then
            repo_url="https://mirrors.ustc.edu.cn/${distro_name}"
            repo_alias='USTC'
        fi

        zypper ar -fcg "${repo_url}/distribution/${repo_keyword}/repo/oss" "${repo_alias}:${repo_keyword##*/}:OSS" &> /dev/null
        zypper ar -fcg "${repo_url}/distribution/${repo_keyword}/repo/non-oss" "${repo_alias}:${repo_keyword##*/}:NON-OSS" &> /dev/null
        zypper ar -fcg "${repo_url}/update/${repo_keyword}/oss" "${repo_alias}:${repo_keyword##*/}:UPDATE-OSS" &> /dev/null
        zypper ar -fcg "${repo_url}/update/${repo_keyword}/non-oss" "${repo_alias}:${repo_keyword##*/}:UPDATE-NON-OSS" &> /dev/null


        # zypper ar -fcg https://mirrors.ustc.edu.cn/opensuse/distribution/leap/42.3/repo/oss USTC:42.3:OSS
        # zypper ar -fcg https://mirrors.ustc.edu.cn/opensuse/distribution/leap/42.3/repo/non-oss USTC:42.3:NON-OSS
        # zypper ar -fcg https://mirrors.ustc.edu.cn/opensuse/update/leap/42.3/oss USTC:42.3:UPDATE-OSS
        # zypper ar -fcg https://mirrors.ustc.edu.cn/opensuse/update/leap/42.3/non-oss USTC:42.3:UPDATE-NON-OSS

        # zypper ar -fcg http://download.opensuse.org/distribution/leap/42.3/repo/oss/ OpenSUSE:42.3:OSS
        # zypper ar -fcg http://download.opensuse.org/distribution/leap/42.3/repo/non-oss/ OpenSUSE:42.3:NON-OSS
        # zypper ar -fcg http://download.opensuse.org/update/leap/42.3/oss/ OpenSUSE:42.3:UPDATE-OSS
        # zypper ar -fcg http://download.opensuse.org/update/leap/42.3/non-oss/ OpenSUSE:42.3:UPDATE-NON-OSS

    fi
}

funcPackRepositorySetting(){
    # apt-get|yum|dnf|zypper
    local pack_func_name=${pack_manager%%-*}
    # Repository Setting
    funcPackageManagerOperation
    funcRepository"${pack_func_name^^}"
    funcPackageManagerOperation "upgrade"
    funcFinishStatement "Package Repository Setting & System Update"
}


#########  2-3. Essential Packages Installation  #########
funcEssentialPackInstallation(){
    if [[ "${pack_manager}" == 'apt-get' ]]; then
        funcCommandExistCheck 'systemctl' || funcPackageManagerOperation 'install' "sysv-rc-conf" # same to chkconfig
        # https://github.com/koalaman/shellcheck/wiki/SC2143
        if ! dpkg --list | grep -q 'firmware-linux-nonfree'; then
            funcPackageManagerOperation 'install' "firmware-linux-nonfree"
        fi
    fi

    # bash-completion
    funcPackageManagerOperation 'install' "bash-completion"

    # pdsh - issue commands to groups of hosts in parallel
    funcCommandExistCheck 'pdsh' || funcPackageManagerOperation 'install' "pdsh"
    funcCommandExistCheck 'bc' || funcPackageManagerOperation 'install' 'bc'
    # command parallel
    if ! funcCommandExistCheck 'parallel'; then
        local parallel_name=${parallel_name:-'parallel'}
        # SLES repo in AWK has no parallel utility
        [[ "${pack_manager}" == 'zypper' ]] && parallel_name='gnu_parallel'
        funcPackageManagerOperation 'install' "${parallel_name}"
    fi

    # https://en.wikipedia.org/wiki/Util-linux
    local util_linux=${util_linux:-'util-linux'}
    [[ "${pack_manager}" == 'yum' ]] && util_linux='util-linux-ng'
    funcPackageManagerOperation 'install' "${util_linux}"

    # command dig
    local dns_utils=${dns_utils:-'dnsutils'}
    [[ "${pack_manager}" != 'apt' ]] && dns_utils='bind-utils'
    funcPackageManagerOperation 'install' "${dns_utils}"

    # # hping
    # local hping_name=${hping_name:-'hping'}
    # [[ "${pack_manager}" == 'zypper' ]] && hping_name='hping3'
    # # procps
    # local procps_name=${procps_name:-'procps'}
    # [[ "${pack_manager}" == 'dnf' ]] && procps_name='procps-ng'
    # #  iproute
    # local iproute_name=${iproute_name:-'iproute'}
    # case "${pack_manager}" in
    #     apt-get|zypper ) iproute_name='iproute2' ;;
    #     dnf|yum ) iproute_name='iproute' ;;
    # esac
    # funcPackageManagerOperation 'install' "${hping_name} ${procps_name} ${iproute_name}"

    funcPackageManagerOperation 'install' "psmisc mlocate tree dstat"
    funcPackageManagerOperation 'install' "nmap tcpdump traceroute"

    # - Haveged Installation for random num generation
    local rng_config_path=${rng_config_path:-'/etc/default/rng-tools'}
    if [[ ! -f "${rng_config_path}" ]]; then
        funcPackageManagerOperation 'install' "rng-tools haveged"
        if [[ -f "${rng_config_path}" ]]; then
            [[ -f "${rng_config_path}${bak_suffix}" ]] || cp -fp "${rng_config_path}" "${rng_config_path}${bak_suffix}"
            sed -i -r '/^HRNGDEVICE/d;/#HRNGDEVICE=\/dev\/null/a HRNGDEVICE=/dev/urandom' "${rng_config_path}"
        fi
    fi

    # - Chrony
    case "${pack_manager}" in
        apt-get )
            # https://github.com/koalaman/shellcheck/wiki/SC2143
            if dpkg --list | grep -q 'ntp'; then
                funcPackageManagerOperation 'remove' "ntp"
            fi

            if ! dpkg --list | grep -q 'chrony'; then
                funcPackageManagerOperation 'install' "chrony"
            fi

            funcSystemServiceManager 'chrony' 'start'
            ;;
        dnf|yum )
            [[ $(rpm -qa | awk -F- 'match($1,/^ntp$/){print $1}') == 'ntp' ]] && funcPackageManagerOperation "remove" "ntp"
            [[ $(rpm -qa | awk -F- 'match($1,/^chrony$/){print $1}') == 'chrony' ]] && funcPackageManagerOperation 'install' "chrony"
            funcSystemServiceManager 'chronyd' 'start'
            ;;
        zypper )
            # zypper packages -i 操作較爲耗時，約2.5s
            [[ -z $(zypper packages -i | awk -F\| 'match($3,/^[[:space:]]*ntp[[:space:]]*$/){print}') ]] || funcPackageManagerOperation "remove" "ntp"
            [[ -z $(zypper packages -i | awk -F\| 'match($3,/^[[:space:]]*chrony[[:space:]]*$/){print}') ]] && funcPackageManagerOperation 'install' "chrony"
            [[ -f '/etc/ntp.conf.rpmsave' ]] && rm -f '/etc/ntp.conf.rpmsave'
            funcSystemServiceManager 'chronyd' 'start'
            ;;
    esac

    # - vim editor
    if ! funcCommandExistCheck 'vim'; then
        local vim_pack_name=${vim_pack_name:-'vim'}
        case "${pack_manager}" in
            dnf|yum ) vim_pack_name='vim-enhanced' ;;
        esac
        funcPackageManagerOperation 'install' "${vim_pack_name}"
    fi
    local vim_config=${vim_config:-'/etc/vimrc'}
    [[ -f '/etc/vim/vimrc' ]] && vim_config='/etc/vim/vimrc'

    if [[ -f "${vim_config}" ]]; then
        [[ -f "${vim_config}${bak_suffix}" ]] || cp -fp "${vim_config}" "${vim_config}${bak_suffix}"
        sed -i -r '/custom configuration start/,/custom configuration end/d' "${vim_config}"
        $download_tool "$vim_url" >> "${vim_config}"
    fi

    # https://www.cyberciti.biz/faq/vim-vi-text-editor-save-file-without-root-permission/
    # :w !sudo tee %
    # command W :execute ':silent w !sudo tee % > /dev/null' | :edit!

    # vim cut&paste not working in Stretch / Debian 9
    # https://unix.stackexchange.com/questions/318824/vim-cutpaste-not-working-in-stretch-debian-9
    # set mouse-=a
    if [[ "${distro_name}" == 'debian' && "${codename}" == 'stretch' ]]; then
        local vim_defaults=${vim_defaults:-'/usr/share/vim/vim80/defaults.vim'}
        [[ -s "${vim_defaults}" ]] && sed -i -r "/^if has\('mouse'\)/,+2{s@^@\"@g}" "${vim_defaults}"
    fi

    funcFinishStatement "Essential Packages Installation"
}


#########  2-4. Hostname & Timezone Setting  #########
funcHostnameTimezoneSetting(){
    # - Hostname Setting
    local current_hostname=${current_hostname:-}
    current_hostname=$(hostname)

    if [[ -z "${new_hostname}" ]]; then
        if [[ -n "${codename}" ]]; then
            new_hostname="${codename^}"
        elif [[ -n "${distro_name}" ]]; then
            new_hostname="${distro_name^}"
        fi

        if [[ "${codename}" == 'wheezy' ]]; then
            new_hostname="${new_hostname}${ip_public##*.}"
        else
            new_hostname="${new_hostname}_${ip_public##*.}"
        fi
    fi

    if funcCommandExistCheck 'hostnamectl'; then
        hostnamectl set-hostname "${new_hostname}"
    else
        hostname "${new_hostname}" &> /dev/null   # temporarily change, when reboot, it will recover
        if [[ -f '/etc/sysconfig/network' ]]; then
            sed -r -i '/^HOSTNAME=/s@^(HOSTNAME=).*@\1'"${new_hostname}"'@g' /etc/sysconfig/network #RHEL
        elif [[ -f '/etc/hostname' ]]; then
            echo "${new_hostname}" > /etc/hostname  #Debian/OpenSUSE
        fi
    fi

    local hosts_path=${hosts_path:-'/etc/hosts'}
    if [[ -f "${hosts_path}" ]]; then
        sed -r -i '/^(127.0.0.1|::1)/s@ '"${current_hostname}"'@ '"${new_hostname}"'@g' "${hosts_path}"

        if [[ -z $(sed -r -n '/^127.0.0.1/{/'"${new_hostname}"'/p}' "${hosts_path}") ]]; then
            if [[ -z $(sed -r -n '/^127.0.0.1/p' "${hosts_path}") ]]; then
                sed -i '$a 127.0.0.1 '"${new_hostname}"'' "${hosts_path}"
            else
                sed -i '/^127.0.0.1/a 127.0.0.1 '"${new_hostname}"'' "${hosts_path}"
            fi
        fi
    fi

    # - Timezone Setting
    local new_timezone_path="/usr/share/zoneinfo/${new_timezone}"
    [[ -z "${new_timezone}" || ! -f "${new_timezone_path}" ]] && new_timezone="${default_timezone}"

    if funcCommandExistCheck 'timedatectl'; then
        timedatectl set-timezone "${new_timezone}"
        timedatectl set-local-rtc false
        timedatectl set-ntp true
    else
        if [[ "${pack_manager}" == 'apt-get' ]]; then
            echo "${new_timezone}" > /etc/timezone
            funcCommandExistCheck 'dpkg-reconfigure' && dpkg-reconfigure -f noninteractive tzdata &> /dev/null
        else
            # RHEL/OpenSUSE
            local localtime_path='/etc/localtime'
            [[ -f "${localtime_path}" ]] && rm -f "${localtime_path}"
            ln -fs "$new_timezone_path" "${localtime_path}"
        fi
    fi

    funcFinishStatement "Hostname & Timezone Setting" "${new_hostname}" "${new_timezone}"
}


#########  2-5. Add new created ordinary user into group wheel/sudo  #########
funcAddNormalUser(){
    funcCommandExistCheck 'sudo' || funcPackageManagerOperation 'install' "sudo"
    local user_if_existed=${user_if_existed:-0}

    if [[ -n "${new_username}" ]]; then
        # Debian/Ubuntu: sudo      RHEL/OpenSUSE: wheel
        local sudo_group_name=${sudo_group_name:-'wheel'}
        [[ "${pack_manager}" == 'apt-get' ]] && sudo_group_name='sudo'

        if [[ -z $(awk -F: 'match($1,/^'"${new_username}"'$/){print}' /etc/passwd) ]]; then
            # type 1 - create new user and add it into group wheel/sudo
            if [[ "${grant_sudo}" -eq 1 ]]; then
                useradd -mN -G "${sudo_group_name}" "${new_username}" &> /dev/null
            else
                useradd -mN "${new_username}" &> /dev/null
            fi

            local new_password="${new_username}"
            # Debian/SUSE not support --stdin
            case "${pack_manager}" in
                apt-get )
                    # https://debian-administration.org/article/668/Changing_a_users_password_inside_a_script
                    echo "${new_username}:${new_password}" | chpasswd &> /dev/null
                    ;;
                dnf|yum )
                    echo "${new_password}" | passwd --stdin "${new_username}" &> /dev/null
                    ;;
                zypper )
                    # https://stackoverflow.com/questions/27837674/changing-a-linux-password-via-script#answer-27837785
                    echo -e "${new_password}\n${new_password}" | passwd "${new_username}" &> /dev/null
                    ;;
            esac

            # setting user password expired date
            passwd -n "${pass_change_minday}" -x "${pass_change_maxday}" -w "${pass_change_warnningday}" "${new_username}"  &> /dev/null
            chage -d0 "${new_username}" &> /dev/null  # new created user have to change passwd when first login

        else
            # type 2 - user has been existed
            # gpasswd -a "${new_username}"  "${sudo_group_name}" 1> /dev/null
            [[ "${grant_sudo}" -eq 1 ]] && usermod -a -G "${sudo_group_name}" "${new_username}" 2> /dev/null
            local user_if_existed=1
        fi

        local sudo_config_path=${sudo_config_path:-'/etc/sudoers'}

        if [[ -f "${sudo_config_path}" ]]; then
            [[ -f "${sudo_config_path}${bak_suffix}" ]] || cp -fp "${sudo_config_path}" "${sudo_config_path}${bak_suffix}"

            if [[ "${pack_manager}" == 'apt-get' ]]; then
                sed -r -i 's@#*[[:space:]]*(%sudo[[:space:]]+ALL=\(ALL:ALL\)[[:space:]]+ALL)@# \1@;/%sudo ALL=NOPASSWD:ALL/d;/group sudo/a %sudo ALL=NOPASSWD:ALL' "${sudo_config_path}"
            else
                sed -r -i 's@#*[[:space:]]*(%wheel[[:space:]]+ALL=\(ALL\)[[:space:]]+ALL)@# \1@;s@#*[[:space:]]*(%wheel[[:space:]]+ALL=\(ALL\)[[:space:]]+NOPASSWD: ALL)@\1@' "${sudo_config_path}"
            fi
        fi

        if [[ "${grant_sudo}" -eq 1 ]]; then
            if [[ "${user_if_existed}" -eq 1 ]]; then
                funcFinishStatement "Add existed normal user into group ${sudo_group_name}" "${new_username}"
            else
                funcFinishStatement "Create normal user & add into group ${sudo_group_name}" "${new_username}"
            fi
        else
            if [[ "${user_if_existed}" -eq 1 ]]; then
                printf "Normal user you specified (${c_red}%s${c_normal}) has been existed!\n" "${new_username}"
            else
                funcFinishStatement "Create normal user" "${new_username}"
            fi
        fi

    fi
}


#########  2-6. SSH Configuring  #########
funcOpenSSHParameterConfiguration(){
    local key="${1:-}"
    local val="${2:-}"
    local path=${path:-'/etc/ssh/sshd_config'}

    if [[ -n "${key}" && -n "${val}" && -s "${path}" && -n $(man sshd_config | sed -r -n '/^[[:space:]]*'"${key}"'[[:space:]]*/p') ]]; then
        local record_origin=${record_origin:-}

        # if result has more then one line, use double quote "" wrap it
        # whole line start with keyword
        record_origin=$(sed -r -n '/^'"${key}"'[[:space:]]+/{s@[[:space:]]*$@@g;p}' "${path}")
        # whole line inclue keyword start with "#"
        record_origin_comment=$(sed -r -n '/^#?[[:space:]]*'"${key}"'[[:space:]]+/{s@[[:space:]]*$@@g;p}' "${path}")

        if [[ -z "${record_origin}" ]]; then
            if [[ -z "${record_origin_comment}" ]]; then
                sed -i -r '$a '"${key} ${val}"'' "${path}"  # append
            else
                sed -i -r '/^#[[:space:]]*'"${key}"'[[:space:]]+/a '"${key} ${val}"'' "${path}"
            fi

        else
            funcDeleteOpenSSHDuplicateLine(){
                record_origin_counts=$(sed -r -n '/^'"${key}"'[[:space:]]+/=' "${path}" | sed -n '$=')
                if [[ "${record_origin_counts}" -gt 1 ]]; then
                    line_num=$(sed -r -n '/^'"${key}"'[[:space:]]+/=' "${path}" | sed '$!d')
                    sed -i ''"${line_num}"'d' "${path}"
                    funcDeleteOpenSSHDuplicateLine
                fi
            }
            funcDeleteOpenSSHDuplicateLine

            [[ "${record_origin##* }" != "${val}" ]] && sed -i -r '/^'"${key}"'/s@.*@'"${key} ${val}"'@' "${path}"
        fi

    fi
}

funcOpenSSHConfiguring(){
    # OpenSUSE merge client & service side into one package 'openssh'
    local ssh_config=${ssh_config:-'/etc/ssh/ssh_config'}
    local sshd_config=${sshd_config:-'/etc/ssh/sshd_config'}

    # - client side
    local client_pack_name=${client_pack_name:-}
    case "${pack_manager}" in
        apt-get ) client_pack_name='openssh-client' ;;
        dnf|yum ) client_pack_name='openssh-clients' ;;
        zypper ) client_pack_name='openssh' ;;
    esac
    funcPackageManagerOperation 'install' "${client_pack_name}"

    # - server side
    if [[ ! -f "${sshd_config}" && "${enable_sshd}" -eq 1 ]]; then
        local server_pack_name=${server_pack_name:-'openssh-server'}
        [[ "${pack_manager}" == 'zypper' ]] && server_pack_name='openssh'
        funcCommandExistCheck 'sshd' || funcPackageManagerOperation 'install' "${server_pack_name}"

        local ssh_service_name=${ssh_service_name:-'sshd'}
        [[ "${pack_manager}" == 'apt-get' ]] && ssh_service_name='ssh'
        funcCommandExistCheck 'sshd' && funcSystemServiceManager "${ssh_service_name}" 'start'
    fi

    [[ ! -f "${ssh_config}${bak_suffix}" && -f "${ssh_config}" ]] && cp -pf "${ssh_config}" "${ssh_config}${bak_suffix}"
    [[ ! -f "${sshd_config}${bak_suffix}" && -f "${sshd_config}" ]] && cp -pf "${sshd_config}" "${sshd_config}${bak_suffix}"

    # sshd port detection
    sshd_existed=${sshd_existed:-0}
    if [[ -f "${sshd_config}" ]]; then
        sshd_existed=1
        ssh_port=${ssh_port:-22}
        ssh_port=$(sed -r -n '/^#?Port/s@^#?Port[[:space:]]*(.*)@\1@p' "${sshd_config}" 2> /dev/null)
    fi

    if [[ -f "${sshd_config}" ]]; then
        local ssh_version=${ssh_version:-0}
        ssh_version=$(ssh -V 2>&1 | sed -r -n 's@.*_([[:digit:].]{3}).*@\1@p')  # 7.2, 6.7, 5.3
        # Only Use SSH Protocol 2
        sed -i -r 's@^#?(Protocol 2)@\1@' "${sshd_config}"

        # AllowGroups : This keyword can be followed by a list of group name patterns, separated by spaces.
        local group_allow_name
        group_allow_name=${group_allow_name:-'ssh_group_allow'}
        [[ -z $(sed -n '/^'"${group_allow_name}"':/p' /etc/gshadow) ]] && groupadd "${group_allow_name}" &>/dev/null
        funcOpenSSHParameterConfiguration 'AllowGroups' "${group_allow_name}"
        gpasswd -a "${login_user}" "${group_allow_name}" &>/dev/null

        [[ -n "${new_username}" ]] && gpasswd -a "${new_username}" "${group_allow_name}" &>/dev/null

        # Disable root Login via SSH PermitRootLogin {yes,without-password,forced-commands-only,no}
        if [[ "${disable_ssh_root}" -eq 1 ]]; then
            if [[ "${login_user}" != 'root' || ("${login_user}" == 'root' && -n "${new_username}") ]]; then
                gpasswd -d root "${group_allow_name}" &>/dev/null
                funcOpenSSHParameterConfiguration 'PermitRootLogin' 'no'
            fi
        fi

        # Disabling sshd DNS Checks
        funcOpenSSHParameterConfiguration 'UseDNS' 'no'
        # Log Out Timeout Interval, just work for Protocol 2
        funcOpenSSHParameterConfiguration 'ClientAliveCountMax' '3'
        funcOpenSSHParameterConfiguration 'ClientAliveInterval' '180'
        # Disallow the system send TCP keepalive messages to the other side
        funcOpenSSHParameterConfiguration 'TCPKeepAlive' 'no'
        # Don't read the user's ~/.rhosts and ~/.shosts files
        funcOpenSSHParameterConfiguration 'IgnoreRhosts' 'yes'
        # Disable Host-Based Authentication
        funcOpenSSHParameterConfiguration 'HostbasedAuthentication' 'no'
        # Disallow Empty Password Login
        funcOpenSSHParameterConfiguration 'PermitEmptyPasswords' 'no'
        # Enable Logging Message {QUIET, FATAL, ERROR, INFO, VERBOSE, DEBUG, DEBUG1, DEBUG2, DEBUG3}
        funcOpenSSHParameterConfiguration 'LogLevel' 'VERBOSE'
        # Check file modes and ownership of the user's files and home directory before accepting login
        funcOpenSSHParameterConfiguration 'StrictModes' 'yes'

        # Log sftp level file access (read/write/etc.) that would not be easily logged otherwise.
        # https://unix.stackexchange.com/questions/61580/sftp-gives-an-error-received-message-too-long-and-what-is-the-reason#answer-327284
        # https://serverfault.com/questions/660160/openssh-difference-between-internal-sftp-and-sftp-server
        sed -i -r '/^#?Subsystem[[:space:]]*sftp/d;$a Subsystem sftp internal-sftp -l INFO' "${sshd_config}"

        # Checks whether the account has been locked with passwd -l
        # AWS EC2
        if [[ "${distro_name}" == 'sles' ]]; then
            funcOpenSSHParameterConfiguration 'UsePAMCheckLocks' 'no'
        else
            funcOpenSSHParameterConfiguration 'UsePAMCheckLocks' 'yes'
        fi

        # Supported HostKey algorithms by order of preference
        sed -i -r 's@^#?(HostKey /etc/ssh/ssh_host_rsa_key)$@\1@' "${sshd_config}"
        sed -i -r 's@^#?(HostKey /etc/ssh/ssh_host_ecdsa_key)$@\1@' "${sshd_config}"

        # https://wiki.mozilla.org/Security/Guidelines/OpenSSH
        if [[ $(echo "${ssh_version} > 6.7" | bc) == 1 ]]; then
            sed -i -r 's@^#?(HostKey /etc/ssh/ssh_host_ec25519_key)$@\1@' "${sshd_config}"
            # Specifies the available KEX (Key Exchange) algorithms
            funcOpenSSHParameterConfiguration 'KexAlgorithms' 'curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256'
            # Ciphers Setting
            funcOpenSSHParameterConfiguration 'Ciphers' 'chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr'
            # Message authentication codes (MACs) Setting
            funcOpenSSHParameterConfiguration 'MACs' 'hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com'
            # Turn on privilege separation  yes/sandbox
            funcOpenSSHParameterConfiguration 'UsePrivilegeSeparation' 'sandbox'

        else
            # Specifies the available KEX (Key Exchange) algorithms
            funcOpenSSHParameterConfiguration 'KexAlgorithms' 'diffie-hellman-group-exchange-sha256'
            # Ciphers Setting
            funcOpenSSHParameterConfiguration 'Ciphers' 'aes256-ctr,aes192-ctr,aes128-ctr'
            # Message authentication codes (MACs) Setting
            funcOpenSSHParameterConfiguration 'MACs' 'hmac-sha2-512,hmac-sha2-256'
        fi

        if [[ "${just_keygen}" -eq 1 && -s "${login_user_home}/.ssh/authorized_keys" ]]; then
            # Using PAM
            # funcOpenSSHParameterConfiguration 'UsePAM' 'yes'
            #the follow `ChallengeResponseAuthentication` and `PasswordAuthentication` used by PAM authentication
            # Disable Challenge-response Authentication
            # funcOpenSSHParameterConfiguration 'ChallengeResponseAuthentication' 'yes'
            # Disable Password Authentication
            funcOpenSSHParameterConfiguration 'PasswordAuthentication' 'no'
            # Use Public Key Based Authentication
            funcOpenSSHParameterConfiguration 'PubkeyAuthentication' 'yes'

            # Specify File Containing Public Key Allowed Authentication Login
            # AuthorizedKeysFile  .ssh/authorized_keys
            funcOpenSSHParameterConfiguration 'AuthorizedKeysFile' '%h/.ssh/authorized_keys'

            # Just Allow Public Key Authentication Login
            if [[ $(echo "${ssh_version} > 6.7" | bc) == 1 ]]; then
                funcOpenSSHParameterConfiguration 'AuthenticationMethods' 'publickey'
            fi

            # publickey (SSH key), password publickey (password), keyboard-interactive (verification code)
            # funcOpenSSHParameterConfiguration 'AuthenticationMethods' 'publickey,password publickey,keyboard-interactive'

        fi

    fi

    if [[ "${login_user}" == 'root' && -f "${login_user_home}/.ssh/authorized_keys" && -n "${new_username}" && "${just_keygen}" -eq 1 ]]; then
        # add authorized_keys to new created user
        local newuser_home=${newuser_home:-}
        newuser_home=$(awk -F: 'match($0,/^'"${new_username}"'/){print $6}' /etc/passwd)
        if [[ -n "${newuser_home}" ]]; then
            (umask 077; [[ -d "${newuser_home}/.ssh" ]] || mkdir -p "${newuser_home}/.ssh"; cat "${login_user_home}/.ssh/authorized_keys" >> "${newuser_home}/.ssh/authorized_keys"; chown -R "${new_username}" "${newuser_home}/.ssh")
        fi
    fi

    if [[ -z "${ssh_version:-}" ]]; then
        funcFinishStatement "SSH Configuring"
    else
        funcFinishStatement "SSH Configuring" "V ${ssh_version}"
    fi
}


#########  2-7. Firewall Setting - firewalld/iptables/ufw/SuSEfirewall2  #########
# Block Top 10 Known-bad IPs
# $download_tool https://isc.sans.edu/top10.html | sed -r -n '/ipdetails.html/{s@.*?ip=([^"]+)".*@\1@g;s@^0+@@g;s@\.0+@.@g;p}'

funcFirewall_iptables(){
    # https://github.com/ismailtasdelen/Anti-DDOS

    # specified for centos/rhel
    funcCommandExistCheck 'iptables' || funcPackageManagerOperation 'install' "iptables iptables-services"

    # start iptables servic first time will prompt "iptables: No config file." add a rule first
    if [[ ! -f /etc/sysconfig/iptables ]]; then
        # write temporarily rule to create this configuration file
        iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
        service iptables save 1> /dev/null
        funcSystemServiceManager 'iptables' 'start'
    fi

    # iptables -nL --line-num
    iptables -P INPUT ACCEPT
    iptables -F
    iptables -X
    iptables -Z
    service iptables save 1> /dev/null

    # Just allow localhost use ping
    # iptables -A INPUT -p icmp -m icmp --icmp-type 8 -m limit --limit 1/s --limit-burst 2 -j ACCEPT
    iptables -A INPUT -p icmp -m icmp --icmp-type 8 -s 127.0.0.1 -d 0/0 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type 0 -s 0/0 -d 127.0.0.1 -m state --state ESTABLISHED,RELATED -j ACCEPT

    # PORT Scanners (stealth also)
    iptables -A INPUT -m state --state NEW -p tcp --tcp-flags ALL ALL -j DROP
    iptables -A INPUT -m state --state NEW -p tcp --tcp-flags ALL NONE -j DROP

    # anti-spoofing
    iptables -N SYN_FLOOD
    iptables -A INPUT -p tcp --syn -j SYN_FLOOD
    iptables -A SYN_FLOOD -m limit --limit 2/s --limit-burst 6 -j RETURN
    iptables -A SYN_FLOOD -j DROP

    ## open http/https server port to all ##
    # iptables -A INPUT -m state --state NEW -p tcp -m multiport --dports 80,443 -j ACCEPT

    if [[ "${sshd_existed}" -eq 1 ]]; then
        if [[ "${restrict_remote_login}" -eq 1 && -n "${login_user_ip}" ]]; then
            iptables -A INPUT -s "${login_user_ip}" -m state --state NEW -m tcp -p tcp --dport "${ssh_port}" -j ACCEPT
        else
            iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport "${ssh_port}" -j ACCEPT
        fi
    fi

    # Allow loopback interface to do anything.
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # iptables -A INPUT -m state --state ESTABLISHED -j ACCEPT
    # Allow incoming connections related to existing allowed connections.
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Allow outgoing connections EXCEPT invalid
    iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

    iptables -P INPUT DROP
    service iptables save 1> /dev/null
    funcSystemServiceManager 'iptables' 'restart'
}

funcFirewall_firewalld(){
    # https://www.certdepot.net/rhel7-get-started-firewalld/
    # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-firewalld-on-centos-7

    funcCommandExistCheck 'firewalld' || funcPackageManagerOperation 'install' "firewalld"

    #/usr/lib/firewalld/services  /etc/firewalld/services
    # firewall-cmd --state
    # firewall-cmd --get-zones
        # work drop internal external trusted home dmz public block
    # firewall-cmd --zone=home --list-all
    # firewall-cmd --get-default-zone
    # firewall-cmd --list-all
    # firewall-cmd --list-ports
    # firewall-cmd --zone=public --list-services --permanent
    # firewall-cmd --get-icmptypes
    # systemctl status firewalld

    funcSystemServiceManager 'firewalld' 'start'

    firewall-cmd --set-default-zone=public &> /dev/null

    # # disable ping
    # firewall-cmd --add-icmp-block=echo-request --permanent &> /dev/null

    # firewall-cmd --zone=public --add-service=ssh --permanent &> /dev/null
    firewall-cmd --permanent --zone=public --remove-service=ssh &> /dev/null

    if [[ "${sshd_existed}" -eq 1 ]]; then
        if [[ "${restrict_remote_login}" -eq 1 && -n "${login_user_ip}" ]]; then
            # --remove-rich-rule
            # firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.0/24" port port=22 protocol="tcp" accept'
            firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" source address="'"${login_user_ip}"'" port port='"${ssh_port}"' protocol="tcp" log accept'
            # log stores in /var/log/messages

        else
            # --remove-port
            firewall-cmd --zone=public --add-port="${ssh_port}"/tcp --permanent &> /dev/null
        fi
    fi

    # http/https/mysql/dns/dhcp/kerberos/pop3/smtp/rsyncd/vnc-server/tor-socks/docker-registry
    # firewall-cmd --zone=public --add-service=http --permanent &> /dev/null
    firewall-cmd --reload 1> /dev/null
}

funcFirewall_ufw(){
    # https://help.ubuntu.com/community/UFW
    # https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands
    # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-with-ufw-on-ubuntu-16-04
    funcCommandExistCheck 'ufw' || funcPackageManagerOperation 'install' "ufw"
    funcSystemServiceManager 'ufw' 'start'

    # /etc/default/ufw

    echo "y" | ufw reset 1> /dev/null
    ufw default deny incoming 1> /dev/null
    ufw default allow outgoing 1> /dev/null

    # ufw status numbered
    # ufw allow ssh   # ufw delete allow ssh
    # ufw allow 6660:6670/tcp

    # ufw allow/deny from 192.168.100.0/24 1> /dev/null
    # ufw deny/allow in on eth0 [from 192.168.100.0/24] to any port 80 1> /dev/null
    # ufw allow to any port 80
    # ufw allow/limit from 192.168.100.106/32 to any port 22 proto tcp 1> /dev/null
    # ufw allow 80,443/tcp 1> /dev/null   #ufw allow http/https, ufw deny 80/tcp
    # ufw allow proto tcp from any to any port 80,443 1> /dev/null

    if [[ "$sshd_existed" -eq 1 ]]; then
        if [[ "${restrict_remote_login}" -eq 1 && -n "${login_user_ip}" ]]; then
            ufw limit from "${login_user_ip}" to any port "${ssh_port}" proto tcp 1> /dev/null
        else
            # ufw allow "${ssh_port}"/tcp 1> /dev/null
            ufw limit "${ssh_port}"/tcp 1> /dev/null
        fi
    fi
    # https://serverfault.com/questions/790143/ufw-enable-requires-y-prompt-how-to-automate-with-bash-script
    echo "y" | ufw enable 1> /dev/null
    ufw logging on 1> /dev/null
}

funcFirewall_SuSEfirewall2(){
    local susefirewall2
    susefirewall2=${susefirewall2:-'/etc/sysconfig/SuSEfirewall2'}
    [[ -f "${susefirewall2}${bak_suffix}" ]] || cp -fp "${susefirewall2}" "${susefirewall2}${bak_suffix}"

    ##################   SuSEfirewall2   #####################
    # funcCommandExistCheck 'SuSEfirewall2' || funcPackageManagerOperation 'install' "SuSEfirewall2"
    # funcSystemServiceManager 'SuSEfirewall2' 'start'
    #
    # # SuSEfirewall2 open EXT TCP http https
    # # SuSEfirewall2 open EXT TCP ssh
    # [[ "${sshd_existed}" -eq 1 ]] && SuSEfirewall2 open EXT TCP "${ssh_port}"
    #
    # funcSystemServiceManager 'SuSEfirewall2' 'restart'


    ##################   yast2 firewall   #####################
    # https://knowledgelayer.softlayer.com/procedure/configure-software-firewall-sles
    # https://release-8-16.about.gitlab.com/downloads/#opensuse421

    # INT - Internal Zone  |  DMZ - Demilitarized Zone  |  EXT - External Zone
    # /etc/sysconfig/SuSEfirewall2

    # yast2 firewall summary
    # yast2 firewall interfaces/logging/startup show

    # yast2 firewall interfaces add interface=`ip a s dev eth0 | awk '/ether/{printf "eth-id-%s", $2}'` zone=INT
    # yast2 firewall interfaces add interface=`ip a s dev eth1 | awk '/ether/{printf "eth-id-%s", $2}'` zone=EXT

    # list in $(yast2 firewall services list)
    # FW_CONFIGURATIONS_EXT
    # yast2 firewall services add zone=EXT service=service:sshd

    # FW_SERVICES_EXT_TCP / FW_SERVICES_EXT_UDP
    # yast2 firewall services add zone=EXT tcpport=22
    # yast2 firewall services add zone=EXT udpport=53
    # yast2 firewall services add tcpport=80,443,22,25,465,587 udpport=80,443,22,25,465,587 zone=EXT

    # FW_SERVICES_ACCEPT_EXT
    #Custome Rule, space separated list of <source network>[,<protocol>,<destination port>,<source port>,<options>]
    # FW_SERVICES_ACCEPT_EXT="116.228.89.242,tcp,777 192.168.92.123,tcp,567,789 192.168.45.145,tcp,,85"

    # yast2 firewall startup atboot/manual
    # yast2 firewall startup manual

    # rcSuSEfirewall2 status/start/stop/restart

    funcPackageManagerOperation 'install' "yast2-firewall"

    if [[ "$sshd_existed" -eq 1 ]]; then
        yast2 firewall services add zone=EXT service=service:sshd 1> /dev/null

        if [[ "${restrict_remote_login}" -eq 1 && -n "${login_user_ip}" ]]; then
            local login_user_info
            login_user_info="${login_user_ip},tcp,${ssh_port}"
            sed -r -i '/^FW_SERVICES_ACCEPT_EXT=/{s@[[:space:]]*'"${login_user_info}"'[[:space:]]*@@g;s@^(FW_SERVICES_ACCEPT_EXT=".*)(")$@\1'" ${login_user_info}"'\2@g;s@(=")[[:space:]]*@\1@g;}' "${susefirewall2}"
        else
            yast2 firewall services add zone=EXT tcpport="${ssh_port}" 1> /dev/null
        fi

    fi

    yast2 firewall startup atboot 2> /dev/null
    yast2 firewall enable 1> /dev/null
    rcSuSEfirewall2 start 1> /dev/null
}

funcFirewallSetting(){
    local firewall_type=${firewall_type:-}
    case "${pack_manager}" in
        apt-get ) firewall_type='ufw' ;;
        zypper ) firewall_type='SuSEfirewall2' ;;
        dnf|yum ) [[ $("${pack_manager}" info firewalld 2>&1 | awk -F": " 'match($1,/^Name/){print $NF;exit}') == 'firewalld' ]] && firewall_type='firewalld' || firewall_type='iptables' ;;
    esac

    funcFirewall_"${firewall_type}"
    funcFinishStatement "Firewall Setting" "${firewall_type}"
}


#########  2-8. System Optimization & Kernel Parameters Tunning  #########
funcKernelParametersTunning(){
    # 1 - /etc/security/limits.conf
    local security_limit_config=${security_limit_config:-'/etc/security/limits.conf'}
    if [[ -f "${security_limit_config}" ]]; then
        [[ -f "${security_limit_config}${bak_suffix}" ]] || cp -fp "${security_limit_config}" "${security_limit_config}${bak_suffix}"
        sed -i -r '/^\* (soft|hard) nofile /d;/End of file/d' "${security_limit_config}"
        local nofile_num='655360'
        echo -n -e "* soft nofile ${nofile_num}\n* hard nofile ${nofile_num}\n# End of file\n" >> "${security_limit_config}"
    fi

    # 2 - /etc/sysctl.conf
    local sysctl_config=${sysctl_config:-'/etc/sysctl.conf'}
    if [[ -f "${sysctl_config}" ]]; then
        [[ -f "${sysctl_config}${bak_suffix}" ]] || cp -fp "${sysctl_config}" "${sysctl_config}${bak_suffix}"
        sed -i '/Custom Kernel Parameters Setting Start/,/Custom Kernel Parameters Setting End/d' "${sysctl_config}"
        $download_tool "${sysctl_url}" >> "${sysctl_config}"
    fi

    funcFinishStatement "System Optimization & Kernel Parameters Tunning"
}


#########  2-9. GRUB Configuring  #########
funcGRUBConfiguring(){
    local grub_regexp='^[-+]?[0-9]{1,}(\.[0-9]*)?$'
    if [[ "${grub_timeout}" =~ $grub_regexp ]]; then
        grub_timeout=${grub_timeout/[-+]}
        grub_timeout=${grub_timeout%%.*}
        [[ "${grub_timeout}" -gt 4 ]] && grub_timeout=4
    else
        grub_timeout="${default_grub_timeout}"
    fi

    if [[ -f /etc/default/grub ]]; then
        sed -r -i '/^GRUB_TIMEOUT=/s@^(GRUB_TIMEOUT=).*@\1'"${grub_timeout}"'@g' /etc/default/grub

        case "${pack_manager}" in
            apt-get )
                # Debian/Ubuntu
                funcCommandExistCheck 'update-grub' && update-grub &> /dev/null
                ;;
            zypper|dnf|yum )
                # RHEL/CentOS/OpenSUSE
                if [[ -f "/boot/efi/EFI/${distro_name}/grub.cfg" ]]; then
                    # UEFI-based machines
                    grub2-mkconfig -o "/boot/efi/EFI/${distro_name}/grub.cfg" &> /dev/null
                else
                    # BIOS-based machines
                    grub2-mkconfig -o /boot/grub2/grub.cfg &> /dev/null
                fi
                ;;
        esac

    elif [[ -f /etc/grub.conf ]]; then
        sed -r -i '/^timeout=/s@^(timeout=).*@\1'"$grub_timeout"'@g' /etc/grub.conf
    fi

    funcFinishStatement "GRUB Configuring" "${grub_timeout} seconds"
}


#########  2-10. Security Configuring  #########
# - Record All User Terminal Sessions
# http://www.2daygeek.com/automatically-record-all-users-terminal-sessions-activity-linux-script-command
# https://unix.stackexchange.com/questions/25639/how-to-automatically-record-all-your-terminal-sessions-with-script-utility

# **Attention** This setting may results in utility "rsync" not work, prompt the following error:
# protocol version mismatch -- is your shell clean?
# (see the rsync man page for an explanation)
# rsync error: protocol incompatibility (code 2) at compat.c(178) [sender=3.1.2]

funcRecrodUserLoginSessionInfo(){
    local session_record_dir=${session_record_dir:-'/var/log/session'}
    if [[ ! -d "${session_record_dir}" ]]; then
        mkdir -p "${session_record_dir}"
        chmod 1777 "${session_record_dir}"
        chattr +a "${session_record_dir}"
    fi

    local session_record_profile=${session_record_profile:-'/etc/bashrc'}
    [[ -s '/etc/bash.bashrc' ]] && session_record_profile='/etc/bash.bashrc'
    sed -r -i '/Record terminal sessions start/,/Record terminal sessions end/d' "${session_record_profile}"

# append
# tee -a "${session_record_profile}" 1>/dev/null <<EOF
cat >> "${session_record_profile}" <<EOF
# Record terminal sessions start
login_ip=\${login_ip:-}
if [[ -n "\${SSH_CLIENT:-}" ]]; then
    login_ip=\$(echo "\${SSH_CLIENT}" | awk '{print \$1}')
elif [[ -n "\${SSH_CONNECTION:-}" ]]; then
    login_ip=\$(echo "\${SSH_CONNECTION}" | awk '{print \$1}')
else
    login_ip=\$(who | sed -r -n 's@.*\(([^\)]+)\).*@\1@gp')
    [[ "\${login_ip}" == ":0" ]] && login_ip='127.0.0.1'
fi

if [[ "X\${SESSION_RECORD:-}" == 'X' ]]; then
    login_timestamp=\$(date +"%Y%m%d-%a-%H%M%S")
    # \$\$ current bash process ID (PID)

    if [[ -z "\${login_ip}" ]]; then
        record_output_path="/var/log/session/\${login_timestamp}_\${USER}_r\${RANDOM}.log"
    else
        record_output_path="/var/log/session/\${login_timestamp}_\${USER}_\${login_ip}_r\${RANDOM}.log"
    fi

    SESSION_RECORD='start'
    export SESSION_RECORD
    # /usr/bin/script blongs to package util-linux or util-linux-ng
    script -t -f -q 2>"\${record_output_path}.timing" "\${record_output_path}"
    exit
fi

# ps -ocommand= -p $PPID
# Record terminal sessions end
EOF
}

funcBashSecurityConfiguration(){
    local bash_configuration_profile=${bash_configuration_profile:-'/etc/bashrc'}
    [[ -s '/etc/bash.bashrc' ]] && bash_configuration_profile='/etc/bash.bashrc'
    sed -r -i '/Bash custom setting start/,/Bash custom setting end/d' "${bash_configuration_profile}"

# append
# tee -a "${bash_configuration_profile}" 1>/dev/null <<EOF
cat >> "${bash_configuration_profile}" <<EOF
# Bash custom setting start
# automatic logout timeout (seconds)
TMOUT=300

# Bash custom setting end
EOF
}


funcSecurityConfiguring(){
    funcRecrodUserLoginSessionInfo
    funcBashSecurityConfiguration

    funcFinishStatement "Security Configuring"
}


#########  3. Operation Time Cost  #########
funcOperationTimeCost(){
    finish_time=$(date +'%s')        # processing end time
    total_time_cost=$((finish_time-start_time))   # time costing

    printf "\nTotal time cost is ${c_red}%s${c_normal} seconds!\n" "${total_time_cost}"
    printf "To make configuration effect, please ${c_red}%s${c_normal} your system!\n" "reboot"

    remove_old_kernel=${remove_old_kernel:-}

    case "${pack_manager}" in
        dnf|yum )
            remove_old_kernel="${pack_manager} remove \$(rpm -qa | awk -v verinfo=\$(uname -r) 'BEGIN{gsub(\".?el[0-9].*$\",\"\",verinfo)}match(\$0,/^kernel/){if(\$0!~verinfo) print \$0}')"
            ;;
        apt-get )
            remove_old_kernel="${pack_manager} purge \$(dpkg -l | awk -v verinfo=\$(uname -r) 'match(\$0,/linux-image-/){if(\$2!~verinfo) print \$2}')"
            ;;
        zypper )
            [[ $(rpm -qa | grep ^kernel-default | wc -l) -gt 1 ]] && remove_old_kernel="${pack_manager} remove \$(zypper packages --installed-only | awk -F\| -v verinfo=\$(uname -r) 'BEGIN{OFS=\"-\"}match(\$1,/^i/)&&match(\$0,/kernel-default/){gsub(\"-default\",\"\",verinfo);gsub(\" \",\"\",\$0);if(\$4!~verinfo){print\$3,\$4}}')"
            ;;
    esac

    [[ -z "${remove_old_kernel}" ]] || printf "\nAfter reboot system, executing following command to remove old version kernel: \n${c_blue}%s${c_normal}\n\n" "sudo ${remove_old_kernel}"
}


#########  4. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
funcPackageManagerDetection
funcOSInfoDetection
funcOperationBar

funcDisableSELinux
funcPackRepositorySetting
funcEssentialPackInstallation
funcHostnameTimezoneSetting
funcAddNormalUser
funcOpenSSHConfiguring
funcFirewallSetting
funcKernelParametersTunning
funcGRUBConfiguring
funcSecurityConfiguring

funcOperationTimeCost


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    unset str_len
    unset bak_suffix
    unset pass_change_minday
    unset pass_change_maxday
    unset pass_change_warnningday
    unset disable_ssh_root
    unset enable_sshd
    unset change_repository
    unset grub_timeout
    unset just_keygen
    unset new_hostname
    unset new_username
    unset new_timezone
    unset grant_sudo
    unset proxy_server
    unset executing_path
    unset login_user_home
    unset gateway_ip
    unset download_tool_origin
    unset download_tool
    unset country
    unset pack_manager
    unset flag
    unset distro_fullname
    unset distro_name
    unset codename
    unset version_id
    unset ip_local
    unset ip_public
    unset start_time
    unset sshd_existed
    unset ssh_port
    unset finish_time
    unset total_time_cost
    unset remove_old_kernel
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
}

trap funcTrapEXIT EXIT

# Script End

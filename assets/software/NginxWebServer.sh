#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://nginx.org/en/   https://www.nginx.com/   https://nginx.org/en/pgp_keys.html
#Installation:
# - https://nginx.org/en/linux_packages.html
# - https://www.nginx.com/resources/wiki/start/topics/tutorials/install/
#Optimization https://lempstacker.com/tw/LEMP-Installation-and-Nginx-Optimization/
#Target: Automatically Install & Update Nginx Web Server Via Package Manager On GNU/Linux
#Writer: MaxdSre
#Date: June 08, 2017 15:32 Thu +0800
#Update Date:
# - Feb 25, 2017 13:42 +0800
# - Mar 14, 2017 10:32~13:44 +0800
# - May 17, 2017 12:02 -0400


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'NWSTemp_XXXXX'}
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

readonly official_site='https://nginx.org'   #Nginx Official Site
readonly nginx_gpg_pub_key=${nginx_gpg_pub_key:-'ABF5BD827BD9BF62'}
release_type=${release_type:-'stable'}   #default is stable, if -m is setting, it will be mainline
software_fullname=${software_fullname:-'Nginx Web Server'}
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup
is_existed=${is_existed:-0}   # Default value is 0， check if system has installed Nginx
readonly os_check_script='https://raw.githubusercontent.com/MaxdSre/ShellScript/master/assets/gnulinux/gnuLinuxDistroVersionDetection.sh'

version_check=${version_check:-0}
is_uninstall=${is_uninstall:-0}
os_detect=${os_detect:-0}
list_release=${list_release:-0}
mainline_select=${mainline_select:-0}
enable_firewall=${enable_firewall:-0}
proxy_server=${proxy_server:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Installing / Updating Nginx Web Server (stable) On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check current stable release version
    -l    --list release info using Markdown format
    -o    --os info, detect os distribution info
    -m    --mainline version, default is stable version
    -f    --firewall, enable firewall (iptable/firewalld/ufw/SuSEfirewall2)
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
    bash_version="${BASH_VERSINFO[0]}"
    [[ "${bash_version}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."


    [[ "$mainline_select" -eq 1 ]] && release_type='mainline'

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

funcSystemServiceManager(){
    # systemctl / service & chkconfig
    local service_name="$1"
    local action="$2"
    if funcCommandExistCheck 'systemctl'; then
        case "${action}" in
            start|stop|reload|restart|status )
                systemctl unmask "${service_name}" &> /dev/null
                [[ "${action}" == 'start' ]] && systemctl enable "${service_name}" &> /dev/null
                systemctl "$action" "${service_name}" &> /dev/null
                ;;
            * ) systemctl status "${service_name}" 1> /dev/null ;;
        esac
    else
        case "$action" in
            start|stop|reload|restart|status )
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

funcOperationBar(){
cat <<EOF

=========================================
  Operation Processing, Just Be Patient
=========================================

EOF
}

funcOSInfoDetection(){
    if [[ "${os_detect}" -eq 1 ]]; then
        $download_tool "${os_check_script}" | bash -s --
        exit
    fi

    local osinfo=${osinfo:-}
    osinfo=$($download_tool "${os_check_script}" | bash -s -- -j | sed -r -n 's@[{}]@@g;s@","@\n@g;s@":"@|@g;s@(^"|"$)@@g;p')

    [[ -n $(echo "${osinfo}" | sed -n -r '/^error\|/p' ) ]] && funcExitStatement "${c_red}Fatal${c_normal}, this script doesn't support your system!"

    distro_fullname=${distro_fullname:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^pretty_name\|/p') ]] && distro_fullname=$(echo "${osinfo}" | awk -F\| 'match($1,/^pretty_name$/){print $NF}')

    distro_name=${distro_name:-}
    if [[ -n $(echo "${osinfo}" | sed -n -r '/^distro_name\|/p') ]]; then
        distro_name=$(echo "${osinfo}" | awk -F\| 'match($1,/^distro_name$/){print $NF}')
        distro_name=${distro_name%%-*}    # centos, fedora
    fi

    family_name=${family_name:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^family_name\|/p') ]] && family_name=$(echo "${osinfo}" | awk -F\| 'match($1,/^family_name$/){print $NF}')

    codename=${codename:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^codename\|/p') ]] && codename=$(echo "${osinfo}" | awk -F\| 'match($1,/^codename$/){print $NF}')

    version_id=${version_id:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^version_id\|/p') ]] && version_id=$(echo "${osinfo}" | awk -F\| 'match($1,/^version_id$/){print $NF}')

    ip_local=${ip_local:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^ip_local\|/p') ]] && ip_local=$(echo "${osinfo}" | awk -F\| 'match($1,/^ip_local$/){print $NF}')

    ip_public=${ip_public:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^ip_public\|/p') ]] && ip_public=$(echo "${osinfo}" | awk -F\| 'match($1,/^ip_public$/){print $NF}')
}


#########  1-2 getopts Operation  #########
start_time=$(date +'%s')    # Start Time Of Operation

while getopts "hcuolmfp:" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        u ) is_uninstall=1 ;;
        o ) os_detect=1 ;;
        l ) list_release=1 ;;
        m ) mainline_select=1 ;;
        f ) enable_firewall=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done



#########  2-1. Release Info List  #########
funcReleaseInfoList(){
    printf "${c_blue}%s${c_normal}\n\n" "Nginx Release News"
    $download_tool "${official_site}" | awk 'BEGIN{print "Date|Version|Type\n---|---|---"}$0~/^(stable|mainline)/{$0~/stable/?type="stable":type="mainline";b=gensub(/[[:space:]]*<[^>]*>/,"","g",a);c=gensub(/nginx-/,"|","g",b);printf("%s|%s\n",c,type)};{a=$0}'
    exit
}

#########  2-2. Firewall Setting  #########
funcFirewallSetting(){
    local sshd_existed=${sshd_existed:-0}
    if [[ -f '/etc/ssh/sshd_config' ]]; then
        local sshd_existed=1
        local ssh_port=${ssh_port:-22}
        ssh_port=$(sed -r -n '/^#?Port/s@^#?Port[[:space:]]*(.*)@\1@p' /etc/ssh/sshd_config 2> /dev/null)
    fi

    case "${distro_name}" in
        rhel|centos )
            if [[ ${version_id%%.*} -ge 7 ]]; then
                funcCommandExistCheck 'firewalld' || yum -y install firewalld &> /dev/null
                funcSystemServiceManager 'firewalld' 'start'

                # [[ "$sshd_existed" -eq 1 ]] && firewall-cmd --zone=public --add-service=ssh --permanent &> /dev/null
                [[ "${sshd_existed}" -eq 1 ]] && firewall-cmd --zone=public --add-port="${ssh_port}"/tcp --permanent &> /dev/null
                firewall-cmd --zone=public --add-service=http --permanent &> /dev/null
                firewall-cmd --zone=public --add-service=https --permanent &> /dev/nul
                firewall-cmd --reload 1> /dev/null
            else
                funcCommandExistCheck 'iptables' || yum -y install iptables iptables-services 1> /dev/null
                if [[ ! -f /etc/sysconfig/iptables ]]; then
                    iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
                    service iptables save 1> /dev/null
                    funcSystemServiceManager 'iptables' 'start'

                    iptables -P INPUT ACCEPT
                    iptables -F
                    iptables -X
                    iptables -Z
                    service iptables save 1> /dev/null
                    # iptables -A INPUT -i lo -j ACCEPT
                    # iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
                    [[ "${sshd_existed}" -eq 1 ]] && iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport "${ssh_port}" -j ACCEPT
                    iptables -A INPUT -m state --state NEW -p tcp -m multiport --dports 80,443 -j ACCEPT
                    iptables -A INPUT -m state --state ESTABLISHED -j ACCEPT
                    iptables -P INPUT DROP
                else
                    [[ "${sshd_existed}" -eq 1 ]] && iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport "${ssh_port}" -j ACCEPT
                    iptables -A INPUT -m state --state NEW -p tcp -m multiport --dports 80,443 -j ACCEPT
                fi

                service iptables save 1> /dev/null
                funcSystemServiceManager 'iptables' 'restart'
            fi
            ;;
        debian|ubuntu )
            funcCommandExistCheck 'ufw' || apt-get -y install ufw 1> /dev/null
            funcSystemServiceManager 'ufw' 'start'

            [[ "${sshd_existed}" -eq 1 ]] && ufw allow "${ssh_port}/tcp" 1> /dev/null
            [[ "${sshd_existed}" -eq 1 ]] && ufw limit "${ssh_port}/tcp" 1> /dev/null
            ufw allow 80,443/tcp 1> /dev/null
            echo "y" | ufw enable 1> /dev/null
            # ufw logging on 1> /dev/null
            apt-get -y autoremove 1> /dev/null
            ;;
        sles|opensuse )
            funcCommandExistCheck 'SuSEfirewall2' || zypper in -yl SuSEfirewall2 1> /dev/null
            funcSystemServiceManager 'SuSEfirewall2' 'start'
            local service_list='http https'
            [[ "${sshd_existed}" -eq 1 ]] && service_list="${service_list} ${ssh_port}"
            SuSEfirewall2 open EXT TCP "${service_list}"
            funcSystemServiceManager 'SuSEfirewall2' 'restart'
            ;;
    esac
}

#########  2-3. Install/Update/Upgrade/Uninstall Operation Function  #########
funcOperationProcess(){
    case "${1:-}" in
        update ) local action=1 ;;
        upgrade ) local action=2 ;;
        remove ) local action=3 ;;
        * )  local action=0 ;; # default 0 installation
    esac

    if [[ "${mainline_select}" -eq 1 ]]; then
        local has_mainline="$release_type/"
    else
        local has_mainline=''
    fi

    case "${distro_name}" in
        rhel|centos )
            source_file='/etc/yum.repos.d/nginx.repo'
            case "${action}" in
                0 )
                    [[ -f "${source_file}" ]] && cp -fp "${source_file}" "${source_file}${bak_suffix}"
                    echo -n -e "[nginx]\nname=nginx repo\nbaseurl=${official_site}/packages/${has_mainline}${distro_name}/${version_id%%.*}/\$basearch/\ngpgcheck=0\nenabled=1\n" > "${source_file}"
                    yum clean all 1> /dev/null
                    yum -q makecache fast 1> /dev/null
                    yum -y install nginx &> /dev/null
                    ;;
                1 )
                    yum -y update nginx &> /dev/null
                    ;;
                2 )
                    funcOperationProcess
                    ;;
                3 )
                    yum -y remove nginx &> /dev/null
                    if [[ -f "${source_file}${bak_suffix}" ]]; then
                        mv "${source_file}${bak_suffix}" "$source_file"
                    else
                        [[ -f "${source_file}" ]] && rm -f "${source_file}"
                    fi
                    ;;
            esac
            ;;
        debian|ubuntu )
            source_file='/etc/apt/sources.list.d/nginx.list'
            case "${action}" in
                0 )
                #Use https protocol, other it may prompt error
                [[ -f "${source_file}" ]] && cp -fp "${source_file}" "${source_file}${bak_suffix}"
                $download_tool "${official_site}/keys/nginx_signing.key" | apt-key add - &> /dev/null   #method 1
                # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$nginx_gpg_pub_key" &> /dev/null  #method 2
                [[ "${distro_name}" == 'ubuntu' && ${version_id%%.*} -ge '17' ]] && codename='yakkety'    # currently nginx not provide zesty(17.04) repo

                echo -n -e "deb ${official_site}/packages/${has_mainline}$distro_name/ ${codename} nginx\ndeb-src ${official_site}/packages/${distro_name}/ ${codename} nginx\n" > "${source_file}"
                # apt-get -y --force-yes install
                apt-get -y install apt-transport-https &> /dev/null
                apt-get update 1> /dev/null
                apt-get -y install nginx &> /dev/null
                funcCommandExistCheck 'systemctl' || apt-get -y install sysv-rc-conf &> /dev/null   # same to chkconfig
                    ;;
                1 )
                    apt-get -y install --only-upgrade nginx &> /dev/null
                    ;;
                2 )
                    funcOperationProcess
                    ;;
                3 )
                    apt-get -y purge nginx &> /dev/null
                    apt-get -y autoremove 1> /dev/null
                    if [[ -f "${source_file}${bak_suffix}" ]]; then
                        mv "${source_file}${bak_suffix}" "$source_file"
                    else
                        [[ -f "${source_file}" ]] && rm -f "${source_file}"
                    fi
                    apt-key del "${nginx_gpg_pub_key}" &> /dev/null
                    ;;
            esac
            ;;
        sles|opensuse )
            case "${action}" in
                0 )
                    zypper rr -y nginx &> /dev/null
                    zypper ar -fG -t yum -c ''"${official_site}"'/packages/'"${has_mainline}"'sles/12' nginx &> /dev/null
                    zypper ref -f -r nginx 1> /dev/null
                    # zypper se -s -r nginx --match-exact nginx
                    zypper in -yl -r nginx nginx 1> /dev/null
                    ;;
                1 )
                    zypper up -y nginx &> /dev/null
                    ;;
                2 )
                    funcOperationProcess
                    ;;
                3 )
                    zypper rm -y nginx &> /dev/null
                    zypper rr -y nginx &> /dev/null
                    ;;
            esac
            ;;
        * )
            funcExitStatement "${c_red}Sorry${c_normal}: your ${c_red}${distro_fullname}${c_normal} may not be supported by Nginx official repo currently!"
            ;;
    esac
}

#########  2-3. Local Version Check  #########
funcVersionLocalCheck(){
    if funcCommandExistCheck 'nginx'; then
        is_existed=1
        if [[ "${bash_version}" -ge 4 ]]; then
            current_version_local=$(nginx -V |& sed -r -n '1s@.*/([[:digit:].]*)@\1@p')
        else
            current_version_local=$(nginx -V 2>&1 | sed -r -n '1s@.*/([[:digit:].]*)@\1@p')
        fi
    fi
}

#########  2-3. Online Version Check & Operating  #########
funcVersionOnlineCheck(){
    version_online_arr=($($download_tool "${official_site}" | sed -n -r '/'"${release_type}"'/{0,/'"${release_type}"'/{x;s@<[^>]*>@@g;s@(.*)nginx-(.*)@\1 \2@p}};h'))
    release_date=${version_online_arr[0]}
    latest_version_online=${version_online_arr[1]}

    [[ -z "${latest_version_online}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: fail to get latest online version on official site!"

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
            funcExitStatement "Existed version local (${c_red}${current_version_local}${c_normal}) > Latest ${c_blue}${release_type}${c_normal} online version (${c_red}${latest_version_online}${c_normal})!"
        elif [[ "${latest_version_online}" > "${current_version_local}" && -n "${current_version_local}" ]]; then
            printf "Existed version local ($c_red%s$c_normal) < Latest $c_blue%s$c_normal online version ($c_red%s$c_normal)!\n" "${current_version_local}" "${release_type}" "${latest_version_online}"
            funcOperationBar
            update_upgrade_enable=1     # update or upgrade
        else
            printf "Existed version local (${c_red}%s${c_normal}) < Latest ${c_blue}${release_type}${c_normal} version online (${c_red}%s${c_normal})!\n" "${current_version_local}" "${latest_version_online}"
        fi
    else
        printf "No %s find in your system!\n" "${software_fullname}"
        funcOperationBar
        funcOperationProcess    # install
    fi

    # - update or upgrade
    if [[ "${update_upgrade_enable:-0}" -eq 1 ]]; then
        release_type_local='stable'
        case "${distro_name}" in
            rhel|centos )
                [[ -n $(sed -r -n '/mainline/p' /etc/yum.repos.d/nginx.repo) ]] && release_type_local='mainline' ;;
            debian|ubuntu )
                [[ -n $(sed -r -n '/mainline/p' /etc/apt/sources.list.d/nginx.list) ]] && release_type_local='mainline' ;;
            sles|opensuse )
                [[ -n $(zypper lr -Eau | sed -r -n '/.*nginx.*mainline.*/p') ]] && release_type_local='mainline' ;;
        esac

        # 本地版本 < 在線版本
        # stable  mainline 升級
        # stable  stable    更新
        # mainline  mainline  更新
        # mainline  (stable < mainline) 更新
        if [[ "${release_type_local}" == 'stable' && "${release_type}" == 'mainline' ]]; then
            funcOperationProcess 'upgrade'
        else
            funcOperationProcess 'update'
        fi

    fi
}

#########  2-4. Uninstall  #########
funcUninstallOperation(){
    [[ "${is_existed}" -eq 1 ]] || funcExitStatement "${c_blue}Note${c_normal}: no ${software_fullname} is found in your system!"

    funcOperationBar
    funcOperationProcess 'remove'

    funcCommandExistCheck 'nginx' || funcExitStatement "${software_fullname} (v ${c_red}${current_version_local}${c_normal}) is successfully removed from your system!"
}

funcPostInstallationConfiguration(){
    [[ ${bash_version} -ge 4 ]] && new_installed_version=$(nginx -V |& sed -r -n '1s@.*/([[:digit:].]*)@\1@p') || new_installed_version=$(nginx -V 2>&1 | sed -r -n '1s@.*/([[:digit:].]*)@\1@p')

    if [[ "${latest_version_online}" != "${new_installed_version}" ]]; then
        funcOperationProcess 'remove'
        [[ "${is_existed}" -eq 1 ]] && operation_type='update' || operation_type='install'
        funcExitStatement "${c_red}Sorry${c_normal}: ${c_blue}${operation_type}${c_normal} operation is faily!"
    fi

    funcSystemServiceManager 'nginx' 'start'

    # - check web dir
    nginx_web_dir=$(sed -r -n '/[[:space:]]*location[[:space:]]*\/[[:space:]]*\{/,/}/{/root/s@[[:space:]]*root[[:space:]]*(.*);@\1@p}' /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf 2> /dev/null)
    [[ -n "${nginx_web_dir}" && -d "${nginx_web_dir}" ]] || nginx_web_dir='/usr/share/nginx/html'
    echo "${distro_fullname}" >> "${nginx_web_dir}/index.html"

    if [[ -n "${ip_public}" ]]; then
        ip_address="${ip_public}"
    elif [[ -n "${ip_local}" && "${ip_public}" != "${ip_local}" ]]; then
        ip_address='127.0.0.1'
    fi

    if [[ $($download_tool -I "${ip_address}" | awk '{print $2;exit}') == '200' ]]; then
        if [[ "$is_existed" -eq 1 ]]; then
            printf "%s was updated to ${c_blue}%s${c_normal} version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${release_type}" "${latest_version_online}"
        else
            printf "Installing %s ${c_blue}%s${c_normal} version ${c_red}%s${c_normal} successfully!\n" "${software_fullname}" "${release_type}" "${latest_version_online}"
        fi

        printf "Opening ${c_blue}%s${c_normal} in your browser to see welcome page!\n" "http://${ip_address}"
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
funcOSInfoDetection
[[ "$list_release" -eq 1 ]] && funcReleaseInfoList

funcVersionLocalCheck
if [[ "${is_uninstall}" -eq 1 ]]; then
    funcUninstallOperation
else
    funcVersionOnlineCheck
    [[ "$enable_firewall" -eq 1 ]] && funcFirewallSetting
    funcPostInstallationConfiguration
    funcTotalTimeCosting
fi


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset release_type
    unset software_fullname
    unset bak_suffix
    unset is_existed
    unset version_check
    unset is_uninstall
    unset os_detect
    unset list_release
    unset mainline_select
    unset enable_firewall
    unset proxy_server
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

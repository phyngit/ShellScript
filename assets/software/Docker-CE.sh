#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://www.docker.com
#Installation:
# - https://docs.docker.com/engine/installation/
# - https://docs.docker.com/engine/userguide/
# - https://docs.docker.com/engine/installation/linux/linux-postinstall/
# - https://www.ptrace-security.com/2017/06/14/how-to-install-docker-on-kali-linux-2017-1/    How to install Docker on Kali Linux 2017
# - https://macay.webhostbug.com/discussion/393/install-docker-in-kali-linux-debian-testing   Install Docker in Kali Linux Debian Testing
#Target: Automatically Install & Update Docker Via Package Manager On GNU/Linux
#Writer: MaxdSre:
#Date: Aug 09, 2017 11:58 +0800
#Update Date
# - May 19, 2017 09:24 -0400
# - Jun 05, 2017 08:56 +0800

########################################################
# Docker CE: Ubuntu, Debian, CentOS, Fedora            #
# Docker EE: Ubuntu, RHEL, CentOS, Oracle Linux, SLES  #
# Docker CE Stable Timeline: March, June, September    #
########################################################


#######################################################################
# Debian: wheezy, jessie, stretch                                     #
# Ubuntu: trusty(14.04), xenial(16.04), yakkety(16.10), zesty(17.04)  #
# CentOS: 7
# Kali Linux 2017.01  ==  Debian Stretch                              #
#######################################################################

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'DCETemp_XXXXX'}
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
readonly official_site='https://www.docker.com'   #Docker Official Site
readonly download_page='https://download.docker.com/linux'
readonly os_check_script='https://raw.githubusercontent.com/MaxdSre/ShellScript/master/assets/gnulinux/gnuLinuxDistroVersionDetection.sh'
docker_data_dir=${docker_data_dir:-'/var/lib/docker'}

is_existed=${is_existed:-0}
version_check=${version_check:-0}
is_edge=${is_edge:-0}
os_detect=${os_detect:-0}
is_uninstall=${is_uninstall:-0}
remove_datadir=${remove_datadir:-0}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
script [options] ...
script | sudo bash -s -- [options] ...
Installing / Updating Docker CE(stable) On GNU/Linux (CentOS/Debian/Ubuntu)!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -c    --check, check installed or not
    -e    --edge, choose edge version, default is stable
    -o    --os info, detect os distribution info
    -u    --uninstall, uninstall software installed
    -r    --remove datadir /var/lib/docker, along with -u
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
    # 2 - specified for CentOS/Debian/Ubuntu
    [[ -s /etc/redhat-release || -s /etc/debian_version ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script just support CentOS/Debian/Ubuntu!"

    local kernel_version=${kernel_version:-}
    kernel_version=$(uname -r | sed -r -n 's@([0-9]+.[0-9]+).*@\1@p')
    kernel_version=${kernel_version%%-*}

    if ! funcCommandExistCheck 'bc'; then
        if funcCommandExistCheck 'yum'; then
            yum -y -q install bc 1> /dev/null
        elif funcCommandExistCheck 'apt-get'; then
            apt-get -yq install bc 1> /dev/null
        fi
    fi


    if [[ $(echo "${kernel_version} < 3.10" | bc) == 1 ]]; then
        funcExitStatement "${c_red}Sorry${c_normal}: Your Linux kernel version ${c_blue}$(uname -r)${c_normal} is not supported for running docker. Please upgrade your kernel to ${c_blue}3.10.0${c_normal} or newer!"
    fi

    # 3 - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && now_user="$USER" || now_user="$SUDO_USER"
    # [[ "${now_user}" == 'root' ]] && user_home='/root' || user_home="/home/${now_user}"
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

    codename=${codename:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^codename\|/p') ]] && codename=$(echo "${osinfo}" | awk -F\| 'match($1,/^codename$/){print $NF}')

    version_id=${version_id:-}
    [[ -n $(echo "${osinfo}" | sed -n -r '/^version_id\|/p') ]] && version_id=$(echo "${osinfo}" | awk -F\| 'match($1,/^version_id$/){print $NF}')

    local is_support=${is_support:-1}   # is docker official repo support

    case "${distro_name}" in
        centos ) [[ "${version_id%%.*}" -lt 7 ]] && is_support=0 ;;
        debian|ubuntu )
            case "$distro_name" in
                debian ) [[ "${version_id%%.*}" -lt 7 ]] && is_support=0 ;;
                ubuntu ) [[ "${codename}" =~ (trusty|xenial|yakkety|zesty) ]] || is_support=0 ;;
            esac
            ;;
        kali ) [[ "${version_id%%.*}" -lt 2017 ]] && is_support=0 ;;
        * ) is_support=0 ;;
    esac

    [[ "${is_support}" -eq 1 ]] || funcExitStatement "Sorry, this script doesn't support your system ${c_blue}${distro_fullname}${c_normal}."
}

#########  1-2 getopts Operation  #########
start_time=$(date +'%s')    # Start Time Of Operation

while getopts "ceourp:h" option "$@"; do
    case "$option" in
        c ) version_check=1 ;;
        e ) is_edge=1 ;;
        o ) os_detect=1 ;;
        u ) is_uninstall=1 ;;
        r ) remove_datadir=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2. Docker Operation Function  #########
funcDockerLocalVersionCheck(){
    if funcCommandExistCheck 'docker'; then
        docker_local_version=$(docker version --format '{{.Server.Version}}')
        if [[ -n "${docker_local_version}" ]]; then
            docker_local_version=${docker_local_version/.ce/-ce}
            if [[ "${version_check}" -eq 1 ]]; then
                funcExitStatement "Docker version installed in your system is ${c_red}${docker_local_version}${c_normal}."
            else
                printf "Docker version installed in your system is ${c_red}%s${c_normal}.\n" "${docker_local_version}"
            fi
            is_existed=1
        fi
    else
        if [[ "${version_check}" -eq 1 ]]; then
            funcExitStatement "No Docker find in your system."
        else
            if [[ "$is_uninstall" -ne 1 ]]; then
                printf "No Docker find in your system.\n"
                funcOperationBar
            fi
        fi

    fi
}

funcLatestOnlineVersionCheck(){
    local docker_online_version=${docker_online_version:-}
    case "${distro_name}" in
        centos )
            docker_online_version=$(yum info available docker-ce 2> /dev/null | sed -r -n '/^Version/s@.*:[[:space:]]*(.*)$@\1@p')
            if [[ -z "${docker_online_version}" ]]; then
                docker_online_version=$(yum info installed docker-ce 2> /dev/null | sed -r -n '/^Version/s@.*:[[:space:]]*(.*)$@\1@p')
            fi
            ;;
        debian|ubuntu )
            docker_online_version=$(apt-cache madison docker-ce | sed -r -n '/docker-ce/{1s@[^[:digit:]]*([[:digit:].]*).*@\1-ce@p}')
            ;;
        kali )
            docker_online_version=$(apt-cache madison docker-engine | sed -r -n '/docker-engine/{1s@[^[:digit:]]*([[:digit:].]*).*@\1-ce@p}')
            ;;
    esac

    docker_online_version=${docker_online_version/.ce/-ce}

    if [[ "$is_existed" -eq 1 && -n "${docker_online_version}" ]]; then
        if [[ "${docker_local_version}" == "${docker_online_version}" ]]; then
            funcExitStatement "${c_blue}Attention:${c_normal} latest online version ${c_red}${docker_local_version}${c_normal} existed in your system!"
        else
            printf "Available version online is ${c_red}%s${c_normal}.\n" "${docker_online_version}"
            funcOperationBar
        fi
    fi
}

funcCentOSOperation(){
    # https://docs.docker.com/engine/installation/linux/centos/
    local action=${action:-0}  # installation
    case "${1:-}" in
        remove ) local action=1 ;;
        * ) local action=0 ;;
    esac

    local docker_repo_path='/etc/yum.repos.d/docker-ce.repo'

    case "${action}" in
        0 )
            if [[ ! -f "${docker_repo_path}" ]]; then
                # 1 - Remove Unofficial Old Docker packages
                yum -q makecache fast &> /dev/null
                yum -y -q remove docker docker-{common,selinux,engine} container-selinux &> /dev/null
            fi

            # 2 - Add Docker Repository
            # $download_tool $download_page/centos/docker-ce.repo | sed -n '/ce-stable-debuginf/,$d;/^$/d;p' > /etc/yum.repos.d/docker-ce.repo
            $download_tool "${download_page}/centos/docker-ce.repo" > "${docker_repo_path}"

            sed -i '/enabled=/s@enabled=1@enabled=0@g' "${docker_repo_path}"
            if [[ "${is_edge}" -eq 1 ]]; then
                sed -i '/docker-ce-edge]$/,/docker-ce-edge-debuginfo/s@enabled=0@enabled=1@' "${docker_repo_path}"
            else
                sed -i '/docker-ce-stable]$/,/docker-ce-stable-debuginfo/s@enabled=0@enabled=1@' "${docker_repo_path}"
            fi

            # 3 - Install Docker-CE
            yum -q makecache fast &> /dev/null
            funcLatestOnlineVersionCheck
            yum -y -q install docker-ce &> /dev/null
            ;;
        1 )
            yum -y -q remove docker-ce &> /dev/null
            [[ -f "${docker_repo_path}" ]] && rm -f "${docker_repo_path}"
            [[ "${remove_datadir}" -eq 1 && -d "${docker_data_dir}" ]] && rm -rf "${docker_data_dir}"
            ;;
    esac
}

funcDebianOperation(){
    # https://docs.docker.com/engine/installation/linux/ubuntu/
    # https://docs.docker.com/engine/installation/linux/debian/
    local action=${action:-0}  # installation
    case "${1:-}" in
        remove ) local action=1 ;;
        * ) local action=0 ;;
    esac

    local docker_repo_path='/etc/apt/sources.list.d/docker.list'

    case "${action}" in
        0 )
            if [[ ! -f "${docker_repo_path}" ]]; then
                # 1 - Remove Unofficial Old Docker packages
                apt-get -yq purge docker{,-engine} &> /dev/null
                apt-get -yq autoremove &> /dev/null
                apt-get update &> /dev/null

                apt-get -yq --force-yes install apt-transport-https &> /dev/null

                # 2 - Essential Packages
                funcCommandExistCheck 'systemctl' || apt-get -yq install sysv-rc-conf &> /dev/null
                # software-properties-common used for add-apt-repository
                # python-software-properties used for add-apt-repository
                external_pack='apt-transport-https ca-certificates curl'
                case "${distro_name}" in
                    ubuntu )
                        if [[ "${version_id}" == '14.04' ]]; then # Trusty 14.04
                            external_pack="${external_pack} linux-image-extra-$(uname -r) linux-image-extra-virtual"
                        fi
                        # external_pack="${external_pack} software-properties-common"
                        ;;
                    debian )
                        if [[ "${version_id%%.*}" -eq 7 ]]; then    # Wheezy 7.x
                            # https://docs.docker.com/engine/installation/linux/debian/#install-using-the-repository
                            # external_pack="${external_pack} python-software-properties"
                            echo "deb http://ftp.debian.org/${distro_name} ${codename}-backports main" > /etc/apt/sources.list.d/backports.list
                            # apt-get -t $codename-backports install "package"
                        else
                            # external_pack="${external_pack} gnupg2 software-properties-common"
                            external_pack="${external_pack} gnupg2"
                        fi
                        ;;
                esac

                apt-get -yq install "${external_pack}" &> /dev/null

                # 3 - Import GnuPG key
                $download_tool "${download_page}/${distro_name}/gpg" | apt-key add - &> /dev/null
                # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0EBFCD88

                # 4 - Add Docker Repository
                [[ -f '/etc/apt/sources.list' ]] && sed -i '/docker.com/d' /etc/apt/sources.list
            fi

            if [[ "$is_edge" -eq 1 ]]; then
                echo "deb [arch=amd64] ${download_page}/${distro_name} ${codename} stable edge" > "${docker_repo_path}"
            else
                echo "deb [arch=amd64] ${download_page}/${distro_name} ${codename} stable" > "${docker_repo_path}"
            fi

            # 5 - Install Docker-CE
            apt-get update &> /dev/null
            funcLatestOnlineVersionCheck
            apt-get -yq install docker-ce &> /dev/null
            ;;
        1 )
            apt-get -yq purge docker-ce &> /dev/null
            apt-get -yq autoremove &> /dev/null
            [[ -f "${docker_repo_path}" ]] && rm -f "${docker_repo_path}"
            # delete docker GnuPG key
            apt-key del 0EBFCD88 1> /dev/null
            [[ "${remove_datadir}" -eq 1 && -d "${docker_data_dir}" ]] && rm -rf "${docker_data_dir}"
            ;;
    esac
}

funcKaliOperation(){
    # https://www.ptrace-security.com/2017/06/14/how-to-install-docker-on-kali-linux-2017-1/
    #https://macay.webhostbug.com/discussion/393/install-docker-in-kali-linux-debian-testing
    local action=${action:-0}  # installation
    case "${1:-}" in
        remove ) local action=1 ;;
        * ) local action=0 ;;
    esac

    local docker_repo_path='/etc/apt/sources.list.d/docker.list'

    case "${action}" in
        0 )
            local dockerproject_url=${dockerproject_url:-'https://apt.dockerproject.org'}

            if [[ ! -f "${docker_repo_path}" ]]; then
                # 1 - Remove Unofficial Old Docker packages
                apt-get -yq purge docker{,-engine} &> /dev/null
                apt-get -yq autoremove &> /dev/null
                apt-get update &> /dev/null

                apt-get -yq --force-yes install apt-transport-https &> /dev/null

                # 2 - Essential Packages
                funcCommandExistCheck 'systemctl' || apt-get -yq install sysv-rc-conf &> /dev/null
                external_pack='apt-transport-https ca-certificates dirmngr'
                apt-get -yq install "${external_pack}" &> /dev/null

                # 3 - Import GnuPG key
                # Docker Release Tool (releasedocker) <docker@docker.com>
                $download_tool "${dockerproject_url}/gpg" | apt-key add - &> /dev/null
                # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

                # 4 - Add Docker Repository
                [[ -f '/etc/apt/sources.list' ]] && sed -i '/docker.com/d' /etc/apt/sources.list
            fi

            echo "deb ${dockerproject_url}/repo debian-stretch main" > "${docker_repo_path}"

            # 5 - Install Docker-CE
            apt-get update &> /dev/null
            funcLatestOnlineVersionCheck
            apt-get -yq install docker-engine &> /dev/null
            ;;
        1 )
            apt-get -yq purge docker-engine &> /dev/null
            apt-get -yq autoremove &> /dev/null
            [[ -f "${docker_repo_path}" ]] && rm -f "${docker_repo_path}"
            # delete docker GnuPG key
            apt-key del 58118E89F3A912897C070ADBF76221572C52609D 1> /dev/null
            [[ "${remove_datadir}" -eq 1 && -d "${docker_data_dir}" ]] && rm -rf "${docker_data_dir}"
            ;;
    esac
}

funcDockerOperation(){
    case "${distro_name}" in
        centos )
            local operation_name='CentOS'
            ;;
        debian|ubuntu )
            local operation_name='Debian'
            ;;
        kali )
            local operation_name='Kali'
            ;;
        * ) funcExitStatement "Sorry, Docker repo don't support your system ${c_blue}${distro_fullname}${c_normal}." ;;
    esac

    if [[ "${is_uninstall}" -eq 1 ]]; then
        if [[ "${is_existed}" -eq 1 ]]; then
            [[ "${now_user}" == 'root' ]] || gpasswd -d "${now_user}" docker &> /dev/null
            func${operation_name}Operation 'remove'
            funcCommandExistCheck 'docker' || funcExitStatement "Docker is successfully removed from your system!"
        else
            funcExitStatement "No Docker find in your system."
        fi

    else
        # funcOperationBar
        func${operation_name}Operation

        if [[ "${now_user}" != 'root' ]]; then
            groupadd docker &> /dev/null
            usermod -aG docker "${now_user}" &> /dev/null
        fi

        funcSystemServiceManager 'docker' 'start'
        local current_docker_version=${current_docker_version:-}
        current_docker_version=$(docker version --format '{{.Server.Version}}')
        printf "Current Docker version in your system is ${c_red}%s${c_normal}.\n" "${current_docker_version}"

    fi
}

#########  3. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
funcOSInfoDetection

funcDockerLocalVersionCheck
funcDockerOperation


########  4.Operation Time Cost  ########
finish_time=$(date +'%s')        # End Time Of Operation
total_time_cost=$((finish_time-start_time))   # Total Time Of Operation
printf "Total time cost is $c_red%s$c_normal seconds!\n" "$total_time_cost"
[[ "${is_uninstall}" -eq 1 || "${is_existed}" -eq 1 ]] || printf "${c_blue}%s${c_normal}\n" "Please logout then relogin to make docker service effort!"


#########  5. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset docker_data_dir
    unset is_existed
    unset version_check
    unset is_edge
    unset os_detect
    unset is_uninstall
    unset remove_datadir
    unset download_tool
    unset proxy_server
    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

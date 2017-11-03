#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #IFS  Internal Field Separator

#Target: Installing MySQL/MariaDB/Percona Via Their Official Repository On GNU/Linux (RHEL/CentOS/Fedora/Debian/Ubuntu/SLES/OpenSUSE)
#Writer: MaxdSre
#Date: Nov 03, 2017 16:49 Fri +0800
#Update Time:
# - July 19, 2017 13:18 Wed +0800 ~ Sep 08, 2017 17:58 Fri +0800
# - Oct 27, 2017 17:46 Fri +0800

# https://www.percona.com/blog/2017/11/02/mysql-vs-mariadb-reality-check/
# https://www.atlantic.net/community/whatis/mysql-vs-mariadb-vs-percona/

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'MVTemp_XXXXX'}
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
str_len=${str_len:-16}               # printf str width
bak_suffix=${bak_suffix:-'_bak'}     # suffix word for file backup

readonly github_raw_url='https://raw.githubusercontent.com'
readonly mysql_veriants_version_list="${github_raw_url}/MaxdSre/ShellScript/master/sources/mysqlVariantsVersionAndLinuxDistroRelationTable.txt"

auto_installation=${auto_installation:-0}
root_password_new=${root_password_new:-''}
mysql_variant_type=${mysql_variant_type:-''}
variant_version=${variant_version:-''}
proxy_server=${proxy_server:-''}

readonly data_dir_default='/var/lib/mysql'
readonly mysql_port_default='3306'

data_dir=${data_dir:-"${data_dir_default}"}
mysql_port=${mysql_port:-"${mysql_port_default}"}

db_name=${db_name:-}
db_version=${db_version:-}
db_version_no_new=${db_version_no_new:-}

service_name=${service_name:-'mysql'}

# is_existed=${is_existed:-0}
# version_check=${version_check:-0}
# is_uninstall=${is_uninstall:-0}
# remove_datadir=${remove_datadir:-0}


#########  1-1 Initialization Prepatation  #########
funcInfoPrintf(){
    local item="$1"
    local value="$2"
    [[ -n "$1" && -n "$2" ]] && printf "%${str_len}s ${c_red}%s${c_normal}\n" "$item:" "$value"
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
    [[ -f '/etc/os-release' || -f '/etc/redhat-release' || -f '/etc/debian_version' || -f '/etc/SuSE-release' ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script just support RHEL/CentOS/Debian/Ubuntu/OpenSUSE derivates!"

    # 3 - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    # [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    funcCommandExistCheck 'curl' || funcExitStatement "${c_red}Error${c_normal}: No ${c_blue}curl${c_normal} command finds, please install it!"

    # 4 - current login user detection
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && login_user="$USER" || login_user="$SUDO_USER"
    login_user_home=${login_user_home:-}
    login_user_home=$(awk -F: 'match($1,/^'"${login_user}"'$/){print $(NF-1)}' /etc/passwd)
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

    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal}!"
    fi

}

funcSystemServiceManager(){
    # systemctl / service & chkconfig
    local l_service_name="${1:-}"
    local action="${2:-}"
    if funcCommandExistCheck 'systemctl'; then
        case "${action}" in
            start|stop|reload|restart|status|enable|disable )
                systemctl unmask "${l_service_name}" &> /dev/null
                [[ "${action}" == 'start' ]] && systemctl enable "${l_service_name}" &> /dev/null
                systemctl "$action" "${l_service_name}" &> /dev/null
                ;;
            * ) systemctl status "${l_service_name}" 1> /dev/null ;;
        esac
    else
        case "$action" in
            start|stop|restart|status )

                if funcCommandExistCheck 'chkconfig'; then
                    local sysv_command='chkconfig'  # for RedHat/OpenSUSE
                elif funcCommandExistCheck 'sysv-rc-conf'; then
                    local sysv_command='sysv-rc-conf'   # for Debian
                fi

                [[ "${action}" == 'start' ]] && $sysv_command "${l_service_name}" on &> /dev/null
                service "${l_service_name}" "$action" &> /dev/null
                ;;
            * ) service status "${l_service_name}" 1> /dev/null ;;
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

funcOSInfoDetection(){
    local release_file=${release_file:-}
    local distro_fullname=${distro_fullname:-}
    local distro_family_own=${distro_family_own:-}
    distro_name=${distro_name:-}
    version_id=${version_id:-}
    codename=${codename:-}

    # CentOS 5, CentOS 6, Debian 6 has no file /etc/os-release
    if [[ -s '/etc/os-release' ]]; then
        release_file='/etc/os-release'
        #distro name，eg: centos/rhel/fedora, debian/ubuntu, opensuse/sles
        distro_name=$(sed -r -n '/^ID=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")
        #version id, eg: 7/8, 16.04/16.10, 13.2/42.2
        if [[ "${distro_name,,}" == 'debian' && -s /etc/debian_version ]]; then
            version_id=$(cat /etc/debian_version)
        else
            version_id=$(sed -r -n '/^VERSION_ID=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")
        fi

        # Fedora, Debian，SUSE has no parameter ID_LIKE, only has ID
        distro_family_own=$(sed -r -n '/^ID_LIKE=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")
        [[ "$distro_family_own" == '' ]] && distro_family_own="$distro_name"

        case "${distro_name,,}" in
            debian|ubuntu ) codename=$(sed -r -n '/^VERSION=/s@.*[,(][[:space:]]?([^[:space:]\)]+).*@\L\1@p' "${release_file}") ;;
            opensuse ) codename=$(sed -r -n '/CODENAME/s@.*=[[:space:]]?(.*)@\L\1@p' /etc/SuSE-release) ;;
            * ) codename='' ;;
        esac    # End case

    elif [[ -s '/etc/redhat-release' ]]; then  # for CentOS 5, CentOS 6
        release_file='/etc/redhat-release'
        distro_name=$(rpm -q --qf "%{name}" -f "${release_file}") #centos-release,fedora-release
        distro_name=${distro_name%%-*}    # centos, fedora
        version_id=$(sed -r -n 's@[^[:digit:]]*([[:digit:]]{1}).*@\1@p' "${release_file}") # 5/6
        distro_family_own='rhel'   # family is rhel (RedHat)

    elif [[ -s /etc/debian_version && -s /etc/issue.net ]]; then    # for Debian 6
        release_file='/etc/issue.net'   #Debian GNU/Linux 6.0
        distro_name=$(sed -r -n 's@([^[:space:]]*).*@\L\1@p' "${release_file}")
        version_id=$(sed -r -n 's@[^[:digit:]]*([[:digit:]]{1}).*@\1@p' "${release_file}") #6
        distro_family_own='debian'   # family is debian (Debian)

        case "${version_id}" in
            6 ) codename='squeeze' ;;
            * ) codename='' ;;
        esac    # End case

    else
        funcExitStatement "${c_red}Sorry${c_normal}: this script can't detect your system!"
    fi      # End if

    #distro full pretty name, for CentOS ,file redhat-release is more detailed
    if [[ -s '/etc/redhat-release' ]]; then
        distro_fullname=$(cat /etc/redhat-release)
    else
        distro_fullname=$(sed -r -n '/^PRETTY_NAME=/s@.*="?([^"]*)"?@\1@p' "${release_file}")
    fi

    local is_obsoleted=${is_obsoleted:-0}
    distro_name="${distro_name,,}"
    case "${distro_name}" in
        rhel|centos )
            [[ "${version_id%%.*}" -le 5 ]] && is_obsoleted=1
            ;;
        debian )
            # 7|Wheezy|2013-05-04|2016-04-26
            # 6.0|Squeeze|2011-02-06|2014-05-31
            [[ "${version_id%%.*}" -le 7 ]] && is_obsoleted=1
            ;;
        ubuntu )
            # Ubuntu 14.04.5 LTS|Trusty Tahr|2016-08-04|April 2019
            # Ubuntu 15.10|Wily Werewolf|2015-10-22|July 28, 2016
            # Ubuntu 15.04|Vivid Vervet|2015-04-23|February 4, 2016
            [[ "${version_id%%.*}" -lt 14 || "${version_id%%.*}" -eq 15 ]] && is_obsoleted=1
            ;;
    esac

    [[ "${is_obsoleted}" -eq 1 ]] && funcExitStatement "${c_red}Sorry${c_normal}: your system ${c_blue}${distro_fullname}${c_normal} is obsoleted!"

    # Convert family name
    case "${distro_family_own,,}" in
        debian ) local distro_family_own='Debian' ;;
        suse|sles ) local distro_family_own='SUSE' ;;
        rhel|"rhel fedora"|fedora|centos ) local distro_family_own='RedHat' ;;
        * ) local distro_family_own='Unknown' ;;
    esac    # End case

    # echo "
    # =========================================
    #     GNU/Linux Distribution Information
    # =========================================
    # "
    # [[ -z "${distro_name}" ]] || funcInfoPrintf 'Distro Name' "${distro_name}"
    # [[ -z "${version_id}" ]] || funcInfoPrintf 'Version ID' "${version_id}"
    # [[ -z "${codename}" ]] || funcInfoPrintf "Code Name" "${codename}"
    # [[ -z "${distro_fullname}" ]] || funcInfoPrintf 'Full Name' "${distro_fullname}"

    echo -e "${c_blue}System Info:${c_normal}\n${c_red}${distro_fullname}${c_normal}\n"

    version_id=${version_id%%.*}
}

funcCodenameForDatabase(){
    local databaseType="${1:-}"
    local distroName="${2:-}"
    local versionId="${3:-}"
    [[ -z "${versionId}" ]] || versionId="${versionId%%.*}"

    if [[ -n "${databaseType}" ]]; then
        case "${databaseType,,}" in
            mysql )
                case "${distroName,,}" in
                    rhel|centos ) codename="el${versionId}" ;;
                    fedora ) codename="fc${versionId}" ;;
                    sles ) codename="sles${versionId}" ;;
                esac
                ;;
            mariadb )
                case "${distroName,,}" in
                    rhel|centos|fedora|opensuse ) codename="${distroName,,}${versionId}" ;;
                esac
                ;;
            percona )
                case "${distroName,,}" in
                    rhel|centos ) codename="rhel${versionId}" ;;
                esac
                ;;
        esac
    fi

    # MySQL  rhel/centos  --> el7, el6, el5
    # MySQL  fedora       --> fc26, fc25, fc24
    # MySQL  sles         --> sles12, sles11
    # MariaDB  rhel       --> rhel7, rhel6, rhel5
    # MariaDB  centos     --> centos7,centos6
    # MariaDB  fedora     --> fedora26, fedora25
    # MariaDB  opensuse   --> opensuse42
    # Percona rhel/centos  --> rhel7, rhel6, rhel5
}

#########  1-2 getopts Operation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Installing MySQL/MariaDB/Percona On GNU/Linux Via Official Repository!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -a    --auto installation, default choose MySQL variants latest version (Percona > MariaDB > MySQL)
    -t variant_type    --set MySQL variant (MySQL|MariaDB|Percona)
    -v variant_version --set MySQL variant version (eg: 5.6|5.7|8.0|10.1|10.2), along with -t
    -d data_dir    --set data dir, default is /var/lib/mysql
    -s port    --set MySQL port number, default is 3306
    -p root_passwd    --set root password for 'root'@'localhost', default is empty or temporary password in /var/log/mysqld.log or /var/log/mysql/mysqld.log
    -P [protocol:]ip:port    --proxy host (http|https|socks4|socks5), default protocol is http
${c_normal}
EOF
exit
}

while getopts "ap:d:s:t:v:P:h" option "$@"; do
    case "$option" in
        a ) auto_installation=1;;
        p ) root_password_new="$OPTARG" ;;
        d ) data_dir="$OPTARG" ;;
        s ) mysql_port="$OPTARG" ;;
        t ) mysql_variant_type="$OPTARG" ;;
        v ) variant_version="$OPTARG" ;;
        P ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo ;;
    esac
done


################ 2-1. Choose Database & Version ################
funcDetectIfExisted(){
    echo -e "${c_blue}Installed MySQL Or Not Detection:${c_normal}"

    if funcCommandExistCheck 'mysql'; then
        echo -e "${c_red}$(mysql --version)${c_normal}.\n"
        funcExitStatement "${c_red}Attention${c_normal}: MySQL or MySQL Variants have been existed in your system. To use this script, you should remove existed version manually!"
    else
        echo -e "${c_red}No MySQL Or MySQL Variants Find.${c_normal}\n"
    fi
}

# - extract mysql variants lists or variant version lists
funcVariantAndVersionExtraction(){
    local local_variants_version_list="${1:-}"
    local local_distro_name="${2:-}"
    local local_db_name="${3:-}"
    local local_codename="${4:-}"
    local local_output=${local_output:-}

    if [[ -n "${local_distro_name}" && -n "${local_db_name}" && -n "${local_codename}" ]]; then
        # variant version
        local_output=$(awk -F\| 'match($4,/'"${local_distro_name}"'/)&&match($1,/^'"${local_db_name}"'$/)&&match($2,/^'"${local_codename}"'$/){print $3}' "${local_variants_version_list}")

    elif [[ -n "${local_distro_name}" ]]; then
        # mysql variants
        local_output=$(awk -F\| 'match($4,/'"${local_distro_name}"'/){a[$1]=$0}END{PROCINFO["sorted_in"]="@ind_str_asc"; for (i in a) print i}' "${local_variants_version_list}" | sed ':a;N;$!ba;s@\n@ @g')
    fi

    echo "${local_output}"
}

# - variant and version (V2) choose has 3 method
# - 1. via choose list - default operation
funcV2SelectionListOperation(){
    # 1 - database choose
    echo "${c_blue}Available MySQL Variants List:${c_normal}"
    PS3="Choose variant number: "

    select item in $(funcVariantAndVersionExtraction "${variants_version_list}" "${distro_name}"); do
        db_name="${item}"
        [[ -n "${db_name}" ]] && break
    done < /dev/tty

    # 2 - specific version choose
    echo -e "\n${c_blue}Please Select Specific${c_normal} ${c_red}${db_name}${c_normal}${c_blue} Version: ${c_normal}"
    PS3="Choose version number: "

    # generate specific codename for rhel/centos/fedora/sles/opensuse
    funcCodenameForDatabase "${db_name}" "${distro_name}" "${version_id}"

    select item in $(funcVariantAndVersionExtraction "${variants_version_list}" "${distro_name}" "${db_name}" "${codename}"); do
        db_version="${item,,}"
        [[ -n "${db_version}" ]] && break
    done < /dev/tty

    unset PS3
}

# - 2. auto_installation
funcV2AutomaticSelection(){
    # generate specific codename for rhel/centos/fedora/sles/opensuse
    funcCodenameForDatabase "${db_name}" "${distro_name}" "${version_id}"

    # sequence: Percona, MariaDB, MySQL
    db_name='Percona'
    local db_version_list=${db_version_list:-}
    db_version_list=$(funcVariantAndVersionExtraction "${variants_version_list}" "${distro_name}" "${db_name}" "${codename}")
    db_version=$(echo "${db_version_list}" | awk '{print $1}')

    if [[ -z "${db_version}" ]]; then
        db_name='MariaDB'
        db_version_list=$(funcVariantAndVersionExtraction "${variants_version_list}" "${distro_name}" "${db_name}" "${codename}")
        db_version=$(echo "${db_version_list}" | awk '{print $1}')

        if [[ -z "${db_version}" ]]; then
            db_name='MySQL'
            db_version_list=$(funcVariantAndVersionExtraction "${variants_version_list}" "${distro_name}" "${db_name}" "${codename}")
            db_version=$(echo "${db_version_list}" | awk '{print $1}')

            if [[ -z "${db_version}" ]]; then
                funcExitStatement "${c_red}Sorry${c_normal}: no appropriate MySQL variant & version finds!"
            fi    # end MySQL

        fi    # end MariaDB

    fi    # end Percona

}

# - 3. manually setting
funcV2ManuallySpecify(){
    case "${mysql_variant_type}" in
        MySQL|mysql|my ) db_name='MySQL' ;;
        MariaDB|mariadb|ma ) db_name='MariaDB' ;;
        Percona|percona|pe|p ) db_name='Percona' ;;
        * ) funcExitStatement "${c_red}Sorry${c_normal}: please specify correct ${c_blue}MySQL/MariaDB/Percona${c_normal} via ${c_blue}-t${c_normal}!"
    esac

    # generate specific codename for rhel/centos/fedora/sles/opensuse
    funcCodenameForDatabase "${db_name}" "${distro_name}" "${version_id}"

    local db_version_list=${db_version_list:-}
    db_version_list=$(funcVariantAndVersionExtraction "${variants_version_list}" "${distro_name}" "${db_name}" "${codename}")

    db_version="${variant_version}"
    if [[ -z "${db_version_list}" ]]; then
        funcExitStatement "${c_red}Sorry${c_normal}: no specific ${c_blue}${db_name}${c_normal} version finds!"
    elif [[ -z $(echo "${db_version_list}" | sed 's@ @\n@g' | sed -n '/^'"${db_version}"'$/p') ]]; then
        [[ -z "${db_version}" ]] && db_version='NULL'
        funcExitStatement "${c_red}Sorry${c_normal}: version you specified is ${c_blue}${db_version}${c_normal}, please specify correct version: ${c_blue}${db_version_list// /\/}${c_normal} via ${c_blue}-v${c_normal}!"
    fi
}

funcVariantAndVersionChoose(){
    variants_version_list=$(mktemp -t Temp_XXXXX.txt)
    $download_tool "${mysql_veriants_version_list}" > "${variants_version_list}"
    [[ -s "${variants_version_list}" ]] || funcExitStatement "${c_red}Sorry${c_normal}: fail to get MySQL variants version relation table!"

    if [[ "${auto_installation}" -eq 1 ]]; then
        funcV2AutomaticSelection
    elif [[ -n "${mysql_variant_type}" ]]; then
        funcV2ManuallySpecify
    else
        funcV2SelectionListOperation
    fi

    echo "Database choose is ${c_red}${db_name} ${db_version}${c_normal}."

    [[ -f "${variants_version_list}" ]] && rm -f "${variants_version_list}"

    # - MySQL/Percona 5.6 need memory space > 512MB
    case "${db_name}" in
        MySQL|Percona )
            # 524288  512 * 1204   KB
            if [[ "${db_version}" == '5.6' && $(awk 'match($1,/^MemTotal/){print $2}' /proc/meminfo) -le 524288 ]]; then
                funcExitStatement "${c_red}Attention${c_normal}: system memory is less than 512M, ${c_blue}${db_name} ${db_version}${c_normal} needs more memory space while installing or starting."
            fi
            ;;
    esac    # end case db_name

    if [[ "${pack_manager}" == 'apt-get' ]]; then
        funcCommandExistCheck 'systemctl' || funcPackageManagerOperation 'install' "sysv-rc-conf" # same to chkconfig
    fi

    # install bc use to calculate and arithmatic comparasion
    funcCommandExistCheck 'bc' || funcPackageManagerOperation 'install' "bc"

    echo -e "\nBegin to install ${c_blue}${db_name} ${db_version}${c_normal}, just be patient!"
}


################ 2-2. MariaDB Operation ################
funcMariaDBOperation(){
    # https://mariadb.com/kb/en/the-mariadb-library/yum/
    # https://downloads.mariadb.org/mariadb/repositories
    # https://mariadb.com/kb/en/the-mariadb-library/installing-mariadb-deb-files/

    case "${distro_name}" in
        rhel|centos|fedora|opensuse )
            local system_arch=${system_arch:-'amd64'}
            case "$(uname -m)" in
                x86_64 ) system_arch='amd64' ;;
                x86|i386 ) system_arch='x86' ;;
            esac
            ;;
    esac    # end case distro_name

    # remove MairDB 5.5
    funcPackageManagerOperation 'remove' "mariadb-server mariadb-libs"   #5.5

    case "${distro_name}" in
        rhel|centos|fedora )
            local repo_path=${repo_path:-'/etc/yum.repos.d/MariaDB.repo'}

            echo -e "# ${db_name} ${db_version} ${distro_name} repository list\n# http://downloads.mariadb.org/mariadb/repositories/\n[${db_name,,}]\nname = ${db_name}\nbaseurl = http://yum.mariadb.org/${db_version}/${codename}-${system_arch}\ngpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB\ngpgcheck=1" > "${repo_path}"

            # Manually Importing the MariaDB Signing Key
            # rpm --import https://yum.mariadb.org/RPM-GPG-KEY-MariaDB

            # dnf install MariaDB-server  /  yum install MariaDB-server MariaDB-client
            local pack_name_list=${pack_name_list:-'MariaDB-server MariaDB-client'}
            [[ "${distro_name}" == 'fedora' && "${pack_manager}" == 'dnf' ]] && pack_name_list='MariaDB-server'

            funcPackageManagerOperation     # just make cache
            funcPackageManagerOperation 'install' "${pack_name_list}"

            service_name='mysql'
            # mariadb 5.5 just use   service mysql {status,start,stop}
            if [[ "${db_version%%.*}" -lt 10 ]]; then
                service "${service_name}" start &> /dev/null
                service "${service_name}" restart &> /dev/null
            else
                # service name: mariadb/mysql/mysqld
                funcSystemServiceManager "${service_name}" 'start'
                funcSystemServiceManager "${service_name}" 'restart'
            fi
            ;;
        opensuse )
            local repo_path=${repo_path:-'/etc/zypp/repos.d/mariadb.repo'}

            echo -e "# ${db_name} ${db_version} ${distro_name} repository list\n# http://downloads.mariadb.org/mariadb/repositories/\n[${db_name,,}]\nname = ${db_name}\nbaseurl = http://yum.mariadb.org/${db_version}/${codename}-${system_arch}\ngpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB\ngpgcheck=1" > "${repo_path}"

            # Manually Importing the MariaDB Signing Key  CBCB082A1BB943DB
            rpm --import https://yum.mariadb.org/RPM-GPG-KEY-MariaDB &> /dev/null

            # zypper install MariaDB-server MariaDB-client
            # - OpenSUSE Self Repo: mariadb-server, mariadb-client
            # - MariaDB Official Repo: MariaDB-server MariaDB-client
            funcPackageManagerOperation     # just make cache
            funcPackageManagerOperation 'install' "MariaDB-server MariaDB-client"

            # service name: mariadb/mysql/mysqld
            service_name='mysql'
            funcSystemServiceManager "${service_name}" 'start'
            funcSystemServiceManager "${service_name}" 'restart'
            ;;
        debian|ubuntu )
            local repo_path=${repo_path:-'/etc/apt/sources.list.d/mariadb.list'}
            local repo_mirror_url=${repo_mirror_url:-'http://nyc2.mirrors.digitalocean.com'}

            # Repo mirror site url
            local ip_info=${ip_info:-}
            ip_info=$($download_tool_origin ipinfo.io)
            if [[ -n "${ip_info}" ]]; then
                local host_ip=${host_ip:-}
                local host_country=${host_ip:-}
                local host_city=${host_ip:-}
                local host_org=${host_ip:-}
                host_ip=$(echo "$ip_info" | sed -r -n '/\"ip\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
                host_country=$(echo "$ip_info" | sed -r -n '/\"country\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
                host_city=$(echo "$ip_info" | sed -r -n '/\"city\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
                host_org=$(echo "$ip_info" | sed -r -n '/\"org\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')

                case "${host_country}" in
                    CN )
                        [[ "${host_city}" == 'Beijing' ]] && repo_mirror_url='http://mirrors.tuna.tsinghua.edu.cn' || repo_mirror_url='http://mirrors.neusoft.edu.cn'
                        ;;
                    * )
                        # Just for Digital Ocean VPS
                        if [[ -n "${host_org}" && "${host_org}" =~ DigitalOcean ]]; then
                            local mirror_region=${mirror_region:-'nyc2'}
                            case "${host_city}" in
                                Singapore ) mirror_region='sgp1' ;;
                                Amsterdam ) mirror_region='ams2' ;;
                                'New York'|NewYork ) mirror_region='nyc2' ;;
                                'San Francisco'|SanFrancisco ) mirror_region='sfo1' ;;
                            esac
                            repo_mirror_url="http://${mirror_region}.mirrors.digitalocean.com"
                        fi
                        ;;
                esac

            fi

            # {
            #   "ip": "128.199.72.46",
            #   "city": "Singapore",
            #   "region": "Central Singapore Community Development Council",
            #   "country": "SG",
            #   "loc": "1.2855,103.8565",
            #   "org": "AS14061 DigitalOcean, LLC"
            # }

            # - GnuPG key importing
            local gpg_keyid=${gpg_keyid:-'0xF1656F24C74CD1D8'}
            case "${codename}" in
                precise|trusty|wheezy|jessie ) gpg_keyid='0xcbcb082a1bb943db' ;;
            esac

            # Debian  sid       0xF1656F24C74CD1D8 arch=amd64,i386
            #         stretch   0xF1656F24C74CD1D8 arch=amd64,i386,ppc64el
            #         jessie    0xcbcb082a1bb943db arch=amd64,i386
            #         wheezy    0xcbcb082a1bb943db arch=amd64,i386
            # Ubuntu  zesty     0xF1656F24C74CD1D8 arch=amd64,i386
            #         yakkety   0xF1656F24C74CD1D8 arch=amd64,i386
            #         xenial    0xF1656F24C74CD1D8 arch=amd64,i386
            #         trusty    0xcbcb082a1bb943db arch=amd64,i386,ppc64el
            #         precise   0xcbcb082a1bb943db arch=amd64,i386

            local arch_list=${arch_list:-'amd64,i386'}
            case "${codename,,}" in
                stretch|trusty ) arch_list="${arch_list},ppc64el" ;;
            esac

            echo -e "# ${db_name} ${db_version} repository list\n# http://downloads.mariadb.org/mariadb/repositories/\ndeb [arch=${arch_list}] ${repo_mirror_url}/${db_name,,}/repo/${db_version}/${distro_name} ${codename} main\ndeb-src ${repo_mirror_url}/${db_name,,}/repo/${db_version}/${distro_name} ${codename} main" > "${repo_path}"

            funcPackageManagerOperation 'install' "software-properties-common"

            # debian >=9 need dirmngr, used for GnuPG
            # [[ "${distro_name}" == 'debian' && "${version_id%%.*}" -ge 9 ]]
            funcCommandExistCheck 'dirmngr' || funcPackageManagerOperation 'install' 'dirmngr'

            apt-key adv --recv-keys --keyserver keyserver.ubuntu.com "${gpg_keyid}" &> /dev/null
            # apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db/0xF1656F24C74CD1D8

            # https://stackoverflow.com/questions/23358918/preconfigure-an-empty-password-for-mysql-via-debconf-set-selections
            # https://askubuntu.com/questions/79257/how-do-i-install-mysql-without-a-password-prompt
            export DEBIAN_FRONTEND=noninteractive

            # funcCommandExistCheck 'debconf-set-selections' || funcPackageManagerOperation 'install' 'debconf-utils'

            # setting root password during installation via command debconf-set-selections
            # debconf-set-selections <<< 'mariadb-server-'"${db_version}"' mysql-server/root_password password '"${mysql_pass}"''
            # debconf-set-selections <<< 'mariadb-server-'"${db_version}"' mysql-server/root_password_again password '"${mysql_pass}"''

            funcPackageManagerOperation     # make repo cache
            funcPackageManagerOperation 'install' "mariadb-server"

            service_name='mariadb'
            funcSystemServiceManager "${service_name}" 'start'
            funcSystemServiceManager "${service_name}" 'restart'

            unset DEBIAN_FRONTEND
            ;;
    esac    # end case distro_name

}


################ 2-3. MySQL Operation ################
funcMySQLOperation(){
    # https://dev.mysql.com/downloads/repo/yum/
    # https://dev.mysql.com/downloads/repo/suse/
    # https://dev.mysql.com/downloads/repo/apt/

    # https://dev.mysql.com/doc/refman/5.7/en/using-systemd.html
    # /etc/my.cnf or /etc/mysql/my.cnf (RPM platforms)
    # /etc/mysql/mysql.conf.d/mysqld.cnf (Debian platforms)

    case "${distro_name}" in
        rhel|centos|fedora|sles )
            # - GnuPG importing
            local repo_path=${repo_path:-'/etc/yum.repos.d/mysql-community.repo'}
            # https://dev.mysql.com/doc/refman/5.7/en/checking-gpg-signature.html
            local gpg_path=${gpg_path:-'/etc/pki/rpm-gpg/RPM-GPG-KEY-mysql'}

            if [[ "${distro_name}" == 'sles' ]]; then
                repo_path='/etc/zypp/repos.d/mysql-community.repo'
                gpg_path='/etc/RPM-GPG-KEY-mysql'
            fi

            if [[ ! -f "${gpg_path}" ]]; then
                # - method 1
                $download_tool 'https://repo.mysql.com/RPM-GPG-KEY-mysql' > "${gpg_path}"
                # - method 2
                [[ -s "${gpg_path}" ]] || $download_tool 'https://dev.mysql.com/doc/refman/5.7/en/checking-gpg-signature.html' | sed -r -n '/BEGIN PGP/,/END PGP/{s@[[:space:]]*<[^>]*>[[:space:]]*@@g;p}' > "${gpg_path}"
                # - method 3
                [[ -s "${gpg_path}" ]] || rpm --import 'http://dev.mysql.com/doc/refman/5.7/en/checking-gpg-signature.html'

                # - method 4
                # gpg --import mysql_pubkey.asc
                #
                # gpg --keyserver pgp.mit.edu --recv-keys 5072E1F5
                # gpg -a --export 5072E1F5 --output mysql_pubkey.asc
                # rpm --import mysql_pubkey.asc       #  import the key into your RPM configuration to validate RPM install packages
            else
                rpm --import "${gpg_path}" &> /dev/null
            fi

            # - Repo generation
            version_id=${version_id%%.*}
            local releasever_basearch=${releasever_basearch:-}

            case "${distro_name}" in
                rhel|centos ) releasever_basearch="el/${version_id}" ;;
                fedora ) releasever_basearch="fc/\$releasever" ;;
                sles ) releasever_basearch="sles/${version_id}" ;;
            esac

            local extra_paras=${extra_paras:-}
            [[ "${distro_name}" == 'sles' ]] && extra_paras="autorefresh=0\ntype=rpm-md\n"

            echo -e "[mysql-connectors-community]\nname=MySQL Connectors Community\nbaseurl=http://repo.mysql.com/yum/mysql-connectors-community/${releasever_basearch}/\$basearch/\nenabled=1\n${extra_paras}gpgcheck=1\ngpgkey=file://${gpg_path}\n" > "${repo_path}"

            echo -e "[mysql-tools-community]\nname=MySQL Tools Community\nbaseurl=http://repo.mysql.com/yum/mysql-tools-community/${releasever_basearch}/\$basearch/\nenabled=1\n${extra_paras}gpgcheck=1\ngpgkey=file://${gpg_path}\n" >> "${repo_path}"

            # MySQL Community Version
            echo -e "[mysql${db_version//.}-community]\nname=MySQL ${db_version} Community Server\nbaseurl=http://repo.mysql.com/yum/mysql-${db_version}-community/${releasever_basearch}/\$basearch/\nenabled=1\n${extra_paras}gpgcheck=1\ngpgkey=file://${gpg_path}\n"  >> "${repo_path}"

            funcPackageManagerOperation     # just make cache
            funcPackageManagerOperation 'install' "mysql-community-server"

            service_name='mysqld'
            [[ "${distro_name}" == 'sles' ]] && service_name='mysql'
            funcSystemServiceManager "${service_name}" 'start'
            funcSystemServiceManager "${service_name}" 'restart'

            ;;
        debian|ubuntu )
            # Method 1 - install gpg & sources file via official package, appear prompt, not recommend
            # local mysql_official_site=${mysql_official_site:-'https://dev.mysql.com'}
            # local apt_config_url=${apt_config_url:-}
            # apt_config_url=$($download_tool_origin $($download_tool_origin "${mysql_official_site}/downloads/repo/apt/" | sed -r -n '/button03/{s@.*href="([^"]*)".*@'"${mysql_official_site}"'\1@g;p}') | sed -r -n '/No thanks/{s@.*href="(.*)".*@'"${mysql_official_site}"'\1@g;p}')
            #
            # # curl -fsL $(curl -fsL https://dev.mysql.com/downloads/repo/apt/ | sed -r -n '/button03/{s@.*href="([^"]*)".*@https://dev.mysql.com\1@g;p}') | sed -r -n '/No thanks/{s@.*href="(.*)".*@https://dev.mysql.com\1@g;p}'
            # # https://dev.mysql.com/get/mysql-apt-config_0.8.7-1_all.deb
            #
            # if [[ -n "${apt_config_url}" ]]; then
            #     local apt_config_pack_name=${apt_config_pack_name:-}
            #     apt_config_pack_name=${apt_config_url##*/}
            #     local apt_config_pack_save_path=${apt_config_pack_save_path:-"/tmp/${apt_config_pack_name}"}
            #     $download_tool_origin "${apt_config_url}" > "${apt_config_pack_save_path}"
            #
            #     [[ -s "${apt_config_pack_save_path}" ]] && dpkg -i "${apt_config_pack_save_path}"
            # fi

            # Method 1 - Manually operation
            local repo_path=${repo_path:-'/etc/apt/sources.list.d/mysql.list'}

            # deb http://repo.mysql.com/apt/{debian|ubuntu}/ {jessie|wheezy|trusty|utopic|vivid} {mysql-5.6|mysql-5.7|workbench-6.2|utilities-1.4|connector-python-2.0}

            echo -e "deb http://repo.mysql.com/apt/${distro_name}/ ${codename} mysql-tools\ndeb http://repo.mysql.com/apt/${distro_name}/ ${codename} mysql-${db_version}\ndeb-src http://repo.mysql.com/apt/${distro_name}/ ${codename} mysql-${db_version}" > "${repo_path}"

            # Use command 'dpkg-reconfigure mysql-apt-config' as root for modifications.
            # deb http://repo.mysql.com/apt/debian/ stretch mysql-apt-config

            # - GnuPG importing
            # apt-key adv --keyserver pgp.mit.edu --recv-keys 5072E1F5
            # apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 5072E1F5

            local gpg_path=${gpg_path:-}
            gpg_path=$(mktemp -t Temp_XXXXX.txt)       # mysql_gpg.asc
            # - method 1
            $download_tool 'https://repo.mysql.com/RPM-GPG-KEY-mysql' > "${gpg_path}"
            # - method 2
            [[ -s "${gpg_path}" ]] || $download_tool 'https://dev.mysql.com/doc/refman/5.7/en/checking-gpg-signature.html' | sed -r -n '/BEGIN PGP/,/END PGP/{s@[[:space:]]*<[^>]*>[[:space:]]*@@g;p}' > "${gpg_path}"

            apt-key add "${gpg_path}" &> /dev/null
            # apt-key list |& grep 'MySQL Release Engineering'
            [[ -f "${gpg_path}" ]] && rm -f "${gpg_path}"

            export DEBIAN_FRONTEND=noninteractive

            # funcCommandExistCheck 'debconf-set-selections' || funcPackageManagerOperation 'install' 'debconf-utils'
            # debconf-set-selections <<< 'mysql-server mysql-server/root_password password '"${mysql_pass}"''
            # debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password '"${mysql_pass}"''

            funcPackageManagerOperation     # make repo cache
            funcPackageManagerOperation 'install' 'mysql-server'
            # https://dev.mysql.com/doc/mysql-apt-repo-quick-guide/en/#updating-apt-repo-client-lib
            # Special Notes on Upgrading the Shared Client Libraries
            funcPackageManagerOperation 'install' "libmysqlclient20"

            service_name='mysql'
            funcSystemServiceManager "${service_name}" 'start'
            funcSystemServiceManager "${service_name}" 'restart'

            unset DEBIAN_FRONTEND
            ;;
    esac    # end case distro_name

}


################ 2-4. Percona Operation ################
funcPerconaOperation(){
    # https://www.percona.com/doc/percona-server/LATEST/installation/yum_repo.html
    # https://www.percona.com/doc/percona-server/LATEST/installation/apt_repo.html
    # https://www.percona.com/blog/2016/10/13/new-signing-key-for-percona-debian-and-ubuntu-packages/

    case "${distro_name}" in
        rhel|centos )
            local repo_path=${repo_path:-'/etc/yum.repos.d/percona-release.repo'}
            # https://dev.mysql.com/doc/refman/5.7/en/checking-gpg-signature.html
            local gpg_path=${gpg_path:-'/etc/pki/rpm-gpg/RPM-GPG-KEY-Percona'}

            # - GnuPG importing
            [[ -s "${gpg_path}" ]] || $download_tool 'https://www.percona.com/downloads/RPM-GPG-KEY-percona' > "${gpg_path}"

            # - repo generation
            echo -e "[percona-release-\$basearch]\nname = Percona-Release YUM repository - \$basearch\nbaseurl = http://repo.percona.com/release/\$releasever/RPMS/\$basearch\nenabled = 1\ngpgcheck = 1\ngpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Percona\n" > "${repo_path}"

            echo -e "[percona-release-noarch]\nname = Percona-Release YUM repository - noarch\nbaseurl = http://repo.percona.com/release/\$releasever/RPMS/noarch\nenabled = 1\ngpgcheck = 1\ngpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Percona" >> "${repo_path}"

            # [percona-release-$basearch]
            # name = Percona-Release YUM repository - $basearch
            # baseurl = http://repo.percona.com/release/$releasever/RPMS/$basearch
            # enabled = 1
            # gpgcheck = 1
            # gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Percona
            #
            # [percona-release-noarch]
            # name = Percona-Release YUM repository - noarch
            # baseurl = http://repo.percona.com/release/$releasever/RPMS/noarch
            # enabled = 1
            # gpgcheck = 1
            # gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Percona

            # yum install Percona-Server-server-{57,56,55}
            funcPackageManagerOperation
            funcPackageManagerOperation 'install' "Percona-Server-server-${db_version//.}"

            service_name='mysqld'
            funcSystemServiceManager "${service_name}" 'start'
            funcSystemServiceManager "${service_name}" 'restart'

            ;;
        debian|ubuntu )
            # Method 1 - Via official .deb package
            # # https://repo.percona.com/apt/percona-release_0.1-4.stretch.deb
            # local apt_repo_url=${apt_repo_url:-'https://repo.percona.com/apt/'}
            # local repo_pack_name=${repo_pack_name:-"percona-release_0.1-4.$(lsb_release -sc)_all.deb"}
            # repo_pack_name=$($download_tool "${apt_repo_url}" | awk 'match($0,/'"${codename}"'/){a=gensub(/.*href="([^"]*)".*/,"\\1","g",$0);}END{print a}')
            # local repo_pack_save_path=${repo_pack_save_path:-"/tmp/${repo_pack_name}"}
            #
            # $download_tool "${apt_repo_url}${repo_pack_name}" > "${repo_pack_save_path}"
            # dpkg -i "${repo_pack_save_path}"
            # [[ -f "${repo_pack_save_path}" ]] && rm -f "${repo_pack_save_path}"


            # Method 2 - Manually setting
            local repo_path=${repo_path:-'/etc/apt/sources.list.d/percona-release.list'}

            # deb http://repo.percona.com/apt stretch {main,testing,experimental}
            # deb-src http://repo.percona.com/apt stretch {main,testing,experimental}
            echo -e "# Percona releases, stable\ndeb http://repo.percona.com/apt ${codename} main\ndeb-src http://repo.percona.com/apt ${codename} main\n" > "${repo_path}"

            # - GnuPG importing
            funcCommandExistCheck 'dirmngr' || funcPackageManagerOperation 'install' 'dirmngr'
            # https://www.percona.com/blog/2016/10/13/new-signing-key-for-percona-debian-and-ubuntu-packages/
            # old gpg key
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8507EFA5 &> /dev/null
            # new gpg key
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9334A25F8507EFA5 &> /dev/null

            export DEBIAN_FRONTEND=noninteractive

            funcPackageManagerOperation     # just make cache
            funcPackageManagerOperation 'install' "percona-server-server-${db_version} percona-server-common-${db_version} libdbd-mysql-perl"

            service_name='mysql'
            funcSystemServiceManager "${service_name}" 'start'
            funcSystemServiceManager "${service_name}" 'restart'

            unset DEBIAN_FRONTEND
            ;;
    esac    # end case distro_name
}


############# 2-5. MySQL Secure Relevant Configuration #############
funcStrongRandomPasswordGeneration(){
    # https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
    # https://www.howtogeek.com/howto/30184/10-ways-to-generate-a-random-password-from-the-command-line/
    # https://serverfault.com/questions/261086/creating-random-password
    # https://unix.stackexchange.com/questions/462/how-to-create-strong-passwords-in-linux

    local str_length=${str_length:-32}
    local new_password=${new_password:-}

    if [[ -z "${root_password_new}" || "${#root_password_new}" -lt 16 ]]; then
        # openssl rand -base64 32
        new_password=$(tr -dc 'a-zA-Z0-9!@#&()$%{}<>^_+' < /dev/urandom | fold -w "${str_length}" | head -c "${str_length}" | xargs)

        if [[ "${new_password}" =~ ^[1-9a-zA-Z] && "${new_password}" =~ [1-9a-zA-Z]$ ]]; then
            root_password_new="${new_password}"
        else
            funcStrongRandomPasswordGeneration
        fi
    fi
}

funcRootPasswordSetting(){
    # https://dev.mysql.com/doc/refman/5.7/en/alter-user.html#alter-user-authentication
    # -- MySQL 5.7
    # sudo grep 'temporary password' /var/log/mysqld.log
    #                                /var/log/mysql/mysqld.log
    # mysql -uroot -p
    # ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyNewPass4!';
    #
    # -- MySQL 5.6
    # mysql_secure_installation

    funcStrongRandomPasswordGeneration

    local l_login_user_my_cnf=${l_login_user_my_cnf:-"${1:-}"}
    [[ -f "${l_login_user_my_cnf}" ]] && rm -f "${l_login_user_my_cnf}"

    case "${db_name}" in
        MariaDB )
            mysql -e "set password for 'root'@'localhost' = PASSWORD('${root_password_new}');"
            ;;
        MySQL|Percona )
            case "${db_version}" in
                5.5|5.6 )
                    mysql -e "set password for 'root'@'localhost' = PASSWORD('${root_password_new}');"
                    ;;
                * )
                    # 5.7 +
                    case "${distro_name}" in
                        debian|ubuntu )
                            mysql -e "alter user 'root'@'localhost' identified with mysql_native_password by '${root_password_new}';"
                            ;;
                        * )
                            # https://dev.mysql.com/doc/mysql-sles-repo-quick-guide/en/
                            local error_log_file=${error_log_file:-'/var/log/mysqld.log'}
                            [[ -s '/var/log/mysql/mysqld.log' ]] && error_log_file='/var/log/mysql/mysqld.log'

                            local tempRootPassword=${tempRootPassword:-}
                            tempRootPassword=$(awk '$0~/temporary password/{a=$NF}END{print a}' "${error_log_file}")
                            # Please use --connect-expired-password option or invoke mysql in interactive mode.
                            mysql -uroot -p"${tempRootPassword}" --connect-expired-password -e "alter user 'root'@'localhost' identified with mysql_native_password by '${root_password_new}';" 2> /dev/null
                            ;;
                    esac    # end case distro_name
                    ;;
            esac    # end case db_version
            ;;
    esac    # end case db_name

    # https://dev.mysql.com/doc/refman/5.7/en/mysql-commands.html

    # ~/.my.cnf
    # prompt=(\\u@\\h) [\\d]>\\_
    # prompt=MariaDB/Percona/MySQL [\\d]>\\_

    db_version_no_new=$(mysql -uroot -p"${root_password_new}" -Bse "select version();" 2> /dev/null)

    if [[ -n "${db_version_no_new}" ]]; then
        # https://dev.mysql.com/doc/refman/5.7/en/password-security-user.html
        if [[ -n "${l_login_user_my_cnf}" ]]; then
            # echo  -e "[client]\nuser=root\npassword=${root_password_new}\n\n[mysql]\nprompt=(\\u@\\h) [\\d]>\\_" > "${login_user_home}/.my.cnf"
            echo  -e "[client]\nuser=root\npassword=\"${root_password_new}\"\n\n[mysql]\nprompt=${db_name} [\\d]>\\_" > "${l_login_user_my_cnf}"
            chown "${login_user}" "${l_login_user_my_cnf}"
            chmod 400 "${l_login_user_my_cnf}"
        fi
    else
        funcExitStatement "\n${c_red}Sorry${c_normal}: fail to install ${c_blue}${db_name} ${db_version}${c_normal}."
    fi
}

funcSecureInstallation(){
    # mysql_secure_installation
    # https://dev.mysql.com/doc/refman/5.7/en/default-privileges.html
    local mysql_command="${1:-}"

    # extract from /usr/bin/mysql_secure_installation
    # - set_root_password
    # UPDATE mysql.user SET Password=PASSWORD('$esc_pass') WHERE User='root';

    if [[ -n "${mysql_command}" ]]; then
        # - remove_anonymous_users
        $mysql_command -e "DELETE FROM mysql.user WHERE User='';"
        # - remove_remote_root
        $mysql_command -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        # - remove_test_database
        $mysql_command -e "DROP DATABASE IF EXISTS test;"
        # - reload_privilege_tables
        $mysql_command -e "FLUSH PRIVILEGES;"

        [[ $? -eq 0 ]] && echo -e "\nExecuting ${c_blue}mysql_secure_installation${c_normal} operation finished!"
    fi
}

funcUserLoggingFileSetting(){
    local mysql_command="${1:-}"

    if [[ -n "${mysql_command}" ]]; then
        # https://dev.mysql.com/doc/refman/5.7/en/mysql-logging.html
        local login_user_mysql_history=${login_user_mysql_history:-"${login_user_home}/.mysql_history"}
        [[ -f "${login_user_mysql_history}" ]] && rm -f "${login_user_mysql_history}"
        ln -s /dev/null "${login_user_mysql_history}"
        [[ $? -eq 0 ]] && echo -e "Create history file ${c_blue}${login_user_mysql_history}${c_normal} as a symbolic link to ${c_blue}/dev/null${c_normal} finished!"
    fi
}

funcLoadTimeZoneTables(){
    # https://dev.mysql.com/downloads/timezones.html
    # https://mariadb.com/kb/en/library/mysql_tzinfo_to_sql/
    # https://dev.mysql.com/doc/refman/5.7/en/time-zone-support.html
    # https://dev.mysql.com/doc/refman/5.7/en/mysql-tzinfo-to-sql.html
    local mysql_command="${1:-}"

    if [[ -n "${mysql_command}" && -d '/usr/share/zoneinfo' ]]; then
        if funcCommandExistCheck 'mysql_tzinfo_to_sql'; then
            mysql_tzinfo_to_sql /usr/share/zoneinfo 2> /dev/null | ${mysql_command} mysql

            [[ $? -eq 0 ]] && echo -e "Executing ${c_blue}mysql_tzinfo_to_sql${c_normal} to load the time zone tables finished!"
        fi
    fi
}

funcUserDefinedFunction(){
    local mysql_command="${1:-}"

    # Percona Server is distributed with several useful UDF (User Defined Function) from Percona Toolkit.
    if [[ "${db_name}" == 'Percona' ]]; then
        local mysql_command="${1:-}"
        $mysql_command -e "CREATE FUNCTION fnv1a_64 RETURNS INTEGER SONAME 'libfnv1a_udf.so'"
        $mysql_command -e "CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so'"
        $mysql_command -e "CREATE FUNCTION murmur_hash RETURNS INTEGER SONAME 'libmurmur_udf.so'"
    fi
}

########## 2-6. MySQL Port Or Data dir Change Configuration ##########
funcPortAndDatadirParamaterVerification(){
    # 1- verify if the port specified is available
    if [[ "${mysql_port}" -ne "${mysql_port_default}" ]]; then
        if [[ "${mysql_port}" =~ ^[1-9]{1}[0-9]{1,4}$ ]]; then
            local sys_port_start
            sys_port_start=$(sysctl -a 2> /dev/null | awk 'match($1,/ip_local_port_range/){print $(NF-1)}')
            local sys_port_end
            sys_port_end=$(sysctl -a 2> /dev/null | awk 'match($1,/ip_local_port_range/){print $NF}')

            if [[ "${mysql_port}" -lt "${sys_port_start}" || "${mysql_port}" -gt "${sys_port_end}" ]]; then
                echo -e "\n${c_red}Attention:${c_normal}\nport you specified ${c_blue}${mysql_port}${c_normal} is out of range ${c_blue}(${sys_port_start},${sys_port_end})${c_normal} defined in ${c_blue}/proc/sys/net/ipv4/ip_local_port_range${c_normal}.\nStill use default port ${c_blue}${mysql_port_default}${c_normal}."

                mysql_port="${mysql_port_default}"
            else
                local port_service_info
                port_service_info=$(awk 'match($2,/^'"${mysql_port}"'\/tcp$/){print}' /etc/services)
                if [[ -n "${port_service_info}" ]]; then
                    echo -e "\n${c_red}Attention:${c_normal}\nport you specified ${c_blue}${mysql_port}${c_normal} has been assigned to ${c_blue}${port_service_info%% *}${c_normal} in ${c_blue}/etc/services${c_normal} defaultly.\nStill use default port ${c_blue}${mysql_port_default}${c_normal}."

                    mysql_port="${mysql_port_default}"
                else
                    echo -e "\nPort you specified ${c_blue}${mysql_port}${c_normal} is available."
                fi    # end if port_service_info
            fi    # end if sys_port_range
        else
            echo -e "\n${c_red}Attention:${c_normal}\nPort you specified ${c_blue}${mysql_port}${c_normal} is illegal.\nStill use default port ${c_blue}${mysql_port_default}${c_normal}."

            mysql_port="${mysql_port_default}"
        fi
    fi

    # 2- verify data dir
    if [[ "${data_dir}" != "${data_dir_default}" ]]; then
        if [[ -d "${data_dir}" ]]; then
            local data_dir_temp=${data_dir_temp:-"${data_dir}.$(date +'%s').old"}
            mv "${data_dir}" "${data_dir_temp}"
            echo -e "${c_red}Attention: ${c_normal}Existed dir ${c_blue}${data_dir}${c_normal} has been rename to ${c_blue}${data_dir_temp}${c_normal}."
        fi

        [[ -d "${data_dir}" ]] && rm -rf "${data_dir}"
        mkdir -p "${data_dir}"
        chmod --reference=${data_dir_default} "${data_dir}"
        cp -R ${data_dir_default}/. "${data_dir}"
        chown -R mysql:mysql "${data_dir}"
        echo -e "Copy files under ${c_blue}${data_dir_default}${c_normal} to newly created dir ${c_blue}${data_dir}${c_normal} finished."
    fi
}

funcPortDatadirConfigureFormulate(){
    local l_conf_path="${1:-}"

    if [[ -s "${l_conf_path}" ]]; then
        [[ -z $(sed -r -n '/^\[mysqld\]/{p}' "${l_conf_path}") ]] && sed -i '$a [mysqld]' "${l_conf_path}"

        # - data_dir
        if [[ "${data_dir}" != "${data_dir_default}" ]]; then
            if [[ -z $(sed -r -n '/\[mysqld\]/,${/^datadir[[:space:]]*=/{p}}' "${l_conf_path}") ]]; then
                sed -r -i '/\[mysqld\]/a datadir='"${data_dir}"'' "${l_conf_path}"
            else
                sed -r -i '/\[mysqld\]/,${/^datadir[[:space:]]*=/{s@(.*=[[:space:]]*).*@\1'"${data_dir}"'@g}}' "${l_conf_path}"
            fi
        fi    # end data_dir

        # - port
        if [[ "${mysql_port}" -ne "${mysql_port_default}" ]]; then
            if [[ -z $(sed -r -n '/\[mysqld\]/,${/^port[[:space:]]*=/{p}}' "${l_conf_path}") ]]; then
                if [[ -z $(sed -r -n '/\[mysqld\]/,${/^datadir[[:space:]]*=/{p}}' "${l_conf_path}") ]]; then
                    sed -r -i '/\[mysqld\]/a port        = '"${mysql_port}"'' "${l_conf_path}"
                else
                    sed -r -i '/^port[[:space:]]*=/d; /^datadir[[:space:]]*=/i port        = '"${mysql_port}"'' "${l_conf_path}"
                fi    # end if
            else
                sed -r -i '/[mysqld]/,${/^port[[:space:]]*=/{s@(.*=[[:space:]]*).*@\1'"${mysql_port}"'@g}}' "${l_conf_path}"
            fi     # end if
        fi    # end port

    fi
}

funcPortDatadirChangeForMySQL(){
    # https://dev.mysql.com/doc/refman/5.7/en/cannot-create.html

    # - data_dir
    case "${distro_name}" in
        rhel|centos|fedora|sles )
            local conf_path=${conf_path:-'/etc/my.cnf'}

            if [[ "${data_dir}" != "${data_dir_default}" ]]; then
                sed -r -i '/[mysqld]/,${/^datadir[[:space:]]*=/{s@(.*=[[:space:]]*).*@\1'"${data_dir}"'@g}}' "${conf_path}"
            fi

            # Don't change socket path, or it will prompt   ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/lib/mysql/mysql.sock' (2)

            # Be careful of SELinux
            # [Warning] Can't create test file /data/mysql/centos.lower-test
            # https://phe1129.wordpress.com/2012/04/02/change-mysql-data-folder-on-selinux/
            # https://dba.stackexchange.com/questions/80232/mysql-cant-create-test-file-error-on-centos

            # ls -lh -Zd /var/lib/mysql
            # drwxr-x--x. mysql mysql system_u:object_r:mysqld_db_t:s0 /var/lib/mysql
            # chcon -R -u system_u -r object_r -t mysqld_db_t /data/mysql

            # Disable SELinux Currently, Later will configure for it
            local selinux_config=${selinux_config:-'/etc/selinux/config'}
            if [[ -f "${selinux_config}" ]]; then
                [[ -f "${selinux_config}${bak_suffix}" ]] || cp -fp "${selinux_config}" "${selinux_config}${bak_suffix}"
                sed -i -r 's@(SELINUX=)enforcing@\1disabled@g;s@#*(SELINUXTYPE=.*)@#\1@g' "${selinux_config}"
            fi
            ;;
        debian|ubuntu )
            local conf_path=${conf_path:-'/etc/mysql/mysql.conf.d/mysqld.cnf'}

            if [[ "${data_dir}" != "${data_dir_default}" ]]; then
                # datadir     = /var/lib/mysql
                [[ -s "${conf_path}" ]] && sed -r -i '/^datadir[[:space:]]*=/{s@(.*=[[:space:]]*).*@\1'"${data_dir}"'@g}' "${conf_path}"

                # For Ubuntu
                # https://dba.stackexchange.com/questions/106085/cant-create-file-var-lib-mysql-user-lower-test
                local apparmor_mysqld_path=${apparmor_mysqld_path:-'/etc/apparmor.d/usr.sbin.mysqld'}
                [[ -s "${apparmor_mysqld_path}" ]] && sed -r -i '/Allow data dir access/,/^$/{s@'"${data_dir_default}/"'@'"${data_dir}/"'@g}' "${apparmor_mysqld_path}"
            fi
            ;;
    esac

    # - port
    if [[ "${mysql_port}" -ne "${mysql_port_default}" ]]; then
        # default has parameter datadir= in [mysqld] section
        [[ -s "${conf_path}" ]] && sed -r -i '/^port[[:space:]]*=/d; /^datadir[[:space:]]*=/i port        = '"${mysql_port}"'' "${conf_path}"
    fi

    echo -e "Configuration file path: ${c_blue}${conf_path}${c_normal}\n"
}

funcPortDatadirChangeForPercona(){
    case "${distro_name}" in
        rhel|centos )
            local conf_path=${conf_path:-'/etc/my.cnf'}
            [[ $(echo "${db_version} >= 5.7" | bc) == 1 ]] && conf_path='/etc/percona-server.conf.d/mysqld.cnf'
            ;;
        debian|ubuntu )
            local conf_path=${conf_path:-'/etc/mysql/my.cnf'}
            [[ $(echo "${db_version} >= 5.7" | bc) == 1 ]] && conf_path='/etc/mysql/percona-server.conf.d/mysqld.cnf'
            ;;
    esac

    funcPortDatadirConfigureFormulate "${conf_path}"
    echo -e "Configuration file path: ${c_blue}${conf_path}${c_normal}\n"
}

funcPortDatadirChangeForMariaDB(){
    # opensues 未測試
    case "${distro_name}" in
        rhel|centos|fedora|opensuse )
            local conf_path=${conf_path:-'/etc/my.cnf'}
            ;;
        debian|ubuntu )
            local conf_path=${conf_path:-'/etc/mysql/my.cnf'}
            ;;
    esac

    funcPortDatadirConfigureFormulate "${conf_path}"
    echo -e "Configuration file path: ${c_blue}${conf_path}${c_normal}\n"
}

funcPortAndDatadirChangeConfiguration(){
    funcPortAndDatadirParamaterVerification
    funcSystemServiceManager "${service_name}" 'stop'
    funcPortDatadirChangeFor"${db_name}"
    funcSystemServiceManager "${service_name}" 'start'
}

############# 2-7. MySQL Post-installation Configuration #############
funcPostInstallationConfiguration(){
    local login_user_my_cnf=${login_user_my_cnf:-"${login_user_home}/.my.cnf"}
    local mysql_custom_command=${mysql_custom_command:-"mysql --defaults-file=${login_user_my_cnf}"}

    funcRootPasswordSetting "${login_user_my_cnf}"
    funcSecureInstallation "${mysql_custom_command}"
    funcPortAndDatadirChangeConfiguration
    funcUserLoggingFileSetting "${mysql_custom_command}"
    funcLoadTimeZoneTables "${mysql_custom_command}"
    funcUserDefinedFunction "${mysql_custom_command}"

    local mysql_datadir_port=( $(mysqld --verbose --help | awk 'match($1,/^(datadir|port)$/){print $NF}') )

    echo -e "\nSuccessfully installing ${c_blue}${db_version_no_new}${c_normal}, account info stores in ${c_blue}~/.my.cnf${c_normal}!\n\nData dir: ${c_blue}${mysql_datadir_port[0]}${c_normal}\nPort number: ${c_blue}${mysql_datadir_port[1]}${c_normal}\nVersion info:\n${c_blue}$(mysql --version)${c_normal}.\n"
}


#########  3. Central Control & Executing Process  #########
funcCentralControlOperation(){
    funcInitializationCheck
    funcInternetConnectionCheck
    funcDownloadToolCheck
    funcPackageManagerDetection
    funcOSInfoDetection

    funcDetectIfExisted
    funcVariantAndVersionChoose
    func"${db_name}"Operation
    funcPostInstallationConfiguration
}

funcCentralControlOperation


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset str_len
    unset bak_suffix
    unset auto_installation
    unset data_dir
    unset root_password_new
    unset mysql_port
    unset service_name
    unset mysql_variant_type
    unset variant_version
    unset proxy_server
    unset db_name
    unset db_version
    unset db_version_no_new
    unset variants_version_list
}

trap funcTrapEXIT EXIT

# APT interrupt install operation will occur the following condition :
# E: Could not get lock /var/lib/dpkg/lock - open (11: Resource temporarily unavailable)
# E: Unable to lock the administration directory (/var/lib/dpkg/), is another process using it?
# solution is :
# rm -rf /var/lib/dpkg/lock /var/cache/apt/archives/lock
# dpkg --configure -a

# ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'mypass';
# ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyNewPass4!';

# sudo apt-get purge MariaDB* mariadb* Percona* mysql* -yq
# sudo apt-get autoremove -yq
# sudo rm -rf .my.cnf* .mysql_history /var/log/mysqld.log /var/log/mysql /var/lib/mysql/ /data/ /etc/mysql* /etc/my.cnf*

# Script End

#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #IFS  Internal Field Separator

#Target: Detection GNU/Linux Distribution Info
#Note: Be Used For RHEL, Debian, SLES and veriants Distribution
#Writer: MaxdSre
#Date: Aug 30, 2017 11:58 Wed +0800
#Reconfiguration Date:
# - Oct 19, 2016 10:45 Wed +0800
# - Feb 23, 2017 14:50~17:01 +0800
# - Mar 11, 2017 10:48~12.27 +0800
# - May 5, 2017 20:08 Fri -0400
# - June 6, 2017 21:02 Tue +0800
# - Aug 17, 2017 14:37 Thu +0800

#Docker Script https://get.docker.com/
#Gitlab Script https://packages.gitlab.com/gitlab/gitlab-ce/install


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'DVDTemp_XXXXX'}
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
readonly str_len=${str_len:-16}               # printf str width

output_format=${output_format:-0}
proxy_server=${proxy_server:-''}
ip_public=${ip_public:-''}
ip_public_region=${ip_public_region:-''}
ip_proxy=${ip_proxy:-''}
ip_proxy_region=${ip_proxy_region:-''}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Detect GNU/Linux Distribution System Info!

[available option]
    -h    --help, show help info
    -j    --json, output result via json format
    -p [protocol:]ip:port    --proxy host (http|https|socks4|socks5), default protocol is http
${c_normal}
EOF
}

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

funcInternetConnectionCheck(){
    local gateway_ip=${gateway_ip:-}
    # CentOS: iproute Debian/OpenSUSE: iproute2
    if funcCommandExistCheck 'ip'; then
        local net_command='ip'
        gateway_ip=$(ip route | awk 'match($1,/^default/){print $3}')
    elif funcCommandExistCheck 'netstat'; then
        local net_command='netstat'
        gateway_ip=$(netstat -rn | awk 'match($1,/^Destination/){getline;print $2;exit}')
    else
        funcExitStatement "${c_red}Error${c_normal}: No ${c_blue}ip${c_normal} or ${c_blue}netstat${c_normal} command found, please install it!"
    fi

    if [[ -n "${gateway_ip}" ]] && ping -q -w 1 -c 1 "${gateway_ip}" &> /dev/null; then
        [[ "${net_command}" == 'ip' ]] && ip_local=$(ip route get 1 | awk '{print $NF;exit}')
    fi
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
    local referrer_page=${referrer_page:-"https://duckduckgo.com/?q=github"}
    # local user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6.4) AppleWebKit/537.29.20 (KHTML, like Gecko) Chrome/60.0.3030.92 Safari/537.29.20"

    download_tool_origin=${download_tool_origin:-}

    if funcCommandExistCheck 'curl'; then
        download_tool="curl -fsL --retry ${retry_times} --retry-delay ${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-keepalive --referer ${referrer_page}"   # curl -s URL -o /PATH/FILE； -fsSL
        # --user-agent ${user_agent}
        download_tool_origin="${download_tool}"

        if [[ -n "$proxy_server" ]]; then
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
        download_tool_origin="${download_tool}"

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


    # - Detect Real External IP
    local ip_public_dig=${ip_public_dig:-}
    local ip_public_dig_info=${ip_public_dig_info:-}
    local ip_public_dig_country=${ip_public_dig_country:-}
    local ip_public_dig_city=${ip_public_dig_city:-}
    local ip_public_dig_region=${ip_public_dig_region:-}
    if funcCommandExistCheck 'dig'; then
        ip_public_dig=$(dig +short myip.opendns.com @resolver1.opendns.com) # get real public ip
        # Error Info ";; connection timed out; no servers could be reached"
        local ip_public_dig_pattern="^([0-9]{1,3}.){3}[0-9]{1,3}$"
        if [[ "${ip_public_dig}" =~ $ip_public_dig_pattern ]]; then
            ip_public_dig_info=$($download_tool ipinfo.io/"${ip_public_dig}")
        fi

        if [[ -n "${ip_public_dig_info}" ]]; then
            ip_public_dig_country=$(echo "$ip_public_dig_info" | sed -r -n '/\"country\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
            ip_public_dig_city=$(echo "$ip_public_dig_info" | sed -r -n '/\"city\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
            ip_public_dig_region="${ip_public_dig_country}.${ip_public_dig_city}"
        fi
    fi

    local ip_public_info=${ip_public_info:-}
    local ip_public_country=${ip_public_country:-}
    local ip_public_city=${ip_public_city:-}

    ip_public_info=$($download_tool ipinfo.io)
    # ip_public_info=$($download_tool_origin ipinfo.io)
    if [[ -n "${ip_public_info}" ]]; then
        ip_public=$(echo "$ip_public_info" | sed -r -n '/\"ip\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
        ip_public_country=$(echo "$ip_public_info" | sed -r -n '/\"country\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
        ip_public_city=$(echo "$ip_public_info" | sed -r -n '/\"city\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
        ip_public_region="${ip_public_country}.${ip_public_city}"
    else
        # https://stackoverflow.com/questions/14594151/methods-to-detect-public-ip-address-in-bash
        # https://www.gnu.org/software/bash/manual/html_node/Redirections.html
        if [[ -d "/dev" ]]; then
            # https://major.io/icanhazip-com-faq/
            # exec 6<> /dev/tcp/icanhazip.com/80
            # echo -e 'GET / HTTP/1.0\r\nHost: icanhazip.com\r\n\r' >&6
            # while read i; do [[ -n "$i" ]] && ip_public="$i" ; done <&6
            # exec 6>&-

            exec 6<> /dev/tcp/ipinfo.io/80
            echo -e 'GET / HTTP/1.0\r\nHost: ipinfo.io\r\n\r' >&6
            # echo -e 'GET /ip HTTP/1.0\r\nHost: ipinfo.io\r\n\r' >&6
            # echo -e 'GET /country HTTP/1.0\r\nHost: ipinfo.io\r\n\r' >&6

            # ip_public=$(cat 0<&6 | sed -r -n '/^\{/,/^\}/{/\"ip\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}}')
            ip_public_info=$(cat 0<&6 | sed -r -n '/^\{/,/^\}/p')
            exec 6>&-

            if [[ -n "${ip_public_info}" ]]; then
                ip_public=$(echo "$ip_public_info" | sed -r -n '/\"ip\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
                ip_public_country=$(echo "$ip_public_info" | sed -r -n '/\"country\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
                ip_public_city=$(echo "$ip_public_info" | sed -r -n '/\"city\"/{s@[[:space:],]*@@g;s@[^:]*:"([^"]*)"@\1@g;p}')
                ip_public_region="${ip_public_country}.${ip_public_city}"
            fi

        fi
    fi




    if [[ -n "${ip_public_dig}" && -n "${ip_public}" ]]; then
        if [[ "${ip_public_dig}" != "${ip_public}" ]]; then
            ip_proxy="${ip_public}"
            ip_proxy_region="${ip_public_region}"
            ip_public="${ip_public_dig}"
            ip_public_region="${ip_public_dig_region}"
        fi
    elif [[ -n "${ip_public_dig}" ]]; then
        ip_public="${ip_public_dig}"
        ip_public_region="${ip_public_dig_region}"
    fi

}

# http://wiki.bash-hackers.org/howto/getopts_tutorial
# https://www.mkssoftware.com/docs/man1/getopts.1.asp
while getopts "hjp:" option "$@"; do
    case "$option" in
        j ) output_format=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  1-2 Logic Processing  #########
funcOSDetectionProcess(){
    local release_file=${release_file:-}
    local distro_name=${distro_name:-}
    local version_id=${version_id:-}
    local distro_fullname=${distro_fullname:-}
    local distro_family_own=${distro_family_own:-}
    local official_site=${official_site:-}
    local codename=${codename:-}

    # CentOS 5, CentOS 6, Debian 6 has no file /etc/os-release
    if [[ -s '/etc/os-release' ]]; then
        release_file='/etc/os-release'
        #distro name，eg: centos/rhel/fedora,debian/ubuntu,opensuse/sles
        # distro_name=$(. "${release_file}" && echo "${ID:-}")
        distro_name=$(sed -r -n '/^ID=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")
        #version id, eg: 7/8, 16.04/16.10, 13.2/42.2
        if [[ "$distro_name" == 'debian' && -s /etc/debian_version ]]; then
            version_id=$(cat /etc/debian_version)
        else
            # version_id=$(. "${release_file}" && echo "${VERSION_ID:-}")
            version_id=$(sed -r -n '/^VERSION_ID=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")
        fi

        #distro full pretty name, for CentOS ,file redhat-release is more detailed
        if [[ -s '/etc/redhat-release' ]]; then
            distro_fullname=$(cat /etc/redhat-release)
        else
            # distro_fullname=$(. "${release_file}" && echo "${PRETTY_NAME:-}")
            distro_fullname=$(sed -r -n '/^PRETTY_NAME=/s@.*="?([^"]*)"?@\1@p' "${release_file}")
        fi
        # Fedora, Debian，SUSE has no parameter ID_LIKE, only has ID
        # distro_family_own=$(. "${release_file}" && echo "${ID_LIKE:-}")
        distro_family_own=$(sed -r -n '/^ID_LIKE=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")
        [[ "$distro_family_own" == '' ]] && distro_family_own="$distro_name"
        # GNU/Linux distribution official site
        # official_site=$(. "${release_file}" && echo "${HOME_URL:-}")
        official_site=$(sed -r -n '/^HOME_URL=/s@.*="?([^"]*)"?@\L\1@p' "${release_file}")

        case "${distro_name}" in
            debian|ubuntu ) codename=$(sed -r -n '/^VERSION=/s@.*[,(][[:space:]]?([^[:space:]\)]+).*@\L\1@p' "${release_file}") ;;
            opensuse ) codename=$(sed -r -n '/CODENAME/s@.*=[[:space:]]?(.*)@\L\1@p' /etc/SuSE-release) ;;
            * ) codename='' ;;
        esac    # End case

    elif [[ -s '/etc/redhat-release' ]]; then  # for CentOS 5, CentOS 6
        release_file='/etc/redhat-release'
        distro_name=$(rpm -q --qf "%{name}" -f "${release_file}") #centos-release,fedora-release
        distro_name=${distro_name%%-*}    # centos, fedora
        version_id=$(sed -r -n 's@[^[:digit:]]*([[:digit:]]{1}).*@\1@p' "${release_file}") # 5/6
        distro_fullname=$(cat "${release_file}")
        distro_family_own='rhel'   # family is rhel (RedHat)

    elif [[ -s /etc/debian_version && -s /etc/issue.net ]]; then    # for Debian 6
        release_file='/etc/issue.net'   #Debian GNU/Linux 6.0
        distro_name=$(sed -r -n 's@([^[:space:]]*).*@\L\1@p' "${release_file}")
        version_id=$(sed -r -n 's@[^[:digit:]]*([[:digit:]]{1}).*@\1@p' "${release_file}") #6
        distro_fullname=$(cat "${release_file}")
        distro_family_own='debian'   # family is debian (Debian)

        case "${version_id}" in
            6 ) codename='squeeze' ;;
            * ) codename='' ;;
        esac    # End case

    else
        if [[ "${output_format}" -eq 1 ]]; then
            output_json="{"
            output_json=$output_json"\"error\":\"this script can't detect your system\""
            output_json=$output_json"}"
            echo "${output_json}"
        else
            echo "Sorry, this script can't detect your system!"
        fi  # End if
        exit
    fi      # End if

    # Convert family name
    case "${distro_family_own,,}" in
        debian ) local distro_family_own='Debian' ;;
        suse|sles ) local distro_family_own='SUSE' ;;
        rhel|"rhel fedora"|fedora|centos ) local distro_family_own='RedHat' ;;
        * ) local distro_family_own='Unknown' ;;
    esac    # End case

    if [[ "${output_format}" -eq 1 ]]; then
        output_json="{"
        output_json=$output_json"\"pretty_name\":\"$distro_fullname\","
        output_json=$output_json"\"distro_name\":\"$distro_name\","
        [[ -n "$codename" ]] && output_json=$output_json"\"codename\":\"$codename\","
        output_json=$output_json"\"version_id\":\"$version_id\","
        output_json=$output_json"\"family_name\":\"$distro_family_own\","
        [[ -n "$official_site" ]] && output_json=$output_json"\"official_site\":\"$official_site\","
        [[ -n "$ip_local" ]] && output_json=$output_json"\"ip_local\":\"$ip_local\","
        [[ -n "$ip_public" ]] && output_json=$output_json"\"ip_public\":\"$ip_public\","
        [[ -n "$ip_public_region" ]] && output_json=$output_json"\"ip_public_region\":\"$ip_public_region\","
        [[ -n "${ip_proxy}" ]] && output_json=$output_json"\"ip_proxy\":\"$ip_proxy\","
        [[ -n "${ip_proxy_region}" ]] && output_json=$output_json"\"ip_proxy_region\":\"$ip_proxy_region\","
        output_json=${output_json%,*}
        output_json=$output_json"}"
        echo "${output_json}"
    else
        funcInfoPrintf 'Pretty Name' "$distro_fullname"
        funcInfoPrintf 'Distro Name' "$distro_name"
        [[ -n "$codename" ]] && funcInfoPrintf 'Code Name' "$codename"
        funcInfoPrintf 'Version ID' "$version_id"
        funcInfoPrintf 'Family Name' "$distro_family_own"
        [[ -n "$official_site" ]] && funcInfoPrintf 'Official Site' "$official_site"
        [[ -n "$ip_local" ]] && funcInfoPrintf 'Local IP Addr' "$ip_local"
        [[ -n "$ip_public" ]] && funcInfoPrintf 'Public IP Addr' "$ip_public ($ip_public_region)"
        [[ -n "$ip_proxy" ]] && funcInfoPrintf 'Proxy IP Addr' "$ip_proxy ($ip_proxy_region)"
    fi  # End if
}


#########  3. Executing Process  #########
funcInternetConnectionCheck
funcDownloadToolCheck
funcOSDetectionProcess


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset output_format
    unset proxy_server
    unset ip_public
    unset ip_public_region
    unset ip_proxy
    unset ip_proxy_region
    unset output_json

    unset http_proxy
    unset HTTPS_PROXY
    unset download_tool
    unset download_tool_origin
}

trap funcTrapEXIT EXIT

# Script End

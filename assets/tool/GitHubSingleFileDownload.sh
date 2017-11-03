#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://github.com/
#Target: Download Single File From GitHub Via Origin URL By Bash Script On GNU/Linux
#Writer: MaxdSre
#Date: Jun 09, 2017 09:44 Fri +0800
#Update Time:
# - Jan 12, 2016 01:26 Tue +0800
# - Sep 23, 2016 11:51 Fri +0800
# - Nov 02, 2016 12:51 Wed +0800
# - Dec 21, 2016 15:45 Wed +0800


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'GHSFDTemp_XXXXX'}
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
github_url=${github_url:-}
save_dir=${save_dir:-}
proxy_server=${proxy_server:-}
origin_complete_name=${origin_complete_name:-}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Download Single File From GitHub Via Origin URL On GNU/Linux!

[available option]
    -h    --help, show help info
    -l url    --sepcify file url on GitHub
    -d dir    --specify file save dir, default is home dir (~/)
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
    # - OS support check
    [[ -s /etc/os-release || -s /etc/SuSE-release || -s /etc/redhat-release || (-s /etc/debian_version && -s /etc/issue.net) ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script doesn't support your system!"

    # - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && now_user="$USER" || now_user="$SUDO_USER"
    [[ "${now_user}" == 'root' ]] && user_home='/root' || user_home="/home/${now_user}"
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


funcFileInfoBar(){
cat <<EOF
${c_red}
=========================================
          File          Info
=========================================
${c_normal}
EOF
}


#########  1-2 getopts Operation  #########
while getopts "hl:d:p:" option "$@"; do
    case "$option" in
        l ) github_url="$OPTARG" ;;
        d ) save_dir="$OPTARG" ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done



#########  2.  Logical Process Function  #########
# - check GitHub url legal or not
funcGitHubUrlCheck(){
    if [[ -z "${github_url}" ]]; then
        funcExitStatement "${c_red}Error${c_normal}: please specify a GitHub url!"
    elif [[ ! "${github_url}" =~ ^https://github.com/* ]]; then
        funcExitStatement "${c_red}Error${c_normal}: illegal url ${c_blue}${github_url}${c_normal}, please specify a legal GitHub url!"
    fi
}

# - file save dir, 1. specified dir 2. home dir
funcSaveDirCheck(){
    if [[ -n "${save_dir}" && -d "${save_dir}" ]]; then
        [[ -w "${save_dir}" ]] || funcExitStatement "${c_red}Error${c_normal}: directory you specified ${c_blue}${save_dir}${c_normal} doesn't has ${c_red}write${c_normal} permission for current user ${c_blue}${now_user}${c_normal}!"
    else
        save_dir="${user_home}"
    fi
}

# - Extract File's Complete Name Via Origin URL
funcExtractFileCompleteName(){
    # echo "Begin to extract file complete origin name, just be patient!"
    origin_complete_name=$($download_tool "${github_url}" | sed -r -n '/final-path/s@.*<strong.*>(.*)<.*>@\1@p')
    [[ -z "${origin_complete_name}" ]] && funcExitStatement "${c_red}Error${c_normal}: fail to get file name via specified GitHub url!"
    # printf "Name of file you wanna download is ${c_blue}%s${c_normal}!\n" "${origin_complete_name}"
}

#########  2-1.  Download Target File Via Origin URL  #########
funcDownloadFile(){
    echo "Begin to download file ${c_blue}${origin_complete_name}${c_normal}, just be patient!"

    local file_save_path="${save_dir}/${origin_complete_name}"
    if [[ -f "${file_save_path}" ]]; then
        local file_backup_path="${file_save_path}_bak"
        [[ -f "${file_backup_path}" ]] && rm -f "${file_backup_path}"
        mv "${file_save_path}" "${file_backup_path}"   #backup existing file with same name
        echo "Rename existed file ${c_blue}${file_save_path}${c_normal} to ${c_blue}${file_backup_path}${c_normal}, download operation continue!"
    fi

    local transformed_url=${github_url//blob\/}
    local transformed_url=${transformed_url/github.com/raw.githubusercontent.com}

    $download_tool "${transformed_url}" > "${file_save_path}"

    if [[ -f "${file_save_path}" ]]; then
        printf "File ${c_blue}%s${c_normal} has been saved under directory ${c_blue}%s${c_normal}!\n" "${origin_complete_name}" "${save_dir}"

        if funcCommandExistCheck 'stat'; then
            funcFileInfoBar
            stat "${file_save_path}"
        fi
    else
        funcExitStatement "${c_red}Sorry${c_normal}: fail to download file ${c_red}${origin_complete_name}${c_normal}!"
    fi
}


#########  3. Executing Process  #########
funcInitializationCheck
funcGitHubUrlCheck
funcSaveDirCheck
funcInternetConnectionCheck
funcDownloadToolCheck

funcExtractFileCompleteName
funcDownloadFile


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset github_url
    unset save_dir
    unset proxy_server
    unset download_tool
    unset proxy_server
    unset origin_complete_name
}

trap funcTrapEXIT EXIT

# Script End

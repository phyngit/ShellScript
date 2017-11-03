#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Target: Generation Random Unused Port (root or non-root)On GNU/Linux
#Writer: MaxdSre
#Date: June 08, 2017 14:01 Thu +0800
#Update Time:
# - Sep 08, 2016 23:00 Thu +0800
# - Nov 01, 2016 11:23 Thu +0800
# - Dec 21, 2016 15:56 Wed +0800
# - Feb 27, 2017 09:59 Mon +0800
# - May 6, 2017 17:53 Sat -0400

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'PUPGTemp_XXXXX'}
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

output_format=${output_format:-0}
port_for_root=${port_for_root:-0}
simple_format=${simple_format:-0}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Generating Random Unused Port On GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -j    --json, output result via json format
    -r    --root, just gengeate port no. from 0~1024
    -s    --simple, just output port generated
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

    if funcCommandExistCheck 'ss'; then
        check_tool='ss'   # ss -tuanp
        port_field='5'   # awk field $5
        state_field='2'   # awk field $2
    elif funcCommandExistCheck 'netstat'; then
        check_tool='netstat' # netstat -tuanp
        port_field='4'   # awk field $4
        state_field='6'   # awk field $6
    else
        funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}ss${c_normal} or ${c_blue}netstat${c_normal} command found!"
    fi  # End if
}


#########  1-2 getopts Operation  #########
while getopts "hjrs" option "$@"; do
    case "$option" in
        j ) output_format=1 ;;
        r ) port_for_root=1 ;;
        s ) simple_format=1 ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  Logical Processing  #########
# - Usable Ports Range Check
# Generation type, default is non-root (1024,65536), when $2 is root, it specity (0,1024)
funcUnusedPortRangeCheck(){
    local_port_start=${local_port_start:-0}
    local_port_end=${local_port_end:-1024}
    compare_operator=${compare_operator:-'<'}
    generate_type=${generate_type:-'root'}

    if [[ "${port_for_root}" -ne 1 ]]; then
        local_port_start=$(sysctl -a 2> /dev/null | awk 'match($1,/ip_local_port_range/){print $(NF-1)}')
        local_port_end=$(sysctl -a 2> /dev/null | awk 'match($1,/ip_local_port_range/){print $NF}')
        compare_operator='>'
        generate_type='non-root'
        # local_port_start=1024
    fi

    if [[ "${output_format}" -ne 1 && "${simple_format}" -ne 1 ]]; then
        printf "Port range (${c_blue}%s${c_normal},${c_blue}%s${c_normal}), generate type ${c_red}%s${c_normal}!\n" "${local_port_start}" "${local_port_end}" "${generate_type}"
    fi
}

# - Used Port Check
funcUsedPortCheck(){
    temp_port_used_list=$(mktemp -t "${mktemp_format}") #temporary file
    # 1 - 查看系統正在被監聽的端口
    "$check_tool" -tuanp | awk 'match($1,/^(tcp|udp)/)&&match($'"$state_field"',/(LISTEN|ESTAB|UNCONN)/){port=gensub(/.*:(.*)/,"\\1","g",$'"$port_field"');print port}' | awk '{if($0'"$compare_operator"'1024){a[$0]++}}END{for(i in a) print i}'  > "$temp_port_used_list"

    # 2 - 查看文件/etc/services中被分配的端口號，去重後寫入臨時文件
    awk 'match($1,/^[^#]/){port=gensub(/([[:digit:]]+)\/.*/,"\\1","g",$2);print port}' /etc/services | awk '!a[$0]++{if($0'"$compare_operator"'1024){print $0}}' >> "$temp_port_used_list"
    # sed -n -r 's@.*[[:space:]]+([0-9]+)/.*@\1@p' /etc/services
}

# - Generate Random Port Unused
funcGenerateRandomPort(){
    local port_used_list="$1"
    local port_from="$2"
    local port_to="$3"
    random_num=$(head -n 18 /dev/urandom | cksum | awk '{print $1}') # 讀取行數根據實際需要更改
    # https://github.com/koalaman/shellcheck/wiki/Sc2004
    port=$((random_num%port_to))

    [[ $(grep -c -w "${port}" "${port_used_list}") -gt 0 || "${port}" -lt "${port_from}" ]] && port=$(funcGenerateRandomPort "${port_used_list}" "${port_from}" "${port_to}") # 進行函數迭代 iterate
    echo "${port}"
}

# - Port Generation & Output
funcPortGenerationAndOutput(){
    local generated_port=${generated_port:-}
    generated_port=$(funcGenerateRandomPort "${temp_port_used_list}" "${local_port_start}" "${local_port_end}") #調用函數

    if [[ "${output_format}" -eq 1 ]]; then
        output_json="{"
        output_json=$output_json"\"generate_type\":\"${generate_type}\","
        [[ "${simple_format}" -eq 1 ]] || output_json=$output_json"\"port_range\":\"${local_port_start}-${local_port_end}\","
        output_json=$output_json"\"port_no\":\"${generated_port}\","
        output_json=${output_json%,*}
        output_json=$output_json"}"
        echo "${output_json}"
    else
        if [[ "${simple_format}" -eq 1 ]]; then
            echo "${c_red}${generated_port}${c_normal}"
        else
            printf "Newly gengeated port num is ${c_blue}%s${c_normal}.\n" "${generated_port}"
        fi
    fi

    [[ -f "${temp_port_used_list}" ]] && rm -f "${temp_port_used_list}"
}


#########  3. Executing Process  #########
funcInitializationCheck
funcUnusedPortRangeCheck
funcUsedPortCheck
funcPortGenerationAndOutput


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    unset output_format
    unset port_for_root
    unset simple_format
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
}

trap funcTrapEXIT EXIT

# Script End

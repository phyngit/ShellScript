#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Target: Extract Port Being Used & Corresponding Service On GNU/Linux
#Writer: MaxdSre
#Date: Sep 21, 2017 10:40 Thu +0800
#Update Time:
# - Aug 10, 2016 Wed +0800
# - Dec (28, 2016 16:34 Wed +0800 ~ 29 17:09 Thu +0800)
# - Dec 21, 2016 15:56 Wed +0800
# - Feb 27, 2017 14:04~18:32 Mon +0800
# - Apr 07, 2017 14:28 Fri +0800
# - May 06, 2017 16:05 Sat -0400
# - Jun 08, 2017 15:11 Thu +0800
# - Sep 11, 2017 13:44 Mon +0800
# - Sep 14, 2017 16:53 Mon +0800
# - Sep 15, 2017 17:32 Fri +0800  (Reconfiguration)


#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'PUIDTemp_XXXXX'}
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
just_listen=${just_listen:-0}
service_name_specify=${service_name_specify:-}
proto_type=${proto_type:-''}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Detect Port Being Used & Corresponding Services Info In GNU/Linux!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -m    --markdown, output result via markdown format
    -l    --listen, just show port state is listen
    -s service_name    --specify specific service name, just search corresponding service
    -p protocol    --specify specific port protocol (tcp/udp), default is all
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
    if [[ -n "${name}" ]]; then
        local executing_path=${executing_path:-}
        executing_path=$(which "${name}" 2> /dev/null || command -v "$name" 2> /dev/null)
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

    funcCommandExistCheck 'ps' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}ps${c_normal} command found!"

    if funcCommandExistCheck 'ss'; then
        check_tool='ss'   # ss -tuanp
    elif funcCommandExistCheck 'netstat'; then
        check_tool='netstat' # netstat -tuanp
    else
        funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}ss${c_normal} or ${c_blue}netstat${c_normal} command found!"
    fi  # End if

    # - AWK Version Check version below 4 can not use PROCINFO["sorted_in"]
    if funcCommandExistCheck 'gawk'; then
        awk --version &> /dev/null
        if [[ $? -eq 0 ]]; then
            awk_version=$(awk --version | awk '{print gensub(/([^.]*).*/,"\\1","g",$3);exit}')
        else
            funcExitStatement "${c_red}Error${c_normal}, please install package ${c_blue}gawk${c_normal} first!"
        fi
    else
        funcExitStatement "${c_red}Error${c_normal}, no ${c_blue}gawk${c_normal} command found. Please install package ${c_blue}gawk${c_normal} first!!"
    fi
}


#########  1-2 getopts Operation  #########
while getopts "hmls:p:tu" option "$@"; do
    case "$option" in
        m ) output_format=1 ;;
        l ) just_listen=1 ;;
        s ) service_name_specify="$OPTARG" ;;
        p ) proto_type="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-1. Extract Port Used & Corresponding Service Name  #########
funcProcessAndPortInfoExtraction(){
    process_list=$(mktemp -t "${mktemp_format}")
    port_service_list=$(mktemp -t "${mktemp_format}")

    # Format 1 -- ps -ef
    # UID|PID|PPID|C|STIME|TTY|TIME|CMD
    # root|1|0|0|08:11|?|00:00:01|/sbin/init

    # Format 2 -- ps axu
    # USER|PID|%CPU|%MEM|VSZ|RSS|TTY|STAT|START|TIME|COMMAND
    # root|1|0.0|0.0|139416|7148|?|Ss|08:11|0:01|/sbin/init

    # - User-defined format.
    # man ps | sed -r -n '/^STANDARD FORMAT SPECIFIERS$/,/^ENVIRONMENT VARIABLES$/p'
    # ps -eo pid,ppid,uid,uname,tty,pri,ni,stat,%mem,%cpu,comm,rss,drs,trs,vsz,start,cmd --sort=-%mem

    ps -eo pid,ppid,comm,uid,uname,tty,pri,ni,stat,start,%mem,%cpu,cmd --sort=pid > "${process_list}"
    # PID|PPID|COMMAND|UID|USER|TT|PRI|NI|STAT|STARTED|%MEM|%CPU|CMD
    # 1|0|init|0|root|?|19|0|Ss|Apr 20|0.0|0.0|/sbin/init

    case "${proto_type,,}" in
        tcp|tc|t ) proto_type='tcp' ;;
        udp|ud|u ) proto_type='udp' ;;
        * ) proto_type='tcp|udp';;
    esac

    local listen_list=${listen_list:-'LISTEN|ESTAB|UNCONN'}
    [[ "${just_listen}" -eq 1 ]] && listen_list='LISTEN'

    service_name_specify="${service_name_specify,,}"

    case "${check_tool,,}" in
        ss )
            if [[ "${awk_version}" -lt 4 ]]; then
                ss -tuanp | awk 'BEGIN{IGNORECASE=1}match($0,/'"${service_name_specify}"'/)&&match($1,/^('"${proto_type}"')/)&&match($2,/('"${listen_list}"')/){protocol=$1;state=$2;port=gensub(/.*:(.*)/,"\\1","g",$5);service=gensub(/.*:\(\("([^"]*)",.*/,"\\1","g",$7);pid=gensub(/[^,]*,(pid=)?([[:digit:]]+),.*/,"\\2","g",$7);print protocol,port,state,service,pid}' | awk '!a[$0]++' | sort -n -k 2  > "${port_service_list}"
            else
                ss -tuanp | awk 'BEGIN{IGNORECASE=1}match($0,/'"${service_name_specify}"'/)&&match($1,/^('"${proto_type}"')/)&&match($2,/('"${listen_list}"')/){protocol=$1;state=$2;port=gensub(/.*:(.*)/,"\\1","g",$5);service=gensub(/users:\(\("([^"]*)",.*/,"\\1","g",$7);pid=gensub(/users:[^,]*,(pid=)?([[:digit:]]+),.*/,"\\2","g",$7);print protocol,port,state,service,pid}' | awk '!a[$0]++' | awk '{a[$0]=$2}END{PROCINFO["sorted_in"]="@val_num_asc";for(i in a){print i}}' > "${port_service_list}"
            fi  # End if
            ;;
        netstat )
            if [[ "${awk_version}" -lt 4 ]]; then
                netstat -tuanp | awk 'BEGIN{IGNORECASE=1}match($0,/'"${service_name_specify}"'/)&&match($1,/^('"${proto_type}"')/)&&match($6,/('"${listen_list}"')/){protocol=$1;if($6~/ESTAB/){state="ESTAB"}else{state=$6};port=gensub(/.*:(.*)/,"\\1","g",$4);pid=gensub(/(.*)\/(.*)/,"\\1","g",$7);service=gensub(/(.*)\/(.*)/,"\\2","g",$7);print protocol,port,state,service,pid}' | awk '!a[$0]++' | sort -n -k 2 > "${port_service_list}"
            else
                netstat -tuanp | awk 'BEGIN{IGNORECASE=1}match($0,/'"${service_name_specify}"'/)&&match($1,/^('"${proto_type}"')/)&&match($6,/('"${listen_list}"')/){protocol=$1;if($6~/ESTAB/){state="ESTAB"}else{state=$6};port=gensub(/.*:(.*)/,"\\1","g",$4);pid=gensub(/(.*)\/(.*)/,"\\1","g",$7);service=gensub(/(.*)\/(.*)/,"\\2","g",$7);print protocol,port,state,service,pid}' | awk '!a[$0]++' | awk '{a[$0]=$2}END{PROCINFO["sorted_in"]="@val_num_asc";for(i in a){print i}}' > "${port_service_list}"
            fi  # End if
            ;;
    esac    # End case

    # output format
    # tcp 22 ESTAB sshd 6122
    # tcp 22 LISTEN sshd 2830

    cp "${port_service_list}" /tmp/123.txt
}


#########  2-2. Core Processing Procedure  #########
funcDisplayingHeaderSetting(){
    if [[ "${output_format}" -eq 1 ]]; then
        printf "\nProto/Port|State|PID|Memory|CPU|Service Name|Service Path\n---|---|---|---|---|---|---\n"
    else
        printf "${c_red}%-10s${c_normal} ${c_red}%-6s${c_normal} ${c_red}%-6s${c_normal} ${c_red}%-4s${c_normal} ${c_red}%-4s${c_normal} ${c_red}%-16s${c_normal} ${c_red}%-50s${c_normal}\n" "Proto/Port" "State" "PID" "Memory" "CPU" "Service Name" "Service Path"
    fi
}

funcSSHHostIPDetection(){
    local host_ip_info=${1:-}
    local host_ip=${host_ip:-}

    if [[ -n "${host_ip_info}" ]]; then
        host_ip_info=$(echo "${host_ip_info}" | sed -r 's@(\(|\))@@g')

        if [[ "${host_ip_info}" =~ ^([0-9]{1,3}.){3}[0-9]{1,3}$ ]]; then
            host_ip="${host_ip_info}"
        else
            # https://www.gnu.org/software/gawk/manual/html_node/Case_002dsensitivity.html
            host_ip=$(awk 'BEGIN{IGNORECASE=1}match($0,/'"${host_ip_info}"'/){print $1;exit}' /etc/hosts 2> /dev/null)

            if [[ -z "${host_ip}" ]]; then
                local system_user=${system_user:-}
                system_user=$(awk 'match($1,/^'"${process_id}"'$/){print $5}' "${process_list}" 2> /dev/null)

                local ssh_config_path=${ssh_config_path:-}

                if [[ "${system_user}" == 'root' ]]; then
                    ssh_config_path='/root/.ssh/config'
                elif [[ -n "${system_user}" ]]; then
                    ssh_config_path="/home/${system_user}/.ssh/config"
                fi

                [[ -s "${ssh_config_path}" ]] && host_ip=$(sed -r -n '/^Host[[:space:]]*'"${host_ip_info}"'$/,/Host[[:space:]]+/{/HostName/{s@[^[:digit:]]*(.*)$@\1@g;p}}' "${ssh_config_path}")
            fi    # end if host_ip

        fi    # end if host_ip_info

        echo "${host_ip}"
    fi
}

funcSSHSessionInfo(){
    # protocol port process_state service_name process_id
    local l_service_info_origin="${1:-}"

    # PID|PPID|COMMAND|UID|USER|TT|PRI|NI|STAT|STARTED|%MEM|%CPU|CMD

    case "${l_service_info_origin}" in
        sshd )
            # remote host connect local host
            local r2l_user_info=${r2l_user_info:-}
            # root@pts/0      readonly [priv]    root@notty
            r2l_user_info=$(awk 'match($1,/^'"${process_id}"'$/){print $NF}' "${process_list}")

            # match pattern: pid --> ppid
            [[ -n "${r2l_user_info}" && -z $(echo "${r2l_user_info}" | sed -n '/@/p') ]] && r2l_user_info=$(awk 'match($2,/^'"${process_id}"'$/){print $NF}' "${process_list}")

            if [[ -n "${r2l_user_info}" ]]; then
                local r2l_user=${r2l_user:-}
                local r2l_terminal=${r2l_terminal:-}
                # sshd: root@pts/0
                r2l_user="${r2l_user_info%%@*}"
                r2l_terminal="${r2l_user_info##*@}"

                case "${r2l_terminal}" in
                    notty )
                        # http://www.sysadminworld.com/2011/ps-aux-shows-sshd-rootnotty/

                        service_info="${c_blue}${l_service_info_origin}${c_normal} from ${r2l_user_info} (${c_red}$(awk 'match($2,/^'"${process_id}"'$/){print $NF}' "${process_list}")${c_normal})"
                        ;;
                    * )
                        local r2l_ip=${r2l_ip:-}
                        # extract ip wrapped with ()
                        r2l_ip=$(who | awk 'match($1,/^'"${r2l_user}"'$/)&&match($2,/^'"${r2l_terminal//\//\\/}"'$/){print $NF}')
                        r2l_ip=$(funcSSHHostIPDetection "${r2l_ip}")

                        local current_tty=${current_tty:-}

                        if [[ -n "${r2l_ip}" ]]; then
                            # https://unix.stackexchange.com/questions/270272/how-to-get-the-tty-in-which-bash-is-running
                            [[ $(awk -v a="$$" '$2==a{print $6}' "${process_list}") == "${r2l_terminal}" ]] && current_tty=' TTY'

                            service_info="${c_blue}${l_service_info_origin}${c_normal} from ${r2l_user_info}${c_red}${current_tty}${c_normal} (${r2l_ip})"
                        else
                            service_info="${c_blue}${l_service_info_origin}${c_normal} from ${r2l_user_info}"
                        fi
                        ;;
                esac    # end case r2l_terminal

            else
                # sshd: root@pts/0
                service_info=$(awk '$1=='"${process_id}"'{print gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0)}' "${process_list}")
            fi
            ;;
        ssh )
            # local host connect remote host
            local l2r_user_info=${l2r_user_info:-}
            l2r_user_info=$(awk 'match($1,/^'"${process_id}"'$/){print gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0)}' "${process_list}")
            #  trim 'ssh ' or 'ssh -Y ' at the beging of str
            l2r_host_info="${l2r_user_info##* }"

            if [[ "${l2r_host_info}" =~ ^([0-9]{1,3}.){3}[0-9]{1,3}$ ]]; then
                service_info="${l_service_info_origin} ${l2r_host_info}"

            elif [[ "${l2r_host_info}" =~ -W ]]; then
                # front_host -W IP:PORT user
                local target_host=${target_host:-}
                local intermediate_host=${intermediate_host:-}

                target_host=$(echo "${l2r_host_info}" | sed -r -n 's@.*-W[[:space:]]+([^[:space:]]*).*@\1@g;p')
                intermediate_host=$(echo "${l2r_host_info}" | sed -r -n 's@^([^[:space:]]+)[[:space:]].*@\1@g;p')

                if [[ -n "${target_host}" && -n "${intermediate_host}" ]]; then
                    local intermediate_host_ip=${intermediate_host_ip:-}
                    intermediate_host_ip=$(funcSSHHostIPDetection "${intermediate_host}")
                    service_info="${c_blue}${l_service_info_origin}${c_normal} to ${target_host%%:*} via ${intermediate_host} (${intermediate_host_ip})"
                else
                    service_info=$(awk '$1=='"${process_id}"'{print gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0)}' "${process_list}")
                fi

            else
                local remote_host_ip=${remote_host_ip:-}
                remote_host_ip=$(funcSSHHostIPDetection "${l2r_host_info}")

                if [[ -n "${remote_host_ip}" ]]; then
                    service_info="${c_blue}${l_service_info_origin}${c_normal} to ${l2r_host_info} (${remote_host_ip})"
                else
                    service_info=$(awk '$2=='"${process_id}"'{print gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0)}' "${process_list}")
                fi

            fi
            ;;
        sftp )
            # local host connect remote host
            local user_info=${user_info:-}
            user_info=$(awk 'match($1,/^'"${process_id}"'$/){print gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0)}' "${process_list}")
            host_info="${user_info##* }"

            if [[ "${user_info}" =~ ^([0-9]{1,3}.){3}[0-9]{1,3}$ ]]; then
                service_info="${l_service_info_origin} ${host_info}"
            else
                local remote_host_ip=${remote_host_ip:-}
                remote_host_ip=$(funcSSHHostIPDetection "${host_info}")

                if [[ -n "${remote_host_ip}" ]]; then
                    service_info="${c_blue}${l_service_info_origin}${c_normal} to ${host_info} (${remote_host_ip})"
                else
                    service_info="${user_info}"
                fi

            fi

            ;;
    esac    # end case l_service_info_origin
}

funcNginxProcessInfo(){
    # master process / work process
    local l_service_info_origin="${1:-}"

    if [[ "${l_service_info_origin}" == 'nginx' ]]; then
        funcCommandExistCheck "${l_service_info_origin}" && l_service_info_origin=$(command -v "${service_info_origin}")

        local nginx_process_info=${nginx_process_info:-}
        nginx_process_info=$(awk 'match($1,'"${process_id}"'){print gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0)}' "${process_list}")

        local process_type=${process_type:-}
        if [[ -n "${nginx_process_info}" ]]; then

            local n_process_type=${n_process_type:-}
            n_process_type=$(echo "${nginx_process_info}" | sed -r -n 's@nginx:[[:space:]]*@@g;s@[[:space:]]*process.*@@g;p')

            case "${n_process_type}" in
                master|worker|'cache manager' ) process_type="${n_process_type} process" ;;
            esac

            service_info="${l_service_info_origin} (${process_type})"
        fi

    fi
}

funcCoreProcessingProcedure(){
    local mem_total=${mem_total:-}
    mem_total=$(free -m | awk 'match($1,/^Mem/){print $2}') #megabytes  MB

    funcDisplayingHeaderSetting

    while IFS=" " read -r protocol port process_state service_name process_id; do
        # tcp 22 LISTEN sshd 2830
        if [[ -z "${process_id}" ]]; then
            #http://tldp.org/LDP/Bash-Beginners-Guide/html/sect_09_05.html
            continue
        fi

        # PID|PPID|COMMAND|UID|USER|TT|PRI|NI|STAT|STARTED|%MEM|%CPU|CMD
        # 1|0|init|0|root|?|19|0|Ss|Apr 20|0.0|0.0|/sbin/init

        service_info_origin=$(awk 'match($1,/^'"${process_id}"'$/){cmd_name=$3;cmd_path=gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0);print cmd_path}' "${process_list}" | sed -r 's@.*-Dcatalina.home=([^[:space:]]+).*@\1@g;s@.*-Djetty.home=(.*) -Djetty.base.*@\1@;s@.*QuorumPeerMain (.*)/bin.*@\1@g;s@.*-Dproject.dir=(.*)( .*)?@\1@g;s@^([^[:space:]]+).*@\1@g;s@:$@@g;')

        service_info_origin="${service_info_origin,,}"

        service_info=${service_info:-}

        if [[ "${service_info_origin}" =~ ^[^/] ]]; then

            case "${service_info_origin}" in
                ssh|sshd ) funcSSHSessionInfo "${service_info_origin}" ;;
                nginx ) funcNginxProcessInfo "${service_info_origin}" ;;
                * )
                    funcCommandExistCheck "${service_info_origin}" && service_info=$(command -v "${service_info_origin}")
                    ;;
            esac    # end case

        else

            if [[ "${service_info_origin}" =~ sshd$ ]]; then
                service_info="${service_info_origin} (server)"
            elif [[ "${service_info_origin}" =~ ssh$ ]]; then

                if [[ $(awk 'match($1,/^'"${process_id}"'$/){cmd_name=$3;cmd_path=gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0);print cmd_path}' "${process_list}") =~ sftp ]]; then
                    # search ppid
                    local process_ppid
                    process_ppid=$(awk 'match($1,/^'"${process_id}"'$/){print $2}' "${process_list}")
                    local service_info_detail
                    service_info_detail=$(awk 'match($1,/^'"${process_ppid}"'$/){cmd_name=$3;cmd_path=gensub(/.* [[:digit:]].[[:digit:]] (.*)$/,"\\1","g",$0);print cmd_path}' "${process_list}")
                    if [[ "${service_info_detail%% *}" == 'sftp' ]]; then
                        service_info_origin='sftp'
                        process_id="${process_ppid}"
                        funcSSHSessionInfo "${service_info_origin}"
                    fi
                else
                    service_info="${service_info_origin}"
                fi
            else
                service_info="${service_info_origin}"
            fi

        fi    # end if

        # - output format
        if [[ -n "${service_info}" ]]; then
            local mem_consume=${mem_consume:-}
            # mem_consume=$(awk -v mem_total="${mem_total}" 'match($1,/'"${process_id}"'/){mem_percent=gensub(/.* ([[:digit:]]+.[[:digit:]]+)[[:space:]]*[[:digit:]]+.[[:digit:]]+.*/,"\\1","g",$0);a=(mem_percent/100)*mem_total; if (a>0) printf("%s%/%s MB\n",mem_percent,(mem_percent/100)*mem_total)}' "${process_list}")

            mem_consume=$(awk 'match($1,/^'"${process_id}"'$/){mem_percent=gensub(/.* ([[:digit:]]+.[[:digit:]]+)[[:space:]]+[[:digit:]]+.[[:digit:]]+.*/,"\\1","g",$0);printf("%s%\n",mem_percent)}' "${process_list}")

            local cpu_consume=${cpu_consume:-}
            cpu_consume=$(awk 'match($1,/^'"${process_id}"'$/){cpu_percent=gensub(/.* [[:digit:]]+.[[:digit:]]+[[:space:]]+([[:digit:]]+.[[:digit:]]+)[[:space:]]+.*/,"\\1","g",$0); printf("%s%\n",cpu_percent)}' "${process_list}")


            if [[ "${output_format}" -eq 1 ]]; then
                echo "${protocol}/${port}|${process_state}|${process_id}|${mem_consume}|${cpu_consume}|${service_name}|${service_info}"
            else
                printf "%-10s %-6s %-6s %5s %5s %-16s %-50s\n" "${protocol}/${port}" "${process_state}" "${process_id}" "${mem_consume}" "${cpu_consume}" "${service_name}" "${service_info}"

            fi  # End if

        fi  # End if

        unset service_info_origin
        unset service_info

    done < "${port_service_list}" # End while

}


#########  3. Executing Process  #########
funcInitializationCheck
funcProcessAndPortInfoExtraction
funcCoreProcessingProcedure


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset output_format
    unset just_listen
    unset proto_type
    unset service_name_specify
    unset process_list
    unset port_service_list
}

trap funcTrapEXIT EXIT

# Script End

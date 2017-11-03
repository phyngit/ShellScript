#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Target: Extract GNU/Linux Release Lifecycle Info (RHEL/CentOS/Debian/Ubuntu)
#Writer: MaxdSre
#Date: Oct 12, 2017 11:58 Thu +0800
#Reconfiguration Date:
# - June 25, 2017 19:18 Sun +0800
# - Aug 03, 2017 14:38 Thu +0800
# - Aug 28, 2017 09:18 Mon +0800
# - Sep 12, 2017 15:49 Tue +0800
# - Sep 26, 2017 09:29 Tue +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'LifeCycleTemp_XXXXX'}
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

distribution_choose=${distribution_choose-:''}
show_details=${show_details:-0}
markdown_format=${markdown_format:-0}
proxy_server=${proxy_server:-''}

#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Listing GNU/Linux Release Lifecycle Info (RHEL/CentOS/Debian/Ubuntu)!

[available option]
    -h    --help, show help info
    -c distribution    --specify distribution (RHEL/CentOS/Debian/Ubuntu)
    -d    --show details, list all info
    -m    --output Markdown format
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
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    funcCommandExistCheck 'gawk' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gawk${c_normal} command found, please install it!"

    funcCommandExistCheck 'sed' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}sed${c_normal} command found, please install it!"

    funcCommandExistCheck 'curl' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}curl${c_normal} command found, please install it!"

    funcCommandExistCheck 'parallel' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}parallel${c_normal} command found, please install it!"
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
    local referrer_page=${referrer_page:-'https://duckduckgo.com/?q=gnulinux'}

    if funcCommandExistCheck 'curl'; then
        download_tool="curl -fsL --retry ${retry_times} --retry-delay ${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-keepalive --referer ${referrer_page}"

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

    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal}!"
    fi
}


#########  1-2 getopts Operation  #########
while getopts "c:dmp:h" option "$@"; do
    case "$option" in
        c ) distribution_choose="$OPTARG" ;;
        d ) show_details=1 ;;
        m ) markdown_format=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done

funcLinuxDistributionMenuList(){
    local distribution_arr=("RHEL" "CentOS" "Debian" "Ubuntu")    # index array
    echo "${c_red}Available GNU/Linux Distribution List:${c_normal}"
    PS3="Choose distribution number(e.g. 1, 2,...):"
    local choose_name=${choose_name:-}

    select item in "${distribution_arr[@]}"; do
        choose_name="${item}"
        [[ -n "${choose_name}" ]] && break
    done < /dev/tty

    distribution_choose="${choose_name}"
    echo -e '\n'
    unset PS3
}

case "${distribution_choose,,}" in
    r|redhat|rhel ) distribution_choose='RHEL' ;;
    c|centos ) distribution_choose='CentOS' ;;
    d|debian ) distribution_choose='Debian' ;;
    u|ubuntu ) distribution_choose='Ubuntu' ;;
    * ) funcLinuxDistributionMenuList ;;
esac


#########  2. GNU/Linux Distributions  #########

#########  2-1. RHEL  #########
# Red Hat Enterprise Linux Life Cycle
# https://access.redhat.com/support/policy/updates/errata/
# Red Hat Enterprise Linux Release Dates
# https://access.redhat.com/articles/3078
funcLifeCycleRHEL(){
    local rhel_release_info_page='https://access.redhat.com/articles/3078'
    local rhel_life_cycle_page='https://access.redhat.com/support/policy/updates/errata'
    rhel_release_date=$(mktemp -t "${mktemp_format}")
    rhel_eus_date=$(mktemp -t "${mktemp_format}")

    # extract Extended Update Support (EUS) date
    ${download_tool} "${rhel_life_cycle_page}" | sed -r -n '/\(ends/{s@^[[:space:]]*@@g;s@(<[^>]*>|\(|\))@@g;s@ ends @|@g;s@([[:digit:]]+)st@\1@g;p}' | awk -F\| 'BEGIN{OFS="|"}{if(arr[$1]==""){"date --date=\""$2"\" +\"%F\"" | getline a;arr[$1]=a}}END{PROCINFO["sorted_in"]="@ind_str_asc";for (i in arr) print i,arr[i]}' > "${rhel_eus_date}"

    # extract per specific version and relevant info
    ${download_tool} "${rhel_release_info_page}" | sed -r -n '/id=\"RHEL/,/\/table/{/tbody/,/\/tbody/{s@<\/?(tbody|a)[[:space:]]*[^>]*>@@g;s@<(tr|td)>@@;s@<\/td>@|@g;s@(\.)[[:space:]]*@\1@g;s@RHEL ([[:digit:].]+)[[:space:]]*.*@\1|@g;p}}' | awk '{if($0!~/<\/tr>/){ORS="";print $0}else{printf "\n"}}' | awk -F\| 'BEGIN{OFS="|"}{if(a[$1]==""){a[$1]=$0}}END{PROCINFO["sorted_in"]="@ind_num_desc";for(i in a) print a[i]}'  > "${rhel_release_date}"

    # output header setting
    local field_seperator=${field_seperator:-}
    if [[ "${show_details}" -eq 1 ]]; then
        [[ "${markdown_format}" -eq 1 ]] && field_seperator='---|---|---|---\n'
        printf "%s|%s|%s|%s\n${field_seperator}" "Version" "Release Date" "EUS Date" "Kernel Version"
    else
        [[ "${markdown_format}" -eq 1 ]] && field_seperator='---|---|---\n'
        printf "%s|%s|%s\n${field_seperator}" "Version" "Release Date" "EUS Date"
    fi

    awk -F\| '{if(a[$1]==""){a[$1]=$1}}END{PROCINFO["sorted_in"]="@ind_num_desc";for (i in a) print i}' "${rhel_eus_date}" "${rhel_release_date}" | while read -r version_specific; do
        local specific_version_info=${specific_version_info:-}
        local specific_eus_date=${specific_eus_date:-}

        if [[ ${version_specific%%.*} -le 5 ]]; then
            continue
        else
            specific_version_info=$(awk -F\| 'match($1,/^'"${version_specific}"'$/)' "${rhel_release_date}")
            specific_eus_date=$(awk -F\| 'match($1,/^'"${version_specific}"'$/){print $NF}' "${rhel_eus_date}")

            if [[ -n "${specific_version_info}" ]]; then
                echo "${specific_version_info}" | while IFS="|" read -r version release errate kernel;do
                    if [[ "${show_details}" -eq 1 ]]; then
                        echo "${version_specific}|${release}|${specific_eus_date}|${kernel}"
                    else
                        echo "${version_specific}|${release}|${specific_eus_date}"
                    fi
                done

            else
                echo "${version_specific}||${specific_eus_date}"
            fi
        fi
    done

    [[ -f "${rhel_eus_date}" ]] && rm -f "${rhel_eus_date}"
    unset rhel_eus_date
    [[ -f "${rhel_release_date}" ]] && rm -f "${rhel_release_date}"
    unset rhel_release_date
}

#########  2-2. CentOS  #########
# Release Notes for supported CentOS distributions
# https://wiki.centos.org/Manuals/ReleaseNotes
funcLifeCycleCentOS(){
    centos_release_note=$(mktemp -t "${mktemp_format}")
    centos_announce_archive=$(mktemp -t "${mktemp_format}")
    centos_release_date=$(mktemp -t "${mktemp_format}")
    rhel_eus_date=$(mktemp -t "${mktemp_format}")
    rhel_life_cycle='https://access.redhat.com/support/policy/updates/errata/'  #Red Hat Enterprise Linux Life Cycle
    release_note_site='https://wiki.centos.org/Manuals/ReleaseNotes'    # Release Notes for supported CentOS distributions
    announce_archive_site='https://lists.centos.org/pipermail/centos-announce/'     # The CentOS-announce Archives
    wiki_site='https://wiki.centos.org'

    # Step 1.1 通過ReleaseNotes頁面提取各Release版本的Release note
    funcCentOSReleaseNote(){
        ${download_tool} "${release_note_site}" | sed -r -n '/Release Notes for CentOS [[:digit:]]/{s@<\/a>@\n@g;p}' | sed -r -n '/ReleaseNotes\/CentOS/{s@.*\"(.*)\".*@\1@g;p}' | while read -r line; do
            release_note_page="${wiki_site}${line}"
            # release_note_page_update_time=$(${download_tool} "${release_note_page}" | sed -r -n '/Last updated/{s@.*<\/strong> ([^>]*) <span class.*@\1@g;p}')  # page last update time
            release_version=${line##*'CentOS'}
            if [[ "${release_version}" == '7' ]]; then
                # Step 1.2 通過各Release版本的Release note提取準確的release版本號
                release_version=$(${download_tool} "${release_note_page}" | sed -r -n '/^<h1/{s@<[^>]*>@@g;s@ \(@.@g;s@\)@@g;s@-@ @g;s@([[:alpha:]]|[[:space:]])@@g;p}')
            fi
            # 7.1611|https://wiki.centos.org/Manuals/ReleaseNotes/CentOS7
            # 7.1406|https://wiki.centos.org/Manuals/ReleaseNotes/CentOS7.1406
            echo "$release_version|$release_note_page" >> "${centos_release_note}"
            # echo "$release_version|$release_note_page"
        done
    }

    # Step 1.2 通過RHEL的Life Cycle頁面提取各RHEL發行版的EUS日期
    funcRedHatExtendedUpdateSupportDate(){
        ${download_tool} "${rhel_life_cycle}" | sed -r -n '/\(ends/{s@^[[:space:]]*@@g;s@(<[^>]*>|\(|\))@@g;s@ ends @|@g;s@([[:digit:]]+)st@\1@g;p}' | awk -F\| 'BEGIN{OFS="|"}{if(arr[$1]==""){"date --date=\""$2"\" +\"%F\"" | getline a;arr[$1]=a}}END{PROCINFO["sorted_in"]="@ind_str_asc";for (i in arr) print i,arr[i]}' > "${rhel_eus_date}"
    }

    [[ "${show_details}" -eq 1 ]] && funcCentOSReleaseNote
    funcRedHatExtendedUpdateSupportDate

    # Step 2.1 通過CentOS-announce Archives頁面，遍歷各個月份的Archives頁面
    # 通過各月份的archive頁，提取符合條件的Release信息，關鍵詞 Release for CentOS
    funcCentOSSpecificReleaseInfo(){
        archive_url="${1}"
        # https://lists.centos.org/pipermail/centos-announce/2006-April/
        curl -fsL ${archive_url} | sed -r -n '/Release for CentOS( Linux |-)[[:digit:]].*x86_64$/{s@ \(@.@g;s@\)@@g;s@-@ @g;s@@@g;p}' | sed -r -n '/(Live|Minimal)/d;s@.*=\"([^"]*)\".*Release for .* ([[:digit:].]+) .*@\2|'"${archive_url}"'\1@g;p'
    }

    export -f funcCentOSSpecificReleaseInfo   # used for command parallel
    # June 2017|2017-June/date.html
    ${download_tool} "${announce_archive_site}" | sed -r -n '/Downloadable/,/\/table/{/(Thread|Subject|Author|Gzip|table|<tr>)/d;s@<\/?td>@@g;s@^[[:space:]]*@@g;/^$/d;p}' | sed -r ':a;N;$!ba;s@\n@ @g;s@<\/tr>@\n@g;' | sed -r -n '/href/{s@^[[:space:]]*@@g;s@([^:]*):.*\"(.*)date.html\".*@'"${announce_archive_site}"'\2@g;p}' | parallel -k -j 0 funcCentOSSpecificReleaseInfo >> "${centos_announce_archive}"

    # Step 2.2 通過各Release版本頁面提取release時間
    funcCentOSReleaseDate(){
        line="$1"
        release_no=${line%%|*}
        release_archive_page=${line#*|}
        release_date=$(curl -fsL "${release_archive_page}" | awk '$0~/<I>/{a=gensub(/.*>(.*)<.*/,"\\1","g",$0);"TZ=\"UTC\" date --date=\""a"\" +\"%F %Z\"" | getline b;print b}')    # %F %T %Z
        # 6.9|2017-04-05 UTC|https://lists.centos.org/pipermail/centos-announce/2017-April/022351.html

        # https://lists.centos.org/pipermail/centos-announce/2014-July/020393.html
        [[ "${release_no}" == "7" ]] && release_no='7.1406'
        # https://lists.centos.org/pipermail/centos-announce/2007-April/013660.html
        [[ "${release_no}" == "5" ]] && release_no='5.0'
        echo "${release_no}|${release_date}|${release_archive_page}"
    }

    export -f funcCentOSReleaseDate   # used for command parallel
    cat "${centos_announce_archive}" | parallel -k -j 0 funcCentOSReleaseDate >> "${centos_release_date}"

    # Step 3 對提取到的數據進行去重，並按Release版本逆序排序，將Step1中獲取的release note地址合併到輸入結果中
    declare -A rhel7Arr=( ["7.1406"]='7' ["7.1503"]='7.1' ["7.1511"]='7.2' ["7.1611"]='7.3' ["7.1708"]='7.4' )   # CentOS與RHEL的版本對應關係

    # output header setting
    local field_seperator=${field_seperator:-}
    if [[ "${show_details}" -eq 1 ]]; then
        [[ "${markdown_format}" -eq 1 ]] && field_seperator='---|---|---|---\n'
        printf "%s|%s|%s|%s\n${field_seperator}" "Version" "Release Date" "EUS Date" "Release Note"
    else
        [[ "${markdown_format}" -eq 1 ]] && field_seperator='---|---|---\n'
        printf "%s|%s|%s\n${field_seperator}" "Version" "Release Date" "EUS Date"
    fi

    # Step 3.1 release版本去重、排序
    awk -F\| '{!a[$1]++;arr[$1]=$0}END{PROCINFO["sorted_in"]="@ind_str_desc";for (i in arr) print arr[i]}' "${centos_release_date}" | while IFS="|" read -r release_no release_date release_archive_page; do
        # Step 3.2 提取對應release版本的release note
        release_note_page=$(awk -F\| '$1=="'"${release_no}"'"{print $2}' "${centos_release_note}")
        if [[ "${release_no}" =~ ^7 ]]; then
            pattern_str=${rhel7Arr[${release_no}]}
        else
            pattern_str="${release_no}"
        fi
        eus_date=$(awk -F\| '$1=="'"${pattern_str}"'"{print $2}' "${rhel_eus_date}")

        # printf "%s|%s|%s\n" "${release_no}" "${release_date}" "${eus_date}"

        if [[ "${show_details}" -eq 1 ]]; then
            if [[ "${markdown_format}" -eq 1 ]]; then
                if [[ -n "${release_note_page}" ]]; then
                    printf "[%s](%s)|%s|%s|[%s](%s)\n" "${release_no}" "${release_archive_page}" "${release_date}" "${eus_date}" "${release_note_page##*/}" "${release_note_page}"
                else
                    printf "[%s](%s)|%s|%s|%s\n" "${release_no}" "${release_archive_page}" "${release_date}" "${eus_date}"
                fi
            else
                if [[ -n "${release_note_page}" ]]; then
                    printf "%s|%s|%s|%s\n" "${release_no}" "${release_date}" "${eus_date}" "${release_note_page}"
                else
                    printf "%s|%s|%s|%s\n" "${release_no}" "${release_date}" "${eus_date}"
                fi
            fi

        else
            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "[%s](%s)|%s|%s\n" "${release_no}" "${release_archive_page}" "${release_date}" "${eus_date}"
            else
                printf "%s|%s|%s\n" "${release_no}" "${release_date}" "${eus_date}"
            fi
        fi

    done

    [[ -f "${centos_release_note}" ]] && rm -f "${centos_release_note}"
    unset centos_release_note
    [[ -f "${centos_announce_archive}" ]] && rm -f "${centos_announce_archive}"
    unset centos_announce_archive
    [[ -f "${centos_release_date}" ]] && rm -f "${centos_release_date}"
    unset centos_release_date
    [[ -f "${rhel_eus_date}" ]] && rm -f "${rhel_eus_date}"
    unset rhel_eus_date
}

#########  2-3. Debian  #########
# Debian Long Term Support
# https://wiki.debian.org/LTS
# DebianReleases
# https://wiki.debian.org/DebianReleases
funcDebianDateFormat(){
    local item="${1:-}"

    if [[ -n "${item}" ]]; then
        local item_format=${item_format:-}
        item_format=$(date --date="${item}" +"%F" 2>/dev/null)
        [[ -n "${item_format}" ]] && item="${item_format}"
        echo "${item}"
    fi
}

funcLifeCycleDebian(){
    local official_site='https://www.debian.org'
    local debian_release_note='https://wiki.debian.org/DebianReleases'
    local debian_wiki_site='https://wiki.debian.org'
    local debian_lts_note="${debian_wiki_site}/LTS"

    # debian_lts_date=$(mktemp -t "${mktemp_format}")
    # ${download_tool} "${debian_lts_note}" | sed -r -n '/schedule/,/Legend/{/amd64/d;/background-color/!d;s@<tr>@@g;s@[[:space:]]*<[^>]+>[[:space:]]*@@g;s@^.*(until|to)[[:space:]]*@@g;s@.*“([^”]+)”.*@\1@g;p}' | sed -r -n 'N;s@\n@|@gp' > "${debian_lts_date}"

    if [[ "${markdown_format}" -eq 1 ]]; then
        if [[ "${show_details}" -eq 1 ]]; then
            printf "%s|%s|%s|%s|%s\n---|---|---|---|---\n" "Version" "CodeName" "Release Date" "EOL Date" "LTS Date"
        else
            printf "%s|%s|%s|%s\n---|---|---|---\n" "Version" "CodeName" "Release Date" "EOL Date"
        fi
    else
        if [[ "${show_details}" -eq 1 ]]; then
            printf "%s|%s|%s|%s|%s\n" "Version" "CodeName" "Release Date" "EOL Date" "LTS Date"
        else
            printf "%s|%s|%s|%s\n" "Version" "CodeName" "Release Date" "EOL Date"
        fi
    fi

    ${download_tool} "${debian_release_note}" | sed -r -n '/End of life date/,/point releases/{/<strong>/d;/td/!d;s@ / <a@|<a@g;s@ / @||@g;s@href="([^"]+)">([^<]+)<@>\2|\1<@g;s@[[:space:]]*<tr>[[:space:]]*@---@g;s@[[:space:]]*(<[^>]+>)[[:space:]]*@\1@g;s@<p[^>]+>@@g;/line-56/,${s@<td><\/td>@||@g};s@<td>-<\/td>@||@g;/anchor/{s@^(---).*>([^<]*)<\/td>$@\1\n\2|@g};s@<\/td>@|@g;s@[[:space:]]*(<[^>]+>)[[:space:]]*@@g;s@~@@g;s@[[:space:]]*\([^\)]*\)[[:space:]]*@@g;s@([[:digit:]]{,2})(st|nd|th)( [[:digit:]]{4})@\1\3@g;p}' | sed -r '1d;:a;N;$!ba;s@\n@@g;s@---@\n@g;' | while IFS="|" read -r release_version codename codename_url releases_date release_url eol_date eol_url lts_date lts_url; do
        # 9|Stretch|/DebianStretch|June 17 2017|https://www.debian.org/News/2017/20170617|approx. 2020||approx. 2022|
        # 8|Jessie|/DebianJessie|April 25 2015|https://www.debian.org/News/2015/20150426|June 6 2018|https://www.debian.org/security/faq#lifespan|June 6 2020|/LTS|

        # omit empth release_version
        [[ -z "${release_version}" ]] && continue

        [[ -n "${codename_url}" && "${codename_url}" =~ ^\/ ]] && codename_url="${debian_wiki_site}${codename_url}"

        [[ -n "${releases_date}" ]] &&  releases_date=$(funcDebianDateFormat "${releases_date}")
        [[ -n "${eol_date}" ]] &&  eol_date=$(funcDebianDateFormat "${eol_date}")
        [[ -n "${lts_date}" ]] &&  lts_date=$(funcDebianDateFormat "${lts_date}")

        [[ -n "${lts_url}" && "${lts_url}" =~ ^\/ ]] && lts_url="${debian_wiki_site}${lts_url}"

        if [[ "${show_details}" -eq 1 ]]; then
            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "%s|[%s](%s)|[%s](%s)|[%s](%s)|[%s](%s)\n" "${release_version}" "${codename}" "${codename_url}" "${releases_date}" "${release_url}" "${eol_date}" "${eol_url}" "${lts_date}" "${lts_url}" | sed -r 's@\[\]\(\)@@g;/^[[:digit:]]/!d'
            else
                printf "%s|%s|%s|%s|%s\n" "${release_version}" "${codename}" "${releases_date}" "${eol_date}" "${lts_date}"
            fi    # end if markdown_format

        else
            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "%s|[%s](%s)|[%s](%s)|[%s](%s)\n" "${release_version}" "${codename}" "${codename_url}" "${releases_date}" "${release_url}" "${eol_date}" "${eol_url}"
            else
                printf "%s|%s|%s|%s\n" "${release_version}" "${codename}" "${releases_date}" "${eol_date}"
            fi    # end if markdown_format

        fi    # end if show_details

    done
}


#########  2-4. Ubuntu  #########
# List of releases
# https://wiki.ubuntu.com/Releases
funcLifeCycleUbuntu(){
    ubuntu_release_note='https://wiki.ubuntu.com/Releases'
    ubuntu_wiki_site='https://wiki.ubuntu.com'

    ubuntu_release_info=$(mktemp -t "${mktemp_format}")
    $download_tool "${ubuntu_release_note}" > "${ubuntu_release_info}"

    if [[ "${markdown_format}" -eq 1 ]]; then
        if [[ "${show_details}" -eq 1 ]]; then
            printf "%s|%s|%s|%s|%s\n---|---|---|---|---\n" "Version" "CodeName" "Release Date" "EOL Date" "Doc"
        else
            printf "%s|%s|%s|%s\n---|---|---|---\n" "Version" "CodeName" "Release Date" "EOL Date"
        fi
    else
        if [[ "${show_details}" -eq 1 ]]; then
            printf "%s|%s|%s|%s|%s\n" "Version" "CodeName" "Release Date" "EOL Date" "Doc"
        else
            printf "%s|%s|%s|%s\n" "Version" "CodeName" "Release Date" "EOL Date"
        fi
    fi

    # Step 1. Current
    sed -r -n '/Current/,/Future/{/(table|h3|h2)/d;s@<(td|p|span|strong)[[:space:]]*[^>]*>@@g;s@<\/(span|a|strong)>@@g;s@class="[^"]*" @@;s@<a href="([^"]*)">@\1~@g;s@<tr>[[:space:]]*@@g;s@[[:space:]]*<\/td>@|@g;s@^[[:space:]]*@@g;p}' "${ubuntu_release_info}" | awk '{if($0!~/<\/tr>/){ORS="";print $0}else{printf "\n"}}' | sed -r '/^Ubuntu/!d' | while IFS="|" read -r release_version codename_info doc_info release_date_info eol_info;do
        release_version=${release_version//Ubuntu /}
        codename=${codename_info##*~}
        codename_url=${ubuntu_wiki_site}${codename_info%%~*}
        doc_type=${doc_info##*~}
        doc_url=${ubuntu_wiki_site}${doc_info%%~*}
        release_date=$(date --date="${release_date_info##*~}" +"%F")
        release_date_url=${release_date_info%%~*}

        local eol_date=${eol_date:-}
        local eol_url=${eol_url:-}

        if [[ -z "${eol_info}" ]]; then
            eol_date=''
            eol_url=''
        elif [[ -n "${eol_info}" && "${eol_info}" =~ \~ ]]; then
            eol_date=${eol_info##*~}
            eol_url=${eol_info%%~*}
        else
            if [[ "${eol_info}" =~ [0-9]{4} ]]; then
                eol_date=${eol_info}
            fi
        fi

        local eol_date_temp=${eol_date_temp:-}
        if [[ -n "${eol_date}" ]]; then
            eol_date=$(echo "${eol_date}" | sed -r 's@[[:alpha:]]*,@,@g')
            eol_date_temp=$(date --date="${eol_date//HWE /}" +"%F" 2> /dev/null)
            [[ -n "${eol_date_temp}" ]] && eol_date="${eol_date_temp}"
        fi

        if [[ "${show_details}" -eq 1 ]]; then
            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "%s|[%s](%s)|[%s](%s)|[%s](%s)|[%s](%s)\n" "${release_version}" "${codename}" "${codename_url}" "${release_date}" "${release_date_url}" "${eol_date}" "${eol_url}" "${doc_type}" "${doc_url}" | sed -r 's@\[\]\(\)@@g'
            else
                printf "%s|%s|%s|%s|%s\n" "${release_version}" "${codename}" "${release_date}" "${eol_date}" | sed -r 's@\[\]\(\)@@g'
            fi
        else

            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "%s|[%s](%s)|[%s](%s)|[%s](%s)\n" "${release_version}" "${codename}" "${codename_url}" "${release_date}" "${release_date_url}" "${eol_date}" "${eol_url}" | sed -r 's@\[\]\(\)@@g'
            else
                printf "%s|%s|%s|%s\n" "${release_version}" "${codename}" "${release_date}" "${eol_date}" | sed -r 's@\[\]\(\)@@g;s@<br>$@@g'
            fi
        fi

    done

    # Step 2. End of Life
    sed -r -n '/End of Life<\/h3>/,/Management of releases/{/(table|h3|h2)/d;s@<(td|p|span|strong)[[:space:]]*[^>]*>@@g;s@<\/(span|a|strong)>@@g;s@class="[^"]*" @@;s@<a href="([^"]*)">@\1~@g;s@(^<tr>[[:space:]]*)([^<]*).*@\2<\/td>@g;s@[[:space:]]*<\/td>@|@g;s@^[[:space:]]*@@g;s@<\/strong>@@g;s@ / @=@g;p}' "${ubuntu_release_info}" | awk '{if($0!~/<\/tr>/){ORS="";print $0}else{printf "\n"}}' | sed -r '/^Ubuntu/!d' | while IFS="|" read -r release_version codename_info doc_info release_date_info eol_info;do
        release_version=${release_version//Ubuntu /}
        codename=${codename_info##*~}
        codename_url=${ubuntu_wiki_site}${codename_info%%~*}
        if [[ -z "${doc_info}" ]]; then
            doc_left_type=''
            doc_left_url=''
            doc_right_type=''
            doc_right_url=''
        elif [[ -n "${doc_info}" && "${doc_info}" =~ \= ]]; then
            doc_left_info=${doc_info%%=*}
            doc_right_info=${doc_info##*=}

            if [[ -n "${doc_left_info}" && "${doc_left_info}" =~ \~ ]]; then
                doc_left_type=${doc_left_info##*~}
                doc_left_url=${ubuntu_wiki_site}${doc_left_info%%~*}
            fi

            if [[ -n "${doc_right_info}" && "${doc_right_info}" =~ \~ ]]; then
                doc_right_type=${doc_right_info##*~}
                doc_right_url=${ubuntu_wiki_site}${doc_right_info%%~*}
            fi
        elif [[ -n "${doc_info}" && "${doc_info}" =~ \~ ]]; then
            doc_left_type=${doc_info##*~}
            doc_left_url=${ubuntu_wiki_site}${doc_info%%~*}
            doc_right_type=''
            doc_right_url=''
        fi

        release_date=$(date --date="${release_date_info##*~}" +"%F")
        release_date_url=${release_date_info%%~*}

        if [[ -z "${eol_info}" ]]; then
            eol_left_date=''
            eol_left_url=''
            eol_right_date=''
            eol_right_url=''
        elif [[ -n "${eol_info}" && "${eol_info}" =~ \<br\> ]]; then
            eol_left_info=${eol_info%%'<br>'*}
            eol_right_info=${eol_info##*'<br>'}

            if [[ -n "${eol_left_info}" && "${eol_left_info}" =~ \~ ]]; then
                eol_left_date=${eol_left_info##*~}
                eol_left_url=${eol_left_info%%~*}
            fi

            if [[ -n "${eol_right_info}" && "${eol_right_info}" =~ \~ ]]; then
                eol_right_date=${eol_right_info##*~}
                eol_right_url=${eol_right_info%%~*}
            fi
        elif [[ -n "${eol_info}" && "${eol_info}" =~ \~ ]]; then
            eol_left_date=${eol_info##*~}
            eol_left_url=${eol_info%%~*}
            eol_right_date=''
            eol_right_url=''
        fi

        local eol_left_date_temp=${eol_left_date_temp:-}
        if [[ -n "${eol_left_date}" ]]; then
            eol_left_date=$(echo "${eol_left_date}" | sed -r 's@[[:alpha:]]*,@,@g')
            eol_left_date_temp=$(date --date="${eol_left_date//HWE /}" +"%F" 2> /dev/null)
            if [[ -n "${eol_left_date_temp}" ]]; then
                if [[ "${eol_left_date}" =~ HWE ]]; then
                    eol_left_date="HWE ${eol_left_date_temp}"
                else
                    eol_left_date="${eol_left_date_temp}"
                fi
            fi
        fi

        local eol_right_date_temp=${eol_right_date_temp:-}
        if [[ -n "${eol_right_date}" ]]; then
            eol_right_date=$(echo "${eol_right_date}" | sed -r 's@[[:alpha:]]*,@,@g')
            eol_right_date_temp=$(date --date="${eol_right_date//HWE /}" +"%F" 2> /dev/null)
            if [[ -n "${eol_right_date_temp}" ]]; then
                if [[ "${eol_right_date}" =~ HWE ]]; then
                    eol_right_date="HWE ${eol_right_date_temp}"
                else
                    eol_right_date="${eol_right_date_temp}"
                fi
            fi
        fi

        # Version|Code name|Release date|End of Life date|Docs
        if [[ "${show_details}" -eq 1 ]]; then
            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "%s|[%s](%s)|[%s](%s)|[%s](%s)<br>[%s](%s)|[%s](%s) / [%s](%s)\n" "${release_version}" "${codename}" "${codename_url}" "${release_date}" "${release_date_url}" "${eol_left_date}" "${eol_left_url}" "${eol_right_date}" "${eol_right_url}" "${doc_left_type}" "${doc_left_url}" "${doc_right_type}" "${doc_right_url}" | sed -r 's@\[\]\(\)@@g;s@[[:space:]]*\/[[:space:]]*\|@\|@g;s@[[:space:]]*\/[[:space:]]*$@@g'
            else
                printf "%s|%s|%s|%s<br>%s\n" "${release_version}" "${codename}" "${release_date}" "${eol_left_date}" "${eol_right_date}" | sed -r 's@\[\]\(\)@@g;s@[[:space:]]*\/[[:space:]]*\|@\|@g;s@<br>$@@g'
            fi
        else

            if [[ "${markdown_format}" -eq 1 ]]; then
                printf "%s|[%s](%s)|[%s](%s)|[%s](%s)<br>[%s](%s)\n" "${release_version}" "${codename}" "${codename_url}" "${release_date}" "${release_date_url}" "${eol_left_date}" "${eol_left_url}" "${eol_right_date}" "${eol_right_url}" | sed -r 's@\[\]\(\)@@g;s@[[:space:]]*\/[[:space:]]*\|@\|@g;s@[[:space:]]*\/[[:space:]]*$@@g'
            else
                printf "%s|%s|%s|%s<br>%s\n" "${release_version}" "${codename}" "${release_date}" "${eol_left_date}" "${eol_right_date}" | sed -r 's@\[\]\(\)@@g;s@[[:space:]]*\/[[:space:]]*\|@\|@g;s@<br>$@@g'
            fi
        fi

    done

    [[ -f "${ubuntu_release_info}" ]] && rm -f "${ubuntu_release_info}"
    unset ubuntu_release_info
}


#########  3. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
funcLifeCycle"${distribution_choose}"


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset distribution_choose
    unset show_details
    unset markdown_format
    unset proxy_server
}

trap funcTrapEXIT EXIT

# Script End

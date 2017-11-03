#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Target: Extract Proxy IP From Proxy Site On GNU/Linux
#Writer: MaxdSre:
#Date: Oct 10, 2017 15:04 Fri +0800
#Update Time:
# - Jun 13, 2017 09:54 Tue +0800
# - June 23, 2017 11:29 Fri +0800
# - July 24, 2017 16:34 Mon +0800
# - Aug 04, 2017 15:15 Fri +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'PIETemp_XXXXX'}
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

list_proxy_sites=${list_proxy_sites:-0}
show_details=${show_details:-0}
proxy_site_specify=${proxy_site_specify:-}
include_country=${include_country:-}
exclude_country=${exclude_country:-}
protocol_type=${protocol_type:-}
anonymity_type=${anonymity_type:-}
proxy_server=${proxy_server:-}
use_proxy=${use_proxy:-0}
user_agent=${user_agent:-'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3200.0 Iron Safari/537.36'}
real_country=${real_country:-}

strict_speed_test=${strict_speed_test:-0}
curl_speed_time=${curl_speed_time:-1}     #time second -y, --speed-time <time>   must integer
curl_speed_limit=${curl_speed_limit:-35}    # speed byte -Y, --speed-limit <speed>
curl_max_time=${curl_max_time:-2}         #time second -m, --max-time <seconds>


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Extracting Proxy IP (HTTP/SOCKS) From Proxy Sites On GNU/Linux!

[available option]
    -h    --help, show help info
    -l    --list all supported proxy sites
    -n site    --specify proxy site No. listed in '-l'
    -d    --details, show all info, default is simple mode
    -i country   --just include specified country, use ISO 3166 code, eg: US, CA, JP, SG, KR
    -e country   --exclude specified country, use ISO 3166 code, eg: US, CA, JP, SG, KR
    -t protocol  --protocol type (http|socks4|socks5), default is 'socks5'
    -a anonymity --anonymity level for http (low|medium|high), default is 'high'
    -s    --connection speed testing strictly, default is normal
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
        executing_path=$(which "$name" 2> /dev/null || command -v "$name" 2> /dev/null)
        [[ -n "${executing_path}" ]] && return 0 || return 1
    else
        return 1
    fi
}

funcInitializationCheck(){
    # 1 - Check root or sudo privilege
    # [[ "$UID" -ne 0 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script requires superuser privileges (eg. root, su)."

    # 2 - OS support check
    [[ -s /etc/os-release || -s /etc/SuSE-release || -s /etc/redhat-release || (-s /etc/debian_version && -s /etc/issue.net) ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script doesn't support your system!"

    # 3 - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    funcCommandExistCheck 'seq' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}seq${c_normal} command found!"

    # the command is part of 'nmap' utility
    funcCommandExistCheck 'nping' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}nping${c_normal} command found, please install ${c_blue}nping${c_normal} or ${c_blue}nmap${c_normal} utility first!"

    funcCommandExistCheck 'parallel' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}parallel${c_normal} command found!"

    # setting for command 'parallel' temporarily
    ulimit -n 65536 2> /dev/null    # open files
    ulimit -u 8192 2> /dev/null     # max user processes

    # parallel: Warning: Only enough file handles to run 252 jobs in parallel.
    # parallel: Warning: Running 'parallel -j0 -N 252 --pipe parallel -j0' or
    # parallel: Warning: raising ulimit -n or /etc/security/limits.conf may help.
}

funcInternetConnectionCheck(){
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
            use_proxy=1
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

    if funcCommandExistCheck 'curl'; then
        download_tool_origin="curl -fsL --retry ${retry_times} --retry-delay ${retry_delay_time} --connect-timeout ${connect_timeout_time} --no-keepalive"

        if [[ -n "${proxy_server}" ]]; then
            # curl version > 7.21.7
            case "${p_proto}" in
                # https ) export HTTPS_PROXY="${p_host}" ;;
                socks4 ) download_tool_proxy="${download_tool_origin} -x ${p_proto}a://${p_host}";;
                socks5 ) download_tool_proxy="${download_tool_origin} -x ${p_proto}h://${p_host}";;
                http|* ) download_tool_proxy="${download_tool_origin} -x ${p_host}";;
            esac
        fi
    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal}s!"
    fi

    download_tool=${download_tool:-"${download_tool_origin}"}
    [[ "${use_proxy}" -eq 1 ]] && download_tool="${download_tool_proxy}"

}

#########  1-2 getopts Operation  #########
# start_time=$(date +'%s')    # Start Time Of Operation

while getopts "hldn:i:e:t:a:sp:" option "$@"; do
    case "$option" in
        l ) list_proxy_sites=1 ;;
        d ) show_details=1 ;;
        n ) proxy_site_specify="$OPTARG" ;;
        i ) include_country="$OPTARG" ;;
        e ) exclude_country="$OPTARG" ;;
        t ) protocol_type="$OPTARG" ;;
        a ) anonymity_type="$OPTARG" ;;
        s ) strict_speed_test=1 ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


proxy_site_info=$(mktemp -t "${mktemp_format}")
cat > "${proxy_site_info}" <<EOF
No|Site|CN|socks4|socks5|transparent|anonymous|high-anonymous(elite)|Site
1|Premium Proxy|1|1|1|1|0|1|https://premproxy.com
2|Nntime|1|0|0|1|1|1|http://nntime.com
3|Didsoft|0|1|1|1|1|1|https://free-proxy-list.net/
4|PROXYS™|1|0|0|1|0|1|http://www.proxys.com.ar
5|Proxz|0|0|0|0|0|1|http://www.proxz.com
6|ProxyNova|0|0|0|1|0|1|https://www.proxynova.com
7|Daily Proxy|0|0|0|1|0|1|http://www.dailyproxylists.com
# 8|HideMyAss|0|0|0|1|1|1|http://proxylist.hidemyass.com
# 9|freeproxylists.net|0|0|0|1|1|1|http://freeproxylists.net/ 暫未實現通過curl抓取
EOF


#########  2-1. List Proxy Sites  #########
funcListProxySites(){
    awk -F\| 'BEGIN{printf("%-3s %-16s %10s\n","No","Site","URL")}match($1,/^[[:digit:]]/){printf("%-3s %-16s %-20s\n",$1,$2,$NF)}' "${proxy_site_info}"

    # awk -F\| 'BEGIN{printf("%-3s %-12s %4s %8s %8s %8s %8s %6s\n","No","Site","CN","socks4","socks5","transparent","anonymous","elite")}match($1,/^[[:digit:]]/){printf("%-3s %-12s %4s %6s %6s %8s %12s %8s\n",$1,$2,$3,$4,$5,$6,$7,$8)}' "${proxy_site_info}"
    exit
}


#########  3 Extract Proxy IP From HTML Page  #########
proxy_ip_extracted=$(mktemp -t "${mktemp_format}")

#########  3-1. Premium Proxy (https://premproxy.com)  #########
# HTTP: transparent, anonymous, elite
funcProxySite_1(){
    # IP:Port|AnonymityLevel|Country|City|ISP
    local page_url='https://premproxy.com/list/'
    local page_no
    page_no=$($download_tool "${page_url}" | sed -r -n '1,/pagination/{/pagination/{s@next@@g;s@[[:space:]]*<[^>]*>[[:space:]]*@ @g;s@[[:space:]]+@ @g;s@.*[[:space:]]+([[:digit:]]+)[[:space:]]*$@\1@g;p}}')

    local flag
    flag=${flag:-"${page_no}"}
    [[ "${page_no}" -ge 10 ]] && flag=9

    seq -f 0%g 1 "${flag}" | parallel -k -j 0 -X $download_tool "${page_url}"{}.htm 2> /dev/null | sed -r -n '/<tbody/,/<\/tbody/{/<tr/{s@<dfn title="([^"]*)">[^<]*<@\1<@g;s@[[:space:]]*<\/td>[[:space:]]*@|@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;s@&nbsp;@@g;p}}' | awk -F\| 'BEGIN{OFS="|"}{print $1,tolower($2),$4,$5,$6}' >> "${proxy_ip_extracted}"

    if [[ "${page_no}" -ge 10 ]]; then
        seq 10 "${page_no}" | parallel -k -j 0 -X $download_tool "${page_url}"{}.htm 2> /dev/null | sed -r -n '/<tbody/,/<\/tbody/{/<tr/{s@<dfn title="([^"]*)">[^<]*<@\1<@g;s@[[:space:]]*<\/td>[[:space:]]*@|@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;s@&nbsp;@@g;p}}' | awk -F\| 'BEGIN{OFS="|"}{print $1,tolower($2),$4,$5,$6}' >> "${proxy_ip_extracted}"
    fi
}

# SOCKS: socks4, socks5
funcProxySite_1_socks(){
    # IP:Port|AnonymityLevel|Country|City|ISP
    local page_url='https://premproxy.com/socks-list/'
    local page_no
    page_no=$($download_tool "${page_url}" | sed -r -n '1,/pagination/{/pagination/{s@next@@g;s@[[:space:]]*<[^>]*>[[:space:]]*@ @g;s@[[:space:]]+@ @g;s@.*[[:space:]]+([[:digit:]]+)[[:space:]]*$@\1@g;p}}')

    # page_no=$($download_tool "${page_url}" | sed -r -n '/next/{s@<[^>]*>@ @gp}' | awk '{print $(NF-1)}')

    local flag
    flag=${flag:-"${page_no}"}
    [[ "${page_no}" -ge 10 ]] && flag=9

    seq -f 0%g 1 "${flag}" | parallel -k -j 0 -X $download_tool "${page_url}"{}.htm 2> /dev/null | sed -r -n '/<tbody/,/<\/tbody/{/<tr/{s@<dfn title="([^"]*)">[^<]*<@\1<@g;s@[[:space:]]*<\/td>[[:space:]]*@|@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;s@&nbsp;@@g;p}}' | awk -F\| 'BEGIN{OFS="|"}{print $1,tolower($2),$4,$5,$6}' >> "${proxy_ip_extracted}"

    if [[ "${page_no}" -ge 10 ]]; then
        seq 10 "${page_no}" | parallel -k -j 0 -X $download_tool "${page_url}"{}.htm 2> /dev/null | sed -r -n '/<tbody/,/<\/tbody/{/<tr/{s@<dfn title="([^"]*)">[^<]*<@\1<@g;s@[[:space:]]*<\/td>[[:space:]]*@|@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;s@&nbsp;@@g;p}}' | awk -F\| 'BEGIN{OFS="|"}{print $1,tolower($2),$4,$5,$6}' >> "${proxy_ip_extracted}"
    fi
}

#########  3-2. Nntime (http://nntime.com)  #########
# HTTP: transparent, anonymous, high-anonymous
funcProxySite_2(){
    # IP:Port|AnonymityLevel|Country|City|ISP
    local page_url='http://nntime.com/'
    local page_no
    page_no=$($download_tool "${page_url}" | sed -r -n '1,/navigation/{/navigation/{s@next@@g;s@[[:space:]]*<[^>]*>[[:space:]]*@ @g;s@[[:space:]]+@ @g;s@.*[[:space:]]+([[:digit:]]+)[[:space:]]*$@\1@g;p}}')

    local flag
    flag=${flag:-"${page_no}"}
    [[ "${page_no}" -ge 10 ]] && flag=9

    seq -f 0%g 1 "${flag}" | parallel -k -j 0 -X $download_tool "${page_url}"proxy-list-{}.htm 2> /dev/null | sed -r -n '/<\/thead>/,/<\/table>/{s@<input.*value="([^"]*)" onclick.*\/>@\1@g;s@(\"|\:|\+)@@g;s@document.write\((.*)\)@|\1@g;s@[[:space:]]*<\/td>[[:space:]]*@|@g;/^$/d;s@<\/tr>@---@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;p}' | sed -r ':a;N;$!ba;s@\n@@g;s@\|[-]+[[:space:]]*@|\n@g;' | awk -F\| 'BEGIN{OFS="|"}NF>0{str_start_pos=(length($1)-length($3)+1);port=substr($1,str_start_pos); sub(/[[:space:]]*proxy/,"",$4); printf("%s:%s|%s|%s|%s\n",$2,port,$4,$7,$6)}' | sed -r 's@[[:space:]]*\(@|@g;s@\)@@g' | awk -F\| '{printf("%s|%s|%s|%s|%s\n",$1,$2,$4,$5,$3)}' >> "${proxy_ip_extracted}"

    if [[ "${page_no}" -ge 10 ]]; then
        seq 10 "${page_no}" | parallel -k -j 0 -X $download_tool "${page_url}"proxy-list-{}.htm 2> /dev/null | sed -r -n '/<\/thead>/,/<\/table>/{s@<input.*value="([^"]*)" onclick.*\/>@\1@g;s@(\"|\:|\+)@@g;s@document.write\((.*)\)@|\1@g;s@[[:space:]]*<\/td>[[:space:]]*@|@g;/^$/d;s@<\/tr>@---@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;p}' | sed -r ':a;N;$!ba;s@\n@@g;s@\|[-]+[[:space:]]*@|\n@g;' | awk -F\| 'BEGIN{OFS="|"}NF>0{str_start_pos=(length($1)-length($3)+1);port=substr($1,str_start_pos); sub(/[[:space:]]*proxy/,"",$4); printf("%s:%s|%s|%s|%s\n",$2,port,$4,$7,$6)}' | sed -r 's@[[:space:]]*\(@|@g;s@\)@@g' | awk -F\| '{printf("%s|%s|%s|%s|%s\n",$1,$2,$4,$5,$3)}' >> "${proxy_ip_extracted}"
    fi

}


#########  3-3. Didsoft (https://free-proxy-list.net)  #########
# HTTP: transparent, anonymous, high-anonymous

# Free Proxy List | https://free-proxy-list.net
# Anonymous Proxy | https://free-proxy-list.net/anonymous-proxy.html
# US Proxy | https://www.us-proxy.org
# SSL (HTTPS) Proxy | https://www.sslproxies.org

funcProxySite_3(){
    # IP:Port|AnonymityLevel|Country|Https
    local proxy_site_list
proxy_site_list=$(cat <<EOF
Free Proxy List|https://free-proxy-list.net
Anonymous Proxy|https://free-proxy-list.net/anonymous-proxy.html
US Proxy|https://www.us-proxy.org
SSL (HTTPS) Proxy|https://www.sslproxies.org
EOF
)

    echo "${proxy_site_list}" | awk -F\| '{print $2}' |  parallel -k -j 0 -X $download_tool {} 2> /dev/null | sed -r -n '/<tbody>/{s@^.*<tbody>@@g;s@<\/tbody>.*$@@g;s@<\/tr>@\n@g;s@<\/td>@|@g;s@<[^>]*>@@g;s@elite proxy@elite@g;p}' | awk -F\| 'NF>0{printf("%s:%s|%s|%s|%s\n",$1,$2,tolower($5),$4,tolower($7))}' >> "${proxy_ip_extracted}"
}

# SOCKS: socks4, socks5
funcProxySite_3_socks(){
    $download_tool https://www.socks-proxy.net | sed -r -n '/<tbody>/{s@^.*<tbody>@@g;s@<\/tbody>.*$@@g;s@<\/tr>@\n@g;s@<\/td>@|@g;s@<[^>]*>@@g;s@elite proxy@elite@g;p}' | awk -F\| 'NF>0{printf("%s:%s|%s|%s|%s\n",$1,$2,tolower($5),$4,tolower($7))}' >> "${proxy_ip_extracted}"
}


#########  3-4. PROXYS™ (http://www.proxys.com.ar)  #########
# HTTP: transparente, elite
funcProxySite_4(){
    # IP:Port|AnonymityLevel|Country
    local page_url='http://www.proxys.com.ar/'
    $download_tool "${page_url}" | sed -r -n '/st-tables-page/{s@<\/tr>@\n@g;p}' | sed -r -n '/td/!d;s@<a href=.*$@@g;s@<\/td>@|@g;s@[[:space:]]*<[^>]+>[[:space:]]*@@g;p' | awk -F\| '{printf("%s:%s|%s|%s\n",$1,$2,tolower($4),$3)}' >> "${proxy_ip_extracted}"
}


#########  3-5. Proxz (http://www.proxz.com)  #########
funcProxySite_5(){
    # IP:Port|AnonymityLevel|Country
    local page_url='http://www.proxz.com/'
    page_no=$($download_tool --user-agent "\"${user_agent}\"" "${page_url}proxy_list_high_anonymous_0_ext.html" | sed -r -n '1,/Proxylist.*::../{/Proxylist/{s@(<[^>]*>|::..)@@g;s@.*:([[:digit:]]+)$@\1@g;p}}')

    urldecode() { : "${*}" ; echo -e "${_}" | sed 's/%\([0-9A-F][0-9A-F]\)/\\\\\x\1/g' | xargs echo -e | sed -r -n 's@.*\("(.*)"\).*@\1@g;s@%2e@.@g;p'; }

    seq 0 "${page_no}" | parallel -k -j 0 -X $download_tool --user-agent "\"${user_agent}\"" "${page_url}"proxy_list_high_anonymous_{}_ext.html 2> /dev/null | sed -r -n "/eval\(unescape/{s@<\/td><\/tr>@@;s@<\/tr>@\n@g;s@<noscript>Please enable javascript<\/noscript>@@g;s@<\/?(tr|a|script)[[:space:]]*[^>]*>@@g;s@(<td>|\(|\)|;)@@g;s@evalunescape@@g;s@'@@g;s@<\/td>@|@g;s@<td[[:space:]]*[^>]*>@@g;p}" | sed '/^$/d' | while IFS="|" read -r a b c d e f;do ip=$(urldecode "$a"); echo "$ip:$b|${c,,}|$d" >> "${proxy_ip_extracted}"; done

}


#########  3-6. ProxyNova (https://www.proxynova.com)  #########
# HTTP: transparent, elite
funcProxySite_6(){
    # IP:Port|AnonymityLevel|Country|City
    local page_url='https://www.proxynova.com/proxy-server-list/'
    $download_tool "${page_url}"| sed -r -n '/<center>/,/<\/center>/d;/<tbody>/,/<\/tbody>/{s@<\/?(tbody|images|script|a|time|img|div|ins)[[:space:]]*[^>]*>@@g;s@<(td|span)[[:space:]]*[^>]*>@@g;s@^[[:blank:]]*@@g;s@<tr>@@g;p}' | sed -r '/^$/d' | awk '{if($0!~/<\/tr>/){ORS=" ";print $0}else{printf "\n"}}' | sed -r -n "s@<\/span>@@g;s@(document.write|substr\(2\)|\(|\)|'|;|[[:space:]]*\+[[:space:]]*)@@g;s@(<\/td>)@|@g;s@\.{1,}@\.@g;s@^23@@g;p" | awk -F\| '{printf("%s:%s|%s|%s\n",$1,$2,tolower($7),$6)}' | sed -r -n 's@-@|@g;s@[[:space:]]+(|)[[:space:]]+@\1@g;s@: @:@g;p' | sed -r "/^[^[:digit:]]/d;s@(|)[[:space:]]*@\1@g" >> "${proxy_ip_extracted}"
}

#########  3-7. Daily Proxy (http://www.dailyproxylists.com)  #########
# HTTP: transparent, high-anonymous
funcProxySite_7(){
    # IP:Port|AnonymityLevel|Country
    local page_url='http://www.dailyproxylists.com/index.php/proxy-lists'
    $download_tool "${page_url}" | sed -r -n '/document.write/{s@<[^>]*>@@g;s@(document.write|unescape|\(|\)|\")@@g;s@^[[:space:]]*@@g;p}' | sed -r -n 's@^[[:blank:]]*@@g;s@[[:blank:]]$@@g;p' | sed 's@\\@\\\\@g;s@\(%\)\([0-9a-fA-F][0-9a-fA-F]\)@\\x\2@g' | printf $(cat -) | sed -r -n 's@<\/?tr>@\n@g;s@<(td)[[:space:]]*[^>]*>@@g;p' | sed -r -n '/^[^[:digit:]]+/d;/^$/d;s@<[^>]*>@|@g;p' |  awk -F\| '{printf("%s:%s|%s|%s\n",$1,$2,tolower($4),$3)}' >> "${proxy_ip_extracted}"
}

#########  3-8. HideMyAss (http://proxylist.hidemyass.com)  #########
# HTTP: high-anonymous

# This service has been suspended due changes in our infrastructure. But we'll be back with an even better version in a few months!

funcProxySite_8(){
    local page_url='http://proxylist.hidemyass.com/search-1303043#listable'
    local start=1
    proxy_list_html=$(mktemp -t tempXXXXX.txt)
    tempfile_perip=$(mktemp -t tempXXXXX.txt)

    $download_tool "${page_url}" | sed -r -n '/table section/,/table section end/{/^$/d;/indicator/d;s@^[[:space:]]*@@;/^<[\/]?(td|div|span)>$/d;p}' | sed -r -n '/leftborder/,/<\/tr>/{p}' > "${proxy_list_html}"

    sed -n '/<\/tr>/=' "${proxy_list_html}" | while read -r line;do
        # echo "start $start, end $line";
        sed -r -n ''"${start},${line}"'p' "${proxy_list_html}" > "${tempfile_perip}"
        country=$(sed -r -n '/img src=/{n;s@<[^>]*>@@p}' "${tempfile_perip}" | sed -r -n 's@^[[:space:]]*@@g;s@[[:space:]]*$@@g;p')
        port=$(sed -r -n '/class=\"country\"/{x;s@<[^>]*>@@p};h' "${tempfile_perip}" | sed -r -n 's@^[[:space:]]*@@g;s@[[:space:]]*$@@g;p')
        class_none_list=$(sed -r -n '/^\..*none/s@.(.*)\{.*@\1@p' "${tempfile_perip}" | awk 'BEGIN{RS=EOF}{gsub(/\n/,"|");print}')
        ip=$(sed -r -n '/^<\/style/{s@<\/[^>]*>@\n@g;p}' "${tempfile_perip}" | sed -r 's@\.@@g' | sed -r -n 's@^([[:digit:]]+)(<.*)$@\1\n\2@;p' | sed -r -n '/^$/d;/(none|\.)/!p' | sed -r -n '/('"${class_none_list}"')/d;s@<[^>]*>@@;/^$/d;p' | awk 'BEGIN{RS=EOF}{gsub(/\n/," ");print}' | awk '{printf("%s.%s.%s.%s",$1,$2,$3,$4)}')

        echo "$ip:$port|high-anonymous|$country" >> "${proxy_ip_extracted}"

        start=$((line+1));
    done

    [[ -f "${proxy_list_html:-}" ]] && rm -f "${proxy_list_html}"
    [[ -f "${tempfile_perip:-}" ]] && rm -f "${tempfile_perip}"
}


#########  3. Executing Process  #########
funcCountryShortName(){
    # http://fasteri.com/list/2/short-names-of-countries-and-iso-3166-codes
    # curl -fsL http://fasteri.com/list/2/short-names-of-countries-and-iso-3166-codes | sed -r -n '/^<td>/{N;s@\n@@g;s@<\/a>@|@g;s@<[^>]*>@@g;p}'
    local short_name="${1:-}"
    local country=${country:-}

    case "${short_name^^}" in
        'US' ) country='United States' ;;
        'CA' ) country='Canada' ;;
        'HK' ) country='Hong Kong' ;;
        'SG' ) country='Singapore' ;;
        'KR' ) country='Korea' ;;
        'MY' ) country='Malaysia' ;;
        'TW' ) country='Taiwan' ;;
        'CN' ) country='China' ;;
        'VN' ) country='Vietnam' ;;
        'JP' ) country='Japan' ;;
        'FR' ) country='France' ;;
        'IT' ) country='Italy' ;;
        * ) country='';;
    esac

    echo "${country}"
}


funcSpecificProxyIPTesting(){
    line="$1"
    ip_addr=$(echo "${line}" | awk -F\| '{print $1}')
    anonymity=$(echo "${line}" | awk -F\| '{print $2}')
    country=$(echo "${line}" | awk -F\| '{print $3}')
    city=$(echo "${line}" | awk -F\| '{print $4}')
    isp=$(echo "${line}" | awk -F\| '{print $5}')

    ip_val="${ip_addr%%:*}"
    port_val="${ip_addr##*:}"

    if [[ -n "${country_i}" ]]; then
        flag=${flag:-0}
        [[ "${country,,}" == "${country_i,,}" ]] && flag=1
    elif [[ -n "${country_e}" ]]; then
        flag=${flag:-1}
        [[ "${country,,}" == "${country_e,,}" ]] && flag=0
    else
        flag=${flag:-1}
    fi

    if [[ "${flag}" -eq 1 ]]; then
        # https://superuser.com/questions/769541/is-it-possible-to-ping-an-addressport
        # - check ip:port if is open or not, too consume time, not use
        # -n $(nc -znv "${ip_val}" "${port_val}" 2>&1 | sed -r -n '/open$/p')
        local rtt_latency=${rtt_latency:-}

        if [[ "$UID" -ne 0  ]]; then
            rtt_latency=$(nping -c 1 -p "${port_val}" "${ip_val}" 2> /dev/null | sed -r -n '/Avg/{s@.*Avg rtt:[[:space:]]*(.*)@\1@g;p}')
        else
            rtt_latency=$(nping -c 1 --tcp -p "${port_val}" "${ip_val}" 2> /dev/null | sed -r -n '/Avg/{s@.*Avg rtt:[[:space:]]*(.*)@\1@g;p}')
        fi

        if [[ "${rtt_latency}" != 'N/A' ]]; then

            case "${protocol_type,,}" in
                http )
                    curl_speed_test="${curl_speed_test} -x ${ip_addr}"
                    ;;
                socks4 )
                    # -x, --proxy [protocol://]host[:port]   Use the specified proxy.
                    [[ "${curl_version_no}" > '7.21.7' ]] && curl_speed_test="${curl_speed_test} -x socks4a://${ip_addr}" || curl_speed_test="${curl_speed_test} --socks4a ${ip_addr}"
                    ;;
                socks5|* )
                    [[ "${curl_version_no}" > '7.21.7' ]] && curl_speed_test="${curl_speed_test} -x socks5h://${ip_addr}" || curl_speed_test="${curl_speed_test} --socks5-hostname ${ip_addr}"
                    ;;
            esac

            if [[ -n $($curl_speed_test ipinfo.io/country 2> /dev/null) ]]; then
                # the order of fields will affects command 'sort' used in func funcProxyIPExtraction
                if [[ "${show_details}" -eq 1 ]]; then
                    echo "${ip_addr}|${country}|${city}|${isp}|${rtt_latency}"
                else
                    echo "${country}|${rtt_latency}|${ip_addr}"
                fi
            fi

        fi

    fi
}


funcProxyIPExtraction(){
    echo "IP testing process will cost some time, just be patient!"
    case "${protocol_type,,}" in
        h|http|https ) protocol_type='http' ;;
        socks4 ) protocol_type='socks4' ;;
        socks5 ) protocol_type='socks5' ;;
        * ) protocol_type='socks5' ;;
    esac
    real_country=$($download_tool_origin ipinfo.io/country)

    if [[ "${real_country}" == 'CN' ]]; then
        if [[ "${protocol_type}" =~ ^socks ]]; then
            funcProxySite_1_socks
        else
            if [[ "${proxy_site_specify}" -gt 0 && "${proxy_site_specify}" -le 3 ]]; then
                funcProxySite_"${proxy_site_specify}"
            else
                funcProxySite_1
                funcProxySite_2
                funcProxySite_3
            fi

        fi
    else
        if [[ "${protocol_type}" =~ ^socks ]]; then
            funcProxySite_1_socks
            funcProxySite_3_socks
        else
            if [[ "${proxy_site_specify}" -gt 0 && "${proxy_site_specify}" -le 9 ]]; then
                funcProxySite_"${proxy_site_specify}"
            else
                funcProxySite_1
            fi
        fi
    fi

    if [[ -s "${proxy_ip_extracted}" ]]; then
        if [[ "${protocol_type}" =~ ^s ]]; then
            filter_str="${protocol_type}"
        else
            case "${anonymity_type,,}" in
                l|low ) filter_str='transparent|transparente' ;;
                m|medium ) filter_str='anonymous' ;;
                h|high|* ) filter_str='high|high-anonymous|elite' ;;
            esac
        fi

        printf "Protocol type is ${c_red}%s${c_normal}.\n\n" "${protocol_type^^}"

        # - 重要 IMPORTMENT: use keyword 'export' to make variables or functions can be readed by command 'parallel'

        country_i=${country_i:-''}  # include country
        [[ -n "${include_country}" ]] && country_i=$(funcCountryShortName "${include_country}")
        country_e=${country_e:-''}  # exclude country
        [[ -n "${exclude_country}" ]] && country_e=$(funcCountryShortName "${exclude_country}")
        export country_i="${country_i}"
        export country_e="${country_e}"

        curl_speed_test=${curl_speed_test:-"curl -fsL"}

        if [[ "${strict_speed_test}" -ne 1 ]]; then
            curl_speed_time=2     #time second -y, --speed-time <time>  must integer
            curl_speed_limit=50     # speed byte -Y, --speed-limit <speed>
            curl_max_time=3    #time second -m, --max-time <seconds> must integer
        fi

        curl_speed_test="${curl_speed_test} --speed-time ${curl_speed_time} --speed-limit ${curl_speed_limit} --max-time ${curl_max_time}"

        export curl_speed_test="${curl_speed_test}"

        local curl_version_no=${curl_version_no:-}
        curl_version_no=$(curl --version | sed -r -n '1s@.* ([[:digit:].]*) .*@\1@p')
        export curl_version_no="${curl_version_no}"

        export include_country="${include_country}"
        export exclude_country="${exclude_country}"
        export show_details="${show_details}"
        export protocol_type="${protocol_type}"
        # export -f funcCountryShortName
        export -f funcSpecificProxyIPTesting

        # according to the sequenct of the output via function funcSpecificProxyIPTesting
        local sort_order=${sort_order:-'-k 1 -k 2'}
        [[ "${show_details}" -eq 1 ]] && sort_order='-k 5 -k 2'

        awk -F\| 'match($2,/^('"${filter_str}"')/){if(a[$1]=="") a[$1]=$0}END{PROCINFO["sorted_in"]="@ind_num_asc";for (i in a) print a[i]}' "${proxy_ip_extracted}" | parallel -k -j 0 funcSpecificProxyIPTesting 2> /dev/null | sort -t "|" -n ${sort_order}

    fi
}


#########  4. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
[[ "${list_proxy_sites}" -eq 1 ]] && funcListProxySites
funcProxyIPExtraction


#########  5. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    unset list_proxy_sites
    unset show_details
    unset proxy_site_specify
    unset include_country
    unset exclude_country
    unset protocol_type
    unset anonymity_type
    unset proxy_server
    unset use_proxy
    unset user_agent
    unset real_country
    unset strict_speed_test
    unset curl_speed_time
    unset curl_speed_limit
    unset curl_max_time
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
}

trap funcTrapEXIT EXIT

# Script End

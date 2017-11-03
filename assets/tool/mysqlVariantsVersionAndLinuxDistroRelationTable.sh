#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #IFS  Internal Field Separator

#Official Site:
# - https://dev.mysql.com/
# - https://www.percona.com/
# - https://mariadb.org/

#Target: Extract GNU/Linux distribution supported by MySQL/MariaDB/Percona along with specific version list
#Writer: MaxdSre
#Date: Oct 24, 2017 15:40 Tue +0800
#Update Time:
# - Aug 29, 2017 13:06 Tue +0800
# - Aug 30, 2017 19:35 Wed +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'MVVALDRTemp_XXXXX'}
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
readonly c_red="${c_bold}$(tput setaf 1)"     # c_red='\e[31;1m'
readonly c_blue="$(tput setaf 4)"    # c_blue='\e[34m'

readonly github_raw_url='https://raw.githubusercontent.com'
readonly relation_script_path="${github_raw_url}/MaxdSre/ShellScript/master/assets/gnulinux/gnuLinuxLifeCycleInfo.sh"

# not use format tempXXXXX.txt as the script will delete /tmp/temp*.txt when exit
debian_codename_ralation=$(mktemp -t "${mktemp_format}")

dbname_choose=${dbname_choose:-'all'}
proxy_server=${proxy_server:-''}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Extract GNU/Linux distribution supported by MySQL/MariaDB/Percona along with specific version list!

[available option]
    -h    --help, show help info
    -d db_name    -- choose database type (MySQL/MariaDB/Percona), default is all
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

funcInitializationCheck(){
    # - OS support check
    [[ -s /etc/os-release || -s /etc/SuSE-release || -s /etc/redhat-release || (-s /etc/debian_version && -s /etc/issue.net) ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script doesn't support your system!"

    # - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    # [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    funcCommandExistCheck 'gawk' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gawk${c_normal} command found, please install it!"

    funcCommandExistCheck 'sed' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}sed${c_normal} command found, please install it!"

    funcCommandExistCheck 'curl' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}curl${c_normal} command found, please install it!"

    funcCommandExistCheck 'parallel' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}parallel${c_normal} command found, please install it!"

    funcCommandExistCheck 'rpm2cpio' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}rpm2cpio${c_normal} command found, please install it!"

    funcCommandExistCheck 'ar' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}ar${c_normal} command found, please install ${c_blue}binutils${c_normal}!"
}

funcInternetConnectionCheck(){
    # CentOS: iproute Debian/OpenSUSE: iproute2
    local gateway_ip
    if funcCommandExistCheck 'ip'; then
        gateway_ip=$(ip route | awk 'match($1,/^default/){print $3}')
    elif funcCommandExistCheck 'netstat'; then
        gateway_ip=$(netstat -rn | awk 'match($1,/^Destination/){getline;print $2;exit}')
    else
        funcExitStatement "${c_red}Error${c_normal}: No ${c_blue}ip${c_normal} or ${c_blue}netstat${c_normal} command found, please install it!"
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
    local referrer_page=${referrer_page:-'https://duckduckgo.com/?q=mysql'}

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
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal} or ${c_blue}wget${c_normal}!"
    fi
}


#########  1-2 getopts Operation  #########
while getopts "hd:p:" option "$@"; do
    case "$option" in
        d ) dbname_choose="$OPTARG" ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done


#########  2-0. Debian/Ubuntu distro&codename relationship  #########
funcDebianUbuntuCodeRelationTable(){
    $download_tool "${relation_script_path}" | bash -s -- -c ubuntu | awk -F\| -v distro='ubuntu' 'BEGIN{OFS="|"}NR>1{codename=gensub(/^([[:alpha:]]+).*/,"\\1","1",tolower($2));a[codename]=$2}END{for(i in a) print distro,tolower(i)}' >> ${debian_codename_ralation}

    $download_tool "${relation_script_path}" | bash -s -- -c debian | awk -F\| -v distro='debian' 'BEGIN{OFS="|"}NR>1{a[$2]++}END{for(i in a) print distro,tolower(i)}' >> ${debian_codename_ralation}

    # bash gnuLinuxLifeCycleInfo.sh -c ubuntu |  awk -F\| -v distro='ubuntu' 'BEGIN{OFS="|"}NR>1{codename=gensub(/^([[:alpha:]]+).*/,"\\1","1",tolower($2));a[codename]=$2}END{for(i in a) print distro,tolower(i)}'
    #
    # bash gnuLinuxLifeCycleInfo.sh -c debian | awk -F\| -v distro='debian' 'BEGIN{OFS="|"}NR>1{a[$2]++}END{for(i in a) print distro,tolower(i)}'

}


#########  2-1. Percona Operation  #########
# rhel6 ==> rhel6, centos6
# - version|distro_list
funcPerconaDistroListForPerVersion(){
    # $1 = 5.7 https://www.percona.com/downloads/Percona-Server-LATEST/
    local item=${1:-}
    if [[ -n "${item}" ]]; then
        local version=${version:-}
        local version_url=${version_url:-}
        local distro_list=${distro_list:-}
        version="${item%% *}"
        version_url="${item##* }"
        distro_list=$($download_tool $version_url | sed -r -n '/Select Software Platform/{s@redhat/@rhel@g;s@<\/option>@\n@g;p}' | sed -r -n 's@.*/([^"]*)"[[:space:]]*>.*@\1@g;/binary|source|select|^$/d;p' | sed -r ':a;N;$!ba;s@\n@ @g;')
        echo "${version}|${distro_list}" >> "${version_list_info}"
    fi
}

# - db_name|distro|version_list
funcPerconaVersionListPerDistro(){
    local distro=${1:-}
    local version_list=${version_list:-}
    local db_name=${db_name:-'Percona'}
    version_list=$(awk -F\| 'match($NF,/[[:space:]]*'"${distro}"'[[:space:]]*/){a[$1]=$2}END{PROCINFO["sorted_in"]="@ind_str_desc";for(i in a) print i}' "${version_list_info}" | sed -r ':a;N;$!ba;s@\n@ @g;')
    # [[ -z "${version_list}" ]] || echo "${db_name}|${distro}|${version_list}"

    local distro_list=${distro_list:-}

    if [[ -n "${version_list}" ]]; then
        if [[ "${distro}" =~ ^rhel ]]; then
            distro_list='rhel centos'
        else
            [[ -s "${debian_codename_ralation}" ]] && distro_list=$(awk -F\| 'match($2,/^'"${distro}"'$/){print $1}' "${debian_codename_ralation}")
        fi

        [[ -z "${distro_list}" ]] || distro_list="|${distro_list}"
        echo "${db_name}|${distro}|${version_list}${distro_list}"
    fi
    unset distro_list
}

funcPerconaOperation(){
    version_list_info=$(mktemp -t "${mktemp_format}")
    local official_site=${official_site:-'https://www.percona.com'}
    local download_page=${download_page:-"${official_site}/downloads/"}

    # - step 1: version|distro_list
    export version_list_info="${version_list_info}"
    export -f funcPerconaDistroListForPerVersion
    export download_tool="${download_tool}"
    $download_tool "${download_page}" | sed -r -n '/A drop-in replacement for MySQL/,/<\/div>/{/<a/{s@.* href="([^"]*)".*>Download ([[:digit:].]+).*@\2 '"${official_site}"'\1@g;p}}' | parallel -k -j 0 funcPerconaDistroListForPerVersion 2> /dev/null

    # - step 2: db_name|distro|version_list
    export version_list_info="${version_list_info}"
    export debian_codename_ralation="${debian_codename_ralation}"
    export -f funcPerconaVersionListPerDistro

    sed -r 's@.*\|@@g' "${version_list_info}" | sed -r ':a;N;$!ba;s@\n@ @g;s@ @\n@g' | awk '{a[$0]++}END{PROCINFO["sorted_in"]="@ind_str_asc";for (i in a) print i}' | parallel -k -j 0 funcPerconaVersionListPerDistro 2> /dev/null

    [[ -f "${version_list_info}" ]] && rm -f "${version_list_info}"
    unset version_list_info
}


#########  2-2. MySQL Operation  #########
# el5 ==> rhel5, centos5
# fc26 ==> fedora26
funcMySQLOperationForRPM(){
    local item=${1:-}
    if [[ -n "${item}" ]]; then
        local download_page=${download_page:-}
        local pack_name=${pack_name:-}
        local md5_official=${md5_official:-}

        item="${item%|}"
        download_page="${item%%|*}"
        item=${item#*|}
        pack_name="${item%%|*}"
        md5_official="${item##*|}"

        # download_page=$(echo "${item}" | awk -F\| '{print $1}')
        # pack_name=$(echo "${item}" | awk -F\| '{print $2}')
        # md5_official=$(echo "${item}" | awk -F\| '{print $3}')

        distro=$(echo "${pack_name}" | sed -r -n 's@.*release-([[:alnum:]]+).*@\1@g;p')
        pack_download_link=$($download_tool "${download_page}" | sed -r -n '/thanks/{s@.*"(.*)".*@https://dev.mysql.com\1@g;p}')
        pack_download_link="https://dev.mysql.com/get/${pack_name}"

        file_path="/tmp/${pack_name}"
        [[ -f "${file_path}" ]] && rm -f "${file_path}"
        $download_tool "${pack_download_link}" > "${file_path}"
        md5_checksum=$(md5sum "${file_path}" | awk '{print $1}')
        # md5_checksum=$(openssl dgst -md5 "${file_path}" | awk '{print $NF}')
        if [[ "${md5_official}" != "${md5_checksum}" ]]; then
            echo "File ${pack_name}, MD5 ${md5_checksum} not approved"
        else
            extract_dir="/tmp/${pack_name%%.*}"
            [[ -d "${extract_dir}" ]] && rm -rf "${extract_dir}"
            mkdir -p "${extract_dir}"
            # rpm2cpio mysql57-community-release-el7.rpm | cpio -idmv
            cd "${extract_dir}" && rpm2cpio "${file_path}" | cpio -idm 2> /dev/null
            extract_target_path="${extract_dir}${target_path}"

            [[ -s "${extract_target_path}" ]] && awk 'BEGIN{ORS=" "}match($0,/^\[mysql[[:digit:]]/){getline;val=gensub(/.* ([[:digit:].]*) .*/,"\\1","g",$0);a[val]=val}END{PROCINFO["sorted_in"]="@ind_str_desc";for(i in a) print i}' "${extract_target_path}" | sed 's@[[:space:]]*$@\n@;s@.*@'"${db_name}|${distro}"'|&@' | awk -F\| '{if($2~/^el/){printf("%s|%s\n",$0,"rhel centos")}else if($2~/^fc/){printf("%s|%s\n",$0,"fedora")}else if($2~/^sles/){printf("%s|%s\n",$0,"sles")}else{print}}'

            [[ -d "${extract_dir}" ]] && rm -rf "${extract_dir}"
            [[ -f "${file_path}" ]] && rm -f "${file_path}"
        fi

    fi
}

funcMySQLForRPM(){
    rpm_type="${1:-}"
    local repo_page=${repo_page:-}
    local target_path=${target_path:-}
    case "${rpm_type,,}" in
        yum|y )
            repo_page='https://dev.mysql.com/downloads/repo/yum/'
            target_path='/etc/yum.repos.d/mysql-community.repo'
            ;;
        suse|sles|s)
            repo_page='https://dev.mysql.com/downloads/repo/suse/'
            target_path='/etc/zypp/repos.d/mysql-community.repo'
            ;;
    esac

    export download_tool="${download_tool}"
    export -f funcMySQLOperationForRPM
    export target_path="${target_path}"
    local db_name=${db_name:-'MySQL'}
    export db_name="${db_name}"
    curl -fsL "${repo_page}" | sed -r -n '/<table/,/<\/table>/{/(button03|sub-text|md5)/!d;/style=/d;s@^[^<]*@@g;s@.*href="(.*)".*@https://dev.mysql.com\1@g;s@.*\((.*)\).*@\1@g;s@[[:space:]]*<\/td>@\n@g;s@<[^>]*>@@g;p}' | awk '{if($0!~/^$/){ORS="|";print $0}else{printf "\n"}}' | parallel -k -j 0 funcMySQLOperationForRPM 2> /dev/null
}

funcMySQLForDEB(){
    local repo_page=${repo_page:-'https://dev.mysql.com/downloads/repo/apt/'}

    $download_tool "${repo_page}" | sed -r -n '/<table/,/<\/table>/{/(button03|sub-text|md5)/!d;/style=/d;s@^[^<]*@@g;s@.*href="(.*)".*@https://dev.mysql.com\1@g;s@.*\((.*)\).*@\1@g;s@[[:space:]]*<\/td>@\n@g;s@<[^>]*>@@g;p}' | awk '{if($0!~/^$/){ORS="|";print $0}else{printf "\n"}}' | while IFS="|" read -r download_page pack_name md5_official; do
        pack_download_link=$(curl -fsL "${download_page}" | sed -r -n '/thanks/{s@.*"(.*)".*@https://dev.mysql.com\1@g;p}')
        pack_download_link="https://dev.mysql.com/get/${pack_name}"

        file_path="/tmp/${pack_name}"
        [[ -f "${file_path}" ]] && rm -f "${file_path}"
        $download_tool "${pack_download_link}" > "${file_path}"
        md5_checksum=$(md5sum "${file_path}" | awk '{print $1}')
        # md5_checksum=$(openssl dgst -md5 "${file_path}" | awk '{print $NF}')
        if [[ "${md5_official}" != "${md5_checksum}" ]]; then
            echo "File ${pack_name}, MD5 ${md5_checksum} not approved"
        else
            extract_dir="/tmp/${pack_name%%_*}"
            [[ -d "${extract_dir}" ]] && rm -rf "${extract_dir}"
            mkdir -p "${extract_dir}"
            # https://www.cyberciti.biz/faq/how-to-extract-a-deb-file-without-opening-it-on-debian-or-ubuntu-linux/
            cd "${extract_dir}" && ar -x "${file_path}"
            [[ -f "${extract_dir}/control.tar.gz" ]] && tar xf "${extract_dir}/control.tar.gz"
            local db_name=${db_name:-'MySQL'}

            # default order
            # [[ -s "${extract_dir}/config" ]] && sed -r -n '/case/,/esac/{s@^[[:space:]]*@@g;s@\)@@g;/(;;|case|esac)/d;s@^[^"]*"@@g;s@(mysql-|preview)@@g;s@,?[[:space:]]*cluster.*$@@g;s@[[:space:]]*"?@@g;/(^$|\*)/d;p}' "${extract_dir}/config" | sed 'N;s@\n@ @g;' | awk -v db_name="${db_name}" 'BEGIN{OFS="|"}{gsub(/,/," ",$NF);print db_name,$1,$NF}'

            # reverse order
            [[ -s "${extract_dir}/config" ]] && sed -r -n '/case/,/esac/{s@^[[:space:]]*@@g;s@\)@@g;/(;;|case|esac)/d;s@^[^"]*"@@g;s@(mysql-|preview)@@g;s@,?[[:space:]]*cluster.*$@@g;s@[[:space:]]*"?@@g;/(^$|\*)/d;p}' "${extract_dir}/config" | sed 'N;s@\n@ @g;' | while IFS=" " read -r codename version_list; do
                version_list=$(echo "${version_list}" | sed 's@,@\n@g' | awk '{a[$0]=$0}END{PROCINFO["sorted_in"]="@ind_str_desc";for (i in a) print i}' | sed -r ':a;N;$!ba;s@\n@ @g;')

                local distro_list=${distro_list:-}
                if [[ -n "${version_list}" ]]; then
                    [[ -s "${debian_codename_ralation}" ]] && distro_list=$(awk -F\| 'match($2,/^'"${codename}"'$/){print $1}' "${debian_codename_ralation}")

                    [[ -z "${distro_list}" ]] || distro_list="|${distro_list}"
                    echo "${db_name}|${codename}|${version_list}${distro_list}"
                fi
                unset distro_list

            done

            [[ -d "${extract_dir}" ]] && rm -rf "${extract_dir}"
            [[ -f "${file_path}" ]] && rm -f "${file_path}"
        fi

    done
}

funcMySQLOperation(){
    # invoking custom function
    funcMySQLForRPM 'yum'
    funcMySQLForRPM 'suse'
    funcMySQLForDEB
}


#########  2-3. MariaDB Operation  #########
# fedora26 ==> fedora26
# opensuse42 ==> opensuse 42

# all supported distribution lists for every MariaDB release version
# curl -fsL https://downloads.mariadb.org/mariadb/repositories | sed -r -n '/Choose a Version/,/Choose a Mirror/{s@^[[:space:]]*@@g;/^<[^(\/?li)]/d;p}' | awk '{if($0!~/^<\/li>/){ORS=" ";print $0}else{printf "\n"}}' | sed -r -n '/class=""/d;s@.* data-value="([^"]*)".*class="[[:space:]]*([^"]*)".*>([[:digit:].]+)[[:space:]]*\[(.*)\]@\L\3|\4|\2@g;/^[[:digit:]]/!d;p'

funcMariaDBOperation(){
    local mariadb_repositories_page=${mariadb_repositories_page:-'https://downloads.mariadb.org/mariadb/repositories'}
    page_source=$(mktemp -t "${mktemp_format}")
    distro_lists_per_mariadb_version=$(mktemp -t "${mktemp_format}")
    local db_name=${db_name:-'MariaDB'}

    [[ -s "${page_source}" ]] || $download_tool "${mariadb_repositories_page}" > "${page_source}"

    [[ -f "${distro_lists_per_mariadb_version}" ]] && echo '' > "${distro_lists_per_mariadb_version}"

    sed -r -n '/Choose a Version/,/Choose a Mirror/{s@^[[:space:]]*@@g;/^<[^(\/?li)]/d;p}' "${page_source}" | awk '{if($0!~/^<\/li>/){ORS=" ";print $0}else{printf "\n"}}' | sed -r -n '/class=""/d;s@.* data-value="([^"]*)".*class="[[:space:]]*([^"]*)".*>([[:digit:].]+)[[:space:]]*\[(.*)\]@\L\3|\4|\2@g;/^[[:digit:]]/!d;p' | while IFS="|" read -r version types distro;do
        lists=$(echo "$distro" | sed 's@ @\n@g' | awk -F- '{a[$1]++}END{for(i in a) printf("%s ",i)}' | sed -r 's@^[[:space:]]*@@g;s@[[:space:]]*$@\n@g')
        echo "${version}|${types}|${lists}" >> "${distro_lists_per_mariadb_version}"
    done

    # all support distribution by MariaDB
    # cat "${page_source}" | sed -r -n '/Choose a Release/,/Choose a Version/{/<\/(li|ul|div)>/d;s@^[[:space:]]*@@g;s@.*data-value="([^"]*)".*@\1@g;/^(<|[[:upper:]])/d;s@^$@@g;p}' | sed '/^$/d'

    sed -r -n '/Choose a Release/,/Choose a Version/{/<\/(li|ul|div)>/d;s@^[[:space:]]*@@g;s@.*data-value="([^"]*)".*@\1@g;/^(<|[[:upper:]])/d;s@^$@@g;p}' "${page_source}" | awk -F- '!match($0,/^$/){a[$1]++}END{PROCINFO["sorted_in"]="@ind_str_desc";for(i in a) print i}' | while read -r line; do
        lists=$(awk -F\| 'match($NF,/'"${line}"'/){a[$1]++}END{PROCINFO["sorted_in"]="@ind_num_desc";for(i in a) printf("%s ",i)}' "${distro_lists_per_mariadb_version}" | sed -r 's@^[[:space:]]*@@g;s@[[:space:]]*$@\n@g')

        local distro_list=${distro_list:-}

        if [[ "${line}" =~ ^rhel ]]; then
            distro_list='rhel'
        elif [[ "${line}" =~ ^centos ]]; then
            distro_list='centos'
        elif [[ "${line}" =~ ^fedora ]]; then
            distro_list='fedora'
        elif [[ "${line}" =~ ^opensuse ]]; then
            distro_list='opensuse'
        else
            if [[ -n "${lists}" ]]; then
                [[ -s "${debian_codename_ralation}" ]] && distro_list=$(awk -F\| 'match($2,/^'"${line}"'$/){print $1}' "${debian_codename_ralation}")
            fi
        fi

        # The code name for Debian's development distribution is "sid", aliased to "unstable".
        # https://www.debian.org/releases/sid/
        # https://wiki.debian.org/DebianUnstable
        if [[ -z "${distro_list}" ]]; then
            [[ "${line}" == 'sid' ]] && distro_list="|debian"
        else
            distro_list="|${distro_list}"
        fi

        echo "${db_name}|${line}|${lists}${distro_list}"
        unset distro_list
    done

    [[ -f "${page_source}" ]] && rm -f "${page_source}"
    [[ -f "${distro_lists_per_mariadb_version}" ]] && rm -f "${distro_lists_per_mariadb_version}"
}


#########  2-4. Central Operation  #########
funcCentralOperation(){
    funcDebianUbuntuCodeRelationTable

    case "${dbname_choose,,}" in
        MySQL|mysql|my|m )
            funcMySQLOperation
            ;;
        MariaDB|mariadb|ma )
            funcMariaDBOperation
            ;;
        Percona|percona|p )
            funcPerconaOperation
            ;;
        * )
            funcMySQLOperation
            funcMariaDBOperation
            funcPerconaOperation
            ;;
    esac
}


#########  3. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
funcCentralOperation


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset dbname_choose
    unset proxy_server
    unset debian_codename_ralation
}

trap funcTrapEXIT EXIT

# Script End

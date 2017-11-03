#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #IFS  Internal Field Separator

#Official Site: https://www.redhat.com/en
#Documentation:
# - https://access.redhat.com/documentation/en/
# - https://www.suse.com/documentation/
# - https://doc.opensuse.org/

#Target: Download RedHat/SUSE/OpenSUSE Official Product Documentations On GNU/Linux
#Writer: MaxdSre
#Date:
#Update Time: Oct 17, 2017 16:57 Tue +0800
# - Aug 03, 2017 18:57 Thu +0800
# - Sep 16, 2017 +0800 ~ Sep 20, 2017 16:03 +0800  Reconfiguration
# - Sep 26, 2017 19:17 Tue +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'DocTemp_XXXXX'}

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

gnulinux_distro_name=${gnulinux_distro_name:-}
category_manual_choose=${category_manual_choose:-0}
file_type=${file_type:-'PDF'}       # PDF, ePub
doc_save_dir=${doc_save_dir:-''}
proxy_server=${proxy_server:-}
# download fail retry times (count)
max_retry_count=${max_retry_count:-3}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Download RedHat/SUSE/OpenSUSE/AWS Official Product Documentations On GNU/Linux
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -d distro_name    --specify GNU/Linux distribution name (Red Hat/SUSE/OpenSUSE/AWS)
    -c    --category choose, default download all categories under specific product
    -t file_type    --specify file type (pdf|epub), default is pdf
    -s save_dir    --specify documentation save path (e.g. /tmp), default is ~ or ~/Downloads
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
    # [[ "$UID" -ne 0 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script requires superuser privileges (eg. root, su)."

    # 2 - OS support check
    [[ -s /etc/os-release || -s /etc/SuSE-release || -s /etc/redhat-release || (-s /etc/debian_version && -s /etc/issue.net) ]] || funcExitStatement "${c_red}Sorry${c_normal}: this script doesn't support your system!"

    # 3 - bash version check  ${BASH_VERSINFO[@]} ${BASH_VERSION}
    # bash --version | sed -r -n '1s@[^[:digit:]]*([[:digit:].]*).*@\1@p'
    [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && funcExitStatement "${c_red}Sorry${c_normal}: this script need BASH version 4+, your current version is ${c_blue}${BASH_VERSION%%-*}${c_normal}."

    # 4 - current login user detection
    #$USER exist && $SUDO_USER not exist, then use $USER
    [[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && login_user="$USER" || login_user="$SUDO_USER"
    login_user_home=${login_user_home:-}
    login_user_home=$(awk -F: 'match($1,/^'"${login_user}"'$/){print $(NF-1)}' /etc/passwd)

    # 5 -  Check essential command
    funcCommandExistCheck 'curl' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}curl${c_normal} command found!"

    funcCommandExistCheck 'gawk' || funcExitStatement "${c_red}Error${c_normal}, No ${c_blue}gawk${c_normal} command found!"

}

funcInternetConnectionCheck(){
    # CentOS: iproute Debian/OpenSUSE: iproute2
    local gateway_ip=${gateway_ip:-}
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

    else
        funcExitStatement "${c_red}Error${c_normal}: can't find command ${c_blue}curl${c_normal}!"
    fi
}


#########  1-2 getopts Operation  #########
start_time=$(date +'%s')    # Start Time Of Operation

while getopts "hcd:t:s:p:" option "$@"; do
    case "$option" in
        c ) category_manual_choose=1 ;;
        d ) gnulinux_distro_name="$OPTARG" ;;
        t ) file_type="$OPTARG" ;;
        s ) doc_save_dir="$OPTARG" ;;
        p ) proxy_server="$OPTARG" ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done

funcGetOptsConfiguration(){
    # - file type
    case "${file_type,,}" in
        pdf|pd|p ) file_type='pdf' ;;
        epub|epu|ep|e ) file_type='epub' ;;
        * ) file_type='pdf' ;;
    esac

    # - documentation save directory
    if [[ -z "${doc_save_dir}" ]]; then
        # default save directory configuration
        if [[ -d "${login_user_home}/Downloads" ]]; then
            doc_save_dir="${login_user_home}/Downloads"
        elif [[ -d "${login_user_home}/Desktop" ]]; then
            doc_save_dir="${login_user_home}/Desktop"
        else
            doc_save_dir="${login_user_home}"
        fi

    else
        # check if begin with / or ~ or not
        if [[ "${doc_save_dir}" =~ ^[^(\/|\~)] ]]; then
            doc_save_dir="${login_user_home}/${doc_save_dir}"
        fi

        # check if create directory successfully or not
        if [[ ! -d "${doc_save_dir}" ]]; then
            mkdir -p "${doc_save_dir}"  2>/dev/null
            [[ $? -eq 0 ]] || funcExitStatement "${c_red}Patient${c_normal}: login user ${c_blue}${login_user}${c_normal} cannot create directory ${c_red}${doc_save_dir}${c_normal} (Permission denied). Please change login user or use ${c_red}sudo${c_normal}."
        fi

        [[ -w "${doc_save_dir}" ]] || funcExitStatement "${c_red}Patient${c_normal}: login user ${c_blue}${login_user}${c_normal} has no ${c_red}write${c_normal} permission for ${c_blue}${doc_save_dir}${c_normal}. Please change login user or use ${c_red}sudo${c_normal}."
    fi
    doc_save_dir="${doc_save_dir/%\//}"
}


#########  2-1. GNU/Linux Distribution Choose  #########
funcLinuxDistributionMenuList(){
    local distribution_arr=("Red Hat" "SUSE" "OpenSUSE" "AWS")    # index array

    echo "${c_red}Available GNU/Linux Distribution List:${c_normal}"
    PS3="Choose distribution number(e.g. 1, 2,...): "

    local choose_distro_name=${choose_distro_name:-}

    select item in "${distribution_arr[@]}"; do
        choose_distro_name="${item}"
        [[ -n "${choose_distro_name}" ]] && break
    done < /dev/tty

    gnulinux_distro_name="${choose_distro_name}"
    unset PS3
}

funcLinuxDistributionSelection(){
    case "${gnulinux_distro_name,,}" in
        'red hat'|redhat|red|rhel|r ) gnulinux_distro_name='Red Hat' ;;
        suse|su|s ) gnulinux_distro_name='SUSE' ;;
        opensuse|open|o ) gnulinux_distro_name='OpenSUSE' ;;
        amazon|aws|a ) gnulinux_distro_name='AWS' ;;
        * ) funcLinuxDistributionMenuList ;;
    esac

    printf "\nGNU/Linux distribution you choose is ${c_red}%s${c_normal}.\n\n" "${gnulinux_distro_name}"
}


#########  2-2. File Download Procedure  #########
funcFileDownloadProcedure(){
    local l_category_name="${1:-}"
    local l_doc_name="${2:-}"
    local l_doc_url="${3:-}"
    local l_doc_save_name="${4:-}"
    local l_retry_count="${5:-0}"

    [[ -f "${l_doc_save_name}" ]] && rm -f "${l_doc_save_name}"

    $download_tool "${l_doc_url}" > "${l_doc_save_name}"

    if [[ -s "${l_doc_save_name}" ]]; then
        echo "${c_red}${l_category_name}${c_normal} -- ${c_blue}${l_doc_name}${c_normal} (${c_blue}$(ls -hs "${l_doc_save_name}" | awk '{print $1}')${c_normal}) downloads successfully!"
    else
        if [[ "${l_retry_count}" -le "${max_retry_count}" ]]; then
            if funcCommandExistCheck 'sleep'; then
                sleep 1     # sleep 1 second
            fi

            let l_retry_count+=1
            # iteration
            funcFileDownloadProcedure "${l_category_name}" "${l_doc_name}" "${l_doc_url}" "${l_doc_save_name}" "${l_retry_count}"
        else
            echo "${c_red}${l_category_name}${c_normal} -- ${c_blue}${l_doc_name}${c_normal} downloads ${c_red}faily${c_normal}!"

            [[ -f "${l_doc_save_name}" ]] && rm -f "${l_doc_save_name}"
            echo "${l_doc_url}" > "${l_doc_save_name%.*}.txt"
        fi    # end if
    fi    # end if l_doc_save_name
}

funcDocSaveDirectoryStatement(){
    local target_dir="${1:-}"
    if [[ -z "${target_dir}" ]]; then
        printf "Working directory: ${c_red}%s${c_normal}.\n\n" "${doc_save_dir}"
    else
        printf "Working directory: ${c_red}%s${c_normal}.\n\n" "${target_dir}"
    fi

    # nautilus - a file manager for GNOME
    # Open File Save Path In Graphical Windows
    funcCommandExistCheck 'nautilus' && nautilus "${target_dir}" &
}

#########  3-1. Red Hat Distribution Operation  #########
# get specific product documentation page link
# global variables
# - choose_product_topic
# - choose_product
# - choose_version
# - product_content_list
funcRedHatProductPageLinkExtraction(){
    local official_site=${official_site:-'https://access.redhat.com'}
    # Product Documentation   https://access.redhat.com/documentation/en/
    local official_doc_site=${official_doc_site:-"${official_site}/documentation/en/"}

    choose_product_topic=${choose_product_topic:-}
    choose_product=${choose_product:-}
    choose_version=${choose_version:-}      # product version may not exists (has no version)
    choose_category=${choose_category:-}    # product category via specify -c

    local product_topic_list=$(mktemp -t "${mktemp_format}")
    $download_tool "${official_doc_site}" | sed -r -n '/class="grid-item"/{s@<div[^>]*>@@g;s@<\/div>@\n\n@g;s@<li>@\n@g;p}' | sed -r -n 's@.*href="([^"]*)">([^<]*)<.*@\2|'"${official_site}"'\1@g;s@[[:space:]]*<h4[^>]*>@---\n@;s@<[^>]*>@@g;p' | sed -r -n '1d;/^[[:blank:]]*$/d;s@---@@g;p' > "${product_topic_list}"

    # 1 - Product Topic Lists
    local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Product Topic List:${c_normal}"
    PS3="Choose product topic number(e.g. 1, 2,...): "

    select item in $(awk '!match($0,/(\/|^$)/){arr[$0]++}END{PROCINFO["sorted_in"]="@ind_str_desc";for (i in arr) print i}' "${product_topic_list}" | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_product_topic="${item}"
        [[ -n "${choose_product_topic}" ]] && break
    done < /dev/tty

    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK
    printf "\nProduct topic you choose is ${c_red}%s${c_normal}.\n\n" "${choose_product_topic}"

    # 2 - Product Lists Under Specific Topic
    IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Product List Under ${choose_product_topic}:${c_normal}"
    PS3="Choose product number(e.g. 1, 2,...): "

    select item in $(sed -r -n '/^'"${choose_product_topic}"'$/,/^$/{/\|/p}' "${product_topic_list}" | awk -F\| '{print $1}' | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_product="${item}"
        [[ -n "${choose_product}" ]] && break
    done < /dev/tty

    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK

    printf "\nProduct you choose is ${c_red}%s${c_normal}.\n\n" "${choose_product}"

    # 3 - Product Url
    product_url=${product_url:-}
    product_url=$(sed -r -n '/^'"${choose_product_topic}"'$/,/^'"${choose_product}"'\|/{/^'"${choose_product}"'\|/!d;s@^[^\|]*\|(.*)@\1@g;p}' "${product_topic_list}")

    [[ -f "${product_topic_list}" ]] && rm -f "${product_topic_list}"

    [[ "${product_url}" =~ ^https?:// ]] || funcExitStatement "${c_red}Sorry${c_normal}: fail to get url of ${c_red}${choose_product}${c_normal}."

    # 4 - Product Version Lists
    local product_page_html=${product_page_html:-}
    product_page_html=$(mktemp -t "${mktemp_format}")
    product_content_list=$(mktemp -t "${mktemp_format}")

    $download_tool "${product_url}" > "${product_page_html}"

    # check page html code if contains "allTheData" which means it is a Red Hat Product Documentation page
    [[ -z $(sed -r -n '/allTheData/p' "${product_page_html}") ]] && funcExitStatement "${c_red}Sorry${c_normal}: this is not Red Hat Product Documentation."

    sed -r -n '/allTheData/{s@.*=[[:space:]]*@@g;s@<[^>]*>@@g;s@},@}\n\n@g;p}' "${product_page_html}" | sed -n '/"category"/!d;s@:null@:"null"@g;s@\\/@/@g;s@[[:space:]]*"[[:space:]]*@"@g;p' | awk -v official_site_url="${official_site}" 'BEGIN{OFS="|"}{
        if (match($0,/"category"/)) {
            category=gensub(/.*"category":"([^"]*)".*/,"\\1","g",$0);
        } else {category=""};
        if (match($0,/"link"/)) {
            link=gensub(/.*"link":"([^"]*)".*/,"\\1","g",$0);
            if(link!~/^https:\/\//){link=official_site_url""link}
        } else {link=""};
        if (match($0,/"title"/)) {
            title=gensub(/.*"title":"([^"]*)".*/,"\\1","g",$0);
        } else {title=""};
        if (match($0,/"description"/)) {
            description=gensub(/.*"description":"([^"]*)".*/,"\\1","g",$0);
        } else {description=""};
        if (match($0,/"version"/)) {
            version=gensub(/.*"version":"([^"]*)".*/,"\\1","g",$0);
        } else {version=""};
        if (match($0,/"Single-page"/)) {
            single_page=gensub(/.*"Single-page":"([^"]*)".*/,"\\1","g",$0);
            if(single_page!~/^https:\/\//){single_page=official_site_url""single_page}
        } else {single_page=""};
        if (match($0,/"PDF"/)) {
            pdf=gensub(/.*"PDF":"([^"]*)".*/,"\\1","g",$0); if(pdf!~/^https:\/\//){pdf=official_site_url""pdf}
        } else {pdf=""};
        if (match($0,/"ePub"/)) {
            epub=gensub(/.*"ePub":"([^"]*)".*/,"\\1","g",$0); if(epub!~/^https:\/\//){epub=official_site_url""epub}
        } else {epub=""};
        print version,category,title,description,link,single_page,pdf,epub
    }' > "${product_content_list}"

    local version_list=${version_list:-}
    version_list=$(awk -F\| '{arr[$1]++}END{PROCINFO["sorted_in"]="@ind_num_desc";for (i in arr) print i}' "${product_content_list}")

    if [[ -n "${version_list}" ]]; then
        local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
        IFS="|" # Setting temporary IFS

        echo "${c_red}Available Version List Of ${choose_product}:${c_normal}"
        PS3="Choose product version number(e.g. 1, 2,...): "

        select item in $(echo "${version_list}" | sed ':a;N;$!ba;s@\n@|@g'); do
            choose_version="${item}"
            [[ -n "${choose_version}" ]] && break
        done < /dev/tty

        IFS=${IFS_BAK}  # Restore IFS
        unset IFS_BAK

        printf "\nProduct version you choose is ${c_red}%s${c_normal}.\n\n" "${choose_version}"
    fi

    # 5 - Category Lists Under Specific Product
    if [[ "${category_manual_choose}" -eq 1 ]]; then
        local category_list=${category_list:-}
        category_list=$(awk -F\| 'match($1,/^'"${choose_version}"'$/){arr[$2]++}END{PROCINFO["sorted_in"]="@ind_str_asc";for (i in arr) print i}' "${product_content_list}")

        if [[ -n "${category_list}" ]]; then
            local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
            IFS="|" # Setting temporary IFS

            echo "${c_red}Available Category List Of ${choose_product} ${choose_version}:${c_normal}"
            PS3="Choose product category number(e.g. 1, 2,...): "

            select item in $(echo "${category_list}" | sed ':a;N;$!ba;s@\n@|@g'); do
                choose_category="${item}"
                [[ -n "${choose_category}" ]] && break
            done < /dev/tty

            IFS=${IFS_BAK}  # Restore IFS
            unset IFS_BAK

            printf "\nProduct category you choose is ${c_red}%s${c_normal}.\n\n" "${choose_category}"
        fi
    fi

}

funcRedHatOperation(){
    funcRedHatProductPageLinkExtraction

    # - Download Procedure
    local category_dir=${category_dir:-}

    if [[ -z "${choose_version}" ]]; then
        category_dir="${doc_save_dir}/${choose_product_topic}/${choose_product}"
    elif [[ -n $(echo "${choose_version}" | sed -r -n '/^[[:digit:]]+.?[[:digit:]]*$/p') ]]; then
        category_dir="${doc_save_dir}/${choose_product_topic}/${choose_product} ${choose_version}"
    else
        category_dir="${doc_save_dir}/${choose_product_topic}/${choose_product} - ${choose_version}"
    fi

    funcDocSaveDirectoryStatement "${category_dir}"

    local counter_flag=${counter_flag:-1}
    local category_flag=${category_flag:-}
    local file_url=${file_url:-}

    awk -F\| 'match($1,/^'"${choose_version}"'$/)&&match($2,/'"${choose_category}"'/){arr[$0]=$2}END{PROCINFO["sorted_in"]="@val_str_asc";for (i in arr) print i}' "${product_content_list}" | sort -b -f -t"|" -k 1,1 -k 2,2 -k 3r,3 | while IFS="|" read -r version category title description link single_page pdf_url epub_url; do

        case "${file_type,,}" in
            pdf ) file_url="${pdf_url}" ;;
            epub ) file_url="${epub_url}" ;;
        esac

        if [[ -z "${category}" ]]; then
            sub_category_dir="${category_dir}"
            category='NULL'
        else
            sub_category_dir="${category_dir}/${category}"
        fi    # end if

        [[ -d "${sub_category_dir}" ]] || mkdir -p "${sub_category_dir}"

        if [[ -z "${category_flag}" ]]; then
            category_flag="${sub_category_dir}"
        elif [[ -n "${category_flag}" && "${category_flag}" != "${sub_category_dir}" ]]; then
            counter_flag=1
            category_flag="${sub_category_dir}"
        fi    # end if

        if [[ -n "${file_url}" && "${file_url}" =~ ${file_type,,}$ ]]; then
            doc_save_name="${sub_category_dir}/${counter_flag} - ${title//\//&}.${file_url##*.}"
            [[ -f "${doc_save_name}" ]] && rm -f "${doc_save_name}"
            funcFileDownloadProcedure "${category}" "${title}" "${file_url}" "${doc_save_name}"
            let counter_flag+=1
        fi    # end if

    done

    # remove empty dir
    [[ -d "${category_dir}" ]] && find "${category_dir}" -type d -empty -exec ls -d {} \; | while IFS="" read -r line; do [[ -d "${line}" ]]&& rm -rf "${line}"; done

    [[ -f "${product_content_list}" ]] && rm -f "${product_content_list}"
}


#########  3-2. SUSE Distribution Operation  #########
funcSUSEConcatenateCompleteURL(){
    local origin_product_url="${1:-}"   # reference url
    local target_url="${2:-}"   # url need to be concatenated

    if [[ "${target_url}" =~ ^https?: ]]; then
        target_url="${target_url}"
    elif [[ "${target_url}" =~ \.\.\/ ]]; then
        # https://www.suse.com/documentation/
        target_url="${origin_product_url%/*}/${target_url/#\.\.\//}"
    elif [[ -n "${target_url}" ]]; then
        # https://www.suse.com/documentation/sles-12
        target_url="${origin_product_url}/${target_url}"
    fi

    echo "${target_url}"
}

# global variables
# - choose_product
# - choose_version
# - product_full_name
# - doc_info_list
funcSUSEProductPageLinkExtraction(){
    local official_site=${official_site:-'https://www.suse.com'}
    # Product Documentation   https://www.suse.com/documentation/
    local official_doc_site=${official_doc_site:-"${official_site}/documentation/"}

    choose_product=${choose_product:-}
    choose_version=${choose_version:-}
    product_full_name=${product_full_name:-}
    choose_category=${choose_category:-}

    local official_doc_html=${official_doc_html:-}
    official_doc_html=$(mktemp -t "${mktemp_format}")

    $download_tool "${official_doc_site}" | sed -r -n '/<table/,/<\/table>/{/<!--<?tr>/,/<\/tr(> )?-->/d;/<a href=/!d;/openSUSE/d;s@^[[:space:]]*@@g;s@&nbsp;@@g;s@[[:space:]]*([[:digit:]]+<?)@\1@g;s@.*<a href="([^"]+)">([^[:digit:]]+)([[:digit:].]*)<\/a>.*@\2|\3|'"${official_doc_site}"'\1@g;p}' | awk -F\| 'BEGIN{OFS="|"}{if ($2==""){$2="null";print} else {print}}' > "${official_doc_html}"

    # SUSE Linux Enterprise Server for SAP Applications|12|https://www.suse.com/documentation/sles-for-sap/index.html
    # SUSE Linux Enterprise Server for SAP Applications|11|https://www.suse.com/documentation/sles_for_sap_11/index.html
    # SUSE Linux Enterprise Real Time Extension|12|https://www.suse.com/documentation/slerte/index.html
    # SUSE Linux Enterprise Real Time Extension|11|https://www.suse.com/documentation/slerte_11/index.html
    # SUSE Linux Enterprise Real Time Extension|10|https://www.suse.com/documentation/slert/pdfdoc/sle-rt_quick/sle-rt_quick.pdf

    # 1 - Product Lists
    local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Product List:${c_normal}"
    PS3="Choose product number(e.g. 1, 2,...): "

    select item in $(awk -F\| '{gsub(/[[:space:]]+$/,"",$1);gsub(/^[[:space:]]+/,"",$1);arr[$1]++}END{PROCINFO["sorted_in"]="@ind_str_desc";for (i in arr) print i}' "${official_doc_html}" | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_product="${item}"
        [[ -n "${choose_product}" ]] && break
    done < /dev/tty
    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK

    printf "\nProduct you choose is ${c_red}%s${c_normal}.\n\n" "${choose_product}"

    # 2 - Version Lists Under Specific Product
    local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Version List:${c_normal}"
    PS3="Choose version number(e.g. 1, 2,...): "

    select item in $(awk -F\| 'match($1,/^'"${choose_product}"'$/){print $2}' "${official_doc_html}" | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_version="${item}"
        [[ -n "${choose_version}" ]] && break
    done < /dev/tty

    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK

    printf "\nProduct version you choose is ${c_red}%s${c_normal}.\n\n" "${choose_version}"

    # 3 - Product Url
    local product_doc_url=${product_doc_url:-}
    product_doc_url=$(awk -F\| 'match($1,/^'"${choose_product}"'$/)&&match($2,/^'"${choose_version}"'$/){print $NF}' "${official_doc_html}")

    local specific_product_doc_url=${specific_product_doc_url:-}
    [[ "${product_doc_url}" =~ .pdf$ ]] || specific_product_doc_url="${product_doc_url}"
    # SUSE Linux Enterprise Real Time Extension|10|https://www.suse.com/documentation/slert/pdfdoc/sle-rt_quick/sle-rt_quick.pdf

    # save documentation info for all available release version
    local specific_product_info=${specific_product_info:-}
    specific_product_info=$(mktemp -t "${mktemp_format}")

    # remove commented code blocks
    [[ -n "${specific_product_doc_url}" ]] && $download_tool "${specific_product_doc_url}" | sed -r -n '/^[[:space:]]*<!--.*-->[[:space:]]*$/d;/^[[:space:]]*<!--/,/-->[[:space:]]*$/d;p' > "${specific_product_info}"

    # use  class="product"  for specific topic
    # not need topic   Previous Releases

    local topic_lists=${topic_lists:-}
    topic_lists=$(sed -r -n '/class="product"/{s@[[:space:]]*<[^>]*>[[:space:]]*@@g;/^$/d;p}' "${specific_product_info}")

    local topic_count=${topic_count:-}
    topic_count=$(echo "${topic_lists}" | wc -l)

    product_full_name=$(sed -r -n '/<h1>/{s@^[^>]*>([^<]*)<.*@\1@g;p}' "${specific_product_info}")

    # trim trailing /index.html
    # https://www.suse.com/documentation/sles-12/index.html
    specific_product_doc_url=${specific_product_doc_url/%\/index.html/}

    doc_info_list=$(mktemp -t "${mktemp_format}")
    [[ -s "${doc_info_list}" ]] && rm -f "${doc_info_list}"

    # extrect contents between topic via for loop, not need topic  Previous Releases
    for (( i = 1; i < "${topic_count}"; i++ )); do
        local category_start=${category_start:-}
        category_start=$(echo "${topic_lists}" | sed -n ''"${i}"'p')
        local category_end=${category_end:-}
        category_end=$(echo "${topic_lists}" | sed -n ''"$((i+1))"'p')

        # class="prodchapname"   get name, url
        # class="htmlpdf"  .epub .pdf
        sed -r -n '/.*class="product".*>'"${category_start}"'<.*/,/.*class="product".*>'"${category_end}"'<.*/{/class="prodchapname">[^<]+<[^>]*>[[:space:]]*$/d;/class="prodchapname"/{s@.*href="([^"]+)"[^>]*>([^<]*)<.*@---\n\2\n\1@g;s@&reg;@®@g;p};/class="htmlpdf".*.(epub|pdf)/{s@.*href="([^"]+)"[^>]*>.*@\1@g;p}}' "${specific_product_info}" | sed -r '1d;:a;N;$!ba;s@\n@|@g;s@[|][-]+[|]?@\n@g;' | while IFS="|" read -r topic topic_url epub_url pdf_url; do
            topic="${topic/% /}"    # trim trailing white space
            topic_url=$(funcSUSEConcatenateCompleteURL "${specific_product_doc_url}" "${topic_url}")

            # some topic has no .epub, but has .pdf
            if [[ "${epub_url}" =~ \.pdf ]]; then
                pdf_url=$(funcSUSEConcatenateCompleteURL "${specific_product_doc_url}" "${epub_url}")
                epub_url=''
            else
                epub_url=$(funcSUSEConcatenateCompleteURL "${specific_product_doc_url}" "${epub_url}")
                pdf_url=$(funcSUSEConcatenateCompleteURL "${specific_product_doc_url}" "${pdf_url}")
            fi

            # category|product name|product url|pdf url|epub url
            echo "${category_start}|${topic}|${topic_url}|${pdf_url}|${epub_url}" >> "${doc_info_list}"

            # echo "${category_start}|${topic}|${topic_url}"
        done    # end while

        unset category_start
        unset category_end
    done    # end for


    # 4 - Category Lists Under Specific Product
    if [[ "${category_manual_choose}" -eq 1 ]]; then
        local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
        IFS="|" # Setting temporary IFS

        echo "${c_red}Available category List:${c_normal}"
        PS3="Choose category number(e.g. 1, 2,...): "

        select item in $(awk -F\| '{arr[$1]++}END{PROCINFO["sorted_in"]="@ind_str_asc";for (i in arr) print i}' "${doc_info_list}" | sed ':a;N;$!ba;s@\n@|@g'); do
            choose_category="${item}"
            [[ -n "${choose_category}" ]] && break
        done < /dev/tty

        IFS=${IFS_BAK}  # Restore IFS
        unset IFS_BAK

        printf "\nProduct category you choose is ${c_red}%s${c_normal}.\n\n" "${choose_category}"
    fi

    [[ -f "${official_doc_html}" ]] && rm -f "${official_doc_html}"
    [[ -f "${specific_product_info}" ]] && rm -f "${specific_product_info}"
}

funcSUSEOperation(){
    funcSUSEProductPageLinkExtraction

    # - Download Procedure
    local category_dir=${category_dir:-}

    if [[ -z "${product_full_name}" ]]; then
        if [[ "${choose_version}" == 'null' ]]; then
            category_dir="${doc_save_dir}/${choose_product}"
        elif [[ -n "${choose_version}" ]]; then
            category_dir="${doc_save_dir}/${choose_product} ${choose_version}"
        fi
    else
        category_dir="${doc_save_dir}/${product_full_name}"
    fi    # end if

    funcDocSaveDirectoryStatement "${category_dir}"

    local counter_flag=${counter_flag:-1}
    local category_flag=${category_flag:-}
    local file_url=${file_url:-}

    # sort -b -f -t"|" -k 1,1 -k 2r,2 "${doc_info_list}"
    awk -F\| 'match($1,/'"${choose_category}"'/){print}' "${doc_info_list}" | sort -b -f -t"|" -k 1,1 -k 2r,2 | while IFS="|" read -r category topic topic_url pdf_url epub_url; do

        case "${file_type,,}" in
            pdf ) file_url="${pdf_url}" ;;
            epub ) file_url="${epub_url}" ;;
        esac

        sub_category_dir="${category_dir}/${category}"

        if [[ ! -d "${sub_category_dir}" ]]; then
            counter_flag=1
            mkdir -p "${sub_category_dir}"
        fi    # end if

        if [[ -z "${category_flag}" ]]; then
            category_flag="${sub_category_dir}"
        elif [[ -n "${category_flag}" && "${category_flag}" != "${sub_category_dir}" ]]; then
            counter_flag=1
            category_flag="${sub_category_dir}"
        fi    # end if

        if [[ -n "${file_url}" && "${file_url}" =~ ${file_type,,}$ && -d "${sub_category_dir}" ]]; then
            doc_save_name="${sub_category_dir}/${counter_flag} - ${topic//\//&}.${file_url##*.}"
            [[ -f "${doc_save_name}" ]] && rm -f "${doc_save_name}"
            funcFileDownloadProcedure "${category}" "${topic}" "${file_url}" "${doc_save_name}"
            let counter_flag+=1
        fi    # end if

    done    # end while

    # remove empty dir
    [[ -d "${category_dir}" ]] && find "${category_dir}" -type d -empty -exec ls -d {} \; | while IFS="" read -r line; do [[ -d "${line}" ]]&& rm -rf "${line}"; done

    [[ -f "${doc_info_list}" ]] && rm -f "${doc_info_list}"
}


#########  3-3. OpenSUSE Distribution Operation  #########
# global variables
# - choose_version
# - doc_info_list
funcOpenSUSEProductPageLinkExtraction(){
    local official_site=${official_site:-'https://www.opensuse.org/'}
    local official_doc_site=${official_doc_site:-'https://doc.opensuse.org'}

    local official_doc_html=${official_doc_html:-}
    official_doc_html=$(mktemp -t "${mktemp_format}")

    # save documentation info for all available release version
    doc_info_list=$(mktemp -t "${mktemp_format}")
    # release version
    choose_version=${choose_version:-}

    # 1 - Current Release
    $download_tool "${official_doc_site}" > "${official_doc_html}"

    # -- Current Release Version
    local current_release_version=${current_release_version:-}
    # openSUSE Leap 42.3
    current_release_version=$(sed -r -n '/<h2>.*openSUSE.*/{s@[[:space:]]*<[^>]*>@@g;/[[:digit:].]+/{s@.*(openSUSE.*)$@\1@g;p}}' "${official_doc_html}")

    sed -r -n '/<table>/,/<\/table>/{s@^[[:space:]]*@@g;/<\/[^>]*>/d;/^(HTML|single HTML|PDF|ePUB)/d;s@.*href="([^"]*)".*@'"${official_doc_site}"'\1@g;s@<tr>@---\n'"${current_release_version}"'@g;/^<[^>]*>/d;p}' "${official_doc_html}" | sed -r '1d;:a;N;$!ba;s@\n@|@g;s@[|][-]+[|]?@\n@g;' > "${doc_info_list}"

    # release version | title | page | single page | pdf | epub
    # openSUSE Leap 42.3|Startup Guide|https://doc.opensuse.org/documentation/leap/startup/html/book.opensuse.startup/index.html|https://doc.opensuse.org/documentation/leap/startup/single-html/book.opensuse.startup/index.html|https://doc.opensuse.org/documentation/leap/startup/book.opensuse.startup_color_en.pdf|https://doc.opensuse.org/documentation/leap/startup/book.opensuse.startup_en.epub

    # 2 - Previous openSUSE Documentation Archives
    # https://doc.opensuse.org/opensuse.html
    local previous_release_url=${previous_release_url:-}
    previous_release_url=$(sed -r -n '/Documentation Archive/{s@.*href="([^"]*)".*@'"${official_doc_site}"'/\1@g;p}' "${official_doc_html}")

    local previous_official_doc_html=${previous_official_doc_html:-}
    previous_official_doc_html=$(mktemp -t "${mktemp_format}")
    $download_tool "${previous_release_url}" > "${previous_official_doc_html}"

    sed -r -n '/<h2>/{s@[[:space:]]*<[^>]*>[[:space:]]*@@g;p}' "${previous_official_doc_html}" | while IFS="" read -r line; do
        sed -r -n '/'"${line}"'/,/<\/table>/{s@^[[:space:]]*@@g;/<\/[^>]*>/d;/^(HTML|single HTML|PDF|ePUB)/d;s@.*href="([^"]*)".*@'"${official_doc_site}"'\1@g;s@<tr>@---\n'"${line}"'@g;/^<[^>]*>/d;p}' "${previous_official_doc_html}" | sed -r '1d;:a;N;$!ba;s@\n@|@g;s@[|][-]+[|]?@\n@g;' >> "${doc_info_list}"     # append
    done

    [[ -f "${official_doc_html}" ]] && rm -f "${official_doc_html}"
    [[ -f "${previous_official_doc_html}" ]] && rm -f "${previous_official_doc_html}"

    IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Release Version List:${c_normal}"
    PS3="Choose version number(e.g. 1, 2,...): "

    select item in $(awk -F\| '{arr[$1]++}END{PROCINFO["sorted_in"]="@ind_str_desc";for (i in arr) print i}' "${doc_info_list}" | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_version="${item}"
        [[ -n "${choose_version}" ]] && break
    done < /dev/tty

    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK

    printf "\nRelease version you choose is ${c_red}%s${c_normal}.\n\n" "${choose_version}"
}

funcOpenSUSEOperation(){
    funcOpenSUSEProductPageLinkExtraction

    local category_dir="${doc_save_dir}/${choose_version}"
    [[ -d "${category_dir}" ]] || mkdir -p "${category_dir}"

    funcDocSaveDirectoryStatement "${category_dir}"

    local counter_flag=${counter_flag:-1}
    local category_flag=${category_flag:-}
    local file_url=${file_url:-}

    # sort -b -f -t"|" -k 1,1 -k 2,2
    awk -F\| 'BEGIN{OFS="|"}match($1,/^'"${choose_version}"'$/){print}' "${doc_info_list}" | while IFS="|" read -r release_version title page_url single_page_url pdf_url epub_url; do
        case "${file_type,,}" in
            pdf ) file_url="${pdf_url}" ;;
            epub ) file_url="${epub_url}" ;;
        esac

        if [[ -z "${category_flag}" ]]; then
            category_flag="${category_dir}"
        elif [[ -n "${category_flag}" && "${category_flag}" != "${category_dir}" ]]; then
            counter_flag=1
            category_flag="${category_dir}"
        fi    # end if

        if [[ -n "${file_url}" && "${file_url}" =~ ${file_type,,}$ ]]; then
            doc_save_name="${category_dir}/${counter_flag} - ${title//\//&}.${file_url##*.}"
            [[ -f "${doc_save_name}" ]] && rm -f "${doc_save_name}"
            funcFileDownloadProcedure "${choose_version}" "${title}" "${file_url}" "${doc_save_name}"
            let counter_flag+=1
        fi    # end if

    done    # end while

    # remove empty dir
    [[ -d "${category_dir}" ]] && find "${category_dir}" -type d -empty -exec ls -d {} \; | while IFS="" read -r line; do [[ -d "${line}" ]]&& rm -rf "${line}"; done

    [[ -f "${doc_info_list}" ]] && rm -f "${doc_info_list}"
}


#########  3-4. Amazon Web Services (AWS)  #########
# get specific product documentation page link
# global variables
# - choose_product_topic
# - choose_product
# - product_page_url

funcAWSProductPageLinkExtraction(){
    local official_site=${official_site:-'https://aws.amazon.com'}
    local official_doc_site=${official_doc_site:-"${official_site}/documentation/"}
    choose_product_topic=${choose_product_topic:-}
    choose_product=${choose_product:-}
    product_page_url=${product_page_url:-}

    local product_topic_list
    product_topic_list=$(mktemp -t "${mktemp_format}")
    $download_tool "${official_doc_site}" | sed -r -n '/data-toggle="tab">Services </,/data-toggle="tab"> Getting Started </{/<\/a>/!d;s@^[[:blank:]]*@@g;s@<h4[^>]*>@---@g;/<\/h4>/{s@[[:space:]]*<[^>]*>[[:space:]]*@@g};s@<\/a>@&\n@g;p}' | sed -r -n 's@.*href="([^"]+)"[^>]*>([^<]+)<.*$@\2|\1@g;s@[[:space:]]*<[^>]*>[[:space:]]*@@g;s@&nbsp;@ @g;s@&amp;@\&@g;/^[[:blank:]]*$/d;s@---@\n@g;p' > "${product_topic_list}"

    # 1 - Product Topic Lists
    local IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Product Topic List:${c_normal}"
    PS3="Choose product topic number(e.g. 1, 2,...): "

    select item in $(awk '!match($0,/(\/|^$)/){arr[$0]++}END{PROCINFO["sorted_in"]="@ind_str_asc";for (i in arr) print i}' "${product_topic_list}" | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_product_topic="${item}"
        [[ -n "${choose_product_topic}" ]] && break
    done < /dev/tty

    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK
    printf "\nProduct topic you choose is ${c_red}%s${c_normal}.\n\n" "${choose_product_topic}"

    # 2 - Product Lists Under Specific Topic
    IFS_BAK=${IFS_BAK:-"$IFS"}  # Backup IFS
    IFS="|" # Setting temporary IFS

    echo "${c_red}Available Product List Under ${choose_product_topic}:${c_normal}"
    PS3="Choose product number(e.g. 1, 2,...): "

    select item in $(sed -r -n '/^'"${choose_product_topic}"'$/,/^$/{/\|/p}' "${product_topic_list}" | awk -F\| '{print $1}' | sed ':a;N;$!ba;s@\n@|@g'); do
        choose_product="${item}"
        [[ -n "${choose_product}" ]] && break
    done < /dev/tty

    IFS=${IFS_BAK}  # Restore IFS
    unset IFS_BAK

    printf "\nProduct you choose is ${c_red}%s${c_normal}.\n\n" "${choose_product}"

    product_page_url=$(awk -F\| 'match($1,/^'"${choose_product}"'$/){print $NF}' "${product_topic_list}")
    [[ -n "${product_page_url}" && "${product_page_url}" =~ ^/ ]] && product_page_url="${official_site}${product_page_url}"

    [[ -f "${product_topic_list}" ]] && rm -f "${product_topic_list}"
}

funcAWSOperation(){
    funcAWSProductPageLinkExtraction

    # - Download Procedure
    local category_dir="${doc_save_dir}/Amazon Web Services Documentation/${choose_product_topic}/${choose_product}"
    [[ -d "${category_dir}" ]] || mkdir -p "${category_dir}"
    funcDocSaveDirectoryStatement "${category_dir}"

    local counter_flag=${counter_flag:-1}
    local category_flag=${category_flag:-}
    local file_url=${file_url:-}

    $download_tool "${product_page_url}" | sed -r -n '/<tbody>/,/<\/tbody>/{s@<br \/>@@g;s@<\/a>@&\n@g;/href=/!d;p}' | sed -r -n 's@.*href="([^"]+)"[^>]*>([^<]+)<.*$@\2|\1@g;s@^[[:blank:]]*@@g;/\|/!d;/^\|/d;/Kindle/d;/^(PDF|HTML)/!{s@.*@---\n&@g};p' | sed -r -n ':a;N;$!ba;s@\n@|@g;s@\|?---\|?@\n@g;p' | sed -r '/HTML/!d' | while IFS="|" read -r title url html html_url pdf pdf_url; do
        # User Guide for Linux Instances|http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/|HTML|http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/|PDF|http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-ug.pdf

        case "${file_type,,}" in
            pdf ) file_url="${pdf_url}" ;;
        esac

        if [[ -z "${category_flag}" ]]; then
            category_flag="${category_dir}"
        elif [[ -n "${category_flag}" && "${category_flag}" != "${category_dir}" ]]; then
            counter_flag=1
            category_flag="${category_dir}"
        fi    # end if

        if [[ -n "${file_url}" && "${file_url}" =~ ${file_type,,}$ ]]; then
            doc_save_name="${category_dir}/${counter_flag} - ${title//\//&}.${file_url##*.}"
            [[ -f "${doc_save_name}" ]] && rm -f "${doc_save_name}"
            funcFileDownloadProcedure "${category_dir}" "${title}" "${file_url}" "${doc_save_name}"
            let counter_flag+=1
        fi    # end if

    done    # end while

    # remove empty dir
    [[ -d "${category_dir}" ]] && find "${category_dir}" -type d -empty -exec ls -d {} \; | while IFS="" read -r line; do [[ -d "${line}" ]]&& rm -rf "${line}"; done

}


#########  4. Operation Time Cost  #########
funcTotalTimeCosting(){
    finish_time=$(date +'%s')        # End Time Of Operation
    total_time_cost=$((finish_time-start_time))   # Total Time Of Operation
    funcExitStatement "Total time cost is ${c_red}${total_time_cost}${c_normal} seconds!"
}


#########  5. Executing Process  #########
funcInitializationCheck
funcInternetConnectionCheck
funcDownloadToolCheck
funcGetOptsConfiguration

funcLinuxDistributionSelection
func"${gnulinux_distro_name// /}"Operation
funcTotalTimeCosting


#########  4. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    unset gnulinux_distro_name
    unset file_type
    unset category_manual_choose
    unset doc_save_dir
    unset proxy_server
    unset proxy_server
    unset max_retry_count

    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset mktemp_format

    unset choose_product_topic
    unset choose_product
    unset choose_version
    unset choose_category
    unset product_content_list
    unset choose_product
    unset product_full_name
    unset doc_info_list

    unset start_time
    unset finish_time
    unset total_time_cost
}

trap funcTrapEXIT EXIT

# Script End

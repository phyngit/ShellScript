#!/usr/bin/env bash
set -u  #Detect undefined variable
set -o pipefail #Return return code in pipeline fails
# IFS=$'\n\t' #used in loop,  Internal Field Separator

#Official Site: https://daringfireball.net/projects/markdown/
#Target: Automatically Generating Table Of Contents(TOC) For Markdown File(.md) On GNU/Linux
#Writer: MaxdSre
#Date:
#Update Time: Sep 25, 2017 15:35 +0800
# - Jan 29, 2016 20:00 Fri +0800
# - Feb 02, 2016 21:40 Tue +0800
# - Aug 11, 2016 08:27 ~ 15:51 Thu +0800
# - Feb 22, 2017 08:47 ~ 11:24 Wed +0800
# - Apr 11, 2017 17:56 Tue +0800
# - May 9, 2017 10:17 Tue -0400
# - June 08, 2017 11:34 Thu +0800

#########  0-1. Singal Setting  #########
mktemp_format=${mktemp_format:-'MTOCGTemp_XXXXX'}
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
# black 0, red 1, green 2, yellow 3, blue 4, magenta 5, cyan 6, gray 7
readonly c_red="${c_bold}$(tput setaf 1)"     # c_red='\e[31;1m'
readonly c_blue="$(tput setaf 4)"    # c_blue='\e[34m'
is_for_git=${is_for_git:-1}
list_format=${list_format:-0}
toc_type=${toc_type:-'Git'}
toc_order_type=${toc_order_type:-'Ordered Lists'}
file_path=${file_path:-}
quiet_mode=${quiet_mode:-0}


#########  1-1 Initialization Prepatation  #########
funcHelpInfo(){
cat <<EOF
${c_blue}Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...
Markdown TOC Generating On GNU/Linux!

[available option]
    -h          --help, show help info
    -q          --quiet, quiet mode, don't output anything to screen
    -f file     --file path specified
    -t type     --type name (git|gitlab|github|hexo), default is git
    -o order    --order list type (ul|ol), default is 'ol'
${c_normal}
EOF
}

funcExitStatement(){
    local str="$*"
    [[ -n "$str" ]] && printf "%s\n" "$str"
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    exit
}

# script_save_path=$(dirname $(readlink -f "$0"))   # path where this script save

while getopts "hqf:t:o:" option "$@"; do
    case "${option}" in
        f ) file_path="$OPTARG" ;;
        t ) toc_type="$OPTARG" ;;
        o ) toc_order_type="$OPTARG" ;;
        q ) quiet_mode=1 ;;
        h|\? ) funcHelpInfo && exit ;;
    esac
done

# check file path specified exists or not
[[ -z "${file_path}" ]] && funcExitStatement "${c_red}Sorry${c_normal}: Please specify file path with \"-f\", use \"-h\" see help info!"
if [[ -f "${file_path}" ]]; then
    file_save_path=$(readlink -f "${file_path}")
else
    funcExitStatement "${c_red}Sorry${c_normal}: File ${c_blue}${file_path}${c_normal} not exists, please check it!"
fi

# - GitLab/Github flag=1 OR Hexo flag=0 , Git* is default type
if [[ -n "${toc_type}" ]]; then
    case "${toc_type,,}" in
        git|gitlab|github ) is_for_git=1 ;;
        hexo ) is_for_git=0 ;;
        * ) is_for_git=0 ;;
    esac
fi

# - TOC type (Ordered/Unordered Lists), ol is default type
if [[ -n "$toc_order_type" ]]; then
    case "${toc_order_type,,}" in
        o|ol ) list_format=0  ;;
        u|ul ) list_format=1 ;;
        * ) list_format=0 ;;
    esac
fi

# - arrary index present the num of symbol #, title has 6 levels, level 1 is title, start from 2
declare -A flag_arr
flag_arr=([2]=0 [3]=0 [4]=0 [5]=0 [6]=0)


#########  2. Markdown Processing  #########
temp_file=$(mktemp -t "${mktemp_format}")
temp_newfile=$(mktemp -t "${mktemp_format}") #存儲篩選後屬於標題的item

# - 獲取符合條件的item及其行號：從第二行開始以符號#開頭
awk 'NR>1&&match($0,/^#/){printf("%s|%s\n",NR,$0)}' "${file_save_path}" > "${temp_file}"

#變量num用於標記行數
num=1
while IFS="|" read -r line_number item; do
    #通過```出現次數判斷item是否屬於標題，\`用於轉義符號`，在$()中無需使用反斜線\轉移`
    # counts=`awk '$0~/^\`{3}/&&NR<'"$line_number"'{a++}END{print a}' "$file_save_path"`
    counts=$(awk '$0~/^`{3}/&&NR<'"${line_number}"'{a++}END{print a}' "${file_save_path}")
    #判斷出現次數，如果是奇數則丟棄，如果是偶數則保留
    #-z判斷是否爲空，第一個counts是空，但空取餘後是奇數，結果錯誤，故添加該判斷
    remainder=$(( counts%2 ))
    if [[ -z "${counts}" || ${remainder} -eq 0 ]]; then
        echo "${num}|${item}" >> "${temp_newfile}"
        let num+=1
    fi  #End if

done < "${temp_file}"   #End while

temp_newfile_sc2094=$(mktemp -t "${mktemp_format}") #存儲篩選後屬於標題的item
[[ -f "${temp_newfile}" ]] && cp "${temp_newfile}" "${temp_newfile_sc2094}"

# - 拼湊索引
while IFS="|" read -r line_number item; do
    #分別獲取左側，右側內容
    title_content=${item##*'#'}      #可同時兼容#後是否空格 tileContent (right)
    title_level=${item/"$title_content"}     # title_level    (left)

    #從文件開頭到該標題所在行，標題的出現次數，用於標記重複出現的標題，注意：不區分是幾級標題
    #使用符號$進行末尾匹配
    temp_title_content=$(echo "${title_content}" | sed -r 's@[[:punct:]]@@g')
    counts=$(awk '$0~/'"${temp_title_content}"'$/&&NR<='"${line_number}"'{a++}END{print a}' "${temp_newfile_sc2094}")
    len=${#title_level}     #通過${#var}獲取符號`#`的個數
    unset temp_title_content

    case "${len}" in
        2)
            pound_count=${flag_arr[2]}
            flag_arr[2]=$(( pound_count+1 ))
            flag_arr[3]=0
            flag_arr[4]=0
            flag_arr[5]=0
            flag_arr[6]=0
            flag=${flag_arr[2]}.
            ;;
        3)
            pound_count=${flag_arr[3]}
            flag_arr[3]=$(( pound_count+1 ))
            flag_arr[4]=0
            flag_arr[5]=0
            flag_arr[6]=0

            if [[ "${list_format}" -eq 0 ]]; then
                flag=${flag_arr[2]}.${flag_arr[3]}
            else
                flag="    *"    # 1個Tab(每個Tab爲4個空格)
            fi
            ;;
        4)
            pound_count=${flag_arr[4]}
            flag_arr[4]=$(( pound_count+1 ))
            flag_arr[5]=0
            flag_arr[6]=0

            if [[ "${list_format}" -eq 0 ]]; then
                flag=${flag_arr[2]}.${flag_arr[3]}.${flag_arr[4]}
            else
                flag="        *"    # 2個Tab(每個Tab爲4個空格)
            fi
            ;;
        5)
            pound_count=${flag_arr[5]}
            flag_arr[5]=$(( pound_count+1 ))
            flag_arr[6]=0

            if [[ "${list_format}" -eq 0 ]]; then
                flag=${flag_arr[2]}.${flag_arr[3]}.${flag_arr[4]}.${flag_arr[5]}
            else
                flag="            *"    # 3個Tab(每個Tab爲4個空格)
            fi
            ;;
        6)
            pound_count=${flag_arr[6]}
            flag_arr[6]=$(( pound_count+1 ))
            flag=${flag_arr[2]}.${flag_arr[3]}.${flag_arr[4]}.${flag_arr[5]}.${flag_arr[6]}

            if [[ "${list_format}" -eq 0 ]]; then
                flag=${flag_arr[2]}.${flag_arr[3]}.${flag_arr[4]}.${flag_arr[5]}.${flag_arr[6]}
            else
                flag="                *"   # 4個Tab(每個Tab爲4個空格)
            fi
            ;;
    esac    #End case

    #去除行首空格
    right="${title_content#"${title_content%%[![:space:]]*}"}"
    #查找所有匹配的特殊字符並刪除
    # temp=${right//[_#@$)(\{\}\`\~\!\$\%\^\&\*\+\=\:\;\'\"\<\>\.\,\;\?\/\\\|\[\]\，\：]}
    # https://www.gnu.org/software/sed/manual/html_node/Character-Classes-and-Bracket-Expressions.html
    # [:punct:]
    # ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~
    # sed -r -n 's@(\!|\"|\#|\$|%|&|'\''|\(|\)|\*|\+|\,|\-|\.|\/|\:|\;|<|\=|>|\?|\@|\[|\\|\]|\^|\_|`|\{|\||\}|~)@@g;p'
    if [[ "${is_for_git}" -eq 1 ]]; then
        temp=$(echo "${right}" | sed -r 's@(\!|\"|\#|\$|%|&|'\''|\(|\)|\*|\+|\,|\.|\/|\:|\;|<|\=|>|\?|\@|\[|\\|\]|\^|\_|`|\{|\||\}|~)@@g;s@\-+@-@g;s@[[:blank:]]+@ @g')
    else
        temp=$(echo "${right}" | sed -r 's@[[:punct:]]@@g;s@[[:blank:]]+@ @g')
    fi


    #將空格替換爲-
    temp=${temp//[' ']/-}
    #去除行首的- ${var/#PATTERN/SUBSTI}
    temp=${temp/#-}
    #去除行尾的- ${var/%PATTERN/USBSTI}
    temp=${temp/%-}
    #字符轉換爲小寫
    [[ "${is_for_git}" -eq 1 ]] && temp=${temp,,} #Gitlab/GitHub中TOC需全部轉換爲小寫，而Hexo則無需進行大小寫轉換
    #如果出現多次，則需在其後加上出現的次數，用符號 - 間隔
    if [[ "${counts}" -gt 1 ]]; then
        result=$temp'-'$((counts-1))
    else
        result="${temp}"
    fi
    # 將生成的TOC添加至文件末尾
    echo "${flag} [${right}](#${result})  " >> "${file_path}"     #GitHub中須在字串後添加2個空格，TOC才能自動換行
    # echo "${flag} "'['${right}'](#'${result}')  ' >> "${file_path}"     #GitHub中須在字串後添加2個空格，TOC才能自動換行

done < "${temp_newfile}"     #End while

[[ -f "${temp_file}" ]] && rm -f "${temp_file}"
[[ -f "${temp_newfile}" ]] && rm -f "${temp_newfile}"
[[ -f "${temp_newfile_sc2094}" ]] && rm -f "${temp_newfile_sc2094}"

[[ "${is_for_git}" -eq 1 ]] || toc_type='Hexo'
[[ "$list_format" -eq 1 ]] && toc_order_type='Unordered Lists'

[[ "${quiet_mode}" -eq 1 ]] || printf "Successfully create TOC for file ${c_blue}%s${c_normal}!\nUsage type is ${c_blue}%s${c_normal}, List format is ${c_blue}%s${c_normal}!\n" "${file_save_path}" "${toc_type}" "${toc_order_type}"


#########  3. EXIT Singal Processing  #########
# trap "commands" EXIT # execute command when exit from shell
funcTrapEXIT(){
    rm -rf /tmp/"${mktemp_format%%_*}"* 2>/dev/null
    unset is_for_git
    unset list_format
    unset toc_type
    unset toc_order_type
    unset file_path
}

trap funcTrapEXIT EXIT

# Script End

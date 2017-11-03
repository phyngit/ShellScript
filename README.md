# Personal Shell Script Collections

此Repo爲`MaxsSre`個人的Shell Script彙總，範圍涵蓋 **系統檢測**、**系統初始化配置**、**軟件安裝**、**個人小工具** 等。力求兼容主流GNU/Linux發行版，如[RHEL][rhel]/[CentOS][centos]/[Fedora][fedora], [Debian][debian]/[Ubuntu][ubuntu], [SLES][sles]/[OpenSUSE][opensuse]。


## Table Of Contents
1. [Documentation](#documentation)  
2. [GNU/Linux](#gnulinux)  
2.1 [Distro Relevant Info](#distro-relevant-info)  
2.2 [Post-installation Configuration](#post-installation-configuration)  
2.3 [System Tool](#system-tool)  
2.4 [Desktop Enviroment](#desktop-enviroment)  
3. [Software](#software)  
3.1 [Office Suites](#office-suites)  
3.2 [Container](#container)  
3.3 [Programming Language](#programming-language)  
3.4 [LEMP](#lemp)  
4. [Tools](#tools)  
5. [Bibliography](#bibliography)  


*注*：TOC Is Created By Shell Script [markdownTOCGeneration.sh](./assets/tool/markdownTOCGeneration.sh) In This Repository.


## Documentation
腳本使用[ShellCheck][shellcheck]工具檢驗，根據實際情況進行修正。

Shell Script目錄快速跳轉
1. [GNU/Linux](./assets/gnulinux "GNU/Linux系統相關")
2. [Software](./assets/software "軟件安裝、更新")
3. [Tools](./assets/tool "個人小工具")

在腳本後添加參數 `-h` 可查看具體使用說明，此處以腳本`osDebianFamilyPostInstallationConfiguration.sh`爲例

```bash
# bash gnuLinuxPostInstallationConfiguration -h
# curl -fsL https://raw.githubusercontent.com/MaxdSre/ShellScript/master/assets/gnulinux/gnuLinuxPostInstallationConfiguration.sh | sudo bash -s -- -h
Usage:
    script [options] ...
    script | sudo bash -s -- [options] ...

Post Installation Configuring RHEL/CentOS/Fedora/Debian/Ubuntu/OpenSUSE!
This script requires superuser privileges (eg. root, su).

[available option]
    -h    --help, show help info
    -H    --hosts, update /etc/hosts, for China mainland only
    -r    --replace repository source, for China mainland only
    -u username    --add user, create new user, password same to username
    -S    --sudo, grant user sudo privilege which is specified by '-u'
    -n hostname    --hostname, set hostname
    -t timezone    --timezone, set timezone (eg. America/New_York, Asia/Hong_Kong)
    -s    --ssh, enable sshd service (server side), default start on system startup
    -d    --disable root user remoting login (eg: via ssh), along with '-s'
    -k    --keygen, sshd service only allow ssh keygen, disable password, along with '-s'
    -g time    --grub timeout, set timeout num (second)
    -p [protocol:]ip:port    --proxy host (http|https|socks4|socks5), default protocol is http

```

**注意**：該倉庫中的Shell Script優先滿足`MaxsSre`個人使用需求。


## GNU/Linux
GNU/Linux System Relevant

### Distro Relevant Info
No.|漢語|English|Link
---|---|---|---
1|GNU/Linux發行版本信息偵測|Distro Info Detection|[link](./assets/gnulinux/gnuLinuxDistroVersionDetection.sh)
2|GNU/Linux發行版生命週期偵測|Life Cycle Detection|[link](/assets/gnulinux/gnuLinuxLifeCycleInfo.sh)
3|GNU/Linux官方產品文檔下載|Official Product Documentation(PDF/ePub)|[link](/assets/gnulinux/gnuLinuxOfficialDocumentationDownload.sh)


### Post-installation Configuration
No.|漢語|English|Link
---|---|---|---
1|GNU/Linux系統初始化設置|OS Post Installation Configuration|[link](./assets/gnulinux/gnuLinuxPostInstallationConfiguration.sh)

**說明**：
* [GNU/Linux系統初始化設置](./assets/gnulinux/gnuLinuxPostInstallationConfiguration.sh)同時支持[RHEL][rhel]/[CentOS][centos]/[Fedora][fedora]/[Debian][debian]/[Ubuntu][ubuntu]/[OpenSUSE][opensuse]等幾個重要的發行版本。


### System Tool
No.|漢語|English|Link
---|---|---|---
1|GNU/Linux監聽中的端口及對應服務偵測|Ports Being Used & Corresponding Services|[link](./assets/gnulinux/gnuLinuxPortUsedInfoDetection.sh)
2|GNU/Linux隨機端口號生成|Random Unuesd Port No. Generation|[link](./assets/gnulinux/gnuLinuxRandomUnusedPortGeneration.sh)


### Desktop Enviroment
No.|漢語|English|Link
---|---|---|---
1|GNOME桌面環境配置|GNOME 3 Desktop Enviroment Configuration|[link](./assets/gnulinux/GnomeDesktopConfiguration.sh)


## Software
Software Installation or Update

### Office Suites
No.|漢語|English|Link
---|---|---|---
1|SRWareIron瀏覽器|SRWareIron Browser|[link](./assets/software/SRWareIron.sh)
2|Mozilla火狐瀏覽器|Mozilla Firefox Browser|[link](./assets/software/MozillaFirefox.sh)
3|Libre Office辦公套件|Libre Office Suites|[link](./assets/software/LibreOffice.sh)
4|Mozilla ThunderBird郵件客戶端|Mozilla ThunderBird|[link](./assets/software/MozillaThunderbird.sh)
5|FileZilla FTP客戶端|FileZilla|[link](./assets/software/FileZilla.sh)
6|Atom文本編輯器|Atom Text Editor|[link](./assets/software/AtomEditor.sh)
7|Sublime Text 3文本編輯器|Sublime Text 3 Text Editor|[link](./assets/software/SublimeText.sh)

### Container
No.|漢語|English|Link
---|---|---|---
1|Docker CE容器|Docker|[link](./assets/software/Docker-CE.sh)

### Programming Language
No.|漢語|English|Link
---|---|---|---
1|Golang|Golang|[link](./assets/software/Golang.sh)
2|Node.js|Node.js|[link](./assets/software/Nodejs.sh)
3|Oracle JDK|Oracle SE JDK|[link](./assets/software/OracleSEJDK.sh)

### LEMP
No.|漢語|English|Link
---|---|---|---
1|Nginx Web服務器|Nginx Web Server|[link](./assets/software/NginxWebServer.sh)
2|MySQL/MariaDB/Percona數據庫|MySQL Variants|[link](./assets/software/MySQLVariants.sh)


## Tools
Personal Tools

No.|漢語|English|Link
---|---|---|---
1|MarkdownTOC目錄創建|Markdown TOC Creaetion|[link](./assets/tool/markdownTOCGeneration.sh)
2|從[GitHub][github]下載單個文件|Download Single File From [GitHub][github]|[link](./assets/tool/GitHubSingleFileDownload.sh)
3|代理IP提取|Extract Proxy IP|[link](./assets/tool/proxyIPExtractation.sh)
4|MySQL/MariaDB/Percona與GNU/Linux的支持[關係表][mysql_variants]|MySQL Variants Version & GNU/Linux Distro [Relation Table][mysql_variants]|[link](./assets/tool/mysqlVariantsVersionAndLinuxDistroRelationTable.sh)


## Bibliography
* [GNU Operating System](https://www.gnu.org/)


[rhel]:https://www.redhat.com/en "RedHat"
[centos]:https://www.centos.org/ "CentOS"
[fedora]:https://getfedora.org/ "Fedora"
[debian]:https://www.debian.org/ "Debian"
[ubuntu]:https://www.ubuntu.com/ "Ubuntu"
[sles]:https://www.suse.com/ "SUSE"
[opensuse]:https://www.opensuse.org/ "OpenSUSE"
[shellcheck]:https://www.shellcheck.net/ "ShellCheck"
[github]:https://github.com "GitHub"
[mysql_variants]:https://raw.githubusercontent.com/MaxdSre/ShellScript/master/sources/mysqlVariantsVersionAndLinuxDistroRelationTable.txt

<!-- Readme End -->

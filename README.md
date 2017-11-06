# Personal Shell Script Collections

[中文文檔](./README_CN.md)

This project is a collection of Shell Scripts written by myself, every script has a specific purpose. Its topics consist of **System Info Detection**, **System Post-installation Initialization**, **Software Installation & Configuration**, **Personal Gadgets**. I strive to increase the compatibility with mainstream GNU/Linux distributions, e.g. [RHEL][rhel]/[CentOS][centos]/[Fedora][fedora], [Debian][debian]/[Ubuntu][ubuntu], [SLES][sles]/[OpenSUSE][opensuse]。


## Table Of Contents
1. [Documentation](#documentation)  
1.1 [Help Info](#help-info)  
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


*Note*：TOC is created be shell script [markdownTOCGeneration.sh](./assets/tool/markdownTOCGeneration.sh) in this repository.


## Documentation
Scripts are checked by utility [ShellCheck][shellcheck], but partly following its references according the actual situation.

Shell Script TOC Jump TO
1. [GNU/Linux](./assets/gnulinux "GNU/Linux System Relevant")
2. [Software](./assets/software "Software Installation & Update")
3. [Tools](./assets/tool "Personal gadgets")

### Help Info
Adding parameter `-h` at the end of executing command to show the usage of the script being used. Take script `gnuLinuxOfficialDocumentationDownload.sh` as an example:

```bash
# bash gnuLinuxOfficialDocumentationDownload.sh -h
# curl -fsL https://raw.githubusercontent.com/MaxdSre/ShellScript/master/assets/gnulinux/gnuLinuxOfficialDocumentationDownload.sh.sh | sudo bash -s -- -h

Usage:
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
```

**Attention**: These Shell Scripts prioritize personal needs.

## GNU/Linux
GNU/Linux System Relevant

### Distro Relevant Info
No.|Simple Description|Link
---|---|---
1|GNU/Linux Distributions Info Detection|[link](./assets/gnulinux/gnuLinuxDistroVersionDetection.sh)
2|GNU/Linux Distributions Life Cycle Detection|[link](/assets/gnulinux/gnuLinuxLifeCycleInfo.sh)
3|GNU/Linux Distributions Official Documentations Download(PDF/ePub)|[link](/assets/gnulinux/gnuLinuxOfficialDocumentationDownload.sh)


### Post-installation Configuration
No.|Simple Description|Link
---|---|---
1|GNU/Linux System Post-installation Initialization & Configuration|[link](./assets/gnulinux/gnuLinuxPostInstallationConfiguration.sh)

**Note**： This script support the following important distributions [RHEL][rhel]/[CentOS][centos]/[Fedora][fedora]/[Debian][debian]/[Ubuntu][ubuntu]/[OpenSUSE][opensuse] at the same time.

### System Tool
No.|Simple Description|Link
---|---|---
1|GNU/Linux Ports Being Used & Corresponding Services Detection|[link](./assets/gnulinux/gnuLinuxPortUsedInfoDetection.sh)
2|GNU/Linux Random Available Unused Port No. Generation|[link](./assets/gnulinux/gnuLinuxRandomUnusedPortGeneration.sh)


### Desktop Enviroment
No.|Simple Description|Link
---|---|---
1|GNOME 3 Desktop Environment Configuration|[link](./assets/gnulinux/GnomeDesktopConfiguration.sh)


## Software
Software Installation or Update

### Office Suites
No.|Simple Description|Link
---|---|---
1|SRWareIron Browser (based on Chromium)|[link](./assets/software/SRWareIron.sh)
2|Mozilla Firefox Browser|[link](./assets/software/MozillaFirefox.sh)
3|Libre Office Suites|[link](./assets/software/LibreOffice.sh)
4|Mozilla ThunderBird Email Application|[link](./assets/software/MozillaThunderbird.sh)
5|FileZilla FTP|[link](./assets/software/FileZilla.sh)
6|Atom Text Editor|[link](./assets/software/AtomEditor.sh)
7|Sublime Text 3 Text Editor|[link](./assets/software/SublimeText.sh)

### Container
No.|Simple Description|Link
---|---|---
1|Docker Container|[link](./assets/software/Docker-CE.sh)

### Programming Language
No.|Simple Description|Link
---|---|---
1|Golang Programming Language|[link](./assets/software/Golang.sh)
2|Node.js|[link](./assets/software/Nodejs.sh)
3|Oracle SE JDK|[link](./assets/software/OracleSEJDK.sh)

### LEMP
No.|Simple Description|Link
---|---|---
1|Nginx Web Server|[link](./assets/software/NginxWebServer.sh)
2|MySQL/MariaDB/Percona DBMS|[link](./assets/software/MySQLVariants.sh)


## Tools
Personal Gadgets

No.|Simple Description|Link
---|---|---
1|Markdown TOC Creation|[link](./assets/tool/markdownTOCGeneration.sh)
2|Download Single File From [GitHub][github]|[link](./assets/tool/GitHubSingleFileDownload.sh)
3|Extract Proxy IP Extraction|[link](./assets/tool/proxyIPExtractation.sh)
4|[Relation Table](https://raw.githubusercontent.com/MaxdSre/ShellScript/master/sources/mysqlVariantsVersionAndLinuxDistroRelationTable.txt) Of GNU/Linux Distro & MySQL Variants Version|[link](./assets/tool/mysqlVariantsVersionAndLinuxDistroRelationTable.sh)


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


<!-- Readme End -->

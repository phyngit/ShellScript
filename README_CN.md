# 個人Shell Scirpt彙總

該項目是個人Shell Script的彙總，每一個腳本都有其特定的作用。腳本主題涵蓋 **系統信息檢測**、**系統初始化配置**、**軟件安裝配置**、**個人小工具** 等。力求兼容主流的GNU/Linux發行版，如[RHEL][rhel]/[CentOS][centos]/[Fedora][fedora], [Debian][debian]/[Ubuntu][ubuntu], [SLES][sles]/[OpenSUSE][opensuse]。


## 目錄索引
1. [說明](#說明)  
1.1 [幫助信息](#幫助信息)  
2. [GNU/Linux](#gnulinux)  
2.1 [發行版相關信息](#發行版相關信息)  
2.2 [系統初始化配置](#系統初始化配置)  
2.3 [系統工具](#系統工具)  
2.4 [桌面環境](#桌面環境)  
3. [應用程序](#應用程序)  
3.1 [辦公套件](#辦公套件)  
3.2 [容器](#容器)  
3.3 [編程語言](#編程語言)  
3.4 [LEMP開發環境](#lemp開發環境)  
4. [工具](#工具)  
5. [參考書目](#參考書目)  


*注*：TOC由倉庫中的腳本[markdownTOCGeneration.sh](./assets/tool/markdownTOCGeneration.sh)生成。


## 說明
腳本已使用[ShellCheck][shellcheck]工具檢驗，根據實際情況進行修正。

Shell Script目錄快速跳轉
1. [GNU/Linux](./assets/gnulinux "GNU/Linux系統相關")
2. [Software](./assets/software "軟件安裝、更新")
3. [Tools](./assets/tool "個人小工具")


### 幫助信息
在腳本執行命令後添加參數`-h`可查看具體使用說明，此處以腳本`gnuLinuxOfficialDocumentationDownload.sh`爲例：

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

**Attention**: 倉庫中的Shell Script優先滿足個人使用需求。

## GNU/Linux
GNU/Linux系統相關

### 發行版相關信息
No.|Simple Description|Link
---|---|---
1|GNU/Linux發行版本信息偵測|[link](./assets/gnulinux/gnuLinuxDistroVersionDetection.sh)
2|GNU/Linux發行版生命週期偵測|[link](/assets/gnulinux/gnuLinuxLifeCycleInfo.sh)
3|GNU/Linux發行版官方產品文檔下載(PDF/ePub)|[link](/assets/gnulinux/gnuLinuxOfficialDocumentationDownload.sh)


### 系統初始化配置
No.|Simple Description|Link
---|---|---
1|系統初始化設置|[link](./assets/gnulinux/gnuLinuxPostInstallationConfiguration.sh)

**說明**： 該腳本同時支持 [RHEL][rhel]/[CentOS][centos]/[Fedora][fedora]/[Debian][debian]/[Ubuntu][ubuntu]/[OpenSUSE][opensuse]等重要的發行版本。


### 系統工具
No.|Simple Description|Link
---|---|---
1|GNU/Linux監聽中的端口及對應服務偵測|[link](./assets/gnulinux/gnuLinuxPortUsedInfoDetection.sh)
2|GNU/Linux隨機端口號生成|[link](./assets/gnulinux/gnuLinuxRandomUnusedPortGeneration.sh)


### 桌面環境
No.|Simple Description|Link
---|---|---
1|GNOME桌面環境配置|[link](./assets/gnulinux/GnomeDesktopConfiguration.sh)


## 應用程序
軟件安裝與更新

### 辦公套件
No.|Simple Description|Link
---|---|---
1|SRWareIron瀏覽器|[link](./assets/software/SRWareIron.sh)
2|Mozilla火狐瀏覽器|[link](./assets/software/MozillaFirefox.sh)
3|Libre Office辦公套件|[link](./assets/software/LibreOffice.sh)
4|Mozilla ThunderBird郵件客戶端|[link](./assets/software/MozillaThunderbird.sh)
5|FileZilla FTP客戶端|[link](./assets/software/FileZilla.sh)
6|Atom文本編輯器|[link](./assets/software/AtomEditor.sh)
7|Sublime Text 3文本編輯器|[link](./assets/software/SublimeText.sh)


### 容器
No.|Simple Description|Link
---|---|---
1|Docker CE容器|[link](./assets/software/Docker-CE.sh)

### 編程語言
No.|Simple Description|Link
---|---|---
1|Golang|[link](./assets/software/Golang.sh)
2|Node.js|[link](./assets/software/Nodejs.sh)
3|Oracle SE JDK|[link](./assets/software/OracleSEJDK.sh)


### LEMP開發環境
No.|Simple Description|Link
---|---|---
1|Nginx Web服務器|[link](./assets/software/NginxWebServer.sh)
2|MySQL/MariaDB/Percona數據庫|[link](./assets/software/MySQLVariants.sh)


## 工具
個人小工具

No.|Simple Description|Link
---|---|---
1|Markdown TOC目錄創建|[link](./assets/tool/markdownTOCGeneration.sh)
2|從[GitHub][github]下載單個文件|[link](./assets/tool/GitHubSingleFileDownload.sh)
3|代理IP提取|[link](./assets/tool/proxyIPExtractation.sh)
4|MySQL/MariaDB/Percona與GNU/Linux的支持[關係表](https://raw.githubusercontent.com/MaxdSre/ShellScript/master/sources/mysqlVariantsVersionAndLinuxDistroRelationTable.txt)|[link](./assets/tool/mysqlVariantsVersionAndLinuxDistroRelationTable.sh)


## 參考書目
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

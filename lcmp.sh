#!/bin/bash
#
# This is a Shell script for Server initialization and
# LCMP (Linux + Caddy + MariaDB/MySQL + PHP) installation
#
# Supported OS:
# Enterprise Linux 8 (CentOS 8, RHEL 8, Rocky Linux 8, AlmaLinux 8, Oracle Linux 8, openAnolis 8, OpenCloudOS 8)
# Enterprise Linux 9 (CentOS 9, RHEL 9, Rocky Linux 9, AlmaLinux 9, Oracle Linux 9, OpenCloudOS 9)
# Debian 10
# Debian 11
# Debian 12
# Ubuntu 20.04
# Ubuntu 22.04
#
# Copyright (C) 2023 Cloud.Fan <mail@cloud.fan>
#

# 定义变量
phpmyadmin_ver='5.2.1'

trap _exit INT QUIT TERM

cur_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

_red() {
    printf '\033[1;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[1;31;33m%b\033[0m' "$1"
}

_printargs() {
    printf -- "%s" "[$(date)] "
    printf -- "%s" "$1"
    printf "\n"
}

_info() {
    _printargs "$@"
}

_warn() {
    printf -- "%s" "[$(date)] "
    _yellow "$1"
    printf "\n"
}

_error() {
    printf -- "%s" "[$(date)] "
    _red "$1"
    printf "\n"
    exit 2
}

_exit() {
    printf "\n"
    _red "$0 has been terminated."
    printf "\n"
    exit 1
}

_exists() {
    local cmd="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$cmd" >/dev/null 2>&1
    else
        which "$cmd" >/dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

_error_detect() {
    local cmd="$1"
    _info "${cmd}"
    if ! eval "${cmd}" 1>/dev/null; then
        _error "Execution command (${cmd}) failed, please check it and try again."
    fi
}

check_sys() {
    local value="$1"
    local release=''
    if [ -f /etc/redhat-release ]; then
        release="rhel"
    elif grep -Eqi "debian" /etc/issue; then
        release="debian"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="rhel"
    elif grep -Eqi "debian" /proc/version; then
        release="debian"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="rhel"
    fi
    if [ "${value}" == "${release}" ]; then
        return 0
    else
        return 1
    fi
}

get_char() {
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2>/dev/null
    stty -raw
    stty echo
    stty "${SAVEDSTTY}"
}

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

get_rhelversion() {
    if check_sys rhel; then
        local version
        local code=$1
        local main_ver
        version=$(get_opsy)
        main_ver=$(echo "${version}" | grep -oE "[0-9.]+")
        if [ "${main_ver%%.*}" == "${code}" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

get_debianversion() {
    if check_sys debian; then
        local version
        local code=$1
        local main_ver
        version=$(get_opsy)
        main_ver=$(echo "${version}" | grep -oE "[0-9.]+")
        if [ "${main_ver%%.*}" == "${code}" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

get_ubuntuversion() {
    if check_sys ubuntu; then
        local version
        local code=$1
        version=$(get_opsy)
        if echo "${version}" | grep -q "${code}"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

check_kernel_version() {
    local kernel_version
    kernel_version=$(uname -r | cut -d- -f1)
    if version_ge "${kernel_version}" 4.9; then
        return 0
    else
        return 1
    fi
}

check_bbr_status() {
    local param
    param=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "${param}" == "bbr" ]]; then
        return 0
    else
        return 1
    fi
}

## Anolis 兼容

# 检查 /etc/anolis-release 文件是否存在
if [ -f /etc/anolis-release ]; then
    # 如果文件存在，则创建一个指向它的软链接
    ln -s /etc/anolis-release /etc/redhat-release
fi

# Check user
[ ${EUID} -ne 0 ] && _red "This script must be run as root!\n" && exit 1

# Check OS
if  ! get_rhelversion 8 && ! get_rhelversion 9 &&
    ! get_debianversion 10 && ! get_debianversion 11 && ! get_debianversion 12 &&
    ! get_ubuntuversion 20.04 && ! get_ubuntuversion 22.04; then
    _error "Not supported OS, please change OS to Enterprise Linux 8+ or Debian 10+ or Ubuntu 20.04+ and try again."
fi

# Install MariaDB

while true; do
    _info "Please choose a version of the MariaDB:"
    _info "$(_green 1). Do not install the MariaDB database"
    _info "$(_green 2). MariaDB 10.5"
    _info "$(_green 3). MariaDB 10.6"
    _info "$(_green 4). MariaDB 10.11(recommended)"
    _info "$(_green 5). MariaDB 11.3(unstable)"
    read -r -p "[$(date)] Please input a number: (Default 4) " mysql_version
    [ -z "${mysql_version}" ] && mysql_version=4
    case "${mysql_version}" in
    1)
        mariadb_ver="0"
        break
        ;;
    2)
        mariadb_ver="10.5"
        break
        ;;
    3)
        mariadb_ver="10.6"
        break
        ;;
    4)
        mariadb_ver="10.11"
        break
        ;;
    5)
        mariadb_ver="11.3"
        break
        ;;
    *)
        _info "Input error! Please only input a number 1 2 3 4 5"
        ;;
    esac
done

# Set MariaDB root password
if [ "$mariadb_ver" != "0" ]; then
    _info "Please input the root password of MariaDB:"
    read -r -p "[$(date)] (Default password: lcmp-net):" db_pass
    if [ -z "${db_pass}" ]; then
        db_pass="lcmp-net"
    fi
    _info "---------------------------"
    _info "Password = $(_red "${db_pass}")"
    _info "---------------------------"
fi

# Choose PHP version
while true; do
    _info "Please choose a version of the PHP:"
    _info "$(_green 1). PHP 7.4"
    _info "$(_green 2). PHP 8.0"
    _info "$(_green 3). PHP 8.1"
    _info "$(_green 4). PHP 8.2"
    _info "$(_green 5). PHP 8.3"
    read -r -p "[$(date)] Please input a number: (Default 4) " php_version
    [ -z "${php_version}" ] && php_version=4
    case "${php_version}" in
    1)
        php_ver="7.4"
        if check_sys rhel; then
            remi_php="php74"
        fi
        break
        ;;
    2)
        php_ver="8.0"
        if check_sys rhel; then
            remi_php="php80"
        fi
        break
        ;;
    3)
        php_ver="8.1"
        if check_sys rhel; then
            remi_php="php81"
        fi
        break
        ;;
    4)
        php_ver="8.2"
        if check_sys rhel; then
            remi_php="php82"
        fi
        break
        ;;
    5)
        php_ver="8.3"
        if check_sys rhel; then
            remi_php="php83"
        fi
        break
        ;;
    *)
        _info "Input error! Please only input a number 1 2 3 4 5"
        ;;
    esac
done
_info "---------------------------"
_info "PHP version = $(_red "${php_ver}")"
_info "---------------------------"

## 是否使用中国网络加速

_info "Use a mirror server to download files"
while true; do
    _info "$(_green 1). Source station"
    _info "$(_green 2). China Mirror station"
    read -r -p "[$(date)] Please input a number: (Default 1) " use_cnop
    [ -z "${use_cnop}" ] && use_cnop=1
    case "${use_cnop}" in
    1)
        use_cn="n"
        break
        ;;
    2)
        use_cn="y"
        break
        ;;
    *)
        _info "Input error! Please only input a number 1 2"
        ;;
    esac
done


_info "Press any key to start...or Press Ctrl+C to cancel"
char=$(get_char)

_info "Server initialization start"
_error_detect "rm -f /etc/localtime"
_error_detect "ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
if check_sys rhel; then
    if [ -f /etc/anolis-release ]; then
        yum install -yq yum-utils epel-aliyuncs-release
    else
        yum install -yq yum-utils epel-release
    fi
    _error_detect "yum-config-manager --enable epel"
    if get_rhelversion 8; then
        yum-config-manager --enable powertools >/dev/null 2>&1 || yum-config-manager --enable PowerTools >/dev/null 2>&1
        _info "Set enable PowerTools Repository completed"
        rhelver="8"
    fi
    if get_rhelversion 9; then
        _error_detect "yum-config-manager --enable crb"
        _info "Set enable CRB Repository completed"
        echo "set enable-bracketed-paste off" >>/etc/inputrc
        rhelver="9"
    fi
    _error_detect "yum install -yq vim tar zip unzip net-tools bind-utils screen git virt-what wget whois firewalld mtr traceroute iftop htop jq tree"
    if [ -s "/etc/selinux/config" ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's@^SELINUX.*@SELINUX=disabled@g' /etc/selinux/config
        setenforce 0
        _info "Disable SElinux completed"
    fi
    if systemctl status firewalld >/dev/null 2>&1; then
        default_zone="$(firewall-cmd --get-default-zone)"
        firewall-cmd --permanent --add-service=https --zone="${default_zone}" >/dev/null 2>&1
        firewall-cmd --permanent --add-service=http --zone="${default_zone}" >/dev/null 2>&1
        # Enabled udp 443 port for Caddy HTTP/3 feature
        firewall-cmd --permanent --zone="${default_zone}" --add-port=443/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        sed -i 's@AllowZoneDrifting=yes@AllowZoneDrifting=no@' /etc/firewalld/firewalld.conf
        _error_detect "systemctl restart firewalld"
        _info "Set firewall completed"
    else
        _warn "firewalld looks like not running, skip setting up firewall"
    fi
elif check_sys debian || check_sys ubuntu; then
    _error_detect "apt-get update"
    _error_detect "apt-get -yq install lsb-release ca-certificates curl"
    _error_detect "apt-get -yq install vim tar zip unzip net-tools bind9-utils screen git virt-what wget whois mtr traceroute iftop htop jq tree"
    if ufw status >/dev/null 2>&1; then
        _error_detect "ufw allow http"
        _error_detect "ufw allow https"
        _error_detect "ufw allow 443/udp"
    else
        _warn "ufw looks like not running, skip setting up firewall"
    fi
fi

if check_kernel_version; then
    if ! check_bbr_status; then
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
        cat >>/etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 2500000
EOF
        sysctl -p >/dev/null 2>&1
        _info "Set bbr completed"
    fi
fi

if systemctl status systemd-journald >/dev/null 2>&1; then
    sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
    sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=16M/' /etc/systemd/journald.conf
    sed -i 's/^#\?RuntimeMaxUse=.*/RuntimeMaxUse=16M/' /etc/systemd/journald.conf
    _error_detect "systemctl restart systemd-journald"
    _info "Set systemd-journald completed"
fi

echo
netstat -nxtulpe
echo
_info "Server initialization completed"
sleep 3
clear
_info "LCMP (Linux + Caddy + MariaDB + PHP) installation start"
if check_sys rhel; then

    if use_cn="y"; then
        yum-config-manager --add-repo https://gitee.com/yunonl/lcmp/raw/main/conf/caddy.repo
    else
        _error_detect "yum install -yq dnf-plugins-core"
        _error_detect "yum copr enable -yq @caddy/caddy"
    fi
    _error_detect "yum install -yq caddy"
elif check_sys debian || check_sys ubuntu; then
    _error_detect "apt-get install -y debian-keyring debian-archive-keyring apt-transport-https"
    _error_detect "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    if use_cn="y"; then

        _error_detect "curl -1sLf 'https://gitee.com/yunonl/lcmp/raw/main/conf/caddy.debian.deb.txt' | sudo tee -a /etc/apt/sources.list.d/caddy-stable.list"
    else
        _error_detect "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee -a /etc/apt/sources.list.d/caddy-stable.list" 
    fi
    _error_detect "apt-get update"
    _error_detect "apt-get install -y caddy"
fi
_info "Caddy installation completed"

_error_detect "mkdir -p /data/www/default"
_error_detect "mkdir -p /var/log/caddy/"
_error_detect "mkdir -p /etc/caddy/conf.d/"
_error_detect "mkdir /etc/lcmp"
_error_detect "chown -R caddy:caddy /var/log/caddy/"
cat >/etc/caddy/Caddyfile <<EOF
{
	admin off
}
import /etc/caddy/conf.d/*.conf
EOF
_error_detect "cp -f ${cur_dir}/conf/index.html /data/www/default/"
_error_detect "cp -f ${cur_dir}/conf/x.php /data/www/default/"
_error_detect "cp -f ${cur_dir}/conf/vhost.html /etc/lcmp/"
_error_detect "cp -f ${cur_dir}/conf/lcmp.png /data/www/default/"
_info "Set Caddy completed"


## 安装数据库

if [ "$mariadb_ver" != "0" ]; then
    _error_detect "wget -qO mariadb_repo_setup.sh https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
    _error_detect "chmod +x mariadb_repo_setup.sh"
    if [ -f /etc/anolis-release ]; then
        _error_detect "./mariadb_repo_setup.sh --mariadb-server-version=mariadb-${mariadb_ver} --os-type=rhel --os-version=${rhelver} >/dev/null 2>&1"
    else
        _error_detect "./mariadb_repo_setup.sh --mariadb-server-version=mariadb-${mariadb_ver} >/dev/null 2>&1"
    fi
    _error_detect "rm -f mariadb_repo_setup.sh"
    if check_sys rhel; then
            if use_cn="y"; then
                _error_detect "sed -i "s|https://dlm.mariadb.com/repo/mariadb-server/${mariadb_ver}/yum/rhel/|https://mirrors.aliyun.com/mariadb/yum/${mariadb_ver}/rhel/|g" /etc/yum.repos.d/mariadb.repo"
            fi
        _error_detect "yum install -y MariaDB-common MariaDB-server MariaDB-client MariaDB-shared MariaDB-backup"
        mariadb_cnf="/etc/my.cnf.d/server.cnf"
    elif check_sys debian || check_sys ubuntu; then
            if use_cn="y"; then
                sed -i 's|https://dlm.mariadb.com/repo/mariadb-server/'${mariadb_ver}'/repo/debian bookworm main|https://mirrors.aliyun.com/mariadb/repo/'${mariadb_ver}'/debian bookworm main|g' /etc/apt/sources.list.d/mariadb.list
            fi
        _error_detect "apt-get install -y mariadb-common mariadb-server mariadb-client mariadb-backup"
        mariadb_cnf="/etc/mysql/mariadb.conf.d/50-server.cnf"
    fi
    _info "MariaDB installation completed"

    lnum=$(sed -n '/\[mysqld\]/=' "${mariadb_cnf}")
    sed -i "${lnum}ainnodb_buffer_pool_size = 100M\nmax_allowed_packet = 1024M\nnet_read_timeout = 3600\nnet_write_timeout = 3600" "${mariadb_cnf}"
    lnum=$(sed -n '/\[mariadb\]/=' "${mariadb_cnf}")
    sed -i "${lnum}acharacter-set-server = utf8mb4\n\n\[client-mariadb\]\ndefault-character-set = utf8mb4" "${mariadb_cnf}"
    _error_detect "systemctl start mariadb"
    /usr/bin/mysql -e "grant all privileges on *.* to root@'127.0.0.1' identified by \"${db_pass}\" with grant option;"
    /usr/bin/mysql -e "grant all privileges on *.* to root@'localhost' identified by \"${db_pass}\" with grant option;"
    /usr/bin/mysql -uroot -p"${db_pass}" 2>/dev/null <<EOF
    drop database if exists test;
    delete from mysql.db where user='';
    delete from mysql.db where user='PUBLIC';
    delete from mysql.user where user='';
    delete from mysql.user where user='mysql';
    delete from mysql.user where user='PUBLIC';
    flush privileges;
    exit
EOF
    _error_detect "cd /data/www/default"

    # Install phpMyAdmin
    if use_cn="y"; then
        _error_detect "wget -qO pma.tar.gz https://pma.mirrors.cloud.fan/phpMyAdmin/${phpmyadmin_ver}/phpMyAdmin-${phpmyadmin_ver}-all-languages.tar.gz"
    else
        _error_detect "wget -qO pma.tar.gz https://files.phpmyadmin.net/phpMyAdmin/${phpmyadmin_ver}/phpMyAdmin-${phpmyadmin_ver}-all-languages.tar.gz"
    fi
    _error_detect "tar zxf pma.tar.gz"
    _error_detect "rm -f pma.tar.gz"
    _error_detect "mv phpMyAdmin-${phpmyadmin_ver}-all-languages pma"
    _error_detect "cd ${cur_dir}"
    _info "/usr/bin/mysql -uroot -p 2>/dev/null < /data/www/default/pma/sql/create_tables.sql"
    /usr/bin/mysql -uroot -p"${db_pass}" 2>/dev/null </data/www/default/pma/sql/create_tables.sql
    _info "Set MariaDB ${mariadb_ver} completed"
fi

if check_sys rhel; then
    php_conf="/etc/opt/remi/${remi_php}/php-fpm.d/www.conf"
    php_ini="/etc/opt/remi/${remi_php}/php.ini"
    php_fpm="${remi_php}-php-fpm"
    php_sock="unix//var/opt/remi/${remi_php}/run/php-fpm/www.sock"
    sock_location="/var/lib/mysql/mysql.sock"

    if use_cn="y"; then
        if [ -f /etc/anolis-release ]; then
            _error_detect "wget https://mirrors.ustc.edu.cn/remi/enterprise/remi-release-${rhelver}.rpm"
            _error_detect "rpm -ivh --nodeps --force remi-release-${rhelver}.rpm"
            _error_detect "rm -f remi-release-${rhelver}.rpm"
        else
            _error_detect "yum install -yq https://mirrors.ustc.edu.cn/remi/enterprise/remi-release-${rhelver}.rpm"
        fi
    else
        if [ -f /etc/anolis-release ]; then
            _error_detect "wget https://rpms.remirepo.net/enterprise/remi-release-${rhelver}.rpm"
             _error_detect "rpm -ivh --nodeps --force remi-release-${rhelver}.rpm"
             _error_detect "rm -f remi-release-${rhelver}.rpm"
        else
            _error_detect "yum install -yq https://rpms.remirepo.net/enterprise/remi-release-${rhelver}.rpm"
        fi
    fi
    
    _error_detect "yum install -yq ${remi_php}"

    _error_detect "yum install -yq ${remi_php}-php-common ${remi_php}-php-fpm ${remi_php}-php-cli ${remi_php}-php-bcmath ${remi_php}-php-embedded ${remi_php}-php-gd ${remi_php}-php-imap ${remi_php}-php-mysqlnd ${remi_php}-php-dba ${remi_php}-php-pdo ${remi_php}-php-pdo-dblib"
    _error_detect "yum install -yq ${remi_php}-php-pgsql ${remi_php}-php-enchant ${remi_php}-php-gmp ${remi_php}-php-intl ${remi_php}-php-ldap ${remi_php}-php-snmp ${remi_php}-php-soap ${remi_php}-php-tidy ${remi_php}-php-opcache ${remi_php}-php-process"
    _error_detect "yum install -yq ${remi_php}-php-pspell ${remi_php}-php-shmop ${remi_php}-php-sodium ${remi_php}-php-ffi ${remi_php}-php-brotli ${remi_php}-php-lz4 ${remi_php}-php-xz ${remi_php}-php-zstd ${remi_php}-php-pecl-rar"
    _error_detect "yum install -yq ${remi_php}-php-pecl-imagick-im7 ${remi_php}-php-pecl-zip ${remi_php}-php-pecl-grpc ${remi_php}-php-pecl-yaml ${remi_php}-php-pecl-uuid composer"
elif check_sys debian || check_sys ubuntu; then
    php_conf="/etc/php/${php_ver}/fpm/pool.d/www.conf"
    php_ini="/etc/php/${php_ver}/fpm/php.ini"
    php_fpm="php${php_ver}-fpm"
    php_sock="unix//run/php/php${php_ver}-fpm.sock"
    sock_location="/run/mysqld/mysqld.sock"
    if check_sys debian; then
        _error_detect "curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg"
        if use_cn="y"; then
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://mirror.sjtu.edu.cn/sury/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
        else
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
        fi
    fi
    if check_sys ubuntu; then
        _error_detect "add-apt-repository -y ppa:ondrej/php"
        if use_cn="y"; then
            find /etc/apt/sources.list.d/ -type f -name "*.list" -exec  sed  -i.bak -r  's#deb(-src)?\s*http(s)?://ppa.launchpad.net#deb\1 http\2://launchpad.proxy.ustclug.org#ig' {} \;
        fi
    fi
    _error_detect "apt-get update"
    _error_detect "apt-get install -y php${php_ver}-common php${php_ver}-cli php${php_ver}-fpm php${php_ver}-opcache php${php_ver}-readline"
    _error_detect "apt-get install -y libphp${php_ver}-embed php${php_ver}-bcmath php${php_ver}-gd php${php_ver}-imap php${php_ver}-mysql php${php_ver}-dba php${php_ver}-sybase"
    _error_detect "apt-get install -y php${php_ver}-pgsql php${php_ver}-enchant php${php_ver}-gmp php${php_ver}-intl php${php_ver}-ldap php${php_ver}-snmp php${php_ver}-soap"
    _error_detect "apt-get install -y php${php_ver}-mbstring php${php_ver}-curl php${php_ver}-pspell php${php_ver}-xml php${php_ver}-zip php${php_ver}-bz2 php${php_ver}-lz4 php${php_ver}-zstd"
    _error_detect "apt-get install -y php${php_ver}-tidy php${php_ver}-sqlite3 php${php_ver}-imagick php${php_ver}-grpc php${php_ver}-yaml php${php_ver}-uuid"
    _error_detect "mkdir -m770 -p /var/lib/php/${php_ver}/{session,wsdlcache,opcache}"
fi
_error_detect "echo "${php_ver}" > /etc/lcmp/phpver"
_error_detect "echo "${remi_php}" > /etc/lcmp/remiphpver"

_info "PHP installation completed"

sed -i "s@^user.*@user = caddy@" "${php_conf}"
sed -i "s@^group.*@group = caddy@" "${php_conf}"
if check_sys rhel; then
    sed -i "s@^listen.acl_users.*@listen.acl_users = apache,caddy@" "${php_conf}"
    sed -i "s@^;php_value\[opcache.file_cache\].*@php_value\[opcache.file_cache\] = /var/opt/remi/${remi_php}/lib/php/opcache@" "${php_conf}"
elif check_sys debian || check_sys ubuntu; then
    sed -i "s@^listen.owner.*@;&@" "${php_conf}"
    sed -i "s@^listen.group.*@;&@" "${php_conf}"
    sed -i "s@^;listen.acl_users.*@listen.acl_users = caddy@" "${php_conf}"
    sed -i "s@^;listen.allowed_clients.*@listen.allowed_clients = 127.0.0.1@" "${php_conf}"
    sed -i "s@^pm.max_children.*@pm.max_children = 50@" "${php_conf}"
    sed -i "s@^pm.start_servers.*@pm.start_servers = 5@" "${php_conf}"
    sed -i "s@^pm.min_spare_servers.*@pm.min_spare_servers = 5@" "${php_conf}"
    sed -i "s@^pm.max_spare_servers.*@pm.max_spare_servers = 35@" "${php_conf}"
    sed -i "s@^;slowlog.*@slowlog = /var/log/www-slow.log@" "${php_conf}"
    sed -i "s@^;php_admin_value\[error_log\].*@php_admin_value[error_log] = /var/log/www-error.log@" "${php_conf}"
    sed -i "s@^;php_admin_flag\[log_errors\].*@php_admin_flag[log_errors] = on@" "${php_conf}"
    cat >>"${php_conf}" <<EOF
php_value[session.save_handler] = files
php_value[session.save_path]    = /var/lib/php/${php_ver}/session
php_value[soap.wsdl_cache_dir]  = /var/lib/php/${php_ver}/wsdlcache
php_value[opcache.file_cache]   = /var/lib/php/${php_ver}/opcache
EOF
fi
sed -i "s@^disable_functions.*@disable_functions = passthru,exec,shell_exec,system,chroot,chgrp,chown,proc_open,proc_get_status,ini_alter,ini_alter,ini_restore@" "${php_ini}"
sed -i "s@^max_execution_time.*@max_execution_time = 300@" "${php_ini}"
sed -i "s@^max_input_time.*@max_input_time = 300@" "${php_ini}"
sed -i "s@^post_max_size.*@post_max_size = 128M@" "${php_ini}"
sed -i "s@^upload_max_filesize.*@upload_max_filesize = 128M@" "${php_ini}"
sed -i "s@^expose_php.*@expose_php = Off@" "${php_ini}"
sed -i "s@^short_open_tag.*@short_open_tag = On@" "${php_ini}"
sed -i "s#mysqli.default_socket.*#mysqli.default_socket = ${sock_location}#" "${php_ini}"
sed -i "s#pdo_mysql.default_socket.*#pdo_mysql.default_socket = ${sock_location}#" "${php_ini}"
if check_sys rhel; then
    _error_detect "chown root:caddy /var/opt/remi/${remi_php}/lib/php/session"
    _error_detect "chown root:caddy /var/opt/remi/${remi_php}/lib/php/wsdlcache"
    _error_detect "chown root:caddy /var/opt/remi/${remi_php}/lib/php/opcache"
elif check_sys debian || check_sys ubuntu; then 
    _error_detect "chown root:caddy /var/lib/php/${php_ver}/session"
    _error_detect "chown root:caddy /var/lib/php/${php_ver}/wsdlcache"
    _error_detect "chown root:caddy /var/lib/php/${php_ver}/opcache"
fi
_info "Set PHP completed"

cat >/etc/caddy/conf.d/default.conf <<EOF
:80 {
	header {
		Strict-Transport-Security "max-age=31536000; preload"
		X-Content-Type-Options nosniff
		X-Frame-Options SAMEORIGIN
	}
	root * /data/www/default
	encode gzip
	php_fastcgi ${php_sock}
	file_server {
		index index.html
	}
	log {
		output file /var/log/caddy/access.log {
			roll_size 100mb
			roll_keep 3
			roll_keep_for 7d
		}
	}
}
EOF

_error_detect "cp -f ${cur_dir}/conf/lcmp /usr/bin/"
_error_detect "chmod 755 /usr/bin/lcmp"
_error_detect "chown -R caddy:caddy /data/www"
_error_detect "systemctl daemon-reload"
_error_detect "systemctl start ${php_fpm}"
_error_detect "systemctl start caddy"
sleep 3
_error_detect "systemctl restart ${php_fpm}"
_error_detect "systemctl restart caddy"
sleep 1
_info "systemctl enable mariadb"
systemctl enable mariadb >/dev/null 2>&1
_info "systemctl enable ${php_fpm}"
systemctl enable "${php_fpm}" >/dev/null 2>&1
_info "systemctl enable caddy"
systemctl enable caddy >/dev/null 2>&1
pkill -9 gpg-agent
_info "systemctl status mariadb"
systemctl --no-pager -l status mariadb
_info "systemctl status ${php_fpm}"
systemctl --no-pager -l status "${php_fpm}"
_info "systemctl status caddy"
systemctl --no-pager -l status caddy
echo
netstat -nxtulpe

## 定义IP地址变量
ipAddress=`curl -s -4 https://ping0.cc`
echo
_info "LCMP (Linux + Caddy + MariaDB + PHP) installation completed"
_info "    __    ________  _______               __ "
_info "   / /   / ____/  |/  / __ \  ____  ___  / /_"
_info "  / /   / /   / /|_/ / /_/ / / __ \/ _ \/ __/"
_info " / /___/ /___/ /  / / ____/ / / / /  __/ /_  "
_info "/_____/\____/_/  /_/_/   (_)_/ /_/\___/\__/  "
_info "Web Demo Site: http://${ipAddress}"
_info "Web Demo Dir: /data/www/default"
_info "Caddy Server Config: /etc/caddy/"
                                             

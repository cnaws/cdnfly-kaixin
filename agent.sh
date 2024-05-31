#!/bin/bash -x

# 遇到错误时退出
set -o errexit

# 判断系统版本
check_sys() {
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''
    local packageSupport=''

    # 检查release、systemPackage和packageSupport是否已被设置
    if [[ "$release" == "" ]] || [[ "$systemPackage" == "" ]] || [[ "$packageSupport" == "" ]]; then

        # 识别CentOS
        if [[ -f /etc/redhat-release ]]; then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        # 识别Debian
        elif grep -q -E -i "debian" /etc/issue; then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        # 识别Ubuntu
        elif grep -q -E -i "ubuntu" /etc/issue; then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        # 识别Red Hat/CentOS
        elif grep -q -E -i "centos|red hat|redhat" /etc/issue; then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        # 识别Debian（通过/proc/version）
        elif grep -q -E -i "debian" /proc/version; then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        # 识别Ubuntu（通过/proc/version）
        elif grep -q -E -i "ubuntu" /proc/version; then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        # 识别Red Hat/CentOS（通过/proc/version）
        elif grep -q -E -i "centos|red hat|redhat" /proc/version; then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        # 其他系统
        else
            release="other"
            systemPackage="other"
            packageSupport=false
        fi
    fi

    # 输出系统检测结果
    echo -e "release=$release\nsystemPackage=$systemPackage\npackageSupport=$packageSupport\n" > /tmp/ezhttp_sys_check_result

    # 根据不同的检测类型返回结果
    if [[ $checkType == "sysRelease" ]]; then
        [[ "$value" == "$release" ]]
        return
    elif [[ $checkType == "packageManager" ]]; then
        [[ "$value" == "$systemPackage" ]]
        return
    elif [[ $checkType == "packageSupport" ]]; then
        $packageSupport
        return
    fi
}

# 安装依赖
install_depend() {
    if check_sys sysRelease ubuntu; then
        apt-get update
        apt-get -y install wget python-minimal
    elif check_sys sysRelease centos; then
        yum install -y wget python
    fi
}

# 下载文件
download() {
    local url1=$1
    local url2=$2
    local filename=$3

    # 获取下载速度
    speed1=$(curl -m 5 -L -s -w '%{speed_download}' "$url1" -o /dev/null || true)
    speed1=${speed1%%.*}
    speed2=$(curl -m 5 -L -s -w '%{speed_download}' "$url2" -o /dev/null || true)
    speed2=${speed2%%.*}
    echo "speed1: $speed1"
    echo "speed2: $speed2"
    url="$url1\n$url2"
    if [[ $speed2 -gt $speed1 ]]; then
        url="$url2\n$url1"
    fi
    echo -e $url | while read l; do
        echo "using url: $l"
        wget --dns-timeout=5 --connect-timeout=5 --read-timeout=10 --tries=2 "$l" -O "$filename" && break
    done
}

# 获取系统版本
get_sys_ver() {
cat > /tmp/sys_ver.py <<EOF
import platform
import re

sys_ver = platform.platform()
sys_ver = re.sub(r'.*-with-(.*)-.*',"\g<1>",sys_ver)
if sys_ver.startswith("centos-7"):
    sys_ver = "centos-7"
if sys_ver.startswith("centos-6"):
    sys_ver = "centos-6"
print(sys_ver)
EOF
python /tmp/sys_ver.py
}

# 同步时间
sync_time() {
    echo "start to sync time and add sync command to cronjob..."

    if check_sys sysRelease ubuntu || check_sys sysRelease debian; then
        apt-get -y update
        apt-get -y install ntpdate wget
        /usr/sbin/ntpdate -u pool.ntp.org || true
        ! grep -q "/usr/sbin/ntpdate -u pool.ntp.org" /var/spool/cron/crontabs/root > /dev/null 2>&1 && echo '*/10 * * * * /usr/sbin/ntpdate -u pool.ntp.org > /dev/null 2>&1 || (date_str=`curl update.cdnfly.cn/common/datetime` && timedatectl set-ntp false && echo $date_str && timedatectl set-time "$date_str" )'  >> /var/spool/cron/crontabs/root
        service cron restart
    elif check_sys sysRelease centos; then
        yum -y install ntpdate wget
        /usr/sbin/ntpdate -u pool.ntp.org || true
        ! grep -q "/usr/sbin/ntpdate -u pool.ntp.org" /var/spool/cron/root > /dev/null 2>&1 && echo '*/10 * * * * /usr/sbin/ntpdate -u pool.ntp.org > /dev/null 2>&1 || (date_str=`curl update.cdnfly.cn/common/datetime` && timedatectl set-ntp false && echo $date_str && timedatectl set-time "$date_str" )' >> /var/spool/cron/root
        service crond restart
    fi

    # 设置时区
    rm -f /etc/localtime
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    /sbin/hwclock -w
}

# 判断系统版本是否为Ubuntu 16.04或CentOS 7
need_sys() {
    SYS_VER=$(python -c "import platform; import re; sys_ver = platform.platform(); sys_ver = re.sub(r'.*-with-(.*)-.*','\\g<1>',sys_ver); print(sys_ver);")
    if [[ $SYS_VER =~ "Ubuntu-16.04" ]]; then
        echo "$sys_ver"
    elif [[ $SYS_VER =~ "centos-7" ]]; then
        SYS_VER="centos-7"
        echo "$SYS_VER"
    else
        echo "目前只支持ubuntu-16.04和Centos-7"
        exit 1
    fi
}

install_depend
need_sys
sync_time

# 默认下载cdnfly-agent-v5.1.16-centos-7.tar.gz
dir_name="cdnfly-agent-v5.1.16"
tar_gz_name="cdnfly-agent-v5.1.16-centos-7.tar.gz"

cd /opt

download "https://raw.githubusercontent.com/Steady-WJ/cdnfly-kaixin/main/cdnfly/$tar_gz_name" "https://raw.githubusercontent.com/Steady-WJ/cdnfly-kaixin/main/cdnfly/$tar_gz_name" "$tar_gz_name"

rm -rf $dir_name
tar xf $tar_gz_name
rm -rf cdnfly
mv $dir_name cdnfly

# 开始安装
cd /opt/cdnfly/agent
chmod +x install.sh
./install.sh "$@"

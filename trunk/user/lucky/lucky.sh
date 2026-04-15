#!/bin/sh

scriptname=$(basename $0)
scriptfilepath=$(cd "$(dirname "$0")"; pwd)/$(basename $0)

# 获取核心配置
lucky_enable=`nvram get lucky_enable`
lucky_cmd=`nvram get lucky_cmd`
PROG=`nvram get lucky_bin`
lucky_tag=`nvram get lucky_tag`
lucky_extra=`nvram get lucky_extra`

# 设置默认值
[ -z "$lucky_cmd" ] && lucky_cmd="/etc/storage/lucky"
[ -z "$lucky_enable" ] && lucky_enable=0 && nvram set lucky_enable=0
[ -z "$PROG" ] && PROG="/etc/storage/bin/lucky"

user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

logg () {
  echo -e "\033[36;33m$(date +'%Y-%m-%d %H:%M:%S'):\033[0m\033[35;1m $1 \033[0m"
  echo "$(date +'%Y-%m-%d %H:%M:%S')：$1" >>/tmp/lucky.log
  logger -t "【lucky】" "$1"
}

lucky_restart () {
    relock="/var/lock/lucky_restart.lock"
    if [ "$1" = "o" ] ; then
        nvram set lucky_renum="0"
        [ -f $relock ] && rm -f $relock
        return 0
    fi
    lucky_renum=$(nvram get lucky_renum)
    lucky_renum=${lucky_renum:-"0"}
    lucky_renum=`expr $lucky_renum + 1`
    nvram set lucky_renum="$lucky_renum"
    if [ "$lucky_renum" -gt "3" ] ; then
        logg "尝试启动失败次数过多，等待19分钟后重试"
        sleep 1140
        nvram set lucky_renum="1"
    fi
    lucky_start
}

get_tag() {
    logg "开始获取最新版本..."
    tag=$(curl -k --connect-timeout 5 --user-agent "$user_agent" https://api.github.com/repos/gdy666/lucky/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4)
    [ -z "$tag" ] && tag=$(wget --no-check-certificate -T 5 -t 2 --user-agent "$user_agent" -qO- https://api.github.com/repos/gdy666/lucky/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4)
    [ -z "$tag" ] && logg "无法获取最新版本" && return
    nvram set lucky_ver_n=$tag
}

lucky_dl() {
    tag="$1"
    new_tag="$(echo $tag | tr -d 'v' | tr -d ' ')"
    # 优先使用用户自定义链接，否则使用修改后的 release 镜像地址
    lk_url=$(nvram get lucky_url)
    [ -z "$lk_url" ] && lk_url="https://release.66666.host/${tag}/${new_tag}_lucky/lucky_${new_tag}_Linux_mipsle_softfloat.tar.gz"
    
    logg "正在下载: ${lk_url}"
    mkdir -p $(dirname "$PROG")
    
    curl -Lko "/tmp/lucky.tar.gz" "${lk_url}" || wget --no-check-certificate -O "/tmp/lucky.tar.gz" "${lk_url}"
    
    if [ $? -eq 0 ]; then
        tar -xzf /tmp/lucky.tar.gz -C /tmp
        if [ -f /tmp/lucky ]; then
            chmod +x /tmp/lucky
            mv -f /tmp/lucky "$PROG"
            rm -f /tmp/lucky.tar.gz
            logg "程序下载并安装成功"
        else
            logg "解压失败，未找到主程序"
        fi
    else
        logg "下载失败，请检查网络"
    fi
}

lk_keep() {
    if [ -s /tmp/script/_opt_script_check ]; then
        sed -Ei '/【lucky】|^$/d' /tmp/script/_opt_script_check
        echo "[ -z \"\`pidof lucky\`\" ] && eval \"$scriptfilepath start &\" #【lucky】" >> /tmp/script/_opt_script_check
    fi
}

get_web() {
    output="$($PROG -baseConfInfo -cd $lucky_cmd)"
    lucky_port=$(echo "$output" | awk -F'"AdminWebListenPort":' '{print $2}' | awk -F',' '{print $1}')
    safeURL=$(echo "$output" | awk -F'"SafeURL":"' '{print $2}' | awk -F'"' '{print $1}')
    lan_ip=$(nvram get lan_ipaddr)
    [ ! -z "$lucky_port" ] && nvram set lucky_login="http://${lan_ip}:${lucky_port}${safeURL}"
}

lucky_start () {
    [ "$lucky_enable" != "1" ] && exit 0
    logg "正在启动 Lucky..."
    killall lucky >/dev/null 2>&1
    
    [ ! -f "$PROG" ] && get_tag && lucky_dl ${lucky_tag:-$tag}
    [ ! -x "$PROG" ] && chmod +x "$PROG"

    eval "${PROG} -cd ${lucky_cmd} ${lucky_extra} >/tmp/lucky.log 2>&1 &"
    
    sleep 5
    if [ ! -z "`pidof lucky`" ]; then
        lk_ver=$($PROG -info | awk -F'"Version":"' '{print $2}' | awk -F'"' '{print $1}')
        logg "Lucky ${lk_ver} 启动成功"
        lucky_restart o
        get_web
        lk_keep
    else
        logg "启动失败，10秒后尝试重启"
        sleep 10 && lucky_restart x
    fi
}

lucky_close () {
    logg "正在关闭 Lucky..."
    sed -Ei '/【lucky】|^$/d' /tmp/script/_opt_script_check
    killall lucky >/dev/null 2>&1
    nvram set lucky_login=""
}

case $1 in
    start|restart) lucky_start ;;
    stop) lucky_close ;;
    resetuser|resetpass|resetport)
        key="AdminAccount"; [ "$1" = "resetpass" ] && key="AdminPassword"; [ "$1" = "resetport" ] && key="AdminWebListenPort"
        val=${2:-"666"}
        $PROG -setconf -key $key -value $val -cd $lucky_cmd && logg "$key 已重置为 $val"
        ;;
    *) lucky_start ;;
esac

#!/bin/bash
GREENCOLOR="\e[1;32m"
ENDCOLOR="\e[0m"
REDCOLOR="\e[1;31m"
YELLOWCOLOR="\e[1;33m"
echo "==Introduction: Check Network Base Config And Managed Information"
echo -e "------------${REDCOLOR}[Red is Error]${ENDCOLOR} ; ${GREENCOLOR}[Green is OK]${ENDCOLOR} ; ${YELLOWCOLOR}[Yellow is Warning]${ENDCOLOR}------------\n"
echo -e "[If you want to skip Ping step, please use ${GREENCOLOR}'--noping'${ENDCOLOR},will reduce running time]\n"
#================================================================================================================================
CONFIGPATH="/etc/network-cvk-agent/config.json"

declare -A smap
smap["network-cvk-agent"]=0
smap["openvswitch"]=0
smap["ovn-northd"]=0
smap["ovn-controller"]=0
smap["frr"]=0

function WriteIni()
{
    fid=$1
    section=$2
    option=$3
    value=$4
    if [ $# -eq 4 ] ; then
        local src=$(cat $fid | awk '/\['$section'\]/{f=1;next} /\[*\]/{f=0} f')  #先搜寻是否存在option
        if [ ${#src} -eq 0 ] ;then #没有匹配到section，直接新建并添加内容
            echo "[$section]" >> $fid
            echo "    $option=$value"  >> $fid
            return 0
        else
            local src=$(cat -n $fid | awk '/\['$section'\]/{f=1;next} /\[*\]/{f=0} f' | grep $option | grep '=')
            if [  ${#src} -eq 0 ] ; then #没有对应的 option 直接添加
                local last=$(cat -n $fid | awk '/\['$section'\]/{f=1;next} /\[*\]/{f=0} f' | tail -n 1)
                last=$(echo $last | cut -d' ' -f1)
                sed -i "${last}a\    $option=$value" $fid
                return 0
            fi
            local old_value=$(echo $src | cut -d'=' -f2 |cut -d'#' -f1 | cut -d';' -f1  )
            local idx=$(echo $src | cut -d' ' -f1)
            local newcontext="$(cat $fid|sed -n "${idx}p" |  sed "s/$old_value/$value/" |  awk '{gsub(/^\s+|\s+$/, "");print}')"
            sed -i "${idx}c\    $newcontext" $fid
            return 0
        fi
    fi
}

function funcCheckFileExists(){
    if [[ -f  $1 ]];
    then
        cat /dev/null > $1
    else
        touch $1
    fi
}

#$2 nooutput flag
#active 只能检查到主进程是否正常,无法检测其他子进程
function funcServiceStatus() 
{
    service_name=$1

    if [ -z "`systemctl status $service_name | grep -w "active"`" ];then
        if [[ -z $2 ]];then
            echo -e "`printf "%-100s\n" $service_name` ${REDCOLOR}[inactive]${ENDCOLOR}"
        else
            smap[$service_name]=1
        fi
        return 1
    else
        echo -e "`printf "%-100s\n" $service_name` ${GREENCOLOR}[active]${ENDCOLOR}"
        return 0
    fi

}
##[监控服务子进程]
#分两部分：1、监控进程结果 2、主进程日志搜索crash, [ovs]两个进程都有监控 不需要查日志

#1 service_name  2 service_log 3 nooutput flag
function MonitorProcessStatus(){
    service_name=$1
    Dtmp=`systemctl status $service_name  | grep "monitoring pid" | grep "died"  | awk '{print $2,$5}'`
    Htmp=`systemctl status $service_name  | grep "monitoring pid" | grep "healthy"  | awk '{print $2,$5}'`
    #//监控进程反馈
    if [[ -n $Dtmp ]];
    then
        if [[ -n $3 ]];then
            smap[$service_name]=1
            return
        fi
        local lines=`echo "$Dtmp" | wc -l`
        for (( i=1;i<=$lines;i++ ));
        do
            local process=`echo "$Dtmp" | sed -n "$i"p`
            echo -e "`printf "%-100s\n" "$process"` ${REDCOLOR}[Died]${ENDCOLOR}"
        done

    elif [[ -n $Htmp ]];
    then
        local lines=`echo "$Htmp" | wc -l`
        for (( i=1;i<=$lines;i++ ));
        do
            local process=`echo "$Htmp" | sed -n "$i"p`
            echo -e "`printf "%-100s\n" "$process"` ${GREENCOLOR}[OK]${ENDCOLOR}"
        done
    fi
    #//日志中查找
    if [[  -n $2 ]] && [[ $2 != "_" ]];
    then
        crash=`cat $2 | grep crash`
        process=`echo "$2" | awk -F "/" '{print $5}'`
        if [[ -n $crash ]];
        then
            if [[ -z $3 ]];then
                echo -e "`printf "%-100s\n" ${process%.*}` ${REDCOLOR}[Crash]${ENDCOLOR}"
            else
                smap[$service_name]=1
                return
            fi
        else
            echo -e "`printf "%-100s\n" ${process%.*}` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
    fi
}
#1、process 2、service 3、nooutput flag
function funcCheckPSAUX(){
    local ps=`ps -aux | grep $1 | grep -v "grep"`
    if [[ -z $ps ]];
    then
        if [[ -z $3 ]];then    
            echo -e "`printf "%-100s\n" process:$1` ${REDCOLOR}[Died]${ENDCOLOR}"
        else
            smap[$2]=1
            return
        fi
    else
        echo -e "`printf "%-100s\n" process:$1` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckDB(){
    if [[ -f ${CONFIGPATH} ]];
    then
        OVNNBDB=`cat $CONFIGPATH | grep -w ovnnbdb | awk -F '"' '{print $4}'`
        OVNSBDB=`cat $CONFIGPATH | grep -w ovnsbdb | awk -F '"' '{print $4}'`
        if [[ -n $OVNNBDB ]];
        then
            local nbsocknumber=`netstat -xnp | grep $OVNNBDB | wc -l`
            if [[ $nbsocknumber < 3 ]];
            then
                echo -e "`printf "%-100s\n" ovnnbdb.sock_has_disconnected:$OVNNBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
                echo "--排查建议:检查northd、openvswitch、network-cvk-agent与ovnnb.sock的连接情况"
            else
                echo -e "`printf "%-100s\n" ovnnbdb.sock_connected_number:$nbsocknumber` ${GREENCOLOR}[OK]${ENDCOLOR}"
            fi
        fi

        if [[ -n $OVNSBDB ]];
        then
            local sbsocknumber=`netstat -xnp | grep $OVNSBDB | wc -l`
            if [[ $nbsocknumber < 3 ]];
            then
                echo -e "`printf "%-100s\n" ovnsbdb.sock_has_disconnected:$OVNSBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
                echo "--排查建议:检查northd、openvswitch、network-cvk-agent与ovnsb.sock的连接情况"
            else
                echo -e "`printf "%-100s\n" ovnsbdb.sock_connected_number:$sbsocknumber` ${GREENCOLOR}[OK]${ENDCOLOR}"
            fi
        fi
    fi
}

function funcCheck_ov_service(){
    funcServiceStatus $1
    if [[ $? = 0 ]];
    then
        MonitorProcessStatus $1 $2 $3
    fi
}

function funcCheck_Frr_Service(){
    funcServiceStatus "frr.service"
    if [[ $? = 0 ]];
    then
        funcCheckPSAUX "/usr/lib/frr/zebra"
        funcCheckPSAUX "/usr/lib/frr/bgpd" 
        funcCheckPSAUX "/usr/lib/frr/ospfd" 
        funcCheckPSAUX "/usr/lib/frr/staticd"
    fi
}

function funcCheck_Frr_Service_no_output(){
    funcServiceStatus "frr.service"
    if [[ $? = 0 ]];
    then
        funcCheckPSAUX "/usr/lib/frr/zebra" frr nooutput
        funcCheckPSAUX "/usr/lib/frr/bgpd" frr nooutput
        funcCheckPSAUX "/usr/lib/frr/ospfd" frr nooutput
        funcCheckPSAUX "/usr/lib/frr/staticd" frr nooutput
    fi
}

#1、nooutput flag
function funcCheck_Agent_Service(){
    funcServiceStatus "network-cvk-agent.service"
    if [[ $? = 0 ]];
    then
        port=`netstat -anltp | grep 22222`
        if [[ -z $port ]];
        then
            if [[ -z $1 ]];then      
                echo -e "`printf "%-100s\n" port:22222` ${REDCOLOR}[Closed]${ENDCOLOR}"
            else
                smap["network-cvk-agent"]=1
                return
            fi
        else
            echo -e "`printf "%-100s\n" port:22222` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
    fi
}

function funcIsExistListJsonValues() {
    # $1 file  $2 key
    VALUE=`awk BEGIN{RS=EOF}'{gsub(/\n/,"");print}' $1 | grep -o "$2[^]]*" | awk -F '[' '{print $2}'`
    if [ -z "${VALUE// /}" ];then
        TMP=1
    else
        TMP=0
    fi
}

function funcCheckRedis(){
    REDISMODE=`cat $CONFIGPATH | grep -w mode | awk -F '"' '{print $4}'`
    REDISINFO=`cat ${CONFIGPATH} | grep -w address | awk -F '"' '{print $4}'`
    PASSWORD=`cat ${CONFIGPATH} | grep -w password | awk -F '"' '{print $4}'`
    if [[ $REDISMODE = "master" ]];then
        if [[ -z $REDISINFO ]] || [[ -z $PASSWORD ]];then
            echo -e "`printf "%-100s\n" config.json_subscriberconfig_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            echo "--排查建议:请检查network-cvk-agent配置文件中Redis配置信息是否缺失【address、password】"
            return 1
        fi
    else
        if [[ -z $REDISINFO ]];then
            funcIsExistListJsonValues ${CONFIGPATH} "sentinaladdrs"
            if [ $TMP = 1 ];then
                echo -e "`printf "%-100s\n" config.json_subscriberconfig_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
                echo "--排查建议:请检查network-cvk-agent配置文件中Redis配置信息是否缺失【address or sentinaladdrs、password】"
                return 1
            fi
        fi
    fi

    if [ -n "`tail -n 200 /var/log/network-cvk-agent/network-cvk-agent.log | grep "ping redis failed"`" ];then
        echo -e "`printf "%-100s\n" Ping_redis_failed` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:请检查cvk与redis网络状态"
        return 1
    fi

    echo -e "`printf "%-100s\n" check_network-cvk-agent_redis_status` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcAgentStatus(){
    AGENTOFFLINE=`cat $CONFIGPATH | grep -w offline | awk '{print $2}'`
    if [ {$AGENTOFFLINE%?} = true ];then
        echo -e "`printf "%-100s\n" check_network-cvk-agent_service_status` ${YELLOWCOLOR}[OFFLINE]${ENDCOLOR}"
        echo "--排查建议:需手动操作退出离线模式"
        return 1
    elif [ -n "`tail -n 200 /var/log/network-cvk-agent/network-cvk-agent.log | grep "enter offline mode"`" ];then
        echo -e "`printf "%-100s\n" check_network-cvk-agent_service_status` ${YELLOWCOLOR}[OFFLINE]${ENDCOLOR}"
        echo "--排查建议:需手动操作退出离线模式"
        return 1
    elif [ -n "`cat /var/log/network-cvk-agent/network-cvk-agent.log | grep "panic"`" ];then
        echo -e "`printf "%-100s\n" network-cvk-agent.log_panic_exists` ${YELLOWCOLOR}[PANIC]${ENDCOLOR}"
        echo "--排查建议:服务日志中存在panic,可联系开发定位"
        return 1
    fi
}

function funcIsEmpty(){
    if [ -z $1 ];then
        echo -e "`printf "%-100s\n" config.json_$2_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:network-cvk-agent配置文件中$2字段缺失"
        return 1
    else
        return 0
    fi
}

function funcCheckDBfield(){
    OVNNBDB=`cat $CONFIGPATH | grep -w ovnnbdb | awk -F '"' '{print $4}'`
    OVNSBDB=`cat $CONFIGPATH | grep -w ovnsbdb | awk -F '"' '{print $4}'`
    if [[ -n $OVNNBDB ]];
    then
        ls -l $OVNNBDB 1>/dev/null 2>&1 
        if [[ $? = 2 ]];then
            echo -e "`printf "%-100s\n" ovnnbdb.sock_is_not_exist:$OVNNBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" ovnnbdb.sock:$OVNNBDB` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
    else
        echo -e "`printf "%-100s\n" config.json_ovnnbdb.sock_field:$OVNNBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    fi

    if [[ -n $OVNSBDB ]];
    then
        ls -l $OVNSBDB 1>/dev/null 2>&1
        if [[ $? = 2 ]];then
            echo -e "`printf "%-100s\n" ovnsbdb.sock_is_not_exist:$OVNSBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" ovnsbdb.sock:$OVNNBDB` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
    else
        echo -e "`printf "%-100s\n" config.json_ovnsbdb.sock_field:$OVNNBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    fi
}

function funcCheckVpcPeerfilter(){
    funcIsExistListJsonValues ${CONFIGPATH} "vpcpeerfilternetwork"
    if [ $TMP = 1 ];then
        echo -e "`printf "%-100s\n" config.json_vpcpeerfilternetwork_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:network-cvk-agent配置文件中$2字段缺失"
        return 1
    fi
    echo -e "`printf "%-100s\n" check_network-cvk-agent_vpcpeerfilternetwork_field` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcCheckHostVtepIPList(){
    funcIsExistListJsonValues ${CONFIGPATH} "hostvtepiplist"
    if [ $TMP = 1 ];then
        echo -e "`printf "%-100s\n" config.json_hostvtepiplist_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:network-cvk-agent配置文件中$2字段缺失"
        return 1
    else
        local index=1
        while [ -n "`echo "$VALUE" | awk -v awkvar=$index '{print $awkvar}'`" ]
        do
            HOSTVTEP="`echo "$VALUE" | awk -v awkvar=$index '{print $awkvar}' | awk -F '"' '{print $2}'`"
            HOSTVTEPLIST[$index-1]=$HOSTVTEP
            let index+=1
        done
    fi
    echo -e "`printf "%-100s\n" check_network-cvk-agent_hostvtepiplist_field` ${GREENCOLOR}[OK]${ENDCOLOR}"

}

function funcCheckBGPNeighbor(){
    local index=1
    local ipaddr=""
    local status=""
    local bgpinfo="`echo "$BGP_NEIGHBOR_IP_LIST" | sed -n "${index}p"`"
    while [ -n "$bgpinfo" ]
    do
        echo "———————————————————————————————————————————————————————————————"
        ipaddr="`echo $bgpinfo | awk '{print $1}'`"
        status="`echo $bgpinfo | awk '{print $2}'`"
        if [ -z "`ping -c 2 $ipaddr -I br-tun | grep "bytes from"`" ];then
            echo -e "`printf "%-100s\n" Ping_BGP_neighbor_$ipaddr` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            echo -e "`printf "%-100s\n" Status_BGP_neighbor_$ipaddr` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" Ping_BGP_neighbor_$ipaddr` ${GREENCOLOR}[OK]${ENDCOLOR}"
            if [[ $status = "Active" || $status = "Connect" || $status = "idle" || $status = "opensent" || $status = "openconfirm" ]];then
                echo -e "`printf "%-100s\n" Status_BGP_neighbor_$ipaddr` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            else
                echo -e "`printf "%-100s\n" Status_BGP_neighbor_$ipaddr` ${GREENCOLOR}[OK]${ENDCOLOR}"
            fi
        fi
        echo "———————————————————————————————————————————————————————————————"
        let index+=1
        bgpinfo="`echo "$BGP_NEIGHBOR_IP_LIST" | sed -n "${index}p"`"
    done
}

function funcCheckSoO(){
    for host in ${HOSTVTEPLIST[@]}
    do
        soo="`vtysh -c "do show bgp l2vpn evpn" | grep -w "$host" | grep SoO | tail -n 1`"
        if [[ -z $soo ]];then
            echo -e "`printf "%-100s\n" SoO_attribute` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            echo "--排查建议:network-cvk-agent未下发init消息"
            return 1
        fi
    done
    echo -e "`printf "%-100s\n" Check_frr_bgp_SoO` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcCheckHostCvkCluster(){
    for host in ${HOSTVTEPLIST[@]}
    do
        echo "———————————————————————————————————————————————————————————————"
        if [ -z "`ping -c 2 $host -I br-tun | grep "bytes from"`" ];then
            echo -e "`printf "%-100s\n" Ping_hostcvkcluster_$host` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" Ping_hostcvkcluster_$host` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
    done
}

function funcCheckDeviceConnect(){
    device_list=`ovs-vsctl show | grep ovn- -A2 | grep vxlan -A1 | grep remote_ip | awk -F '"' '{print $2}'`
    local index=1
    device=`echo "$device_list" | sed -n "${index}p"`
    while [[ -n $device ]]
    do
        echo "———————————————————————————————————————————————————————————————"
        if [ -z "`ping -c 2 $device -I br-tun | grep "bytes from"`" ];then
            echo -e "`printf "%-100s\n" Ping_device_ip_$device` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" Ping_device_ip__$device` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
        let index+=1
        device=`echo "$device_list" | sed -n "${index}p"`
    done       
}

function funcCheckFrrRouterId(){
    echo "———————————————————————————————————————————————————————————————"
    if [[ $1 != $AGENT_VTEP_IP ]];then
        echo -e "`printf "%-100s\n" frr_router-id` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:FRR_running_config中routerid配置存在错误,应与vtepip一致"
    else
        echo -e "`printf "%-100s\n" frr_router-id` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckBrtun(){
    brtun_ip="`ifconfig br-tun | grep -w inet | awk '{print $2}'`"
    if [[ -z $brtun_ip ]];then
        echo  -e "`printf "%-100s\n" br-tun_not_found` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    fi

    if [[ $brtun_ip != $AGENT_VTEP_IP ]];then
        echo -e "`printf "%-100s\n" Compare_br-tun_ipaddr_and_network-cvk-agent_config.json_vtep_ip` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:br-tun网卡IP变化影响网络服务,请检查br-tun网卡是否改动"
    else
        echo -e "`printf "%-100s\n" Compare_br-tun_ipaddr_and_network-cvk-agent_config.json_vtep_ip` ${GREENCOLOR}[OK]${ENDCOLOR}" 
    fi
    brtun_mtu="`ifconfig br-tun | grep -w mtu | awk '{print  $4}'`"
    if [[ $brtun_mtu < 2000 ]];then
        echo -e "`printf "%-100s\n" br-tun_mtu` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:请将br-tun网卡mtu设置为2000"
    else
        echo -e "`printf "%-100s\n" br-tun_mtu` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
    brtun_status="`ifconfig br-tun | head -n 1 | grep UP`"
    if [[ -z $brtun_status ]];then
        echo -e "`printf "%-100s\n" br-tun_status` ${REDCOLOR}[DOWN]${ENDCOLOR}"
        ifconfig br-tun up
        echo "--已将br-tun网卡up"
    else
        echo -e "`printf "%-100s\n" br-tun_status` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckBridgeExist(){
    ovs-vsctl br-exists $1
    if [[ $? = 2 ]];then
        echo -e "`printf "%-100s\n" OVS_Bridge_$1_not_exist` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        echo -e "`printf "%-100s\n" OVS_Bridge_$1_exist` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckBridgeType(){
    business_type=`ovs-vsctl show | grep business  -A2 | grep datapath | awk '{print $2}'`
    brtun_type=`ovs-vsctl show | grep br-tun  -A2 | grep datapath | awk '{print $2}'`
    if [[ $business_type != $brtun_type ]];then
        echo -e "`printf "%-100s\n" Bridge_Type` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:business网桥和br-tun网桥datapath_type不一致,请检查br-tun网桥下的网卡是否加入DPDK"
    else
        echo -e "`printf "%-100s\n" Bridge_Type` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckDpdkInit(){            #是否还有其他更好的判断方法
    local networkcard
    devargs="`ovs-vsctl show | grep "type: dpdk$" -A2 | grep error`"
    if [[ -n $devargs ]];then
        echo -e "`printf "%-100s\n" OVS_DPDK_STATUS` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:网卡加入dpdk报错,请检查网卡状态"
    else
        echo -e "`printf "%-100s\n" OVS_DPDK_STATUS` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckappctlshow(){
    local lines=`echo "$1" | wc -l`
    for (( i=1;i<=$lines;i++ ));
    do
        local bond=`echo "$1" | sed -n "$i"p | awk '{print $2}'`
        local bondinfo="`ovs-appctl bond/show $bond`"
        if [[ -n $bondinfo ]];then
            local slavecards=`echo "$bondinfo" | grep ^slave`
            local card1status=`echo "$slavecards" | sed -n "1"p | awk '{print $3}'`
            local card2status=`echo "$slavecards" | sed -n "2"p | awk '{print $3}'`
            if [[ $card1status = "disabled" ]] && [[ $card2status = "disabled" ]];then
                echo -e "`printf "%-100s\n" $bond` ${REDCOLOR}[ERROR]${ENDCOLOR}"
                echo "--排查建议:$bond:两张子网卡均为disable状态,请查看子网卡状态"
            elif [[ $card2status = "disabled" ]] || [[ $card2status = "disabled" ]];then
                echo -e "`printf "%-100s\n" $bond` ${YELLOWCOLOR}[WARNING]${ENDCOLOR}"
                echo "--排查建议:$bond:其中一张子网卡为disable状态,请查看子网卡状态"
            else
                echo -e "`printf "%-100s\n" $bond` ${GREENCOLOR}[OK]${ENDCOLOR}"
            fi
        fi
    done
}

function funcChecktnlneighborshow(){
    local macaddrs="`ovs-appctl tnl/neigh/show`"
    local index=3
    local ovsip=""
    local ovsmac=""
    local arpipmac=""
    local arpip=""
    local arpmac=""
    local ovsipmac="`echo "$macaddr" | sed -n "${index}p"`"
    while [[ -n $ovsipmac ]]
    do
        ovsip="`echo $ipmac | awk '{print $1}'`"
        ovsmac="`echo $ipmac | awk '{print $2}'`"
        arpmac="`arp -n | grep $ovsip | awk '{print $3}'`"
        if [[ -z $arpmac ]] || [[ $arpmac != $ovsmac ]];then
            echo -e "`printf "%-100s\n" ovs_tnl/neigh_mac_and_arp_mac_different_$ovsip` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        fi
        let index+=1
        ovsipmac="`echo "$macaddr" | sed -n "${index}p"`"
    done

    echo -e "`printf "%-100s\n" Check_ovs_tnl/neigh_mac_and_arp_mac` ${GREENCOLOR}[OK]${ENDCOLOR}"
} 

function funcFulldetection(){
    #1、检查网络服务状态
    echo "=====================检查网络组件状态===================================="

    echo "———————————————————————————————————————————————————————————————"
    funcServiceStatus "network.service"

    echo "———————————————————————————————————————————————————————————————"
    funcCheck_ov_service "openvswitch.service"

    echo "———————————————————————————————————————————————————————————————"
    funcCheck_ov_service "ovn-northd.service" "/var/log/ovn/ovn-northd.log"

    echo "———————————————————————————————————————————————————————————————"
    funcCheck_ov_service "ovn-controller.service" "/var/log/ovn/ovn-controller.log"

    echo "———————————————————————————————————————————————————————————————"
    funcCheck_Frr_Service

    echo "———————————————————————————————————————————————————————————————"
    funcCheck_Agent_Service

    echo "———————————————————————————————————————————————————————————————"
    funcCheckDB



    #2、检查network-cvk服务配置文件中的内容并且获取相关信息；
    echo "=====================检查network-cvk-agent服务配置====================="

    if [ -f ${CONFIGPATH} ];then
        #检查配置文件并获取基本信息
        AGENT_VTEP_IP=`cat $CONFIGPATH | grep -w vtepip | awk -F '"' '{print $4}'`
        AGENT_AZ_ID=`cat $CONFIGPATH | grep -w az_id | awk -F '"' '{print $4}'`
        AGENT_BGP_AS=`cat $CONFIGPATH | grep -w bgpas | awk -F '"' '{print $4}'`
        funcIsEmpty ${AGENT_VTEP_IP} "vtepip"
        funcIsEmpty ${AGENT_AZ_ID} "az_id"
        funcIsEmpty ${AGENT_BGP_AS} "bgpas"

        funcCheckRedis
        funcAgentStatus
        funcCheckVpcPeerfilter
        funcCheckHostVtepIPList
        funcCheckDBfield
    else
        echo -e "`printf "%-100s\n" network-cvk-agent.service [/etc/network-cvk-agent/config.json]` ${REDCOLOR}[MISS]${ENDCOLOR}"
    fi



    #3、检查跟其他cvk、设备的连通性以及frr通告的相关字段是否齐全
    echo "=====================检查BGP邻居状态及主机cvk集群连通性========================"


    if [ -z "`systemctl status frr.service | grep -w "active"`" ];then
        echo -e "`printf "%-100s\n" frr.service_inactive,please_repair_first` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else 
        BGPSUMMARY=`vtysh -c "do show bgp l2vpn evpn summary"`

        BGP_NEIGHBOR_IP_LIST="`echo "$BGPSUMMARY" | awk 'NR>=7 {print $1,$10}' | sed '$d' | sed '$d'`"

        router_id=`vtysh -c "do show running-config" | grep "bgp router-id" | awk '{print $3}'`
        if [[ -z $1 ]] || [[ $1 != "--noping" ]];then
            funcCheckHostCvkCluster
            funcCheckBGPNeighbor
            funcCheckDeviceConnect
        fi
        funcCheckFrrRouterId $router_id
        funcCheckSoO
    fi



    #4、检查ovs网桥以及物理网卡的一些配置
    echo "=====================检查网卡以及网桥配置=================================="

    funcCheckBrtun

    if [ -z "`systemctl status openvswitch.service | grep -w "active"`" ];then
        echo -e "`printf "%-100s\n" openvswitch.service_inactive,please_repair_first` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        PORTBONDS="`ovs-vsctl show | grep 'bond$'`"
        funcCheckBridgeExist "br-tun"
        funcCheckBridgeExist "business"
        funcCheckBridgeType
        funcChecktnlneighborshow
        funcCheckappctlshow "$PORTBONDS"
        funcCheckDpdkInit
    fi
}

function funcCheckBrtun_nooutput(){
    brtun_ip="`ifconfig br-tun | grep -w inet | awk '{print $2}'`"
    brtun_mtu="`ifconfig br-tun | grep -w mtu | awk '{print $4}'`"
    brtun_status="`ifconfig br-tun | head -n 1 | grep UP`"
    if [[ -z $brtun_status ]];then
        ifconfig br-tun up
        brtun_status="down"
    else
        brtun_status="up"
    fi
    funcCheckFileExists $1
    WriteIni $1 "br-tun" "vtepip" $brtun_ip
    WriteIni $1 "br-tun" "mtu" $brtun_mtu
    WriteIni $1 "br-tun" "status" $brtun_status
}

function funcCheckService_All(){
    funcCheck_Agent_Service "nooutput"
    funcCheck_ov_service "openvswitch.service" "_" "nooutput"
    funcCheck_Frr_Service_no_output
    funcCheck_ov_service "ovn-northd.service" "/var/log/ovn/ovn-northd.log" "nooutput"
    funcCheck_ov_service "ovn-controller.service" "/var/log/ovn/ovn-controller.log" "nooutput"

    funcCheckFileExists $1
    for srv in ${!smap[@]};
    do
        WriteIni $1 $srv "status" ${smap[$srv]}
    done
}




#—————————————————————————————————————————————————| Main Beginning |—————————————————————————————————————————————————————————————— 

if [[ $1 = "service" ]] && [[ -n $2 ]];then
    funcCheckService_All $2
elif [[ $1 = "br-tun" ]] && [[ -n $2 ]];then
    funcCheckBrtun_nooutput $2
else
    funcFulldetection $1
fi

#—————————————————————————————————————————————————| Ending |——————————————————————————————————————————————————————————————————————

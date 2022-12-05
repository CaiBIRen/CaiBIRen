#!/bin/bash
GREENCOLOR="\e[1;32m"
ENDCOLOR="\e[0m"
REDCOLOR="\e[1;31m"
YELLOWCOLOR="\e[1;33m"
echo "==Introduction: Check Network Base Config And Managed Information"
echo -e "------------${REDCOLOR}[Red is Error]${ENDCOLOR} ; ${GREENCOLOR}[Green is OK]${ENDCOLOR} ; ${YELLOWCOLOR}[Yellow is Warning]${ENDCOLOR}------------"
#================================================================================================================================

CONFIGPATH="/etc/network-cvk-agent/config.json"

function funcServiceStatus() 

{
    service_name=$1

    if [ -z "`systemctl status $service_name | grep -w "active"`" ];then
        echo -e "`printf "%-100s\n" $service_name` ${REDCOLOR}[Failed]${ENDCOLOR}"
        return 1
    else
        echo -e "`printf "%-100s\n" $service_name` ${GREENCOLOR}[OK]${ENDCOLOR}"
        return 0
    fi
}

#1、检查网络服务状态
echo "=====================检查网络组件状态============================="

funcServiceStatus "network.service"
funcServiceStatus "openvswitch.service"
funcServiceStatus "ovn-controller.service"
funcServiceStatus "ovn-northd.service"
funcServiceStatus "frr.service"
funcServiceStatus "network-cvk-agent.service"


#2、检查初始化配置
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
    REDISMODE=`cat /etc/network-cvk-agent/config.json | grep -w mode | awk -F '"' '{print $4}'`
    REDISINFO=`cat ${CONFIGPATH} | grep -w address | awk -F '"' '{print $4}'`
    PASSWORD=`cat ${CONFIGPATH} | grep -w password | awk -F '"' '{print $4}'`
    if [ $REDISMODE = "master" ];then
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
    AGENTOFFLINE=`cat /etc/network-cvk-agent/config.json | grep -w offline | awk '{print $2}'`
    if [ {$AGENTOFFLINE%?} = true ];then
        echo -e "`printf "%-100s\n" check_network-cvk-agent_service_status` ${YELLOWCOLOR}[OFFLINE]${ENDCOLOR}"
        echo "--排查建议:需手动操作退出离线模式"
        return 1
    elif [ -n "`tail -n 200 /var/log/network-cvk-agent/network-cvk-agent.log | grep "enter offline mode"`" ];then
        echo -e "`printf "%-100s\n" check_network-cvk-agent_service_redis_status` ${YELLOWCOLOR}[OFFLINE]${ENDCOLOR}"
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

function funcCheckDB(){
    OVNNBDB=`cat /etc/network-cvk-agent/config.json | grep -w ovnnbdb | awk -F '"' '{print $4}'`
    OVNSBDB=`cat /etc/network-cvk-agent/config.json | grep -w ovnsbdb | awk -F '"' '{print $4}'`
    ls -l $OVNNBDB 1>/dev/null 2>&1 
    if [[ $? = 2 ]];then
        echo -e "`printf "%-100s\n" ovnnbdb.sock_is_not_exist:$OVNNBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        echo -e "`printf "%-100s\n" ovnnbdb.sock` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
    ls -l $OVNSBDB 1>/dev/null 2>&1
    if [[ $? = 2 ]];then
        echo -e "`printf "%-100s\n" ovnsbdb.sock_is_not_exist:$OVNSBDB` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        echo -e "`printf "%-100s\n" ovnsbdb.sock` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

echo "=====================检查network-cvk-agent服务配置==========="

if [ -f ${CONFIGPATH} ];then
    #检查配置文件并获取基本信息
    AGENT_VTEP_IP=`cat /etc/network-cvk-agent/config.json | grep -w vtepip | awk -F '"' '{print $4}'`
    AGENT_AZ_ID=`cat /etc/network-cvk-agent/config.json | grep -w az_id | awk -F '"' '{print $4}'`
    AGENT_BGP_AS=`cat /etc/network-cvk-agent/config.json | grep -w bgpas | awk -F '"' '{print $4}'`
    funcIsEmpty ${AGENT_VTEP_IP} "vtepip"
    funcIsEmpty ${AGENT_AZ_ID} "az_id"
    funcIsEmpty ${AGENT_BGP_AS} "bgpas"

    funcCheckRedis
    funcAgentStatus
    funcCheckVpcPeerfilter
    funcCheckHostVtepIPList
    funcCheckDB
else
    echo -e "`printf "%-100s\n" network-cvk-agent.service [/etc/network-cvk-agent/config.json]` ${REDCOLOR}[MISS]${ENDCOLOR}"
fi

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
            echo -e "`printf "%-100s\n" SoO_attribute_missing` ${REDCOLOR}[ERROR]${ENDCOLOR}"
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
            echo -e "`printf "%-100s\n" Ping_device_ip_$host` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" Ping_device_ip__$host` ${GREENCOLOR}[OK]${ENDCOLOR}"
        fi
        let index+=1
        device=`echo "$device_list" | sed -n "${index}p"`
    done       
}

function funcCheckFrrRouterId{
    route_id=`vtysh -c "do show running-config" | grep "bgp router-id" | awk '{print $3}'`
    if [[ $route_id != $AGENT_VTEP_IP ]];then
        echo -e "`printf "%-100s\n" frr_router-id` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:FRR_running_config中routerid配置存在错误,应与vtepip一致"
    else
        echo -e "`printf "%-100s\n" frr_router-id` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

echo "=====================检查BGP邻居状态及主机cvk集群连通性========================"

funcCheckHostCvkCluster

if [ -z "`systemctl status frr.service | grep -w "active"`" ];then
    echo -e "`printf "%-100s\n" frr.service_inactive,please_repair_first` ${REDCOLOR}[ERROR]${ENDCOLOR}"
else 
    BGPSUMMARY=`vtysh -c "do show bgp l2vpn evpn summary"`

    BGP_NEIGHBOR_IP_LIST="`echo "$BGPSUMMARY" | awk 'NR>=7 {print $1,$10}' | sed '$d' | sed '$d'`"

    funcCheckBGPNeighbor
    funcCheckDeviceConnect
    funcCheckFrrRouterId
    funcCheckSoO
fi

function funcCheckBrtun(){
    brtun_ip="`ifconfig br-tun | grep -w inet | awk '{print $2}'`"
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
    if [[ -z brtun_status ]];then
        echo -e "`printf "%-100s\n" br-tun_status` ${REDCOLOR}[DOWN]${ENDCOLOR}"
        ifconfig br-tun UP
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

function funcCheckDpdkInit(){            #是否还有其他更好的判断方法
    local networkcard
    devargs="`ovs-vsctl show | grep "error" | grep -v mi | grep -v tap`"
    if [[ -n $devargs ]];then
        echo -e "`printf "%-100s\n" OVS_DPDK_STATUS` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        echo "--排查建议:网卡加入dpdk报错,请检查网卡状态"
    else
        echo -e "`printf "%-100s\n" OVS_DPDK_STATUS` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckappctlshow(){
    local lines="`echo $1 | wc -l`"
    for (( i=1;i<=$lines;i++ ));
    do
        local bond="`echo $1 | sed -n "$i"p | awk '{print $2}'`"
        local bondinfo="`ovs-appctl bond/show $bond`"
        if [[ -n $bondinfo ]];then
            local slavecards="`echo $bondinfo` | grep ^slave"
            local card1status="`echo $slavecards | sed -n "1"p | awk '{print $3}'`"
            local card2status="`echo $slavecards | sed -n "2"p | awk '{print $3}'`"
            if [[ $card1 = "disable" ]] && [[ $card2 = "disable" ]];then
                echo -e "`printf "%-100s\n" $bond` ${REDCOLOR}[ERROR]${ENDCOLOR}"
                echo "--排查建议:$bond:两张子网卡均为disable状态,请查看子网卡状态"
            elif [[ $card1 = "disable" ]] || [[ $card2 = "disable" ]];then
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

echo "=====================检查网卡以及网桥配置==========================="

funcCheckBrtun

if [ -z "`systemctl status openvswitch.service | grep -w "active"`" ];then
    echo -e "`printf "%-100s\n" openvswitch.service_inactive,please_repair_first` ${REDCOLOR}[ERROR]${ENDCOLOR}"
else
    PORTBONDS="`ovs-vsctl show | grep 'bond$'`"
    funcCheckBridgeExist "br-tun"
    funcCheckBridgeExist "business"
    funcChecktnlneighborshow
    funcCheckappctlshow "$PORTBONDS"
    funcCheckDpdkInit
fi
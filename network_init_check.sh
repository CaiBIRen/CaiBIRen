#!/bin/bash
GREENCOLOR="\e[1;32m"
ENDCOLOR="\e[0m"
REDCOLOR="\e[1;31m"
echo "==Introduction: Check Network Base Config And  Managed Information"
echo -e "------------${REDCOLOR}[Red is Error]${ENDCOLOR} ; ${GREENCOLOR}[Green is OK]${ENDCOLOR}------------"
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
            return 1
        fi
    else
        if [[ -z $REDISINFO ]];then
            funcIsExistListJsonValues ${CONFIGPATH} "sentinaladdrs"
            if [ $TMP = 1 ];then
                echo -e "`printf "%-100s\n" config.json_subscriberconfig_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
                return 1
            fi
        fi
    fi

    AGENTOFFLINE=`cat /etc/network-cvk-agent/config.json | grep -w offline | awk '{print $2}'`
    if [ {$AGENTOFFLINE%?} = true ];then
        echo -e "`printf "%-100s\n" check network-cvk-agent_service_redis_status` ${REDCOLOR}[OFFLINE]${ENDCOLOR}"
        return 1
    elif [ -n "`tail -n 200 /var/log/network-cvk-agent/network-cvk-agent.log | grep "ping redis failed"`" ];then
        echo -e "`printf "%-100s\n" check_network-cvk-agent_service_redis_status` ${REDCOLOR}[OFFLINE]${ENDCOLOR}"
        return 1
    fi

    echo -e "`printf "%-100s\n" check_network-cvk-agent_redis_status` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcIsEmpty(){
    if [ -z $1 ];then
        echo -e "`printf "%-100s\n" config.json_$2_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    else
        return 0
    fi
}

function funcCheckVpcPeerfilter(){
    funcIsExistListJsonValues ${CONFIGPATH} "vpcpeerfilternetwork"
    if [ $TMP = 1 ];then
        echo -e "`printf "%-100s\n" config.json_vpcpeerfilternetwork_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    fi
    echo -e "`printf "%-100s\n" check_network-cvk-agent_vpcpeerfilternetwork_field` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcCheckHostVtepIPList(){
    funcIsExistListJsonValues ${CONFIGPATH} "hostvtepiplist"
    if [ $TMP = 1 ];then
        echo -e "`printf "%-100s\n" config.json_hostvtepiplist_field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    else
        local index=1
        while [ -n "`echo "$VALUE" | awk -v awkvar=$index '{print $awkvar}'`" ]
        do
            HOSTVTEP="`echo "$VALUE" | awk -v awkvar=$index '{print $awkvar}' | awk -F '"' '{print $2}'`"
            HOSTVTEPLIST[$index-1]=${HOSTVTEP}
            let index+=1
        done
    fi
    echo -e "`printf "%-100s\n" check_network-cvk-agent_hostvtepiplist_field` ${GREENCOLOR}[OK]${ENDCOLOR}"

}

echo "=====================检查Network-Cvk-Agent服务初始化配置==========="

if [ -f ${CONFIGPATH} ];then
    #检查配置文件并获取基本信息
    AGENT_VTEP_IP=`cat /etc/network-cvk-agent/config.json | grep -w vtepip | awk -F '"' '{print $4}'`
    AGENT_AZ_ID=`cat /etc/network-cvk-agent/config.json | grep -w az_id | awk -F '"' '{print $4}'`
    AGENT_BGP_AS=`cat /etc/network-cvk-agent/config.json | grep -w bgpas | awk -F '"' '{print $4}'`
    funcIsEmpty ${AGENT_VTEP_IP} "vtepip"
    funcIsEmpty ${AGENT_AZ_ID} "az_id"
    funcIsEmpty ${AGENT_BGP_AS} "bgpas"

    funcCheckRedis
    funcCheckVpcPeerfilter
    funcCheckHostVtepIPList
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
        if [ -z "`ping -c 5 $ipaddr | grep "bytes from"`" ];then
            echo -e "`printf "%-100s\n" Ping_BGP_neighbor $ipaddr` ${REDCOLOR}[Failed]${ENDCOLOR}"
            echo -e "`printf "%-100s\n" Status_BGP_neighbor_$ipaddr status` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        else
            echo -e "`printf "%-100s\n" Ping_BGP_neighbor_$ipaddr` ${GREENCOLOR}[OK]${ENDCOLOR}"
            if [[ $status = "Avtive" || $status = "Connect" || $status = "idle" || $status = "opensent" || $status = "openconfirm" ]];then
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
    for host in HOSTVTEPLIST
    do
        soo="`vtysh -c "do show bgp l2vpn evpn" | grep -w "10.254.69.2" | grep SoO | tail -n 1`"
        if [[ -z $soo ]];then
            echo -e "`printf "%-100s\n" SoO_attribute_missing` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            return 1
        fi
    done
    echo -e "`printf "%-100s\n" Check_frr_bgp_SoO` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

echo "=====================检查BGP邻居状态及连通性========================"

if [ -z "`systemctl status frr.service | grep -w "active"`" ];then
    echo -e "`printf "%-100s\n" frr.service inactive,please repair first` ${REDCOLOR}[ERROR]${ENDCOLOR}"
else 
    BGPSUMMARY=`vtysh -c "do show bgp l2vpn evpn summary"`

    BGP_NEIGHBOR_IP_LIST="`echo "$BGPSUMMARY" | awk 'NR>=7 {print $1,$10}' | sed '$d' | sed '$d'`"

    funcCheckBGPNeighbor
    funcCheckSoO

function funcCheckBrtun(){
    brtun_ip="`ifconfig br-tun | grep -w inet | awk '{print $2}'`"
    if [[ $brtun_ip != $vtepip ]];then
        echo -e "`printf "%-100s\n" Compare_br-tun_ipaddr_and_network-cvk-agent_config.json_vtep_ip` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        echo -e "`printf "%-100s\n" Compare_br-tun_ipaddr_and_network-cvk-agent_config.json_vtep_ip` ${GREENCOLOR}[OK]${ENDCOLOR}" 

    brtun_mtu="`ifconfig br-tun | grep -w mtu | awk '{print  $4}'`"
    if [[ $brtun_mtu < 2000 ]];then
        echo -e "`printf "%-100s\n" Check_br-tun_mtu,should_be_2000` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        echo -e "`printf "%-100s\n" Check_br-tun_mtu,should_be_2000` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcCheckBridgeExist(){
    ovs-vsctl br-exists $1
    if [[ $? = 2 ]];then
        echo -e "`printf "%-100s\n" OVS_Bridge_$1_not_exist` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        echo -e "`printf "%-100s\n" OVS_Bridge_$1_exist` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcCheckDpdkInit(){
    local networkcard
    networkcard="`ovs-vsctl show | grep  "dpdk-devargs"`"
    if [[ -z networkcard ]];then
        echo -e "`printf "%-100s\n" OVS_DPDK_STATUS` ${REDCOLOR}[ERROR]${ENDCOLOR}"
    else
        #详细怎么判断？
        echo -e "`printf "%-100s\n" OVS_DPDK_STATUS` ${GREENCOLOR}[OK]${ENDCOLOR}"
}
    
function funcCheckappctlshow(){

}

function funcChecktnlneighborshow(){
    
} 

function funcCheckbaseflow(){

}

echo "=====================检查网卡以及网桥配置==========================="

funcCheckBrtun

if [ -z "`systemctl status openvswitch.service | grep -w "active"`" ];then
    echo -e "`printf "%-100s\n" openvswitch.service inactive,please repair first` ${REDCOLOR}[ERROR]${ENDCOLOR}"
else
    funcCheckBridgeExist "br-tun"
    funcCheckBridgeExist "business"

    funcCheckDpdkInit
    funcChecktnlneighborshow
    funcCheckappctlshow
    funcCheckbaseflow







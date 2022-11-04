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
    else
        echo -e "`printf "%-100s\n" $service_name` ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

#1、检查网络服务状态
echo "=====================检查网络组件状态========================"

funcServiceStatus "network.service"
funcServiceStatus "openvswitch.service"
funcServiceStatus "ovn-controller.service"
funcServiceStatus "frr.service"
funcServiceStatus "network-cvk-agent.service"


#2、检查初始化配置
function funcIsExistListJsonValues() {
    # $1 file  $2 key
    VALUE="`awk BEGIN{RS=EOF}'{gsub(/\n/," ");print}' $1 | grep -o "$2[^]]*" | awk -F '[' '{print $2}'`"
    if [ -z $value ];then
        return 1
    else
        return 0
    fi
}

function funcCheckRedis(){
    REDISMODE=`cat /etc/network-cvk-agent/config.json | grep -w mode | awk -F '"' '{print $4}'`
    if [ $REDISMODE ="master" ];then
        REDISINFO=`cat /etc/network-cvk-agent/config.json | grep -w address | awk -F '"' '{print $4}'`
        PASSWORD=`cat /etc/network-cvk-agent/config.json | grep -w password | awk -F '"' '{print $4}'`
        if [[ -z $REDISINFO ]] || [[ -z $PASSWORD ]];then
            echo -e "`printf "%-100s\n" config.json subscriberconfig field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            return 1
        fi
    else
        funcIsExistListJsonValues ${CONFIGPATH} "sentinaladdrs"
        TMP=$?
        if [ "$TMP" = 1 ];then
            echo -e "`printf "%-100s\n" config.json subscriberconfig field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
            return 1
        fi


    AGENTOFFLINE=`cat /etc/network-cvk-agent/config.json | grep -w offline | awk -F '"' '{print $4}'`
    if [ AGENTOFFLINE = "true"];then
        echo -e "`printf "%-100s\n" check netwrok-cvk-agent service redis status` ${REDCOLOR}[OFFLINE]${ENDCOLOR}"
        return 1
    elif [ -z "`tail -f -n 200 /var/log/network-cvk-agent/network-cvk-agent.log | grep "ping redis failed"`"];then
        echo -e "`printf "%-100s\n" check netwrok-cvk-agent service redis status` ${REDCOLOR}[OFFLINE]${ENDCOLOR}"
        return 1
    fi

    echo -e "`printf "%-100s\n" check netwrok-cvk-agent redis status` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function funcIsEmpty(){
    if [ -z $1 ];then
        echo -e "`printf "%-100s\n" config.json $2 field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    else
        return 0
    fi
}

function funcCheckVpcPeerfilter(){
    funcIsExistListJsonValues ${CONFIGPATH} "vpcpeerfilternetwork"
    TMP=$?
    if [ "$TMP" = 1 ];then
        echo -e "`printf "%-100s\n" config.json vpcpeerfilternetwork field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    fi
    echo -e "`printf "%-100s\n" check netwrok-cvk-agent vpcpeerfilternetwork field` ${GREENCOLOR}[OK]${ENDCOLOR}"
}

function fucnCheckHostVtepIPList(){
    funcIsExistListJsonValues ${CONFIGPATH} "vpcpeerfilternetwork"
    TMP=$?
    if [ "$TMP" = 1 ];then
        echo -e "`printf "%-100s\n" config.json hostvtepiplist field` ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    else
        local index=1
        while (-z "`echo $value | awk "{print $index}"`")   ???
        do
            HOSTVTEP="`echo $value | awk "{print $index}" | awk -F '"' '{print $2}'`"
            HOSTVTEPLIST[$index-1]=HOSTVTEP
        done
    fi

}

echo "=====================检查服务初始化配置========================"

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
    funcHostVtepIpList
else
    echo -e "`printf "%-100s\n" network-cvk-agent.service [/etc/network-cvk-agent/config.json]` ${REDCOLOR}MISS${ENDCOLOR}"
fi


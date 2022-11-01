#!/bin/bash
GREENCOLOR="\e[1;32m"
ENDCOLOR="\e[0m"
REDCOLOR="\e[1;31m"
echo "==Introduction: Check Network Base Config And  Managed Information"
echo -e "------------${REDCOLOR}[Red is Error]${ENDCOLOR} ; ${GREENCOLOR}[Green is OK]${ENDCOLOR}------------"
#================================================================================================================================

CONFIGPATH="/etc/network-cvk-agent/config.json"

#1、检查网络服务状态
function funcServiceStatus() 

{
    service_name=$1

    if [ -z "`systemctl status $service_name | grep -w "active"`" ];then
        echo -e "`printf "%-30s\n" $service_name`                                                  ${REDCOLOR}[Failed]${ENDCOLOR}"
    else
        echo -e "`printf "%-30s\n" $service_name`                                                  ${GREENCOLOR}[OK]${ENDCOLOR}"
    fi
}

function funcIsEmpty(){
    if [ -z $1 ];then
        echo -e "config.json $2 field missing,please check it                   ${REDCOLOR}[ERROR]${ENDCOLOR}"
        return 1
    else
        return 0
    fi
}

function funcCheckRedis(){
    AGENTOFFLINE=`cat /etc/network-cvk-agent/config.json | grep -w offline | awk -F '"' '{print $4}'`
    if [ AGENTOFFLINE = "true"];then
        echo -e "please check netwrok-cvk-agent service redis status            ${REDCOLOR}[OFFLINE]${ENDCOLOR}"
    fi
    REDISMODE=`cat /etc/network-cvk-agent/config.json | grep -w mode | awk -F '"' '{print $4}'`
}

echo "=====================检查网络组件状态========================"

funcServiceStatus "network.service"
funcServiceStatus "openvswitch.service"
funcServiceStatus "ovn-controller.service"
funcServiceStatus "frr.service"
funcServiceStatus "network-cvk-agent.service"


#2、检查初始化配置
echo "=====================检查服务初始化配置========================"

if [ -f ${CONFIGPATH} ];then
    #检查配置文件并获取基本信息
    AGENT_VTEP_IP=`cat /etc/network-cvk-agent/config.json | grep -w vtepip | awk -F '"' '{print $4}'`
    AGENT_AZ_ID=`cat /etc/network-cvk-agent/config.json | grep -w az_id | awk -F '"' '{print $4}'`
    AGENT_BGP_AS=`cat /etc/network-cvk-agent/config.json | grep -w bgpas | awk -F '"' '{print $4}'`
    funcIsEmpty ${AGENT_VTEP_IP} "vtepip"
    funcIsEmpty ${AGENT_AZ_ID} "az_id"
    funcIsEmpty ${AGENT_BGP_AS} "bgpas"
    
else
    echo -e "network-cvk-agent.service                                          ${REDCOLOR}[/etc/network-cvk-agent/config.json miss]${ENDCOLOR}"
fi
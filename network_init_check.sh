#!/bin/bash

GREENCOLOR="\e[1;32m"
ENDCOLOR="\e[0m"
REDCOLOR="\e[1;31m"

#1、检查网络服务状态
echo "=====================检查网络组件状态========================"

if [ -z "`systemctl status network.service | grep "active"`" ];then
    echo -e "network.service                                                  ${REDCOLOR}[Failed]${ENDCOLOR}"
else
    echo -e "network.service                                                  ${GREENCOLOR}[OK]${ENDCOLOR}"
fi

if [ -z "`systemctl status ovn-controller.service | grep "active"`" ];then
    echo -e "ovn-controller.service                                           ${REDCOLOR}[Failed]${ENDCOLOR}"
else
    echo -e "ovn-controller.service                                           ${GREENCOLOR}[OK]${ENDCOLOR}"
fi

if [ -z "`systemctl status openvswitch.service | grep "active"`" ];then
    echo -e "openvswitch.service                                              ${REDCOLOR}[Failed]${ENDCOLOR}"
else
    echo -e "openvswitch.service                                              ${GREENCOLOR}[OK]${ENDCOLOR}"
fi

if [ -z "`systemctl status frr.service | grep "active"`" ];then
    echo -e "frr.service                                                      ${REDCOLOR}[Failed]${ENDCOLOR}"
else
    echo -e "frr.service                                                      ${GREENCOLOR}[OK]${ENDCOLOR}"
fi

if [ -z "`systemctl status network-cvk-agent.service | grep "active"`" ];then
    echo -e "network-cvk-agent.service                                        ${REDCOLOR}[Failed]${ENDCOLOR}"
else
    echo -e "network-cvk-agent.service                                        ${GREENCOLOR}[OK]${ENDCOLOR}"
fi
echo "=====================检查网卡配置========================"
if [ ! -f /etc/network-cvk-agent/config.json ];then



AgentVtep=`cat /etc/`
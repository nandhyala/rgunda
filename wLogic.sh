#!/bin/sh

log() {
  echo "${self}: $*" >&2
}

usage() {
  log "Invalid arguments passed"
  log "Usage: ${self} <APP_NAME>"
  log "Example: ${self} ADFDEV1"
  exit
}

###### MAIN ######
self=$(basename "$0")
wdir=$(dirname "$0")
wdir=$(readlink -f "${wdir}")
base_path=`dirname ${0}`

APP=$1
w_config="/opt/app/`hostname`.json"
[[ $# -lt 1 ]] && { usage; exit 1; }


if [[ $APP =~ "OMS" ]]; then
  APP_TYPE="ebs"
else
  APP_TYPE="fmw"
fi

if [ ! -f "${w_config}" ] ; then
  log "JSON config file NOT FOUND"
  exit 1
fi

matches=$(egrep -ic "\"$APP\":" ${w_config})

if (( matches == 0 ))
then
  log "No such application entry in config file"
  exit 1
elif (( matches > 1 ))
then
  log "Multiple application entries in config file"
  exit 1
fi

declare -a app_det
app_det=""
cat $w_config | sed '/[\}\{]/d' | sed 's/[",]//g' | sed 's/^[[:space:]]*//g' | sed 's/: /:/g' > /tmp/wlogic.temp
app_det=($( cat /tmp/wlogic.temp ))
M_SERVERS=( $(cat /tmp/wlogic.temp | sed -n -e '/\[$/,/^\]/p' | head -n -1 | tail -n+2 | awk '{printf $1","}' | sed 's/.$//' ) )
ADMIN_URL=$( echo ${app_det[9]} | awk -F':' '{print $2":"$3":"$4}' )
TIER_NAME=$( echo ${app_det[3]} | awk -F':' '{print $2}' )
DOMAIN_HOME=$( echo ${app_det[6]} | awk -F':' '{print $2}' )
"""
env_type:weblogic
version:10.3.6
node_type:appnode
tier_name:adf
env_file:/opt/app/ADFDEV/middleware/user_projects/domains/adf_domain/bin/setDomainEnv.sh
opmn_1:/opt/app/ADFDEV/middleware/Oracle_WT1/instances/instance1/bin
domain_home:/opt/app/ADFDEV/middleware/user_projects/domains/adf_domain
adminnode:yes
adminserver:prn-adfdevs2p01
admin_url:t3://prn-omgdevapp01:7010
mservers:[
oacore_server1
oafm_server1
fomrs_server1
]
login_url:http://prn-omgdevapp01.thefacebook.com:8010
AdminServer:startWebLogic.sh
adf_server1:startManagedWebLogic.sh adf_server1
opmn_1:opmnctl startall
AdminServer:stopWebLogic.sh
adf_server1:stopManagedWebLogic.sh adf_server1
opmn_1:opmnctl stopall
"""
export VAULT_ADDR='https://templar.thefacebook.com'
adminpasswd=$( /usr/local/bin/vault read -field=password /secret/tier/${TIER_NAME}/${APP}_weblogic )
if (( $? != 0 ))
then
  echo "${self}: Vault command failed.."
  exit 64
fi
adminuser=$( /usr/local/bin/vault read -field=username /secret/tier/${TIER_NAME}/${APP}_weblogic )

. ${DOMAIN_HOME}/bin/setDomainEnv.sh >&2

if [[ -f ${COMMON_COMPONENTS_HOME}/common/bin/wlst.sh ]]; then
  wls_command="${COMMON_COMPONENTS_HOME}/common/bin/wlst.sh"
elif [[ -f ${MODULES_DIR}/../common/bin/wlst.sh ]]; then
  wls_command="${MODULES_DIR}/../common/bin/wlst.sh"
else
  wls_command="java weblogic.WLST"
fi

umask 026

{
  if [ "${APP_TYPE}" == "EBS" ]; then
    ${JAVA_HOME}/bin/java -classpath ${FMWCONFIG_CLASSPATH} ${MEM_ARGS} ${JVM_D64} ${JAVA_OPTIONS} weblogic.WLST $wdir/wLogic.py $APP ${M_SERVERS} ${ADMIN_URL} $adminuser "${adminpasswd}" 2>&1
  else
    ${wls_command} $wdir/wLogic.py $APP ${M_SERVERS} ${ADMIN_URL} $adminuser "${adminpasswd}"
  fi
} | {
  # Unfortunately the WLST process dumps everything to stdout, so we use the
  # 'OUTPUT:' prefix to separate junk from the actual metrics.
  awk '
      /^OUTPUT:/ {
          print $2, $3, $4
          next
      }
      {
          print > "/dev/stderr"
      }
  '
}

# vim: syntax=sh:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

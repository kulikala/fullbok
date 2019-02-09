#!/bin/bash

# The Name of an existing EC2 KeyPair to enable SSH access to the instances.
# REQUIRED PARAMETER
# KEY_NAME=name_of_ec2_keypair

# Availability zone of JMeter subnet.
# REQUIRED PARAMETER
# AVAILABILITY_ZONE=

# Comma delimited list of lockdown SSH/RDP access to the hosts.
# (default can be accessed from anywhere)
: ${SSH_FROM:=0.0.0.0/0}

# AMI ID of a master instance.
# (Microsoft Windows Server 2016 Base)
# REQUIRED PARAMETER
# MASTER_INSTANCE_AMI=

# EC2 instance type for a JMeter master.
: ${MASTER_INSTANCE_TYPE:=t3.small}

# JVM heap size for a JMeter master instance.
# Allowed Values: 256M, 512M, 1G, 2G, 4G
: ${MASTER_INSTANCE_JVM_MEMORY:=256M}

# AMI ID of slave instances.
# (Amazon Linux 2 AMI (HVM), SSD Volume Type)
# REQUIRED PARAMETER
# SLAVE_INSTANCE_AMI=

# EC2 instance type for JMeter slave instances.
: ${SLAVE_INSTANCE_TYPE:=t3.micro}

# JVM heap size for JMeter slave instances.
# Allowed Values: 256M, 512M, 1G, 2G, 4G
: ${SLAVE_INSTANCE_JVM_MEMORY:=256M}

# Number of EC2 instances to launch for the JMeter slave.
: ${SLAVE_CAPACITY:=1}

# Spot price for the JMeter slave.
: ${SLAVE_SPOT_PRICE:=0}

# Adds prefix string to resource names.
# (use hyphen instead of underscore)
: ${NAME_PREFIX:=fullbok}

# Comma delimited list of tags to be added to every resources.
# (in the form of 'Key=Value,Key2=Value2')
: ${COMMON_TAGS:=}

# Location of template files
# REQUIRED PARAMETER
# TEMPLATE_LOCATION=https://s3.amazonaws.com/${YOUR_TEMPLATE_LOCATION}/fullbok

# AWS CLI profile
: ${AWS_PROFILE:=}

usage () {
  cat << EOS 1>&2
Usage: ${PROGNAME} [OPTIONS]
  This script creates fullbok stack and requiring macro stack in series.

Options:
  -h, --help
    Shows this help

  -k, --key-name ARG
    The Name of an existing EC2 KeyPair to enable SSH access to the instances.

  -a, --availability-zone ARG
    Availability zone of JMeter subnet.

  -s, --ssh-from ARG
    Comma delimited list of lockdown SSH/RDP access to the hosts.
    Default: 0.0.0.0/0

  --master-instance-ami ARG
    AMI ID of a master instance.
    (Microsoft Windows Server 2016 Base)

  --master-instance-type ARG
    EC2 instance type for a JMeter master.
    Default: t3.small

  --master-instance-jvm-memory ARG
    JVM heap size for a JMeter master instance.
    Allowed Values: 256M, 512M, 1G, 2G, 4G
    Default: 256M

  --slave-instance-ami ARG
    AMI ID of slave instances.
    (Amazon Linux 2 AMI (HVM), SSD Volume Type)

  --slave-instance-type ARG
    EC2 instance type for JMeter slave instances.
    Default: t3.small

  --slave-instance-jvm-memory ARG
    JVM heap size for JMeter slave instances.
    Allowed Values: 256M, 512M, 1G, 2G, 4G
    Default: 256M

  -c, --slave-capacity ARG
    Number of EC2 instances to launch for the JMeter slave.
    Default: 1

  --slave-spot-price ARG
    Spot price for the JMeter slave.
    Default: 0

  -n, --name-prefix ARG
    Adds prefix string to resource names.
    (use hyphen instead of underscore)
    Default: fullbok

  -t, --common-tags ARG
    Comma delimited list of tags to be added to every resources.
    (in the form of 'Key=Value,Key2=Value2')

  -l, --template-location ARG
    Location of template files

  --profile ARG
    AWS CLI profile

EOS

  exit 1
}

main () {
  process_macro \
    && process_fullbok \
    && show_master_global_ip_address \
    && list_slave_global_ip_addresses
}

process_macro () {
  check_stack_exists ${STACK_NAME_MACRO}

  local RET=$?

  if [ ${RET} -eq 0 ]; then
    # Exists
    update_macro
  elif [ ${RET} -eq 1 ]; then
    # Not Exists
    create_macro \
      && wait_create_stack ${STACK_NAME_MACRO}
  else
    # Other State
    return ${RET}
  fi
}

create_macro () {
  echo "Creating stack: ${STACK_NAME_MACRO}"
  echo

  aws cloudformation create-stack \
    --stack-name ${STACK_NAME_MACRO} \
    --template-url ${TEMPLATE_LOCATION}/fullbok-macro.yml \
    --parameters \
      "ParameterKey=NamePrefix,ParameterValue='${NAME_PREFIX}'" \
    --capabilities CAPABILITY_NAMED_IAM \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

update_macro () {
  echo "Updating stack: ${STACK_NAME_MACRO}"
  echo

  local OUT
  OUT=$(aws cloudformation update-stack \
    --stack-name ${STACK_NAME_MACRO} \
    --template-url ${TEMPLATE_LOCATION}/fullbok-macro.yml \
    --parameters \
      "ParameterKey=NamePrefix,ParameterValue='${NAME_PREFIX}'" \
    --capabilities CAPABILITY_NAMED_IAM \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    2>&1 \
  )
  local RET=$?

  if [ ${RET} -eq 0 ]; then
    wait_update_stack ${STACK_NAME_MACRO} \
      && echo Stack has been updated successfully: ${STACK_NAME_MACRO}
  elif [[ "${OUT}" =~ No\ updates\ are\ to\ be\ performed\.$ ]]; then
    echo "Stack is already up to date: ${STACK_NAME_MACRO}"
    echo

    return 0
  else
    echo "${OUT}"

    return ${RET}
  fi
}

process_fullbok () {
  create_or_update_stack ${STACK_NAME_FULLBOK} create_fullbok_change_set
}

create_fullbok_change_set () {
  local TYPE=$1
  local CHANGE_SET=$2

  if [ ${TYPE} = CREATE ]; then
    local MESSAGE="newly created"
  else
    local MESSAGE="existing"
  fi

  echo "Creating change set: ${CHANGE_SET}"
  echo "  of ${MESSAGE} stack: ${STACK_NAME_FULLBOK}"
  echo

  aws cloudformation create-change-set \
    --stack-name ${STACK_NAME_FULLBOK} \
    --template-url ${TEMPLATE_LOCATION}/fullbok-template.yml \
    --parameters \
      "ParameterKey=KeyName,ParameterValue='${KEY_NAME}'" \
      "ParameterKey=AvailabilityZone,ParameterValue='${AVAILABILITY_ZONE}'" \
      "ParameterKey=SSHFrom,ParameterValue='${SSH_FROM}'" \
      "ParameterKey=MasterInstanceAMI,ParameterValue='${MASTER_INSTANCE_AMI}'" \
      "ParameterKey=MasterInstanceType,ParameterValue='${MASTER_INSTANCE_TYPE}'" \
      "ParameterKey=MasterInstanceJvmMemory,ParameterValue='${MASTER_INSTANCE_JVM_MEMORY}'" \
      "ParameterKey=SlaveInstanceAMI,ParameterValue='${SLAVE_INSTANCE_AMI}'" \
      "ParameterKey=SlaveInstanceType,ParameterValue='${SLAVE_INSTANCE_TYPE}'" \
      "ParameterKey=SlaveInstanceJvmMemory,ParameterValue='${SLAVE_INSTANCE_JVM_MEMORY}'" \
      "ParameterKey=SlaveCapacity,ParameterValue='${SLAVE_CAPACITY}'" \
      "ParameterKey=SlaveSpotPrice,ParameterValue='${SLAVE_SPOT_PRICE}'" \
      "ParameterKey=NamePrefix,ParameterValue='${NAME_PREFIX}'" \
      "ParameterKey=CommonTags,ParameterValue='${COMMON_TAGS}'" \
    --capabilities CAPABILITY_NAMED_IAM \
    --change-set-name ${CHANGE_SET} \
    --change-set-type ${TYPE} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

show_master_global_ip_address () {
  echo
  echo "[Global IP Address of Master Instance]"

  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${NAME_PREFIX//-/_}_master_server" \
    --query 'Reservations[].Instances[].PublicIpAddress' \
    --output text \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    | tr '\t' '\n'
}

list_slave_global_ip_addresses () {
  echo
  echo "[List of Global IP Addresses of Slave Instances]"

  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${NAME_PREFIX//-/_}_slave_server" \
    --query 'Reservations[].Instances[].PublicIpAddress' \
    --output text \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    | tr '\t' '\n'
}

PROGNAME=$(basename $0)
THIS_DIR=$(cd $(dirname $0) && pwd)

. ${THIS_DIR}/functions.sh

for OPT in "$@"; do
  case "${OPT}" in
    -h | --help)
      usage
      exit 1
      ;;
    -k | --key-name)
      param_usage $1 $2
      KEY_NAME="$2"
      shift 2
      ;;
    -a | --availability-zone)
      param_usage $1 $2
      AVAILABILITY_ZONE="$2"
      shift 2
      ;;
    -s | --ssh-from)
      param_usage $1 $2
      SSH_FROM="$2"
      shift 2
      ;;
    --master-instance-ami)
      param_usage $1 $2
      MASTER_INSTANCE_AMI="$2"
      shift 2
      ;;
    --master-instance-type)
      param_usage $1 $2
      MASTER_INSTANCE_TYPE="$2"
      shift 2
      ;;
    --master-instance-jvm-memory)
      param_usage $1 $2
      MASTER_INSTANCE_JVM_MEMORY="$2"
      shift 2
      ;;
    --slave-instance-ami)
      param_usage $1 $2
      SLAVE_INSTANCE_AMI="$2"
      shift 2
      ;;
    --slave-instance-type)
      param_usage $1 $2
      SLAVE_INSTANCE_TYPE="$2"
      shift 2
      ;;
    --slave-instance-jvm-memory)
      param_usage $1 $2
      SLAVE_INSTANCE_JVM_MEMORY="$2"
      shift 2
      ;;
    -c | --slave-capacity)
      param_usage $1 $2
      SLAVE_CAPACITY="$2"
      shift 2
      ;;
    --slave-spot-price)
      param_usage $1 $2
      SLAVE_SPOT_PRICE="$2"
      shift 2
      ;;
    -n | --name-prefix)
      param_usage $1 $2
      NAME_PREFIX="$2"
      shift 2
      ;;
    -t | --common-tags)
      param_usage $1 $2
      COMMON_TAGS="$2"
      shift 2
      ;;
    -l | --template-location)
      param_usage $1 $2
      TEMPLATE_LOCATION="$2"
      shift 2
      ;;
    --profile)
      param_usage $1 $2
      AWS_PROFILE="$2"
      shift 2
      ;;
    -- | -)
      shift 1
      param+=( "$@" )
      break
      ;;
    -*)
      echo "${PROGNAME}: illegal option -- '$(echo $1 | sed 's/^-*//')'" 1>&2
      exit 1
      ;;
    *)
      if [[ ! -z "$1" ]] && [[ ! "$1" =~ ^-+ ]]; then
        param+=( "$1" )
        shift 1
      fi
      ;;
  esac
done

# Stack name: macro
: ${STACK_NAME_MACRO:=${NAME_PREFIX}-macro-stack}

# Stack name: fullbok
: ${STACK_NAME_FULLBOK:=${NAME_PREFIX}-stack}

param_usage '--key-name' "${KEY_NAME:-}"
param_usage '--availability-zone' "${AVAILABILITY_ZONE:-}"
param_usage '--master-instance-ami' "${MASTER_INSTANCE_AMI:-}"
param_usage '--slave-instance-ami' "${SLAVE_INSTANCE_AMI:-}"
param_usage '--template-location' "${TEMPLATE_LOCATION:-}"

main

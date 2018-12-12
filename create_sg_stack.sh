#!/bin/bash

# The physical ID of the VPC for which the SecurityGroup is created.
# REQUIRED PARAMETER
# VPC_ID=

# The port number to open.
: ${TARGET_PORT:=80}

# Comma delimited list of public IP addresses of JMeter instances.
# JMETER_INSTANCE_PUBLIC_IP_ADDRESSES=

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
  This script creates fullbok stack and required macro in series.

Options:
  -h, --help
    Shows this help

  -v, --vpc-id ARG
    The physical ID of the VPC for which the SecurityGroup is created.

  -p, --target-port ARG
    The port number to open.
    Default: 80

  -s, --jmeter-instance-public-ip-addresses ARG
    Comma delimited list of public IP addresses of JMeter instances.

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
  process_sg
}

process_sg () {
  create_or_update_stack ${STACK_NAME_SG} create_sg_change_set
}

create_sg_change_set () {
  local TYPE=$1
  local CHANGE_SET=$2

  if [ ${TYPE} = CREATE ]; then
    local MESSAGE="newly created"
  else
    local MESSAGE="existing"
  fi

  echo "Creating change set: ${CHANGE_SET}"
  echo "  of ${MESSAGE} stack: ${STACK_NAME_SG}"
  echo

  aws cloudformation create-change-set \
    --stack-name ${STACK_NAME_SG} \
    --template-url ${TEMPLATE_LOCATION}/fullbok-sg.yml \
    --parameters \
      "ParameterKey=VpcId,ParameterValue='${VPC_ID}'" \
      "ParameterKey=TargetPort,ParameterValue='${TARGET_PORT}'" \
      "ParameterKey=JMeterInstancePublicIpAddresses,ParameterValue='${JMETER_INSTANCE_PUBLIC_IP_ADDRESSES}'" \
      "ParameterKey=NamePrefix,ParameterValue='${NAME_PREFIX}'" \
      "ParameterKey=CommonTags,ParameterValue='${COMMON_TAGS}'" \
    --capabilities CAPABILITY_NAMED_IAM \
    --change-set-name ${CHANGE_SET} \
    --change-set-type ${TYPE} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
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
    -v | --vpc-id)
      param_usage $1 $2
      VPC_ID="$2"
      shift 2
      ;;
    -p | --target-port)
      param_usage $1 $2
      TARGET_PORT="$2"
      shift 2
      ;;
    -s | --jmeter-instance-public-ip-addresses)
      param_usage $1 $2
      JMETER_INSTANCE_PUBLIC_IP_ADDRESSES="$2"
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

# Stack name: sg
: ${STACK_NAME_SG:=${NAME_PREFIX}-sg-stack}

param_usage '--vpc-id' "${VPC_ID:-}"
param_usage '--jmeter-instance-public-ip-addresses' "${JMETER_INSTANCE_PUBLIC_IP_ADDRESSES:-}"
param_usage '--template-location' "${TEMPLATE_LOCATION:-}"

main

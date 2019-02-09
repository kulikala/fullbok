#!/bin/bash

# AWS CLI profile
: ${AWS_PROFILE:=}

check_command_availability () {
  type python > /dev/null 2>&1
}

check_stack_exists () {
  local STACK=$1

  echo "Checking if stack exists: ${STACK}"
  echo

  local OUT
  OUT=$(aws cloudformation describe-stacks \
    --stack-name ${STACK} \
    --query 'Stacks[0].StackStatus' \
    --output text \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    2>&1 \
  )
  local RET=$?

  if [[ "${OUT}" =~ does\ not\ exist$ ]]; then
    # Not Exists
    return 1
  elif [[ "${OUT}" =~ _COMPLETE$ ]]; then
    # Exists
    return 0
  else
    # Other State
    echo "${OUT}"

    return 255
  fi
}

check_up_to_date_change_set () {
  local STACK=$1
  local CHANGE_SET=$2

  echo "Checking change set state: ${CHANGE_SET}"
  echo "  of stack: ${STACK}"
  echo

  local OUT
  OUT=$(aws cloudformation describe-change-set \
    --change-set-name ${CHANGE_SET} \
    --stack-name ${STACK} \
    --query 'StatusReason' \
    --output text \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    2>&1 \
  )
  local RET=$?

  if [[ "${OUT}" =~ No\ updates\ are\ to\ be\ performed\. ]]; then
    echo "Stack is already up to date: ${STACK}"
    echo

    delete_change_set ${STACK} ${CHANGE_SET}
  else
    echo "${OUT}"

    return ${RET}
  fi
}

create_or_update_stack () {
  local STACK=$1
  local CREATE_CHANGE_SET_FUNC=$2
  local CHANGE_SET=$(gen_changeset_name)

  check_stack_exists ${STACK}

  local RET=$?

  if [ ${RET} -eq 0 ]; then
    # Exists
    ${CREATE_CHANGE_SET_FUNC} UPDATE ${CHANGE_SET} \
      && wait_create_change_set ${STACK} ${CHANGE_SET}
    RET=$?

    if [ ${RET} -eq 0 ]; then
      execute_change_set ${STACK} ${CHANGE_SET} \
        && wait_update_stack ${STACK} \
        && echo Stack has been updated successfully: ${STACK}
    else
      check_up_to_date_change_set ${STACK} ${CHANGE_SET}
    fi
  elif [ ${RET} -eq 1 ]; then
    # Not Exists
    ${CREATE_CHANGE_SET_FUNC} CREATE ${CHANGE_SET} \
      && wait_create_change_set ${STACK} ${CHANGE_SET} \
      && execute_change_set ${STACK} ${CHANGE_SET} \
      && wait_create_stack ${STACK} \
      && echo Stack has been created successfully: ${STACK}
  else
    # Other State
    return ${RET}
  fi
}

delete_change_set () {
  local STACK=$1
  local CHANGE_SET=$2

  echo "Removing unnecessary change set: ${CHANGE_SET}"
  echo "  of stack: ${STACK}"
  echo

  aws cloudformation delete-change-set \
    --change-set-name ${CHANGE_SET} \
    --stack-name ${STACK} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

execute_change_set () {
  local STACK=$1
  local CHANGE_SET=$2

  echo "Executing change set: ${CHANGE_SET}"
  echo "  of stack: ${STACK}"
  echo

  aws cloudformation execute-change-set \
    --change-set-name ${CHANGE_SET} \
    --stack-name ${STACK} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

force_command_availability () {
  if ! check_command_availability; then
    echo Commands not exists: python
    echo

    exit 1
  fi
}

gen_changeset_name () {
  # Generate change set name
  echo "${NAME_PREFIX}-$(gen_idstr 16)"
}

gen_idstr () {
  force_command_availability

  local STR_LEN=$1

  python -c \
    "import random, string; print(''.join(random.choices(string.ascii_letters + string.digits, k=${STR_LEN})))"
}

get_latest_amazon_linux_ami () {
  local ADDITIONAL_PARAMS="${1:-}"

  aws ec2 describe-images \
    --filters \
    Name=architecture,Values=x86_64 \
    Name=block-device-mapping.volume-type,Values=gp2 \
    Name=name,Values='amzn2-ami-hvm-2.0.*' \
    Name=owner-alias,Values=amazon \
    Name=root-device-type,Values=ebs \
    Name=virtualization-type,Values=hvm \
    --query 'Images | sort_by(@, &CreationDate) | reverse(@) | [0].ImageId' \
    --output text \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    ${ADDITIONAL_PARAMS}
}

get_latest_windows_server_ami () {
  force_command_availability

  local LANGUAGE=$( \
    python -c \
    "print('${1:-English}'.replace('-', '_').replace(' ', '_').title())" \
  )
  local ADDITIONAL_PARAMS="${2:-}"

  aws ec2 describe-images \
    --filters \
    Name=architecture,Values=x86_64 \
    Name=block-device-mapping.volume-type,Values=gp2 \
    Name=name,Values="Windows_Server-2016-${LANGUAGE}-Full-Base-*" \
    Name=owner-alias,Values=amazon \
    Name=platform,Values=windows \
    Name=root-device-type,Values=ebs \
    Name=virtualization-type,Values=hvm \
    --query 'Images | sort_by(@, &CreationDate) | reverse(@) | [0].ImageId' \
    --output text \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    ${ADDITIONAL_PARAMS}
}

list_latest_amazon_linux_ami_for_regions () {
  local REGIONS=$( \
    aws ec2 describe-regions \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE} \
    --query 'Regions | sort_by(@, &RegionName) | [].RegionName' \
    --output text \
  )

  for r in ${REGIONS}; do
    echo "${r}:"
    echo "  ami: $(get_latest_amazon_linux_ami "--region ${r}")"
  done
}

param_usage () {
  if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
    echo "${PROGNAME}: option requires an argument -- $1" 1>&2
    exit 1
  fi
}

wait_create_change_set () {
  local STACK=$1
  local CHANGE_SET=$2

  echo "Waiting for change set creation to complete: ${CHANGE_SET}"
  echo "  of stack: ${STACK}"
  echo

  aws cloudformation wait change-set-create-complete \
    --change-set-name ${CHANGE_SET} \
    --stack-name ${STACK} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

wait_create_stack () {
  local STACK=$1

  echo "Waiting for stack creation to complete: ${STACK}"
  echo

  aws cloudformation wait stack-create-complete \
    --stack-name ${STACK} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

wait_update_stack () {
  local STACK=$1

  echo "Waiting for stack updates to complete: ${STACK}"
  echo

  aws cloudformation wait stack-update-complete \
    --stack-name ${STACK} \
    ${AWS_PROFILE_PARAM} ${AWS_PROFILE}
}

if [ "${AWS_PROFILE}" != "" ]; then
  AWS_PROFILE_PARAM=--profile
else
  AWS_PROFILE_PARAM=
fi

#!/bin/bash
set -eu

VERSION=0.1.1

# コマンド有無確認
if ! type "aws" > /dev/null 2>&1; then
    echo "aws command not installed."
    exit 1
fi

if ! type "jq" > /dev/null 2>&1; then
    echo "jq command not installed."
    exit 1
fi

# default values
fargateClusterName=main-web-app-cluster
taskDefinitionName=pma-task-def

function usage {
    cat <<EOF
$(basename ${0}) is a tool for phpMyAdmin ecs task running or stop.

Usage:
  $(basename ${0}) [command] <clustername>

Command:
  start       phpMyAdmin ecs fargate task running
  stop        phpMyAdmin ecs fargate task stop
  help        print this
  version     print $(basename ${0}) version

ClusterName:
  default: main-web-app-cluster

EOF
}

function check_aws_my_identity() {
  local myIdentity
  myIdentity=$(aws sts get-caller-identity)
  echo -e "Account: $(echo $myIdentity | jq -r '.Account')"
  echo -e "UserId: $(echo $myIdentity | jq -r '.UserId')"

  echo -e ""
  read -p "Is it alright? [Y/n]: " ANS
  case $ANS in
    [Yy]* )
      echo -e "process continue..."
      ;;
    * )
      echo -e "process exit."
      exit 0
      ;;
  esac
}

# 指定したタスク定義で起動しているタスクを取得する
function get_running_task_arn() {
  aws ecs list-tasks \
    --cluster $fargateClusterName \
    --family $taskDefinitionName \
    --desired-status RUNNING \
    --region ap-northeast-1 \
    | jq '.taskArns[0]' \
    | tr '\n' ',' \
    | sed -e 's/,$/\n/g' \
    | sed 's/"//g'
}

# Get public subnet ids
function get_public_subnets() {
  aws ec2 describe-subnets \
    --filters "Name=tag:aws-cdk:subnet-name,Values=Public" \
    --region ap-northeast-1 \
    | jq '.Subnets[].SubnetId' \
    | tr '\n' ',' \
    | sed -e 's/,$/\n/g' \
    | sed 's/"//g'
}

# Get security group
function get_security_groups() {
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=ecs-pma-sg" \
    --region ap-northeast-1 \
    | jq '.SecurityGroups[].GroupId' \
    | tr '\n' ',' \
    | sed -e 's/,$/\n/g' \
    | sed 's/"//g'
}

function do_wait_running_task() {
  if [[ $# -eq 1 ]]; then
    local taskArn=$1
    aws ecs wait tasks-running \
      --tasks ${taskArn} \
      --cluster "${fargateClusterName}" \
      --region ap-northeast-1
  else
    echo -e "Error: wait running-task."
    exit 1
  fi
}

# Do run task
function do_run_task() {
  if [[ $# -eq 2 ]]; then
    local subnets=$1
    local securityGroups=$2

    # タスク開始
    local taskArn
    taskArn=$(aws ecs run-task \
      --task-definition ${taskDefinitionName} \
      --cluster "${fargateClusterName}" \
      --region ap-northeast-1 \
      --launch-type FARGATE \
      --count 1 \
      --network-configuration "awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${securityGroups}],assignPublicIp=ENABLED}" \
      --query "tasks[0].taskArn" \
      --output text)
    echo $taskArn
  else
    echo -e "Error: run-task."
    exit 1
  fi
}

function get_public_dns_name() {
  local taskArn=$1
  local eni
  # タスク詳細取得
  eni=$(aws ecs describe-tasks \
    --tasks ${taskArn} \
    --cluster $fargateClusterName \
    --region ap-northeast-1 \
    --query "tasks[0].attachments[0].details" \
    | jq -r '.[] | select(.name=="networkInterfaceId").value')

  # ネットワーク・インターフェースからパブリックDNSアドレス取得
  publicDnsName=$(aws ec2 describe-network-interfaces \
    --network-interface-ids ${eni} \
    --region ap-northeast-1 \
    --query "NetworkInterfaces[0].Association.PublicDnsName" \
    --output text)

  echo $publicDnsName
}

function do_stop_task() {
  local taskArn=$1
  aws ecs stop-task \
    --task $taskArn \
    --cluster "${fargateClusterName}" \
    --region ap-northeast-1 \
    --query "task.taskDefinitionArn" \
    --output text
}

function do_wait_stop_task() {
  local taskArn=$1
  aws ecs wait tasks-stopped \
    --tasks ${taskArn} \
    --cluster $fargateClusterName \
    --region ap-northeast-1
}

case "${1:-}" in
  # start
  start)

    # check login
    check_aws_my_identity

    # get cluster name
    fargateClusterName=${2:-"${fargateClusterName}"}

    echo -e "Target ECS Cluster:"
    echo -e "  ${fargateClusterName}"

    echo -e pma task start
    # check family=bastion-task-def already running
    runningTaskArn=`get_running_task_arn`

    # when running task.
    if [[ -n $runningTaskArn && $runningTaskArn != null ]]; then
      echo -e "Already running task."
      echo -e "TaskArn:"
      echo -e "  ${runningTaskArn}"
      publicDnsName=`get_public_dns_name $runningTaskArn`
      echo -e "PublicDnsName:"
      echo -e "  ${publicDnsName}"
      echo -e "URL: "
      echo -e "  https://${publicDnsName}:8443"
      exit 0
    fi

    # get subnet ids
    targetSubnets=`get_public_subnets`
    if [[ -n $targetSubnets ]]; then
      echo -e "Subnets:"
      echo -e "  ${targetSubnets}"
    fi

    # get security group ids
    targetSecurityGroups=`get_security_groups`
    if [[ -n $targetSecurityGroups ]]; then
      echo -e "SecurityGroups:"
      echo -e "  ${targetSecurityGroups}"
    fi

    # do run-task
    echo -e "run task..."
    taskArn=`do_run_task $targetSubnets $targetSecurityGroups`
    echo -e "TaskArn: "
    echo -e "  ${taskArn}"
    do_wait_running_task $taskArn
    publicDnsName=`get_public_dns_name $taskArn`
    echo -e "PublicDnsName:"
    echo -e "  ${publicDnsName}"
    echo -e "URL: "
    echo -e "  https://${publicDnsName}:8443"

    exit 0
  ;;

  stop)
    check_aws_my_identity

    # get cluster name
    fargateClusterName=${2:-"${fargateClusterName}"}

    echo -e "Target ECS Cluster:"
    echo -e "  ${fargateClusterName}"

    echo -e pma task stop

    runningTaskArn=`get_running_task_arn`

    if [[ -n $runningTaskArn ]]; then
      echo -e "TaskArn: ${runningTaskArn}"
      echo -e "stop task..."

      taskDefinitionArn=`do_stop_task $runningTaskArn`

      echo -e "TaskDefinitionArn : ${taskDefinitionArn}"

      do_wait_stop_task $runningTaskArn

      echo -e "stop task finished."
    else
      echo -e "pma task not started."
    fi
    exit 0
  ;;

  help)
    usage
  ;;

  version)
    echo -e version $VERSION
    exit 0
  ;;
  *)
    echo "[ERROR] Invalid subcommand '${1:-}'"
    #usage
    exit 1
    ;;
esac

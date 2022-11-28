# aws-ecs-fargate-pma-task

This is simple shell script for running phpMyAdmin ECS Task.

## How it works

## Usage

### Commands

- start <cluster>
  - phpMyAdmin ecs fargate task running 
- stop <cluster>
  - phpMyAdmin ecs fargate task stop
- help
  - print this
- version
  - print $(basename ${0}) version

## Installation

```shell
wget https://raw.githubusercontent.com/yicr/aws-ecs-fargate-pma-task/main/pma-task.sh | chmod +x pma-task.sh
```

### Requirement
- [aws-cli](https://github.com/aws/aws-cli)
- [jq](https://github.com/stedolan/jq)

## LICENSE
MIT


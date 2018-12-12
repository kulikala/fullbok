# Fullbok: GUI JMeter cluster on EC2 template for AWS CloudFormation

`fullbok` is a set of **AWS CloudFormation** templates to launch your own **JMeter cluster** on _EC2_.

With this templates set, you can launch a **JMeter cluster** with a single master JMeter GUI on _Windows Server 2016_ and arbitrary number of slave JMeter servers on _Amazon Linux 2_.

## Introduction

When you do load testing your web service with _Apache JMeter_, you'll want to run JMeter on server resources separated from those of the target web service uses.
And when you need to simulate thousands of concurrent virtual users, a JMeter cluster with several slave servers is required.

With this **AWS CloudFormation** templates set, you can reduce your time and effort creating a JMeter cluster piece by piece on AWS.

### This templates set creates:

* A JMeter GUI on _Windows Server 2016_ (runs as JMeter cluster master)
* Arbitrary number of JMeter slave servers on _Amazon Linux 2_ with _Auto Scaling Group_
* A _SecurityGroup_ that will be attached to target web servers

### and also includes:

* DEMO environment for load-testing target

### Benefits of this templates set:

* YAML templates are easy to understand what resources they will create
* You can copy and modify those templates as you like
* All preparations are done by `cfn-init` scripts and everything is on the source code

## What's included

### Basic stuff:

#### `fullbok-template.yml`

A YAML formatted **AWS CloudFormation** template.

This creates a new _VPC_, an _EC2_, and an _Auto Scaling Group_.

* Macro transformations by `fullbok-macro.yml` are required.

#### `fullbok-macro.yml`

A YAML formatted **AWS CloudFormation** template contains _AWS Lambda_ macro transformation.

This stack is required when creating a change set from `fullbok-template.yml` or `fullbok-sg.yml`.

#### `create_stack.sh`

A Bash script to launch and update fullbok stack from `fullbok-template.yml`.

This script initially creates a macro stack from `fullbok-macro.yml`.
After the creation of the macro stack completes, this script creates a change set from `fullbok-template.yml`, and executes it.

* Idempotence: this script can run multiple times.
* Bash and [_AWS CLI_](https://aws.amazon.com/cli/) is required to run this script.

### For target web servers:

#### `fullbok-sg.yml`

A YAML formatted **AWS CloudFormation** template.

This creates a _SecurityGroup_ which allows incoming requests from `fullbok` servers.

* Macro transformations by `fullbok-macro.yml` are required.

#### `create_sg_stack.sh`

A Bash script to launch and update _SecurityGroup_ stack from `fullbok-sg.yml`.

This script requires existence of the macro stack from `fullbok-macro.yml`.
Run this script after the successful completion of `create_stack.sh`.
This script creates a change set from `fullbok-sg.yml`, and executes it.

* Idempotence: this script can run multiple times.
* Bash and [_AWS CLI_](https://aws.amazon.com/cli/) is required to run this script.

### Demo:

#### `fullbok-demo-template.yml`

A YAML formatted **AWS CloudFormation** template.

This is for DEMO environment and creates a new _VPC_ and an _Auto Scaling Group_.

Simple PHP scripts are included.
* Just shows `phpinfo()`
* Waits specified microseconds by `time` parameter to respond

### Utilizations:

#### `functions.sh`

A Bash script which is `.` sourced from `create_stack.sh` and `create_sg_stack.sh`.

* This script contains various useful Bash functions and you can use them as you like:
  * `get_latest_amazon_linux_ami` returns AMI ID of the latest build of _Amazon Linux 2_
  * `get_latest_windows_server_ami` returns AMI ID of the latest build of _Windows Server 2016_
  * `list_latest_amazon_linux_ami_for_regions` outputs a list of region and latest _Amazon Linux 2_ AMI ID pairs


## Launching JMeter cluster

1. Clone this repository to your local.

```bash
cd your/local/path/to/fullbok
git clone git@github.com:kulikala/fullbok.git
```

2. Upload `fullbok-*.yml` to your preferred _S3_ bucket.

```bash
aws s3 cp fullbok-*.yml 's3:///your-bucket-name/fullbok'
```

3. Run `create_stack.sh` locally.

```bash
./create_stack.sh ...parameters...
```

### Available parameters for `create_stack.sh`:

```bash
fullbok$ ./create_stack.sh --help
Usage: create_stack.sh [OPTIONS]
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
```

## SecurityGroup for load-testing target VPC

1. Run `create_sg_stack.sh` locally.

```bash
./create_sg_stack.sh ...parameters...
```

### Available parameters for `create_sg_stack.sh`:

```bash
fullbok$ ./create_sg_stack.sh --help
Usage: create_sg_stack.sh [OPTIONS]
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
```

## DEMO environment for load-testing target

1. Open _AWS CloudFormation_ Console.<br>
  [https://console.aws.amazon.com/cloudformation/home#/stacks/create](https://console.aws.amazon.com/cloudformation/home#/stacks/create)

2. Follow instructions on the screen to create a new stack.<br>
  Use `fullbok-demo-template.yml` on your _S3_ bucket.

## Notice

* AWS CLI version 1.16.58 and above is required.

```bash
aws --version
```

* No public _S3_ bucket is provided for `fullbok` templates.

* Deployment of template files and creation of stacks using Gradle is not supported any more.

* I confirmed `create_stack.sh` and `create_sg_stack.sh` only on my macOS.

* Confirmed environment of mine:

```bash
fullbok$ aws --version
aws-cli/1.16.65 Python/3.6.4 Darwin/17.7.0 botocore/1.12.55
```

## License

[Apache License 2.0](LICENSE.md)

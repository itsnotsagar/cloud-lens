# Required IAM Permissions for imgclass-deployer

## Issue

Your `imgclass-deployer` IAM user is missing permissions for:
- EventBridge (events:TagResource, events:CreateConnection)
- SQS (sqs:CreateQueue)
- CloudWatch Logs (logs:CreateLogGroup)

## Solution

Add this IAM policy to your `imgclass-deployer` user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EventBridgeFullAccess",
      "Effect": "Allow",
      "Action": [
        "events:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SQSFullAccess",
      "Effect": "Allow",
      "Action": [
        "sqs:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:TagResource",
        "logs:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3FullAccess",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMFullAccess",
      "Effect": "Allow",
      "Action": [
        "iam:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "APIGatewayFullAccess",
      "Effect": "Allow",
      "Action": [
        "apigateway:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaFullAccess",
      "Effect": "Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Fix (AWS CLI)

### Option 1: Attach AWS Managed Policies (Easiest)

```bash
# EventBridge permissions
aws iam attach-user-policy \
  --user-name imgclass-deployer \
  --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess

# SQS permissions
aws iam attach-user-policy \
  --user-name imgclass-deployer \
  --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
```

**For CloudWatch Logs, create a custom inline policy:**

```bash
aws iam put-user-policy \
  --user-name imgclass-deployer \
  --policy-name CloudWatchLogsAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:TagResource",
          "logs:UntagResource"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Option 2: Create Custom Policy (More Secure)

```bash
# Create the policy
aws iam create-policy \
  --policy-name imgclass-deployer-additional-permissions \
  --policy-document file://policy.json

# Attach to user
aws iam attach-user-policy \
  --user-name imgclass-deployer \
  --policy-arn arn:aws:iam::574143645535:policy/imgclass-deployer-additional-permissions
```

## Complete IAM Policy for Terraform Deployment

If you want a single comprehensive policy, use this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::imgclass-tf-state-aws",
        "arn:aws:s3:::imgclass-tf-state-aws/*"
      ]
    },
    {
      "Sid": "DynamoDBStateLock",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/imgclass-tf-lock"
    },
    {
      "Sid": "S3Management",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMManagement",
      "Effect": "Allow",
      "Action": [
        "iam:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "APIGatewayManagement",
      "Effect": "Allow",
      "Action": [
        "apigateway:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaManagement",
      "Effect": "Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EventBridgeManagement",
      "Effect": "Allow",
      "Action": [
        "events:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SQSManagement",
      "Effect": "Allow",
      "Action": [
        "sqs:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsManagement",
      "Effect": "Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Via AWS Console

1. Go to IAM → Users → imgclass-deployer
2. Click "Add permissions" → "Attach policies directly"
3. Search and attach:
   - `AmazonEventBridgeFullAccess`
   - `AmazonSQSFullAccess`
4. Click "Add permissions"
5. For CloudWatch Logs, go to "Permissions" tab → "Add inline policy"
6. Use JSON editor and paste:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:TagResource",
        "logs:UntagResource"
      ],
      "Resource": "*"
    }
  ]
}
```
7. Name it "CloudWatchLogsAccess" and create

## CloudWatch Log Group Issue

The log group `/aws/lambda/imgclass-cors` already exists from a previous deployment. 

### Option 1: Import it into Terraform state

```bash
cd terraform/aws
terraform import aws_cloudwatch_log_group.cors_lambda /aws/lambda/imgclass-cors
```

### Option 2: Delete it manually

```bash
aws logs delete-log-group --log-group-name /aws/lambda/imgclass-cors
```

Then re-run the deployment.

---

**After adding permissions, re-run your GitHub Actions workflow.**

#!/bin/bash

# Get imputs if no arguments passed
get_input() {
    local prompt_text="$1"
    local var_value="$2"
    if [ -z "$var_value" ]; then
        read -p "$prompt_text: " input
        echo "$input"
    else
        echo "$var_value"
    fi
}

ROLE_NAME=$(get_input "Role Name" "$1")
BUCKET_NAME=$(get_input "S3 Bucket" "$2")

echo "---"
echo "Configuring IAM Role: $ROLE_NAME"
echo "Access Scope: s3://$BUCKET_NAME"
echo "---"

# Policy Template
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

echo "Creating Role..."

if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
    echo "Role '$ROLE_NAME' already exists. Updating permissions..."
else
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://trust-policy.json \
        > /dev/null
    echo "Role created."
fi

# Permissions template
cat > permissions-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF

# Attach Policy
echo "Attaching permissions policy..."
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "LambdaS3AndLogs" \
    --policy-document file://permissions-policy.json

# Retrieve and Display the ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

# Cleanup
rm trust-policy.json permissions-policy.json

echo "---"
echo "Success!"
echo "Your Role ARN is:"
echo "$ROLE_ARN"


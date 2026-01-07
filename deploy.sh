#!/bin/bash

# Prompt for input if no args
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

FUNCTION_NAME=$(get_input "Lambda Function Name" "$1")
BUCKET_NAME=$(get_input "S3 Bucket Name" "$2")
REGION=$(get_input "AWS Region" "$3")
ROLE_ARN=$(get_input "IAM Role ARN" "$4")
LAYER_ARN=$(get_input "Layer ARN" "$5")

echo "Starting Clean Build for Node 24..."

# Clean build
rm -rf dist function.zip
mkdir -p dist
cp index.js package.json dist/

cd dist
npm install --omit=dev --silent
# Remove heavy binary (in the layer)
rm -rf node_modules/@sparticuz

echo "Zipping..."
zip -r -q ../function.zip .
cd ..
rm -rf dist

echo "Uploading Code to S3..."
aws s3 cp function.zip "s3://$BUCKET_NAME/function.zip"

echo "Deploying..."
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" > /dev/null 2>&1; then
    echo "Updating Function..."
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --s3-bucket "$BUCKET_NAME" \
        --s3-key "function.zip" \
        --region "$REGION" > /dev/null
    
    sleep 5
    
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --runtime nodejs24.x \
        --layers "$LAYER_ARN" \
        --region "$REGION"
else
    echo "Creating Function..."
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime nodejs24.x \
        --role "$ROLE_ARN" \
        --handler index.handler \
        --code S3Bucket="$BUCKET_NAME",S3Key="function.zip" \
        --layers "$LAYER_ARN" \
        --timeout 60 \
        --memory-size 2048 \
        --region "$REGION" \
        --architectures x86_64
fi

echo "Done."

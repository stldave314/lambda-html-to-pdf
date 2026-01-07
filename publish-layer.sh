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

REGION=$(get_input "AWS Region" "$1")
BUCKET_NAME=$(get_input "S3 Bucket" "$2")

echo "---"
echo "Building Chromium Layer..."
echo "---"

rm -rf layer-build
mkdir -p layer-build/nodejs

cd layer-build/nodejs
npm init -y > /dev/null

npm install @sparticuz/chromium@latest

cd ..
zip -r -q chromium-layer.zip nodejs

echo "Uploading to S3..."
aws s3 cp chromium-layer.zip "s3://$BUCKET_NAME/chromium-layer.zip"

echo "Publishing Layer..."
LAYER_VERSION_ARN=$(aws lambda publish-layer-version \
    --layer-name "chromium-layer" \
    --description "Chromium for Node 24" \
    --content S3Bucket="$BUCKET_NAME",S3Key="chromium-layer.zip" \
    --compatible-runtimes nodejs24.x \
    --region "$REGION" \
    --query 'LayerVersionArn' \
    --output text)

cd ..
rm -rf layer-build

echo "---"
echo "Layer Published: $LAYER_VERSION_ARN"

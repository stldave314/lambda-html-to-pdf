#!/bin/bash

# Utility function for inputs
get_input() {
    [ -z "$2" ] && read -p "$1: " val && echo "$val" || echo "$2"
}

# 1. Configuration
FUNCTION_NAME=$(get_input "Lambda Function Name" "$1")
REGION=$(get_input "Enter AWS Region" "$2")
STAGE_NAME="prod"

# Get Account ID and Function ARN
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Configuration.FunctionArn' --output text)

if [ -z "$FUNCTION_ARN" ]; then
    echo "Error: Lambda function '$FUNCTION_NAME' not found."
    exit 1
fi

echo "---"
echo "Setting up secure API Gateway for: $FUNCTION_NAME"
echo "---"

# 2. Create REST API
echo "Creating API Gateway..."
API_ID=$(aws apigateway create-rest-api \
    --name "${FUNCTION_NAME}-api" \
    --region "$REGION" \
    --query 'id' --output text)

# Get Root Resource
ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --region "$REGION" \
    --query 'items[0].id' --output text)

# 3. Create Resource (Endpoint: /pdf)
echo "Creating resource path '/pdf'..."
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_ID" \
    --path-part "pdf" \
    --region "$REGION" \
    --query 'id' --output text)

# 4. Create Method (POST) with API Key Security
echo "Configuring POST method..."
aws apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --authorization-type "NONE" \
    --api-key-required \
    --region "$REGION" > /dev/null

# 5. Integrate with Lambda (AWS_PROXY)
# AWS_PROXY allows the Lambda to handle the raw request/response objects directly
echo "Linking Lambda to API..."
aws apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations" \
    --region "$REGION" > /dev/null

# 6. Deployment
echo "Deploying API..."
aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE_NAME" \
    --region "$REGION" > /dev/null

# 7. Grant Permissions
# Allow API Gateway to invoke the specific Lambda function
echo "Granting Invoke permissions..."
# We use || true to suppress error if permission already exists
aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id "apigateway-invoke-${API_ID}" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/pdf" \
    --region "$REGION" > /dev/null 2>&1 || true

# 8. Create Credentials (API Key & Usage Plan)
echo "Generating API Credentials..."

# Create API Key
KEY_ID=$(aws apigateway create-api-key \
    --name "${FUNCTION_NAME}-key" \
    --enabled \
    --region "$REGION" \
    --query 'id' --output text)

# Retrieve the actual secret value
API_KEY_VALUE=$(aws apigateway get-api-key \
    --api-key "$KEY_ID" \
    --include-value \
    --region "$REGION" \
    --query 'value' --output text)

# Create Usage Plan (Required to activate the key)
PLAN_ID=$(aws apigateway create-usage-plan \
    --name "${FUNCTION_NAME}-plan" \
    --description "Plan for PDF Generator" \
    --region "$REGION" \
    --query 'id' --output text)

# Link Plan to API Stage
aws apigateway update-usage-plan \
    --usage-plan-id "$PLAN_ID" \
    --patch-operations op=add,path=/apiStages,value="${API_ID}:${STAGE_NAME}" \
    --region "$REGION" > /dev/null

# Link Key to Plan
aws apigateway create-usage-plan-key \
    --usage-plan-id "$PLAN_ID" \
    --key-id "$KEY_ID" \
    --key-type "API_KEY" \
    --region "$REGION" > /dev/null

# 9. Output Results
API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/pdf"

echo "---"
echo "SETUP COMPLETE"
echo "---"
echo "Endpoint URL:  $API_URL"
echo "API Key:       $API_KEY_VALUE"
echo "---"
echo "Test Command:"
echo "curl -X POST \"$API_URL\" \\"
echo "  -H \"x-api-key: $API_KEY_VALUE\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"bucketName\": \"YOUR_BUCKET\", \"fileName\": \"api_test.pdf\", \"htmlBody\": \"<h1>It Works</h1>\"}'"

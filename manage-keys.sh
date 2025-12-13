#!/bin/bash

# Function to prompt for input
get_input() {
    [ -z "$2" ] && read -p "$1: " val && echo "$val" || echo "$2"
}

# 1. Configuration Context
# We need to find the Usage Plan to attach keys to.
echo "--- API Key Manager ---"
FUNCTION_NAME=$(get_input "Enter Function Name (to find Usage Plan)" "$1")
REGION=$(get_input "Enter AWS Region" "$2")

# 2. Find the Usage Plan ID
# We look for the plan created by the previous script (named "FUNCTION_NAME-plan")
echo "Locating Usage Plan for '$FUNCTION_NAME'..."
PLAN_ID=$(aws apigateway get-usage-plans \
    --region "$REGION" \
    --query "items[?name=='${FUNCTION_NAME}-plan'].id" \
    --output text)

if [ -z "$PLAN_ID" ] || [ "$PLAN_ID" == "None" ]; then
    echo "Error: Could not find a Usage Plan named '${FUNCTION_NAME}-plan'."
    echo "Please ensure you have run 'setup-api.sh' first."
    exit 1
fi

echo "Using Usage Plan ID: $PLAN_ID"

# 3. Management Menu Loop
while true; do
    echo "--------------------------------"
    echo "   API KEY MANAGEMENT MENU"
    echo "--------------------------------"
    echo "1. Create New Key"
    echo "2. List All Keys"
    echo "3. Delete a Key"
    echo "4. Exit"
    read -p "Select an option [1-4]: " OPTION

    case $OPTION in
        1)
            # CREATE
            read -p "Enter name for new key (e.g., Client-B): " KEY_NAME
            echo "Creating key '$KEY_NAME'..."
            
            # Create the key
            KEY_ID=$(aws apigateway create-api-key \
                --name "$KEY_NAME" \
                --enabled \
                --region "$REGION" \
                --query 'id' --output text)
            
            # Fetch the secret value
            KEY_VALUE=$(aws apigateway get-api-key \
                --api-key "$KEY_ID" \
                --include-value \
                --region "$REGION" \
                --query 'value' --output text)

            # LINK to Usage Plan (Crucial Step)
            aws apigateway create-usage-plan-key \
                --usage-plan-id "$PLAN_ID" \
                --key-id "$KEY_ID" \
                --key-type "API_KEY" \
                --region "$REGION" > /dev/null

            echo "--- SUCCESS ---"
            echo "Key Name:  $KEY_NAME"
            echo "Key ID:    $KEY_ID"
            echo "Secret:    $KEY_VALUE"
            echo "----------------"
            ;;
        
        2)
            # LIST
            echo "--- Active API Keys ---"
            # Lists keys, showing Name, ID, and the Secret Value
            aws apigateway get-api-keys \
                --include-values \
                --region "$REGION" \
                --query 'items[*].[name, id, value]' \
                --output table
            ;;
        
        3)
            # DELETE
            echo "--- Delete Key ---"
            read -p "Enter Key ID to delete: " DEL_ID
            
            if [ -z "$DEL_ID" ]; then
                echo "Action cancelled."
            else
                # Unlink from plan first (good practice, though API GW often handles it)
                aws apigateway delete-usage-plan-key \
                    --usage-plan-id "$PLAN_ID" \
                    --key-id "$DEL_ID" \
                    --region "$REGION" > /dev/null 2>&1

                # Delete the key
                aws apigateway delete-api-key \
                    --api-key "$DEL_ID" \
                    --region "$REGION"
                
                echo "Key $DEL_ID deleted."
            fi
            ;;
        
        4)
            echo "Exiting."
            exit 0
            ;;
        
        *)
            echo "Invalid option."
            ;;
    esac
done

#!/bin/bash

# Script to create an Azure Policy Assignment from a JSON file
# Usage: ./create_policy_assignment.sh <policy_assignment_filename>

set -e  # Exit on any error

if [ $# -eq 0 ]; then
    echo "Error: Please provide a policy assignment filename as an argument."
    echo "Usage: $0 <policy_assignment_filename>"
    echo "Example: $0 Subscription-Env-Tag.alz_policy_assignment.json"
    exit 1
fi

FILENAME="$(basename $1)"
SCRIPT_DIR="$(dirname "$0")"
ASSIGNMENT_DIR="$SCRIPT_DIR/../policy_assignments"
ASSIGNMENT_FILE="$ASSIGNMENT_DIR/$FILENAME"

if [ ! -f "$ASSIGNMENT_FILE" ]; then
    echo "Error: File '$ASSIGNMENT_FILE' does not exist."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq to continue."
    exit 1
fi

if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is required but not installed. Please install Azure CLI to continue."
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: Could not determine subscription ID. Make sure you're logged in to Azure CLI."
    exit 1
fi
SUBSCRIPTION_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# Read and process the JSON, replacing management group resource IDs with subscription scope
ASSIGNMENT_CONTENT=$(cat "$ASSIGNMENT_FILE" | sed "s|/providers/Microsoft.Management/managementGroups/placeholder|$SUBSCRIPTION_SCOPE|g")

ASSIGNMENT_NAME=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.name')
DISPLAY_NAME=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.properties.displayName')
DESCRIPTION=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.properties.description')
POLICY_DEFINITION_ID=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.properties.policyDefinitionId')
PARAMETERS=$(echo "$ASSIGNMENT_CONTENT" | jq -c '.properties.parameters')
PARAMS_FILE=$(mktemp)
echo "$PARAMETERS" > "$PARAMS_FILE"
ENFORCEMENT_MODE=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.properties.enforcementMode')
IDENTITY_TYPE=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.identity.identityType')
NON_COMPLIANCE_MESSAGES=$(echo "$ASSIGNMENT_CONTENT" | jq -c '.properties.nonComplianceMessages')

if [ "$ASSIGNMENT_NAME" = "null" ] || [ -z "$ASSIGNMENT_NAME" ]; then
    echo "Error: Assignment name not found in the JSON file."
    exit 1
fi

if [ "$POLICY_DEFINITION_ID" = "null" ] || [ -z "$POLICY_DEFINITION_ID" ]; then
    echo "Error: policyDefinitionId not found in the JSON file."
    exit 1
fi


# Determine identity switch
if [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
    IDENTITY_SWITCH="--mi-system-assigned"
elif [ "$IDENTITY_TYPE" = "UserAssigned" ]; then
    # Extract first resourceId from userAssignedIdentities array
    USER_ASSIGNED_ID=$(echo "$ASSIGNMENT_CONTENT" | jq -r '.identity.userAssignedIdentities[0]')
    if [ "$USER_ASSIGNED_ID" = "null" ] || [ -z "$USER_ASSIGNED_ID" ]; then
        echo "Error: userAssignedIdentities array is missing or empty for UserAssigned identity type."
        exit 1
    fi
    IDENTITY_SWITCH="--mi-user-assigned $USER_ASSIGNED_ID"

else
    echo "Error: Unsupported identityType '$IDENTITY_TYPE'. Only 'SystemAssigned' and 'UserAssigned' are supported."
    exit 1
fi

# Create the policy assignment
    # Build the az CLI command
    AZ_CMD="az policy assignment create --name \"$ASSIGNMENT_NAME\" --display-name \"$DISPLAY_NAME\" --description \"$DESCRIPTION\" --scope \"$SUBSCRIPTION_SCOPE\" --policy \"$POLICY_DEFINITION_ID\" --enforcement-mode \"$ENFORCEMENT_MODE\" $IDENTITY_SWITCH --params @$PARAMS_FILE"

    echo "Executing command:"
    echo "$AZ_CMD"
    eval $AZ_CMD

    # Add non-compliance messages using az policy assignment non-compliance-message create
    NON_COMPLIANCE_COUNT=$(echo "$NON_COMPLIANCE_MESSAGES" | jq 'length')
    for ((i=0; i<NON_COMPLIANCE_COUNT; i++)); do
        MESSAGE=$(echo "$NON_COMPLIANCE_MESSAGES" | jq -r ".[$i].message")
        if [ -n "$MESSAGE" ]; then
            MSG_CMD="az policy assignment non-compliance-message create --name \"$ASSIGNMENT_NAME\" --scope \"$SUBSCRIPTION_SCOPE\" --message \"$MESSAGE\""
            echo "Executing command:"
            echo "$MSG_CMD"
            eval $MSG_CMD
        fi
    done

    echo "Policy assignment '$ASSIGNMENT_NAME' created at subscription scope: $SUBSCRIPTION_SCOPE"
    rm -f "$PARAMS_FILE"

#!/bin/bash

# Script to create an Azure Custom Role Definition from a JSON file
# Usage: ./create_role_definition.sh <role_definition_filename>

set -e  # Exit on any error

# Check if argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide a role definition filename as an argument."
    echo "Usage: $0 <role_definition_filename>"
    echo "Example: $0 fabric_administrator.alz_role_definition.json"
    exit 1
fi

FILENAME="$(basename $1)"
SCRIPT_DIR="$(dirname "$0")"
ROLE_DIR="$SCRIPT_DIR/../role_definitions"
ROLE_FILE="$ROLE_DIR/$FILENAME"

# Check if the file exists
if [ ! -f "$ROLE_FILE" ]; then
    echo "Error: File '$ROLE_FILE' does not exist."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq to continue."
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is required but not installed. Please install Azure CLI to continue."
    exit 1
fi

echo "Reading role definition from: $ROLE_FILE"

# Get the current subscription ID and construct the subscription scope
SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: Could not determine subscription ID. Make sure you're logged in to Azure CLI."
    exit 1
fi

SUBSCRIPTION_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# Read the role definition file and substitute the placeholder
ROLE_CONTENT=$(cat "$ROLE_FILE" | sed "s|\${current_scope_resource_id}|$SUBSCRIPTION_SCOPE|g")

# Extract values using jq from the processed content
ROLE_NAME=$(echo "$ROLE_CONTENT" | jq -r '.name')
DISPLAY_NAME=$(echo "$ROLE_CONTENT" | jq -r '.properties.roleName')
DESCRIPTION=$(echo "$ROLE_CONTENT" | jq -r '.properties.description')
PERMISSIONS=$(echo "$ROLE_CONTENT" | jq -c '.properties.permissions')
ASSIGNABLE_SCOPES=$(echo "$ROLE_CONTENT" | jq -c '.properties.assignableScopes')

# Validate required fields
if [ "$ROLE_NAME" = "null" ] || [ -z "$ROLE_NAME" ]; then
    echo "Error: Role name not found in the JSON file."
    exit 1
fi

if [ "$DISPLAY_NAME" = "null" ] || [ -z "$DISPLAY_NAME" ]; then
    echo "Error: Role display name not found in the JSON file."
    exit 1
fi

if [ "$PERMISSIONS" = "null" ] || [ -z "$PERMISSIONS" ]; then
    echo "Error: Permissions not found in the JSON file."
    exit 1
fi

# Check for single quotes in text fields
if [[ "$DISPLAY_NAME" == *"'"* ]]; then
    echo "Error: Display name contains single quotes, which are not permitted."
    echo "Please remove single quotes from the display name in the JSON file."
    exit 1
fi

if [ "$DESCRIPTION" != "null" ] && [[ "$DESCRIPTION" == *"'"* ]]; then
    echo "Error: Description contains single quotes, which are not permitted."
    echo "Please remove single quotes from the description in the JSON file."
    exit 1
fi

echo "Creating Azure Custom Role Definition:"
echo "  Name: $ROLE_NAME"
echo "  Display Name: $DISPLAY_NAME"
echo "  Description: $DESCRIPTION"
echo "  Subscription Scope: $SUBSCRIPTION_SCOPE"

# Create temporary files for JSON data to avoid shell escaping issues with single quotes
TEMP_PERMISSIONS_FILE=$(mktemp)
echo "$PERMISSIONS" > "$TEMP_PERMISSIONS_FILE"

TEMP_SCOPES_FILE=$(mktemp)
echo "$ASSIGNABLE_SCOPES" > "$TEMP_SCOPES_FILE"

# Build the az role definition create command using file references for JSON
CMD_ARGS=("az" "role" "definition" "create"
          "--role-definition" "@$TEMP_PERMISSIONS_FILE")

# Note: For role definitions, we need to create a complete role definition JSON
# Let's build the complete role definition
COMPLETE_ROLE_DEF=$(echo "$ROLE_CONTENT" | jq '{
    "Name": .properties.roleName,
    "Description": .properties.description,
    "Actions": .properties.permissions[0].actions,
    "NotActions": .properties.permissions[0].notActions,
    "DataActions": .properties.permissions[0].dataActions,
    "NotDataActions": .properties.permissions[0].notDataActions,
    "AssignableScopes": .properties.assignableScopes
}')

TEMP_ROLE_DEF_FILE=$(mktemp)
echo "$COMPLETE_ROLE_DEF" > "$TEMP_ROLE_DEF_FILE"

# Update command to use complete role definition
CMD_ARGS=("az" "role" "definition" "create" "--role-definition" "@$TEMP_ROLE_DEF_FILE")

echo ""
echo "Creating role definition..."

# Execute the command
"${CMD_ARGS[@]}"

COMMAND_EXIT_CODE=$?

# Clean up temporary files
rm -f "$TEMP_PERMISSIONS_FILE"
rm -f "$TEMP_SCOPES_FILE"
rm -f "$TEMP_ROLE_DEF_FILE"

if [ $COMMAND_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Role definition '$DISPLAY_NAME' created successfully!"
else
    echo ""
    echo "❌ Failed to create role definition '$DISPLAY_NAME'."
    exit 1
fi

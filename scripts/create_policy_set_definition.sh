#!/bin/bash

# Script to create an Azure Policy Set Definition from a JSON file
# Usage: ./create_policy_set_definition.sh <policy_set_definition_filename>

set -e  # Exit on any error

# Check if argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide a policy set definition filename as an argument."
    echo "Usage: $0 <policy_set_definition_filename>"
    echo "Example: $0 subscription-env-tag.alz_policy_set_definition.json"
    exit 1
fi

FILENAME="$(basename $1)"
SCRIPT_DIR="$(dirname "$0")"
POLICY_SET_DIR="$SCRIPT_DIR/../policy_set_definitions"
POLICY_SET_FILE="$POLICY_SET_DIR/$FILENAME"

# Check if the file exists
if [ ! -f "$POLICY_SET_FILE" ]; then
    echo "Error: File '$POLICY_SET_FILE' does not exist."
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

echo "Reading policy set definition from: $POLICY_SET_FILE"

# Extract values using jq
POLICY_SET_NAME=$(jq -r '.name' "$POLICY_SET_FILE")
DISPLAY_NAME=$(jq -r '.properties.displayName' "$POLICY_SET_FILE")
DESCRIPTION=$(jq -r '.properties.description' "$POLICY_SET_FILE")
POLICY_DEFINITIONS=$(jq -c '.properties.policyDefinitions' "$POLICY_SET_FILE")
PARAMETERS=$(jq -c '.properties.parameters' "$POLICY_SET_FILE")
METADATA=$(jq -c '.properties.metadata' "$POLICY_SET_FILE")

# Validate required fields
if [ "$POLICY_SET_NAME" = "null" ] || [ -z "$POLICY_SET_NAME" ]; then
    echo "Error: Policy set name not found in the JSON file."
    exit 1
fi

if [ "$DISPLAY_NAME" = "null" ] || [ -z "$DISPLAY_NAME" ]; then
    echo "Error: Display name not found in the JSON file."
    exit 1
fi

if [ "$POLICY_DEFINITIONS" = "null" ] || [ -z "$POLICY_DEFINITIONS" ]; then
    echo "Error: Policy definitions not found in the JSON file."
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

echo "Creating Azure Policy Set Definition:"
echo "  Name: $POLICY_SET_NAME"
echo "  Display Name: $DISPLAY_NAME"
echo "  Description: $DESCRIPTION"

# Get the current subscription ID for transforming management group policy references
SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: Could not determine subscription ID. Make sure you're logged in to Azure CLI."
    exit 1
fi

# Transform policy definitions to use subscription scope instead of management group scope
POLICY_DEFINITIONS_TRANSFORMED=$(echo "$POLICY_DEFINITIONS" | jq --arg sub_id "$SUBSCRIPTION_ID" '
    map(
        if .policyDefinitionId | test("^/providers/Microsoft\\.Management/managementGroups/.*/providers/Microsoft\\.Authorization/policyDefinitions/") then
            .policyDefinitionId = (.policyDefinitionId | gsub("^/providers/Microsoft\\.Management/managementGroups/.*/providers/Microsoft\\.Authorization/policyDefinitions/"; "/subscriptions/\($sub_id)/providers/Microsoft.Authorization/policyDefinitions/"))
        else
            .
        end
    )
')

# Create temporary files for JSON data to avoid shell escaping issues with single quotes
TEMP_DEFINITIONS_FILE=$(mktemp)
echo "$POLICY_DEFINITIONS_TRANSFORMED" > "$TEMP_DEFINITIONS_FILE"

# Build the az policy set-definition create command using file references for JSON
CMD_ARGS=("az" "policy" "set-definition" "create"
          "--name" "$POLICY_SET_NAME"
          "--display-name" "$DISPLAY_NAME"
          "--definitions" "@$TEMP_DEFINITIONS_FILE")

# Always include parameters if they exist
if [ "$PARAMETERS" != "null" ] && [ "$PARAMETERS" != "{}" ]; then
    TEMP_PARAMS_FILE=$(mktemp)
    echo "$PARAMETERS" > "$TEMP_PARAMS_FILE"
    CMD_ARGS+=("--params" "@$TEMP_PARAMS_FILE")
fi

# Add optional parameters
if [ "$DESCRIPTION" != "null" ] && [ -n "$DESCRIPTION" ]; then
    CMD_ARGS+=("--description" "$DESCRIPTION")
fi

if [ "$METADATA" != "null" ] && [ "$METADATA" != "{}" ]; then
    METADATAKV=$(jq -r 'to_entries | map("\(.key)=\(.value)") | join(" ")' <<< "$METADATA")
    CMD_ARGS+=("--metadata" $METADATAKV)
fi

echo ""
echo "Creating policy set definition..."

# Execute the command
"${CMD_ARGS[@]}"

COMMAND_EXIT_CODE=$?

# Clean up temporary files
rm -f "$TEMP_DEFINITIONS_FILE"
[ -n "$TEMP_PARAMS_FILE" ] && rm -f "$TEMP_PARAMS_FILE"

if [ $COMMAND_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Policy set definition '$POLICY_SET_NAME' created successfully!"
else
    echo ""
    echo "❌ Failed to create policy set definition '$POLICY_SET_NAME'."
    exit 1
fi
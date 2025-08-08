#!/bin/bash

# Script to create an Azure Policy Definition from a JSON file
# Usage: ./create_policy_definition.sh <policy_definition_filename>

set -e  # Exit on any error

# Check if argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide a policy definition filename as an argument."
    echo "Usage: $0 <policy_definition_filename>"
    echo "Example: $0 audit-env-tag.alz_policy_definition.json"
    exit 1
fi

FILENAME="$(basename $1)"
SCRIPT_DIR="$(dirname "$0")"
POLICY_DIR="$SCRIPT_DIR/../policy_definitions"
POLICY_FILE="$POLICY_DIR/$FILENAME"

# Check if the file exists
if [ ! -f "$POLICY_FILE" ]; then
    echo "Error: File '$POLICY_FILE' does not exist."
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

echo "Reading policy definition from: $POLICY_FILE"

# Extract values using jq
POLICY_NAME=$(jq -r '.name' "$POLICY_FILE")
DISPLAY_NAME=$(jq -r '.properties.displayName' "$POLICY_FILE")
DESCRIPTION=$(jq -r '.properties.description' "$POLICY_FILE")
MODE=$(jq -r '.properties.mode' "$POLICY_FILE")
POLICY_RULE=$(jq -c '.properties.policyRule' "$POLICY_FILE")
PARAMETERS=$(jq -c '.properties.parameters' "$POLICY_FILE")
METADATA=$(jq -c '.properties.metadata' "$POLICY_FILE")


# Validate required fields
if [ "$POLICY_NAME" = "null" ] || [ -z "$POLICY_NAME" ]; then
    echo "Error: Policy name not found in the JSON file."
    exit 1
fi

if [ "$DISPLAY_NAME" = "null" ] || [ -z "$DISPLAY_NAME" ]; then
    echo "Error: Display name not found in the JSON file."
    exit 1
fi

if [ "$POLICY_RULE" = "null" ] || [ -z "$POLICY_RULE" ]; then
    echo "Error: Policy rule not found in the JSON file."
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

echo "Creating Azure Policy Definition:"
echo "  Name: $POLICY_NAME"
echo "  Display Name: $DISPLAY_NAME"
echo "  Description: $DESCRIPTION"

# Build the az policy definition create command using temporary files for JSON data

CMD_ARGS=("az" "policy" "definition" "create" "--name" "$POLICY_NAME" "--display-name" "$DISPLAY_NAME" "--rules" "$POLICY_RULE")

# Add optional parameters
if [ "$DESCRIPTION" != "null" ] && [ -n "$DESCRIPTION" ]; then
    CMD_ARGS+=("--description" "$DESCRIPTION")
fi

if [ "$MODE" != "null" ] && [ -n "$MODE" ]; then
    CMD_ARGS+=("--mode" "$MODE")
fi

# For parameters and metadata, use temporary files
if [ "$PARAMETERS" != "null" ] && [ "$PARAMETERS" != "{}" ]; then
    CMD_ARGS+=("--params" "$PARAMETERS")
fi

if [ "$METADATA" != "null" ] && [ "$METADATA" != "{}" ]; then
    METADATAKV=$(jq -r 'to_entries | map("\(.key)=\(.value)") | join(" ")' <<< "$METADATA")
    CMD_ARGS+=("--metadata" $METADATAKV)
fi

echo ""
echo "Creating policy definition..."

# Execute the command
"${CMD_ARGS[@]}"
COMMAND_EXIT_CODE=$?

if [ $COMMAND_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Policy definition '$POLICY_NAME' created successfully!"
else
    echo ""
    echo "❌ Failed to create policy definition '$POLICY_NAME'."
    exit 1
fi
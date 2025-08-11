#!/bin/bash
# ⚠️ Needs testing

# Set your subscription ID
SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
SUBSCRIPTION_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# Remove Policy Assignment
az policy assignment delete --name Subscription-Env-Tag --scope "$SUBSCRIPTION_SCOPE"

# Remove Policy Set Definition
az policy set-definition delete --name Subscription-Env-Tag --subscription "$SUBSCRIPTION_ID"

# Remove Policy Definitions
az policy definition delete --name Audit-Env-Tag --subscription "$SUBSCRIPTION_ID"
az policy definition delete --name Inherit-Env-Tag --subscription "$SUBSCRIPTION_ID"

# Remove Custom Role Definitions
az role definition delete --name Fabric-Contributor --subscription "$SUBSCRIPTION_ID"
az role definition delete --name Fabric-Reader --subscription "$SUBSCRIPTION_ID"

# Note: Role assignments are not created by test.sh, so not included here.

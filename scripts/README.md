# Azure Policy Definition Creation Script

## Known Issue

The script may encounter the error:
```
dictionary update sequence element #0 has length 1; 2 is required
```

This is a known issue with certain versions of Azure CLI when handling complex policy definitions with parameters.

## Workarounds

1. **Manual Creation**: Use the Azure Portal or ARM templates instead
2. **Simplified Script**: Create the policy with minimal parameters first, then update
3. **Azure CLI Update**: Update to the latest version of Azure CLI

## Alternative Approach

You can create the policy manually using:

```bash
# Create a temporary file with just the policy rule
jq '.properties.policyRule' policy_definitions/your-file.json > /tmp/rule.json

# Create a temporary file with just the parameters
jq '.properties.parameters' policy_definitions/your-file.json > /tmp/params.json

# Create the policy definition
az policy definition create \
  --name "your-policy-name" \
  --display-name "Your Policy Display Name" \
  --description "Your policy description" \
  --mode "All" \
  --rules @/tmp/rule.json \
  --params @/tmp/params.json

# Clean up
rm /tmp/rule.json /tmp/params.json
```

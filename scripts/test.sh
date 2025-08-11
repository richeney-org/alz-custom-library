#!/usr/bin/env bash
# Quick and dirty script to test the custom library resources

cd "$(dirname "$0")"

./create_role_definition.sh ../role_definitions/fabric_contributor.alz_role_definition.json
./create_role_definition.sh ../role_definitions/fabric_reader.alz_role_definition.json
./create_policy_definition.sh ../policy_definitions/Audit-Env-Tag.alz_policy_definition.json
./create_policy_definition.sh ../policy_definitions/Inherit-Env-Tag.alz_policy_definition.json
./create_policy_set_definition.sh ../policy_set_definitions/Subscription-Env-Tag.alz_policy_set_definition.json
./create_policy_assignment.sh ../policy_assignments/Subscription-Env-Tag.alz_policy_assignment.json
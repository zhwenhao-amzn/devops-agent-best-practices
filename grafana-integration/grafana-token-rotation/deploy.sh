#!/bin/bash
set -e

STACK_NAME="grafana-token-rotation"
REGION="us-east-1"
WORKSPACE_ID="g-c702c721da"
ENDPOINT="https://g-c702c721da.grafana-workspace.us-east-1.amazonaws.com"
SA_ID=16

echo "=== Deploying $STACK_NAME ==="
aws cloudformation deploy \
  --template-file cfn-template.yaml \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    GrafanaWorkspaceId="$WORKSPACE_ID" \
    GrafanaEndpoint="$ENDPOINT" \
    GrafanaServiceAccountId="$SA_ID" \
    RotationIntervalDays=25

echo ""
echo "=== Seeding initial secret with current DevOps Agent service ID ==="
echo "Run this after deployment:"
echo ""
echo "  # Get your current Grafana service ID from DevOps Agent console"
echo "  # Then seed the secret:"
echo "  aws secretsmanager update-secret \\"
echo "    --secret-id devops-agent/grafana-token \\"
echo "    --secret-string '{\"devopsAgentServiceId\":\"YOUR_SERVICE_ID\",\"grafanaTokenId\":null}' \\"
echo "    --region $REGION"
echo ""
echo "=== Test rotation manually ==="
echo "  aws lambda invoke --function-name grafana-token-rotation --region $REGION /dev/stdout"
echo ""
echo "Done!"

# Integrating AWS DevOps Agent with Amazon Managed Grafana

## 1. Overview

AWS DevOps Agent provides **built-in Grafana integration** (GA March 2026) through an AWS-hosted [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana) MCP server. This integration is read-only and supports:

- **Amazon Managed Grafana (AMG)**
- **Grafana Cloud**
- **Self-managed Grafana**

The integration exposes **50+ tools** covering dashboards, Prometheus (PromQL), Loki (LogQL), alerting, OnCall, annotations, incidents, Sift, and panel rendering -- enabling natural language queries against your observability stack directly from the DevOps Agent console.

---

## 2. Built-in Grafana Capabilities

All tools are **read-only**. No write operations are performed against your Grafana instance.

| Category | Tools | Description |
|---|---|---|
| **Dashboards** | `search_dashboards`, `get_dashboard_by_uid`, `get_dashboard_summary`, `query_panel` | Search, retrieve, summarize dashboards; execute panel queries |
| **Datasources** | `list_datasources`, `get_datasource_by_uid` | List and inspect configured datasources |
| **Prometheus** | `query_prometheus`, `query_prometheus_range`, `list_prometheus_metric_names`, `list_prometheus_label_names`, `list_prometheus_label_values` | Full PromQL support -- instant and range queries, metric/label discovery |
| **Loki** | `query_loki`, `query_loki_range`, `list_loki_label_names`, `list_loki_label_values` | Full LogQL support -- instant and range queries, label discovery |
| **Alerting** | `list_alert_rules`, `get_alert_rule_by_uid`, `list_notification_policies`, `list_contact_points` | List alert rules, notification policies, and contact points |
| **Annotations** | `list_annotations`, `get_annotation_by_id` | Query annotations by time range, dashboard, or tags |
| **Incidents** | `list_incidents`, `get_incident_by_id`, `query_incident_previews` | List and inspect Grafana Incident records |
| **OnCall** | `list_oncall_schedules`, `list_oncall_shifts`, `list_oncall_users`, `list_oncall_teams` | Query on-call schedules, shifts, and team assignments |
| **Sift** | `list_investigations`, `get_investigation` | Access Grafana Sift AI-powered investigations |
| **Rendering** | `render_panel_png` | Export dashboard panels as PNG images |
| **Navigation** | `get_dashboard_deeplink`, `get_explore_deeplink` | Generate deep links to dashboards and Explore views |

---

## 3. Setup Guide (~5 minutes)

### Step 1: Create an AMG Service Account Token

1. Open the **Amazon Managed Grafana** console -> select your workspace
2. Navigate to **Administration -> Service Accounts**
3. Click **Add service account**
   - Name: `devops-agent`
   - Role: **Viewer**
4. Click **Add token** on the newly created service account
   - Copy the generated token (format: `glsa_xxxxxxxxxxxx`)

> ⚠️ **AMG limits service account tokens to a maximum of 30 days.** See [Section 5](#5-automated-token-rotation-solution) for an automated rotation solution.

### Step 2: Register Grafana in DevOps Agent

1. Open the **AWS DevOps Agent** console
2. Navigate to **Capability Providers -> Grafana**
3. Click **Register** and provide:
   - **Grafana URL**: `https://<workspace-id>.grafana-workspace.<region>.amazonaws.com`
   - **Service Account Token**: `glsa_xxxxxxxxxxxx`
4. Click **Register** -- DevOps Agent validates connectivity and registers the service

### Step 3: Associate Grafana to Your Agent Space

1. Navigate to **Agent Spaces** -> select your agent space
2. Go to **Capabilities -> Telemetry**
3. Click **Add** -> select **Grafana**
4. Save -- the Grafana tools are now available in this agent space

---

## 4. AMG Known Limitations

| Limitation | Impact |
|---|---|
| **Service account token max 30 days** | Tokens expire and must be rotated. Manual rotation causes downtime. See [Section 5](#5-automated-token-rotation-solution) for automation. |
| **Webhook contact points NOT supported** | AMG does not support webhook-type contact points in alerting. This means you cannot auto-trigger Grafana Sift investigations from AMG alert rules. |
| **ClickHouse datasource not supported** | ClickHouse plugin is not available in AMG. Use a custom MCP server if you need ClickHouse queries. |
| **OpenSearch via Grafana (possible known issue)** | There are reports of OpenSearch datasource queries not working correctly through the Grafana MCP integration. If you encounter this, consider querying OpenSearch directly. |

---

## 5. Automated Token Rotation Solution

### Architecture

```
EventBridge (every 25 days)
    -> Lambda
        -> Grafana API: Create new SA token
        -> DevOps Agent API: Disassociate -> Deregister old -> Register new -> Re-associate
        -> Grafana API: Delete old token
        -> Secrets Manager: Store new token + service ID
```

### Key APIs

```bash
# Register Grafana service
aws devops-agent register-service \
  --service mcpservergrafana \
  --service-details '{
    "endpoint": "https://<workspace-id>.grafana-workspace.<region>.amazonaws.com",
    "name": "my-grafana",
    "authorizationConfig": {
      "bearerToken": "glsa_xxxxxxxxxxxx"
    }
  }'

# Deregister old service (must disassociate from Agent Space first)
aws devops-agent disassociate-service --agent-space-id <space-id> --service-id <old-service-id>
aws devops-agent deregister-service --service-id <old-service-id>

# Re-associate new service
aws devops-agent associate-service --agent-space-id <space-id> --service-id <new-service-id>
```

### Rotation Behavior

- **Downtime**: ~5-10 seconds during the deregister -> register -> re-associate cycle
- **Graceful handling**: Lambda checks for SDK availability and handles partial failures
- **Secret storage**: New token and service ID are persisted in Secrets Manager for the next rotation cycle

### Deployment

```bash
cd grafana-token-rotation
./deploy.sh

# Seed the secret with your initial service ID
aws secretsmanager put-secret-value \
  --secret-id devops-agent/grafana-token \
  --secret-string '{"devopsAgentServiceId":"<your-service-id>","grafanaTokenId":null}'

# Test the rotation
aws lambda invoke --function-name grafana-token-rotation --payload '{}' /dev/stdout
```

---

## 6. When to Use a Custom Grafana MCP Server Instead

The built-in integration is read-only. Consider deploying a **custom MCP server** if you need:

| Use Case | Why Custom |
|---|---|
| **Write operations** | Create/update dashboards, alerts, or annotations |
| **ClickHouse or Elasticsearch direct queries** | These datasources are not available through AMG or the built-in integration |
| **Admin operations** | Manage teams, users, roles, or organization settings |
| **Auto-trigger investigations from AMG alerts** | AMG does not support webhook contact points needed for Sift triggers |

### Reference Implementation

**[aws-samples/sample-aws-devops-agent-ecs-grafana-mcp](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp)**

- CDK-based deployment
- ECS Fargate + AgentCore Runtime
- Cognito OAuth 2.1 authentication
- Full read/write Grafana MCP server

---

## 7. Testing Prompts

After completing setup, try these prompts in the DevOps Agent console:

```
List all dashboards in my Grafana workspace and summarize the most recently updated one.
```

```
The payment-service has a high error rate. Check Prometheus for the error rate over the last 2 hours,
find any recent deployments via annotations, and correlate with Loki logs for error details.
```

```
Show me all annotations from the last 7 days tagged with "deployment" or "incident".
```

```
Give me a full health check: list active alert rules that are firing, check who is currently on-call,
and show me the error rate trend for the top 3 services over the past 24 hours.
```

---

## References

- [AWS DevOps Agent Documentation](https://docs.aws.amazon.com/devops-agent/latest/userguide/)
- [Amazon Managed Grafana -- Service Accounts](https://docs.aws.amazon.com/grafana/latest/userguide/service-accounts.html)
- [grafana/mcp-grafana (GitHub)](https://github.com/grafana/mcp-grafana)
- [aws-samples/sample-aws-devops-agent-ecs-grafana-mcp (GitHub)](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp)
- [AWS Blog -- Integrating Grafana with DevOps Agent](https://aws.amazon.com/blogs/devops/integrating-grafana-with-aws-devops-agent/)

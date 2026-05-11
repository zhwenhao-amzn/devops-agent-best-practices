# 集成 AWS DevOps Agent 与 Amazon Managed Grafana

> 📖 [English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

## 1. 概述

AWS DevOps Agent 提供**内建 Grafana 集成**（2026 年 3 月 GA），通过 AWS 托管的 [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana) MCP server。此集成为只读，支持：

- **Amazon Managed Grafana (AMG)**
- **Grafana Cloud**
- **Self-managed Grafana**

集成提供 **50+ tools**，涵盖 dashboards、Prometheus (PromQL)、Loki (LogQL)、alerting、OnCall、annotations、incidents、Sift 和 panel rendering — 可直接在 DevOps Agent 控制台用自然语言查询您的可观测性堆栈。

---

## 2. 内建 Grafana 功能

所有 tools 均为**只读**，不会对您的 Grafana 执行任何写入操作。

| 类别 | Tools | 说明 |
|---|---|---|
| **Dashboards** | `search_dashboards`, `get_dashboard_by_uid`, `get_dashboard_summary`, `query_panel` | 搜索、获取、摘要 dashboards；执行 panel 查询 |
| **Datasources** | `list_datasources`, `get_datasource_by_uid` | 列出和检查已配置的 datasources |
| **Prometheus** | `query_prometheus`, `query_prometheus_range`, `list_prometheus_metric_names`, `list_prometheus_label_names`, `list_prometheus_label_values` | 完整 PromQL 支持 — instant 和 range 查询、metric/label 探索 |
| **Loki** | `query_loki`, `query_loki_range`, `list_loki_label_names`, `list_loki_label_values` | 完整 LogQL 支持 — instant 和 range 查询、label 探索 |
| **Alerting** | `list_alert_rules`, `get_alert_rule_by_uid`, `list_notification_policies`, `list_contact_points` | 列出 alert rules、notification policies 和 contact points |
| **Annotations** | `list_annotations`, `get_annotation_by_id` | 按时间范围、dashboard 或 tags 查询 annotations |
| **Incidents** | `list_incidents`, `get_incident_by_id`, `query_incident_previews` | 列出和检查 Grafana Incident 记录 |
| **OnCall** | `list_oncall_schedules`, `list_oncall_shifts`, `list_oncall_users`, `list_oncall_teams` | 查询 on-call 排班、班次和团队分配 |
| **Sift** | `list_investigations`, `get_investigation` | 访问 Grafana Sift AI 驱动的调查 |
| **Rendering** | `render_panel_png` | 将 dashboard panels 导出为 PNG 图片 |
| **Navigation** | `get_dashboard_deeplink`, `get_explore_deeplink` | 生成 dashboards 和 Explore 的深层链接 |

---

## 3. 设置指南（约 5 分钟）

### 步骤 1：创建 AMG Service Account Token

1. 打开 **Amazon Managed Grafana** 控制台 → 选择您的 workspace
2. 前往 **Administration → Service Accounts**
3. 点击 **Add service account**
   - Name: `devops-agent`
   - Role: **Viewer**
4. 在新建的 service account 上点击 **Add token**
   - 复制生成的 token（格式：`glsa_xxxxxxxxxxxx`）

> ⚠️ **AMG 限制 service account token 最长 30 天。** 请参阅[第 5 节](#5-自动-token-轮换方案)的自动轮换方案。

### 步骤 2：在 DevOps Agent 注册 Grafana

1. 打开 **AWS DevOps Agent** 控制台
2. 前往 **Capability Providers → Grafana**
3. 点击 **Register** 并提供：
   - **Grafana URL**: `https://<workspace-id>.grafana-workspace.<region>.amazonaws.com`
   - **Service Account Token**: `glsa_xxxxxxxxxxxx`
4. 点击 **Register** — DevOps Agent 验证连接并注册服务

### 步骤 3：将 Grafana 关联到 Agent Space

1. 前往 **Agent Spaces** → 选择您的 agent space
2. 前往 **Capabilities → Telemetry**
3. 点击 **Add** → 选择 **Grafana**
4. 保存 — Grafana tools 现在可在此 agent space 使用

---

## 4. AMG 已知限制

| 限制 | 影响 |
|---|---|
| **Service account token 最长 30 天** | Token 会过期需轮换。手动轮换会造成停机。请参阅[第 5 节](#5-自动-token-轮换方案)的自动化方案。 |
| **不支持 Webhook contact points** | AMG 不支持 webhook 类型的 contact points。无法从 AMG alert rules 自动触发 Grafana Sift 调查。 |
| **不支持 ClickHouse datasource** | AMG 无法使用 ClickHouse plugin。如需 ClickHouse 查询请使用自定义 MCP server。 |
| **OpenSearch via Grafana（可能的已知问题）** | 有报告指出 OpenSearch datasource 查询通过 Grafana MCP 集成无法正常工作。如遇此问题，建议直接查询 OpenSearch。 |

---

## 5. 自动 Token 轮换方案

### 架构

```
EventBridge（每 25 天）
    → Lambda
        → Grafana API：创建新 SA token
        → DevOps Agent API：Disassociate → Deregister 旧 → Register 新 → Re-associate
        → Grafana API：删除旧 token
        → Secrets Manager：存储新 token + service ID
```

### 关键 API

```bash
# 注册 Grafana 服务
aws devops-agent register-service \
  --service mcpservergrafana \
  --service-details '{
    "endpoint": "https://<workspace-id>.grafana-workspace.<region>.amazonaws.com",
    "name": "my-grafana",
    "authorizationConfig": {
      "bearerToken": "glsa_xxxxxxxxxxxx"
    }
  }'

# 取消注册旧服务（必须先从 Agent Space 解除关联）
aws devops-agent disassociate-service --agent-space-id <space-id> --service-id <old-service-id>
aws devops-agent deregister-service --service-id <old-service-id>

# 重新关联新服务
aws devops-agent associate-service --agent-space-id <space-id> --service-id <new-service-id>
```

### 轮换行为

- **停机时间**：deregister → register → re-associate 周期约 5-10 秒
- **优雅处理**：Lambda 检查 SDK 可用性并处理部分失败
- **Secret 存储**：新 token 和 service ID 持久化到 Secrets Manager 供下次轮换使用

### 部署

```bash
cd grafana-token-rotation
./deploy.sh

# 用初始 service ID 初始化 secret
aws secretsmanager put-secret-value \
  --secret-id devops-agent/grafana-token \
  --secret-string '{"devopsAgentServiceId":"<your-service-id>","grafanaTokenId":null}'

# 测试轮换
aws lambda invoke --function-name grafana-token-rotation --payload '{}' /dev/stdout
```

---

## 6. 何时使用自定义 Grafana MCP Server

内建集成为只读。如需以下功能请部署**自定义 MCP server**：

| 使用场景 | 为何需要自定义 |
|---|---|
| **写入操作** | 创建/更新 dashboards、alerts 或 annotations |
| **ClickHouse 或 Elasticsearch 直接查询** | 这些 datasources 无法通过 AMG 或内建集成使用 |
| **管理操作** | 管理 teams、users、roles 或 organization 设置 |
| **从 AMG alerts 自动触发调查** | AMG 不支持 Sift 触发所需的 webhook contact points |

### 参考实现

**[aws-samples/sample-aws-devops-agent-ecs-grafana-mcp](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp)**

- CDK 部署
- ECS Fargate + AgentCore Runtime
- Cognito OAuth 2.1 认证
- 完整读写 Grafana MCP server

---

## 7. 测试 Prompts

完成设置后，在 DevOps Agent 控制台尝试以下 prompts：

```
列出我 Grafana workspace 中的所有 dashboards，并摘要最近更新的那个。
```

```
payment-service 有高错误率。检查 Prometheus 过去 2 小时的错误率，
通过 annotations 找到最近的部署，并关联 Loki logs 中的错误详情。
```

```
显示过去 7 天所有标记为 "deployment" 或 "incident" 的 annotations。
```

```
给我完整的健康检查：列出正在触发的 alert rules，查看目前谁在 on-call，
并显示前 3 个服务过去 24 小时的错误率趋势。
```

---

## 参考资源

- [AWS DevOps Agent 文档](https://docs.aws.amazon.com/devops-agent/latest/userguide/)
- [Amazon Managed Grafana — Service Accounts](https://docs.aws.amazon.com/grafana/latest/userguide/service-accounts.html)
- [grafana/mcp-grafana (GitHub)](https://github.com/grafana/mcp-grafana)
- [aws-samples/sample-aws-devops-agent-ecs-grafana-mcp (GitHub)](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp)
- [AWS Blog — Announcing GA of AWS DevOps Agent](https://aws.amazon.com/blogs/mt/announcing-general-availability-of-aws-devops-agent/)
- [Connecting Grafana（官方文档）](https://docs.aws.amazon.com/devopsagent/latest/userguide/connecting-telemetry-sources-connecting-grafana.html)

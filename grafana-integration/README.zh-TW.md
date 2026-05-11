# 整合 AWS DevOps Agent 與 Amazon Managed Grafana

> 📖 [English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

## 1. 概述

AWS DevOps Agent 提供**內建 Grafana 整合**（2026 年 3 月 GA），透過 AWS 託管的 [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana) MCP server。此整合為唯讀，支援：

- **Amazon Managed Grafana (AMG)**
- **Grafana Cloud**
- **Self-managed Grafana**

整合提供 **50+ tools**，涵蓋 dashboards、Prometheus (PromQL)、Loki (LogQL)、alerting、OnCall、annotations、incidents、Sift 和 panel rendering — 可直接在 DevOps Agent 主控台用自然語言查詢您的可觀測性堆疊。

---

## 2. 內建 Grafana 功能

所有 tools 皆為**唯讀**，不會對您的 Grafana 執行任何寫入操作。

| 類別 | Tools | 說明 |
|---|---|---|
| **Dashboards** | `search_dashboards`, `get_dashboard_by_uid`, `get_dashboard_summary`, `query_panel` | 搜尋、取得、摘要 dashboards；執行 panel 查詢 |
| **Datasources** | `list_datasources`, `get_datasource_by_uid` | 列出和檢視已設定的 datasources |
| **Prometheus** | `query_prometheus`, `query_prometheus_range`, `list_prometheus_metric_names`, `list_prometheus_label_names`, `list_prometheus_label_values` | 完整 PromQL 支援 — instant 和 range 查詢、metric/label 探索 |
| **Loki** | `query_loki`, `query_loki_range`, `list_loki_label_names`, `list_loki_label_values` | 完整 LogQL 支援 — instant 和 range 查詢、label 探索 |
| **Alerting** | `list_alert_rules`, `get_alert_rule_by_uid`, `list_notification_policies`, `list_contact_points` | 列出 alert rules、notification policies 和 contact points |
| **Annotations** | `list_annotations`, `get_annotation_by_id` | 依時間範圍、dashboard 或 tags 查詢 annotations |
| **Incidents** | `list_incidents`, `get_incident_by_id`, `query_incident_previews` | 列出和檢視 Grafana Incident 記錄 |
| **OnCall** | `list_oncall_schedules`, `list_oncall_shifts`, `list_oncall_users`, `list_oncall_teams` | 查詢 on-call 排程、班次和團隊分配 |
| **Sift** | `list_investigations`, `get_investigation` | 存取 Grafana Sift AI 驅動的調查 |
| **Rendering** | `render_panel_png` | 將 dashboard panels 匯出為 PNG 圖片 |
| **Navigation** | `get_dashboard_deeplink`, `get_explore_deeplink` | 產生 dashboards 和 Explore 的深層連結 |

---

## 3. 設定指南（約 5 分鐘）

### 步驟 1：建立 AMG Service Account Token

1. 開啟 **Amazon Managed Grafana** 主控台 → 選擇您的 workspace
2. 前往 **Administration → Service Accounts**
3. 點擊 **Add service account**
   - Name: `devops-agent`
   - Role: **Viewer**
4. 在新建的 service account 上點擊 **Add token**
   - 複製產生的 token（格式：`glsa_xxxxxxxxxxxx`）

> ⚠️ **AMG 限制 service account token 最長 30 天。** 請參閱[第 5 節](#5-自動-token-輪換方案)的自動輪換方案。

### 步驟 2：在 DevOps Agent 註冊 Grafana

1. 開啟 **AWS DevOps Agent** 主控台
2. 前往 **Capability Providers → Grafana**
3. 點擊 **Register** 並提供：
   - **Grafana URL**: `https://<workspace-id>.grafana-workspace.<region>.amazonaws.com`
   - **Service Account Token**: `glsa_xxxxxxxxxxxx`
4. 點擊 **Register** — DevOps Agent 驗證連線並註冊服務

### 步驟 3：將 Grafana 關聯到 Agent Space

1. 前往 **Agent Spaces** → 選擇您的 agent space
2. 前往 **Capabilities → Telemetry**
3. 點擊 **Add** → 選擇 **Grafana**
4. 儲存 — Grafana tools 現在可在此 agent space 使用

---

## 4. AMG 已知限制

| 限制 | 影響 |
|---|---|
| **Service account token 最長 30 天** | Token 會過期需輪換。手動輪換會造成停機。請參閱[第 5 節](#5-自動-token-輪換方案)的自動化方案。 |
| **不支援 Webhook contact points** | AMG 不支援 webhook 類型的 contact points。無法從 AMG alert rules 自動觸發 Grafana Sift 調查。 |
| **不支援 ClickHouse datasource** | AMG 無法使用 ClickHouse plugin。如需 ClickHouse 查詢請使用自訂 MCP server。 |
| **OpenSearch via Grafana（可能的已知問題）** | 有報告指出 OpenSearch datasource 查詢透過 Grafana MCP 整合無法正常運作。如遇此問題，建議直接查詢 OpenSearch。 |

---

## 5. 自動 Token 輪換方案

### 架構

```
EventBridge（每 25 天）
    → Lambda
        → Grafana API：建立新 SA token
        → DevOps Agent API：Disassociate → Deregister 舊 → Register 新 → Re-associate
        → Grafana API：刪除舊 token
        → Secrets Manager：儲存新 token + service ID
```

### 關鍵 API

```bash
# 註冊 Grafana 服務
aws devops-agent register-service \
  --service mcpservergrafana \
  --service-details '{
    "endpoint": "https://<workspace-id>.grafana-workspace.<region>.amazonaws.com",
    "name": "my-grafana",
    "authorizationConfig": {
      "bearerToken": "glsa_xxxxxxxxxxxx"
    }
  }'

# 取消註冊舊服務（必須先從 Agent Space 解除關聯）
aws devops-agent disassociate-service --agent-space-id <space-id> --service-id <old-service-id>
aws devops-agent deregister-service --service-id <old-service-id>

# 重新關聯新服務
aws devops-agent associate-service --agent-space-id <space-id> --service-id <new-service-id>
```

### 輪換行為

- **停機時間**：deregister → register → re-associate 週期約 5-10 秒
- **優雅處理**：Lambda 檢查 SDK 可用性並處理部分失敗
- **Secret 儲存**：新 token 和 service ID 持久化到 Secrets Manager 供下次輪換使用

### 部署

```bash
cd grafana-token-rotation
./deploy.sh

# 用初始 service ID 初始化 secret
aws secretsmanager put-secret-value \
  --secret-id devops-agent/grafana-token \
  --secret-string '{"devopsAgentServiceId":"<your-service-id>","grafanaTokenId":null}'

# 測試輪換
aws lambda invoke --function-name grafana-token-rotation --payload '{}' /dev/stdout
```

---

## 6. 何時使用自訂 Grafana MCP Server

內建整合為唯讀。如需以下功能請部署**自訂 MCP server**：

| 使用場景 | 為何需要自訂 |
|---|---|
| **寫入操作** | 建立/更新 dashboards、alerts 或 annotations |
| **ClickHouse 或 Elasticsearch 直接查詢** | 這些 datasources 無法透過 AMG 或內建整合使用 |
| **管理操作** | 管理 teams、users、roles 或 organization 設定 |
| **從 AMG alerts 自動觸發調查** | AMG 不支援 Sift 觸發所需的 webhook contact points |

### 參考實作

**[aws-samples/sample-aws-devops-agent-ecs-grafana-mcp](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp)**

- CDK 部署
- ECS Fargate + AgentCore Runtime
- Cognito OAuth 2.1 認證
- 完整讀寫 Grafana MCP server

---

## 7. 測試 Prompts

完成設定後，在 DevOps Agent 主控台嘗試以下 prompts：

```
列出我 Grafana workspace 中的所有 dashboards，並摘要最近更新的那個。
```

```
payment-service 有高錯誤率。檢查 Prometheus 過去 2 小時的錯誤率，
透過 annotations 找到最近的部署，並關聯 Loki logs 中的錯誤詳情。
```

```
顯示過去 7 天所有標記為 "deployment" 或 "incident" 的 annotations。
```

```
給我完整的健康檢查：列出正在觸發的 alert rules，查看目前誰在 on-call，
並顯示前 3 個服務過去 24 小時的錯誤率趨勢。
```

---

## 參考資源

- [AWS DevOps Agent 文件](https://docs.aws.amazon.com/devops-agent/latest/userguide/)
- [Amazon Managed Grafana — Service Accounts](https://docs.aws.amazon.com/grafana/latest/userguide/service-accounts.html)
- [grafana/mcp-grafana (GitHub)](https://github.com/grafana/mcp-grafana)
- [aws-samples/sample-aws-devops-agent-ecs-grafana-mcp (GitHub)](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp)
- [AWS Blog — Integrating Grafana with DevOps Agent](https://aws.amazon.com/blogs/devops/integrating-grafana-with-aws-devops-agent/)

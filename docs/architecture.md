# Architecture Diagrams

These diagrams use [Mermaid](https://mermaid.js.org/) syntax and render natively on GitHub.

## 1. Agent Space Design — On-Call Boundary Pattern

```mermaid
graph TB
    subgraph "Agent Space: EcommerceProd"
        direction TB
        AS1[Agent Space Role<br/>AIOpsAssistantPolicy]
        A1[Account 111<br/>Frontend]
        A2[Account 222<br/>API + Lambda]
        A3[Account 333<br/>RDS + DynamoDB]
    end

    subgraph "Agent Space: EcommerceNonProd"
        direction TB
        AS2[Agent Space Role]
        A4[Account 444<br/>Staging]
        A5[Account 555<br/>Development]
    end

    OC1[Prod On-Call Team] --> AS1
    OC2[Non-Prod On-Call Team] --> AS2

    style AS1 fill:#ff9900,color:#fff
    style AS2 fill:#ff9900,color:#fff
    style OC1 fill:#232f3e,color:#fff
    style OC2 fill:#232f3e,color:#fff
```

## 2. Reactive Pattern — AMG Alert → DevOps Agent

```mermaid
sequenceDiagram
    participant CW as CloudWatch<br/>Metrics
    participant AMG as Amazon Managed<br/>Grafana
    participant SNS as SNS Topic
    participant Lambda as Lambda<br/>(HMAC Sign)
    participant DA as DevOps Agent<br/>Webhook
    participant Slack as Slack

    CW->>AMG: Metric breach
    AMG->>SNS: Alert (messageFormat:json)
    SNS->>Lambda: SNS notification
    Lambda->>Lambda: Format payload + HMAC-SHA256 sign
    Lambda->>DA: POST /webhook/generic/{id}<br/>x-amzn-event-signature
    DA->>DA: Investigate (logs, metrics, traces, code)
    DA->>Slack: Investigation results + follow-up options
```

## 3. Proactive Pattern — Scheduled Investigation

```mermaid
sequenceDiagram
    participant EB as EventBridge<br/>Scheduler
    participant Lambda as Lambda<br/>(HMAC Sign)
    participant DA as DevOps Agent<br/>Webhook
    participant EBOut as EventBridge<br/>(aws.aidevops)
    participant Report as Report<br/>Generator

    EB->>Lambda: Cron trigger (daily/weekly)
    Lambda->>Lambda: Build payload + HMAC sign
    Lambda->>DA: POST /webhook/generic/{id}
    DA->>DA: Investigate with Custom Skill
    DA->>EBOut: Event: Completed
    EBOut->>Report: Generate optimization report
```

## 4. MCP Server Integration Pattern

```mermaid
graph LR
    subgraph "Agent Space"
        DA[DevOps Agent]
    end

    subgraph "Public Internet"
        MCP1[MCP Server<br/>OpenSearch<br/>via API GW + Cognito]
        MCP2[MCP Server<br/>Custom Telemetry]
    end

    subgraph "VPC (Private)"
        OS[OpenSearch<br/>Cluster]
        DB[(Custom DB)]
    end

    DA -->|HTTPS + OAuth 2.0| MCP1
    DA -->|HTTPS + API Key| MCP2
    MCP1 -->|VPC Link| OS
    MCP2 -->|VPC Link| DB

    style DA fill:#ff9900,color:#fff
    style MCP1 fill:#527fff,color:#fff
    style MCP2 fill:#527fff,color:#fff
```

## 5. Self-hosted Grafana — Direct Webhook (Zero Lambda)

```mermaid
sequenceDiagram
    participant G as Self-hosted<br/>Grafana
    participant DA as DevOps Agent<br/>Webhook

    G->>G: Alert fires
    G->>G: Notification Template<br/>(devops-agent-payload + HMAC)
    G->>DA: POST /webhook/generic/{id}<br/>Direct Webhook Contact Point
    DA->>DA: Investigate
```

## 6. EventBridge Bidirectional Integration

```mermaid
graph LR
    subgraph Inbound
        EXT[External Events] --> L1[Lambda] --> WH[HMAC Webhook]
    end

    WH --> DA[DevOps Agent]

    subgraph Outbound
        DA --> EB[EventBridge<br/>source: aws.aidevops]
        EB --> |Completed| ACT1[Slack Notification]
        EB --> |Failed| ACT2[PagerDuty Escalation]
        EB --> |TimedOut| ACT3[Auto-Retry Lambda]
    end

    style DA fill:#ff9900,color:#fff
    style EB fill:#e7157b,color:#fff
```

## 7. Cross-Team Investigation Pattern

```mermaid
graph TB
    subgraph "Team A Agent Space"
        ASA[Agent Space A<br/>Frontend Services]
        RA[Read-Only Access] -.-> Shared
    end

    subgraph "Team B Agent Space"
        ASB[Agent Space B<br/>Backend Services]
        RB[Read-Only Access] -.-> Shared
    end

    subgraph "Shared Resources"
        Shared[Shared DB / Network<br/>tag: app-id]
    end

    subgraph "Escalation"
        RK[Runbook] --> Slack[Slack Channel]
    end

    ASA --> RK
    ASB --> RK

    style ASA fill:#ff9900,color:#fff
    style ASB fill:#ff9900,color:#fff
    style Shared fill:#3f8624,color:#fff
```

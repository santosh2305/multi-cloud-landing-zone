# Multi-Cloud Landing Zone — Architecture Diagrams

All diagrams are written in Mermaid and render natively in GitHub.

---

## 1. Overall Architecture

```mermaid
graph TB
    subgraph "Identity Plane"
        AAD[Azure Active Directory<br/>Single IdP]
        SSO[AWS IAM Identity Center<br/>SAML Federation]
        PIM[Azure PIM<br/>Privileged Access]
        AAD --> SSO
        AAD --> PIM
    end

    subgraph "AWS Organisation"
        subgraph "Management Account"
            CT[Control Tower]
            ORG[AWS Organizations]
        end

        subgraph "Security OU"
            AUDIT[Log Archive Account<br/>CloudTrail + Config + GuardDuty]
            SEC[Security Tooling Account<br/>Security Hub]
        end

        subgraph "Shared Services OU"
            NET_AWS[Networking Account<br/>Transit Gateway + Egress VPC]
            DNS_AWS[DNS Account<br/>Route53 Resolver]
        end

        subgraph "Workloads OU"
            subgraph "Production"
                PROD_GEN[Generation Domain<br/>Prod Account]
                PROD_GRID[Grid Domain<br/>Prod Account]
                PROD_RETAIL[Retail Domain<br/>Prod Account]
            end
            subgraph "Non-Production"
                NONPROD[Dev/Staging<br/>Accounts]
            end
        end
    end

    subgraph "Azure Tenant"
        subgraph "Root Management Group"
            POL[Policy Initiatives<br/>Region Lock + Tagging]
        end

        subgraph "Platform MG"
            CONN[Connectivity Subscription<br/>vWAN Hub + Azure Firewall]
            MGMT[Management Subscription<br/>Log Analytics + Sentinel]
            IDENT[Identity Subscription<br/>Azure AD DS if needed]
        end

        subgraph "Landing Zones MG"
            subgraph "Production MG"
                AZ_PROD_GEN[Generation<br/>Prod Subscription]
                AZ_PROD_GRID[Grid<br/>Prod Subscription]
            end
            subgraph "Non-Prod MG"
                AZ_NONPROD[Dev/Staging<br/>Subscriptions]
            end
        end
    end

    subgraph "On-Premises"
        ONPREM[Data Centres<br/>2x Locations MPLS]
    end

    NET_AWS <-->|IPsec VPN| CONN
    NET_AWS <-->|VPN| ONPREM
    CONN <-->|ExpressRoute| ONPREM

    classDef aws fill:#FF9900,color:#000,stroke:#FF9900
    classDef azure fill:#0078D4,color:#fff,stroke:#0078D4
    classDef identity fill:#7B2D8B,color:#fff,stroke:#7B2D8B
    classDef onprem fill:#666,color:#fff,stroke:#666

    class CT,ORG,AUDIT,SEC,NET_AWS,DNS_AWS,PROD_GEN,PROD_GRID,PROD_RETAIL,NONPROD aws
    class POL,CONN,MGMT,IDENT,AZ_PROD_GEN,AZ_PROD_GRID,AZ_NONPROD azure
    class AAD,SSO,PIM identity
    class ONPREM onprem
```

---

## 2. Network Topology

```mermaid
graph LR
    subgraph "AWS — eu-west-1"
        TGW[Transit Gateway]
        
        subgraph "Shared Services VPC"
            EGRESS[Egress VPC<br/>NAT + Inspection]
            DNS_VPC[DNS VPC<br/>Route53 Resolver]
        end

        subgraph "Workload VPCs"
            GEN_VPC[Generation VPC<br/>10.0.16.0/20]
            GRID_VPC[Grid VPC<br/>10.0.32.0/20]
            RETAIL_VPC[Retail VPC<br/>10.0.48.0/20]
        end

        GEN_VPC --> TGW
        GRID_VPC --> TGW
        RETAIL_VPC --> TGW
        EGRESS --> TGW
        DNS_VPC --> TGW
    end

    subgraph "Azure — West Europe"
        VWAN[Virtual WAN Hub<br/>10.16.0.0/23]
        AFW[Azure Firewall<br/>in vWAN Hub]

        subgraph "Spoke VNets"
            AZ_GEN[Generation VNet<br/>10.16.16.0/20]
            AZ_GRID[Grid VNet<br/>10.16.32.0/20]
        end

        AZ_GEN --> VWAN
        AZ_GRID --> VWAN
        VWAN --> AFW
    end

    subgraph "On-Premises"
        DC1[DC — Location 1<br/>172.16.0.0/16]
        DC2[DC — Location 2<br/>172.17.0.0/16]
    end

    TGW <-->|IPsec VPN<br/>BGP| VWAN
    TGW <-->|VPN| DC1
    VWAN <-->|ExpressRoute| DC1
    DC1 <-->|MPLS| DC2
```

---

## 3. Identity Flow

```mermaid
sequenceDiagram
    participant User
    participant AAD as Azure AD
    participant SSO as AWS IAM Identity Center
    participant STS as AWS STS
    participant PIM as Azure PIM

    Note over User,PIM: Standard Access (AWS Console)
    User->>AAD: Authenticate (MFA enforced)
    AAD->>SSO: SAML assertion
    SSO->>STS: AssumeRoleWithSAML
    STS->>User: Temporary credentials (8hr max)

    Note over User,PIM: Privileged Access (Azure)
    User->>PIM: Request elevation
    PIM->>AAD: Just-In-Time role assignment
    AAD->>User: Time-limited privileged access (4hr max)
    PIM->>PIM: Audit log + optional approval workflow
```

---

## 4. Log Aggregation Flow

```mermaid
flowchart LR
    subgraph "AWS Workload Accounts"
        CT_WL[CloudTrail]
        GD[GuardDuty]
        CFG[AWS Config]
        VFL[VPC Flow Logs]
    end

    subgraph "AWS Log Archive Account"
        S3[S3 — Object Lock<br/>7yr retention]
        SH[Security Hub<br/>Findings aggregation]
    end

    subgraph "Azure Workload Subscriptions"
        ACTLOG[Activity Logs]
        DIAG[Diagnostic Settings]
        DEF[Defender for Cloud]
    end

    subgraph "Azure Security Subscription"
        LAW[Log Analytics Workspace]
        SENT[Microsoft Sentinel<br/>SIEM]
        ABLOB[Immutable Blob Storage<br/>7yr retention]
    end

    CT_WL --> S3
    GD --> SH
    CFG --> S3
    VFL --> S3
    SH --> SENT

    ACTLOG --> LAW
    DIAG --> LAW
    DEF --> SENT
    LAW --> ABLOB
```

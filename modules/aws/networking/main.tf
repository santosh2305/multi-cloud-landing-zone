# modules/aws/networking/main.tf
#
# Deploys the Transit Gateway hub-and-spoke network topology.
# See ADR-003 for topology decision rationale.
#
# This module is deployed in the dedicated Networking account.
# Workload accounts attach their VPCs via RAM (Resource Access Manager) share.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Transit Gateway
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Central hub for all VPC connectivity. See ADR-003."
  amazon_side_asn                 = var.tgw_asn
  auto_accept_shared_attachments  = "disable" # Explicit attachment acceptance required
  default_route_table_association = "disable" # Custom route tables defined below
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-tgw"
  })
}

# Share TGW with the entire AWS Organisation via RAM
resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.environment}-tgw-share"
  allow_external_principals = false # Org-only sharing

  tags = var.common_tags
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = var.organization_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# ---------------------------------------------------------------------------
# Transit Gateway Route Tables
# See ADR-003: Route table segmentation between prod and non-prod
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_route_table" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-tgw-rt-prod"
    Purpose = "Routes for production workload VPCs + shared services. No non-prod routes."
  })
}

resource "aws_ec2_transit_gateway_route_table" "nonprod" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-tgw-rt-nonprod"
    Purpose = "Routes for dev/staging VPCs + shared services. Explicitly isolated from prod."
  })
}

resource "aws_ec2_transit_gateway_route_table" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-tgw-rt-shared"
    Purpose = "Shared services VPC route table. Reachable from prod and non-prod."
  })
}

resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-tgw-rt-inspection"
    Purpose = "Egress inspection VPC. Default route for internet-bound traffic."
  })
}

# ---------------------------------------------------------------------------
# Egress VPC (centralised internet egress with inspection)
# ---------------------------------------------------------------------------

resource "aws_vpc" "egress" {
  cidr_block           = var.egress_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-egress-vpc"
    Purpose = "Centralised internet egress. All internet traffic must route through here for inspection."
  })
}

resource "aws_subnet" "egress_tgw" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.egress.id
  cidr_block        = cidrsubnet(var.egress_vpc_cidr, 4, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-egress-tgw-${var.availability_zones[count.index]}"
    Tier = "tgw-attachment"
  })
}

resource "aws_subnet" "egress_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.egress.id
  cidr_block              = cidrsubnet(var.egress_vpc_cidr, 4, count.index + length(var.availability_zones))
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false # No direct public IP assignment

  tags = merge(var.common_tags, {
    Name = "${var.environment}-egress-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_internet_gateway" "egress" {
  vpc_id = aws_vpc.egress.id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-egress-igw"
  })
}

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-egress-nat-eip-${count.index}"
    AZ   = var.availability_zones[count.index]
  })
}

resource "aws_nat_gateway" "egress" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.egress_public[count.index].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-egress-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.egress]
}

# ---------------------------------------------------------------------------
# TGW Attachment for Egress VPC
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "egress" {
  subnet_ids         = aws_subnet.egress_tgw[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.egress.id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-tgw-attach-egress"
    Purpose = "Egress VPC attachment"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "egress" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Default route: all traffic from prod/nonprod goes to inspection VPC
resource "aws_ec2_transit_gateway_route" "prod_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route" "nonprod_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}

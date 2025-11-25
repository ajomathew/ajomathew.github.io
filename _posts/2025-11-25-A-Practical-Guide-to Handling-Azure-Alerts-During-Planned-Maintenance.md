---
title: A Practical Guide to Handling Azure Alerts During Planned Maintenance
date: 2025-11-25
categories: [azure]
tags:
  - azure
  - azure-monitor
  - alert-processing-rules
  - planned-maintenance
  - monitoring
  - devops
---

# Problem description

Availability alerts for VMs in a resource group were configured. During planned maintenance (for example, a VM reboot), the team receives VM availability notifications that are false positives. How can we avoid or resolve these false alarms?

# Approaches

The alert in question uses VM availability metrics evaluated every 1 minute with a 5‑minute lookback window.

## Option 1 — Disable the alert during the maintenance window
- When you stop the VM, disable the alert.
- When you start the VM, re-enable the alert.

This is a simple approach but requires coordinating the start/stop process with alert management.

> Note
> The lookback period is 5 minutes; alerts are evaluated every minute across that window. If a VM stops responding within that window (for example, during reboot), the alert rule can trigger even though the outage is expected.

A common workaround is to add a short delay between VM stop/start and the alert state change (e.g., 6–7 minutes), but that is brittle and depends on the VM heartbeat reporting reliably to Azure Monitor.

## Option 2 — Use Azure Alert Processing Rules (recommended)

### What are Alert Processing Rules (APRs) and how do they work?
Alert Processing Rules (APRs) are a post-processing layer in Azure Monitor that modify what happens after an alert fires — without changing the alert rule itself. APRs let you:

- Suppress notifications (remove action groups)
- Redirect or add action groups
- Override action groups
- Route alerts based on schedule, time, or resource conditions

When an alert fires:
1. Azure Monitor generates an Alert Instance.
2. APRs check whether the alert matches configured rules.
3. APRs apply modifications (suppress, add/remove/override action groups, or route).
4. The modified alert is forwarded to the (modified) action groups.

TL;DR: APRs let you centrally control, suppress, or route alert notifications after an alert fires — without touching each alert rule.

## Implementation using Azure CLI

In my environment, the VM stop/start was implemented with Azure CLI, so I used the `az monitor alert-processing-rule` commands.

> Info: Preview status
> As of 25/11/2025 this feature is in preview according to the Azure docs. (Check the latest docs before production use.)

I injected logic like the script below into the existing stop/start VM script to create or update an APR that suppresses action groups for a short window:

```bash
#!/usr/bin/env bash

# Variables
RESOURCE_GROUP="my-demo-rg"
RULE_NAME="mpclncus-alert-dap-ahub-VM-Availability-processing-rule"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

echo "Checking if alert processing rule '$RULE_NAME' exists..."
RULE_EXISTS=$(az monitor alert-processing-rule show \
  --name "$RULE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv 2>/dev/null)

if [ -z "$RULE_EXISTS" ]; then
  echo "Rule does not exist. Creating new alert processing rule..."
  START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
  END_TIME=$(date -u -d '+10 minutes' +"%Y-%m-%d %H:%M:%S")

  az monitor alert-processing-rule create \
    --name "$RULE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$SCOPE" \
    --rule-type RemoveAllActionGroups \
    --filter-alert-rule-name "Equals vm-availability-alert" \
    --schedule-start-datetime "$START_TIME" \
    --schedule-end-datetime "$END_TIME" \
    --schedule-time-zone "UTC" \
    --enabled true \
    --description "Suppression window: $START_TIME to $END_TIME"

  echo "Alert processing rule created successfully."
else
  echo "Rule exists. Updating suppression window..."
  START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")
  END_TIME=$(date -u -d '+10 minutes' +"%Y-%m-%dT%H:%M:%S")

  az monitor alert-processing-rule update \
    --name "$RULE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --set properties.schedule.effectiveFrom="$START_TIME" \
    --set properties.schedule.effectiveUntil="$END_TIME"

  echo "Alert processing rule updated successfully."
fi

echo "Suppression window: $START_TIME to $END_TIME (UTC)"inst a resource group VM availability alerts has been configured. During planned maintenance - VM reboot - team is getting notifications on VM availability, which is a false positive. How to resolve avoid these false positives.

# Approaches
The alert in question uses VM availability metrics evaluated every 1 minute with a 5‑minute lookback window.
## Option 1 — Disable the alert during the maintenance window
- When you stop the VM, disable the alert.
- When you start the VM, re-enable the alert.

This is a simple approach but requires coordinating the start/stop process with alert management.

> Note
> The lookback period is 5 minutes; alerts are evaluated every minute across that window. If a VM stops responding within that window (for example, during reboot), the alert rule can trigger even though the outage is expected.

A common workaround is to add a short delay between VM stop/start and the alert state change (e.g., 6–7 minutes), but that is brittle and depends on the VM heartbeat reporting reliably to Azure Monitor.

## Option 2 — Use Azure Alert Processing Rules (recommended)

### What are Alert Processing Rules (APRs) and how do they work?
Alert Processing Rules (APRs) are a post-processing layer in Azure Monitor that modify what happens after an alert fires — without changing the alert rule itself. APRs let you:

- Suppress notifications (remove action groups)
- Redirect or add action groups
- Override action groups
- Route alerts based on schedule, time, or resource conditions

They allow central control of alert behavior independent of alert definitions.

When an alert fires:
1. Azure Monitor generates an **Alert Instance**
2. APRs check if the alert matches the rules
3. APR applies modifications such as:
    - **Suppress** (remove action groups)
    - **Add** action groups
    - **Remove** action groups
    - **Override** action groups
    - **Route** based on schedule
4. Modified alert goes to the action groups
APR ≠ Alert Rules — APRs are post-processing of fired alerts.

TL;DR: APRs let you centrally control, suppress, or route alert notifications after the alert fires — without touching each alert rule.

## Implementation using Azure CLI

In my environment, the VM stop/start was implemented with Azure CLI, so I used the `az monitor alert-processing-rule` commands.

> Info: Preview status
> As of 25/11/2025 this feature is in preview according to the Azure docs. (Check the latest docs before production use.)

I injected logic like the script below into the existing stop/start VM script to create or update an APR that suppresses action groups for a short window:
```bash
#!/bin/bash

# Variables
RESOURCE_GROUP="my-demo-rg"
RULE_NAME="VM-Availability-processing-rule"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
# Calculate time windows (UTC)
# Check if alert processing rule exists
echo "Checking if alert processing rule '$RULE_NAME' exists..."
RULE_EXISTS=$(az monitor alert-processing-rule show \
    --name "$RULE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv 2>/dev/null)
if [ -z "$RULE_EXISTS" ]; then
    echo "Rule does not exist. Creating new alert processing rule..."
    START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
    END_TIME=$(date -u -d '+10 minutes' +"%Y-%m-%d %H:%M:%S")
  az monitor alert-processing-rule create \
           --name "$RULE_NAME" \
           --resource-group "$RESOURCE_GROUP" \
           --scopes "$SCOPE" \
           --rule-type RemoveAllActionGroups \
  --filter-alert-rule-name "Equals vm-availability-alert" \
           --schedule-start-datetime "$START_TIME" \
           --schedule-end-datetime "$END_TIME" \
           --schedule-time-zone "UTC" \
           --enabled true \
           --description "Suppression window: $START_TIME to $END_TIME"
    echo "Alert processing rule created successfully."
else
    echo "Rule exists. Updating suppression window..."
  # 'yyyy'-'MM'-'dd'T'HH':'mm':'ss'
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")
    END_TIME=$(date -u -d '+10 minutes' +"%Y-%m-%dT%H:%M:%S")
    az monitor alert-processing-rule update \
        --name "$RULE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --set properties.schedule.effectiveFrom="$START_TIME" \
        --set properties.schedule.effectiveUntil="$END_TIME"
        # --description "Updated suppression window: $START_TIME to $END_TIME"
    echo "Alert processing rule updated successfully."
fi
echo "Suppression window: $START_TIME to $END_TIME (UTC)"
```

#### Couple of observations

While using `az monitor alert-processing-rule create` with filters it is required that we use the parameter with `Equals `.
Example:
- --filter-alert-rule-name Equals vm-availability-alert

Filter format is `<operator> <space-delimited values>` where Operator: one of Equals, NotEquals, Contains, DoesNotContain Values: List of values to match for a given condition.

When using `az monitor alert-processing-rule update` with `--set` 
Update an object by specifying a property path and value to set. Example: `--set property1.property2=<value>`.

```
--set properties.schedule.effectiveFrom="$START_TIME" \
--set properties.schedule.effectiveUntil="$END_TIME"
```

The time format expected in `az monitor alert-processing-rule create` is `'yyyy'-'MM'-'dd' 'HH':'mm':'ss'`
The time format expected in `az monitor alert-processing-rule update` is `'yyyy'-'MM'-'dd'T'HH':'mm':'ss'`

between 'dd' it is ' ' for `create` and 'T' for `update`
---
categories:
- azure
date: '2025-11-25T00:00:00Z'
tags:
- azure
- azure-monitor
- alert-processing-rules
- planned-maintenance
- monitoring
- devops
title: A Practical Guide to Handling Azure Alerts During Planned Maintenance
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
RULE_NAME="VM-Availability-processing-rule"
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


between 'dd' and 'HH' there '<space>' for `az monitor alert-processing-rule create` and 'T' for `az monitor alert-processing-rule update`

# Some of the gotchas 


# Azure Monitor Alert Suppression During Planned VM Downtime

### *Understanding how Alert Processing Rules behave when VM availability alerts fire during suppression*

When performing planned maintenance on Azure Virtual Machines, it's common to temporarily suppress alerts to avoid unnecessary notifications. **Alert Processing Rules (APRs)** in Azure Monitor allow you to mute alert **notifications** without modifying the alert rules themselves.

However, the behavior of alerts *during* and *after* suppression can be confusing.
This guide explains exactly what happens when a **VM Availability** alert fires while suppression is active.

---

## Scenario Overview

You have:

* **Metric Alert:** VM Availability (Percentage)
* **Condition:** Average availability `< 1`
* **Evaluation:** Every **1 minute**, lookback of **5 minutes**
* **Scope:** Resource Group
* **Action Groups:** Email / Teams / Webhook
* **Alert Processing Rule:** Suppress notifications for **10 minutes**

Then you:

* Stop the VM
* The alert fires
* In Azure Portal it shows: **Fired (Suppressed)**

You want to know:

1. What happens when suppression ends and the VM is still off?
2. What happens if you disable the suppression rule after 10 minutes?

---

## 1. When suppression ends and the VM is still off, will I get a notification?

**No — you will *not* receive a notification.**

### Why?

#### Suppressed alerts never “re-send” notifications

From Microsoft Learn:

> “The fired alerts won’t invoke any of their action groups, **not even at the end of the maintenance window**.”
> — Alert Processing Rules

This means:

* The alert **did** fire
* It is **visible** in the portal
* But the action groups were removed when it fired
* Azure Monitor will **not** send notifications after suppression expires

#### Metric alerts are stateful

From Microsoft:

> “Metric alerts are stateful… notifications are sent only when the **state changes** (fired → resolved → fired).”
> — Metric Alerts Overview

Since the VM stayed off, the alert state stayed as **Fired**.
No state change → No new notification.

---

## 2. If I disable the alert processing rule after suppression, will I get the notification now?

**No — disabling the APR will not retroactively send notifications.**

Once suppression is applied:

* The alert is already in "Fired" state
* Its action groups were removed
* Disabling APR only affects **future** alerts
* Azure does **not** “replay” suppressed action groups

From Microsoft:

> “Suppression applies to alerts as they are fired. Fired alerts will not retroactively run their action groups.”

So you will **not** receive any notification unless the alert **resolves and fires again**.

---

## How to trigger notifications after suppression

Azure Monitor requires the alert to **resolve → fire again** to send notifications.

### **Option A: Restart → Stop the VM**

1. Start the VM → Alert **resolves**
2. Stop it again → Alert **fires**
3. Notifications flow normally (suppression no longer active)

### **Option B: Change alert settings temporarily**

Adjust threshold or evaluation → forces a new alert firing.

### **Option C: Test action groups**

Azure Portal → **Action Groups → Test**

---

## Summary Table

| Scenario                                  | Notification Sent? | Reason                       |
| ----------------------------------------- | ------------------ | ---------------------------- |
| Alert fires during suppression            | ❌ No               | Action groups removed        |
| Suppression ends while alert still active | ❌ No               | No state change              |
| Disable suppression after alert fired     | ❌ No               | Past alerts don't re-trigger |
| VM resolves → fires again                 | ✅ Yes              | New state change             |

---

## Key Takeaways

* APR suppresses **notifications**, not the alert itself
* Suppressed notifications are **not replayed** after the window
* Metric alerts only fire again after a **state change**
* If the VM stays off through suppression, you may **miss the alert completely**
* To receive alert notifications after suppression, the alert must **resolve and re-fire**


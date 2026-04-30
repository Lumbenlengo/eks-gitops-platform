# ADR 003 — KEDA over HPA for Worker Service Autoscaling

**Status:** Accepted  
**Date:** 2025-01-01  
**Author:** Patricio Lumbe

---

## Context

The worker service consumes SQS messages. We needed to decide how to scale it.

- **Option A — HPA on CPU/Memory**: Scale based on pod resource usage.
- **Option B — KEDA**: Scale based on SQS queue depth (number of messages waiting).

## Decision

**Option B — KEDA** with `minReplicaCount: 0`.

## Rationale

CPU and memory are lagging indicators for a queue consumer. The pod is idle (low CPU, low memory)
when there are no messages — exactly when it should scale down to zero. When a burst of 500
messages arrives, CPU will only spike *after* pods start consuming — HPA would react too late.

KEDA reads the SQS `ApproximateNumberOfMessages` attribute directly and scales proportionally:
5 messages per replica means 100 messages → 20 replicas, proactively. When the queue empties,
KEDA scales to **zero** — zero idle pods, zero idle cost. HPA cannot scale to zero.

This is the correct architectural pattern for event-driven workloads. The worker service does
not need to run when there is nothing to process.

## Cost implication

At `minReplicaCount: 0`, the worker service costs $0.00 when idle. With HPA minimum of 2 pods on
t3.medium nodes, idle cost is approximately $0.09/hour. At production scale this saving is
significant.

---

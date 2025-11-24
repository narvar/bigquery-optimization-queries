# Option Analysis: Overriding Org-Level Assignment

## Problem
- Entire narvar.com organization assigned to bq-narvar-admin:US.default
- Cannot simply "remove" messaging from reservation
- Need a way to override org-level assignment for specific service account

## Potential Solutions

### Solution A: Create 0-slot reservation (forces on-demand)
1. Create a dummy reservation with 0 baseline slots
2. Assign messaging service account to dummy reservation
3. Service account will use on-demand (no slots in reservation)

### Solution B: Use different project
1. Create new project outside narvar.com organization
2. Move messaging queries to new project
3. New project uses on-demand by default

### Solution C: Request org-level assignment removal
1. Remove organizations/770066481180 assignment
2. Create individual project assignments instead
3. Exclude messaging project from any assignment

## Recommended: Solution A (0-slot reservation)

# Rule: Architectural Best Practices

## Overview
All solution designs and architecture blueprints must be
specifically tailored to the target platform.

## Rules

1. **Platform-Native First:** Always prioritize the platform's
   own native solutions over custom or generic third-party
   workarounds. This ensures the system is easy to maintain,
   operate, and scale.

   - ✅ Use Snowflake Dynamic Tables for transformation
   - ❌ Do NOT use a generic Python pipeline when a native
     feature exists

2. **Simple Designs:** Prefer the simplest design that meets
   the requirement. Avoid over-engineering.

3. **Production-Ready Standards:** All designs must be:
   - Scalable under real-world load
   - Secure by default (least-privilege access)
   - Observable (logging, monitoring, alerting)
   - Maintainable by a standard team

4. **Adhere to Platform Best Practices:** Reference and apply
   the official best practices documentation for the target
   platform when designing any component.

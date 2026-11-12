---
tags: [skill-creator, coordinator, tier]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit, SendMessage, ToolSearch]
---

/coordinator:start high each test in test_cart.py passes when it runs alone, but the suite fails when the whole file runs. The cause is not known. Find the cause, fix it without a change to the public behavior of cart.py, and run the whole suite.

Input files: cart.py, test_cart.py

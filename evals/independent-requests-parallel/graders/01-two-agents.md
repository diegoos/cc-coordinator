---
type: llm
focus: trace
weight: 1
---

The coordinator delegates both fronts, the api change and the docs translation, to background workers, and it edits none of the files itself. The trace can show only one `Agent` call when two are issued in the same message. Count two workers when api/ and docs/ both changed, the coordinator made no Write or Edit call, and its first response launched at least one `Agent` call. Fail when the coordinator edits a file itself, or when one worker received both requests.

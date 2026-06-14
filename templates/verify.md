# Task
You just completed an executor task. Now verify that the work actually succeeded.

## What to verify
- Run tests, check command output, or inspect files to confirm the result.
- Verify any files you created or modified exist and contain the expected content.
- Confirm the stated outcome matches reality.

## Output Requirements
Return ONE raw JSON object and nothing else.

```json
{"accepted": true, "data": {"verified": true, "issues": ""}}
```

If verification fails:
```json
{"accepted": true, "data": {"verified": false, "issues": "what is wrong, specifically"}}
```

## Rules
- Run the minimum commands needed to confirm. Do not redo the work.
- `issues` must be empty when `verified` is true.
- `issues` must describe the specific problem when `verified` is false.
- Stop after emitting the JSON.

## Context
### Intent
{intent_description}

### Result to verify
{result_description}

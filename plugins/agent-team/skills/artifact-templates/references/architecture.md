# Architecture doc template

Written by `architect` from the PRD. Consumed by `planner` and `implementer`.

```markdown
# Kiến trúc: <name>

## Tổng quan
What shape the system has and why, in a paragraph. Then the diagram.

![](./diagrams/overview.excalidraw)

## Ràng buộc dẫn dắt thiết kế
The constraints that actually forced choices — team size, existing stack,
latency budget, cost ceiling. If a constraint did not change a decision, cut it.

## Thành phần
| Thành phần | Trách nhiệm | Không chịu trách nhiệm |
|---|---|---|

The second column matters more than the first. It is what prevents drift.

## Mô hình dữ liệu
Entities, relationships, identity rules, and where each field's source of truth
lives. Note which fields are denormalised and what keeps them in sync.

## Luồng chính
For each significant flow: trigger, steps, what crosses a process or trust
boundary, what happens on failure at each step.

## Quyết định
Link to ADRs. Do not inline the reasoning here; it goes stale in two places.

- [ADR-0001](./adr/0001-....md) — ...

## Chế độ hỏng
| Hỏng ở đâu | Ai phát hiện | Hệ thống làm gì | Người dùng thấy gì |
|---|---|---|---|

## Bảo mật
Trust boundaries, authn vs authz, secret handling, what is logged and what must
never be.

## Những gì đã cân nhắc rồi loại
Brief. Saves the next person from re-proposing a dead end.
```

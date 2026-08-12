# PRD template

Written by `pm` from the brief. Consumed by `architect` and `planner`.

```markdown
# PRD: <name>

## Bối cảnh
Two or three sentences linking back to the brief. Link, do not restate.

## Người dùng và nhu cầu
| Vai trò | Cần gì | Vì sao |
|---|---|---|

## Phạm vi
### Trong phạm vi
### Ngoài phạm vi

## Yêu cầu chức năng
Numbered so stories and tests can cite them.

**FR-1 — <title>**
- Mô tả:
- Tiêu chí chấp nhận:
  - [ ] Given <state>, when <action>, then <observable result>
  - [ ] Edge: empty / one / many / too many
  - [ ] Lỗi: what the user sees when it fails

## Yêu cầu phi chức năng
Only the ones with a real target. Delete the rest rather than writing "should be
fast".

| Loại | Mục tiêu | Cách đo |
|---|---|---|
| Hiệu năng | | |
| Bảo mật | | |
| Truy cập (a11y) | WCAG 2.1 AA | |

## Dữ liệu
Entities, ownership, source of truth, retention, migration of existing rows.

## Epic và story
| Epic | Story | FR liên quan | Ưu tiên |
|---|---|---|---|

## Rủi ro
| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|

## Câu hỏi mở
```

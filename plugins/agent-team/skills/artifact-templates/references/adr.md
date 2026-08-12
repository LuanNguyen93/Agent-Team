# ADR template

One decision per file: `docs/adr/0001-<slug>.md`. Never edit a decided ADR —
supersede it with a new one and link both ways.

```markdown
# ADR-0001: <decision in one line>

- **Trạng thái**: đề xuất | đã chốt | đã thay thế bởi [ADR-0007](...)
- **Ngày**: YYYY-MM-DD
- **Người quyết định**:

## Bối cảnh
What forced a choice now. The facts as they were known at this date — including
what was uncertain. This is the section future readers actually need.

## Quyết định
What we chose, stated actively: "Chúng tôi dùng X để ...".

## Phương án đã cân nhắc
| Phương án | Ưu | Nhược | Vì sao không chọn |
|---|---|---|---|

## Hệ quả
### Tích cực
### Tiêu cực
Name the real costs. An ADR with no downsides was not a decision.

### Việc này khiến khó làm gì về sau
The most valuable line in the document.
```

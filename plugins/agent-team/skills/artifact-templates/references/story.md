# Story template

Written by `pm`. Consumed by `planner`, then `implementer`, then `reviewer` —
who checks the code against these criteria, so they must be checkable.

```markdown
# <epic>-<n>: <title>

**FR liên quan**: FR-3, FR-4
**Ưu tiên**: cao | trung bình | thấp
**Ước lượng**: S | M | L

## Câu chuyện
Là <vai trò>, tôi muốn <hành động>, để <giá trị>.

The "để" clause is the test of whether the story is worth building.

## Tiêu chí chấp nhận
Given / When / Then. Each one must be checkable by a test or by driving the app.

- [ ] Given ..., when ..., then ...
- [ ] Given ..., when ..., then ...

### Biên
- [ ] Rỗng:
- [ ] Một:
- [ ] Nhiều:
- [ ] Quá nhiều:

### Lỗi
- [ ] Khi <failure>, người dùng thấy <message> và <system state>

## Ngoài phạm vi của story này
Explicit. Prevents the story from quietly absorbing its neighbours.

## Phụ thuộc
Stories or infrastructure that must land first.

## Ghi chú kỹ thuật
Only what the planner cannot derive from the architecture doc.

## Định nghĩa hoàn thành
- [ ] Mọi tiêu chí chấp nhận có test tương ứng
- [ ] Quality gates xanh (typecheck, lint, test, build)
- [ ] Đã review bởi context mới
- [ ] Đã verify trên app thật (nếu có UI)
- [ ] Tài liệu cập nhật nếu hành vi đổi
```

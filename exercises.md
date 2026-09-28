# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Thieu Quang Vinh  Mã học viên: 2A202602877

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống thực tế:
Khi cấu hình deploy trên Render (hoặc chạy local qua Uvicorn), nếu ta quên thiết lập biến môi trường `AGENT_API_KEY`:
- **Nếu để mặc định `"changeme"`:** Ứng dụng vẫn khởi động thành công và online bình thường. Kẻ tấn công hoặc bot quét tự động trên Internet có thể dùng ngay khóa mặc định `"changeme"` này để gửi hàng ngàn request vào endpoint `/ask`, tiêu sạch ngân sách LLM của hệ thống mà ta không hề hay biết cho đến khi nhận hóa đơn thanh toán.
- **Với cơ chế fail-fast:** Pydantic ném ngoại lệ `ValidationError` ngay tại thời điểm khởi tạo `Settings()` lúc container vừa boot. Tiến trình dừng ngay lập tức, báo lỗi trực tiếp trên log Render / terminal giúp ta phát hiện và khắc phục ngay trước khi service nhận bất kỳ request nào từ bên ngoài.

Minh chứng log thực tế khi thiếu biến:
```text
pydantic_core._pydantic_core.ValidationError: 1 validation error for Settings
agent_api_key
  Field required [type=missing, input_value={}, input_type=dict]
```

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log JSON thu được:
```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T12:09:59.135686+00:00", "user_id": "sv01", "tokens_in": 89, "tokens_out": 46, "cost_usd": 4.095e-05}
```

Hai việc làm được:
1. **Truy vấn và thống kê định lượng tự động (Structured Aggregation):** Hệ thống thu thập log (như Loki, Datadog, CloudWatch) có thể parse trực tiếp các trường JSON để chạy hàm tính toán, ví dụ: `sum(cost_usd) by (user_id)` để tìm người dùng tiêu tốn nhiều chi phí nhất trong ngày, hoặc tính `avg(tokens_out)`.
2. **Cấu hình cảnh báo tự động (Alerting):** Có thể viết bộ lọc kích hoạt cảnh báo gửi qua Slack/Telegram khi phát hiện một request có `cost_usd > 0.1` hoặc khi tỷ lệ log mang `level: "error"` vượt quá ngưỡng cho phép trong 5 phút.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ~1015 MB |
| Multi-stage | 272 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Quan sát thực tế trên môi trường:
- Kiểm tra bằng lệnh `docker images`, image multi-stage `day12-agent:prod` (tương đương `agent:multi`) có dung lượng ảo trên Docker Desktop là **272 MB** (dung lượng nội dung content size thật chỉ **64 MB**), nhỏ hơn rất nhiều so với bản 1-stage dùng base image `python:3.11` đầy đủ (~1.01 GB).
- **Phần chênh lệch ~740 MB gồm:**
  1. Trình biên dịch C/C++ (`gcc`, `g++`, `make`), công cụ build, header files hệ thống (`glibc-devel`, `python3-dev`) cần thiết để cài đặt wheel chỉ tồn tại ở stage `builder`. Stage `runtime` chỉ copy thư mục gói đã build (`/install` sang `/usr/local`), hoàn toàn không chứa compiler.
  2. Các gói phần mềm, tài liệu man pages và cache của `apt` bị loại bỏ khi dùng base image dạng `slim`.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

- **Với Dockerfile hiện tại:** Các layer trước `COPY . .` (gồm `COPY requirements.txt .`, `RUN pip install...`, và `COPY --from=builder /install /usr/local`) đều ở trạng thái **CACHED** (thời gian thực thi 0.0s). Chỉ từ layer `COPY . .` và các bước kế tiếp (`RUN useradd...`, export manifest) mới phải chạy lại, quá trình build lại hoàn tất chỉ trong khoảng 0.4s.
- **Nếu đặt `COPY . .` lên trước `RUN pip install`:** Mỗi khi sửa dù chỉ một ký tự code trong `app/main.py`, layer `COPY . .` bị thay đổi khiến Docker invalidate toàn bộ cache từ bước đó trở đi. Docker buộc phải thực thi lại lệnh `RUN pip install`, tải và cài đặt lại toàn bộ thư viện từ `requirements.txt` sau mỗi lần chỉnh sửa code, làm chậm quá trình phát triển rất nhiều lần.

Minh chứng log Docker build thực tế (tận dụng cache):
```text
[+] Building 0.4s (11/11) FINISHED
 => CACHED [builder 2/3] COPY requirements.txt .
 => CACHED [builder 3/3] RUN pip install --no-cache-dir -r requirements.txt
 => CACHED [stage-1 3/5] COPY --from=builder /install /usr/local
 => [stage-1 4/5] COPY . .
```

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

1. **Chuỗi sự kiện:**
   - Kẻ tấn công khai thác một lỗ hổng trong mã nguồn ứng dụng (ví dụ: Command Injection, RCE qua thư viện ngoài).
   - Vì container mặc định chạy bằng `root` (UID 0), tiến trình bị chiếm quyền sẽ có toàn quyền `root` bên trong container.
   - Kẻ tấn công tiếp tục khai thác các lỗ hổng container breakout (lỗ hổng nhân Linux kernel, mount nhầm `docker.sock`, hoặc các Linux capabilities được cấp) để thoát ra hệ thống máy host. Do tiến trình chạy với UID 0, khi thoát ra ngoài nó vẫn giữ nguyên quyền `root` (UID 0) trên máy host, cho phép kiểm soát toàn bộ máy chủ.
2. **Lệnh `USER appuser` cắt đứt chuỗi ở đâu:**
   - Cắt đứt ngay từ bước đầu tiên: hacker sau khi khai thác thành công chỉ chiếm được tiến trình chạy dưới quyền của user thường `appuser` (UID 10001, unprivileged). User này không có quyền ghi vào các thư mục hệ thống, không có đặc quyền `sudo`, và không đủ quyền để thực hiện các kỹ thuật leo thang container breakout.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

- Con số tối đa: **20 request** trong 2 giây.
- Cách đạt được:
  - Người dùng gửi 10 request vào giây `10:00:59` (giây cuối cùng của phút 10) $\rightarrow$ hệ thống tính đủ 10 request cho phút thứ 10.
  - Ngay ở giây kế tiếp `10:01:00` (giây đầu tiên của phút 11), bộ đếm theo phút đồng hồ tự động reset về 0.
  - Người dùng gửi tiếp 10 request nữa ngay tại giây `10:01:00`.
  - Kết quả: trong khoảng thời gian chỉ 2 giây (10:00:59 đến 10:01:00), người dùng đã gửi thành công 20 request mà không bị chặn, gấp đôi hạn mức 10 req/phút. Cửa sổ trượt 60 giây (Sliding Window) lưu timestamp từng request trong Sorted Set nên sẽ chặn ngay khi có quá 10 request trong bất kỳ khoảng 60s liên tục nào.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

- **Điểm khác nhau:** Rate limit kiểm soát **tần suất gọi (số request theo thời gian)**, bảo vệ server không bị quá tải. Cost guard kiểm soát **tổng số tiền chi tiêu / token tích lũy theo ngân sách**, bảo vệ tài chính của dự án.
- **Tình huống Rate limit cho qua nhưng Cost guard chặn:** Người dùng chỉ gửi 1 request duy nhất trong vòng 10 phút (tần suất rất thấp, rate limit cho qua), nhưng request này gửi một file tài liệu khổng lồ 100.000 tokens khiến chi phí ước tính vượt quá số dư ngân sách tháng $\rightarrow$ Cost guard chặn trước khi gọi LLM và trả về HTTP 402 Payment Required.
- **Tình huống Cost guard cho qua nhưng Rate limit chặn:** Người dùng mới đầu tháng và còn nguyên ngân sách 10 USD, nhưng gửi liên tiếp 15 câu hỏi ngắn ("xin chào" tốn rất ít token) chỉ trong vòng 5 giây $\rightarrow$ Cost guard thấy chi phí không đáng kể nên cho qua, nhưng Rate limit sẽ chặn từ request thứ 11 và trả về HTTP 429 Too Many Requests.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Thứ tự sự kiện:
1. Khi Redis mất kết nối trong 30 giây, cả 3 container đều thực hiện healthcheck gọi tới endpoint này và kiểm tra Redis thất bại $\rightarrow$ cả 3 container đồng thời trả về lỗi 503.
2. Orchestrator (Docker/Kubernetes/Render) kiểm tra liveness probe thấy thất bại nên kết luận rằng tiến trình của cả 3 container đã bị lỗi $\rightarrow$ tiến hành **kill và restart đồng loạt cả 3 container**.
3. Trong suốt thời gian 3 container bị restart và khởi động lại, cụm service không còn bất kỳ container nào trực chiến $\rightarrow$ toàn bộ người dùng gọi vào hệ thống đều nhận lỗi `502 Bad Gateway`.
4. Nếu sau 30 giây Redis chưa kịp kết nối lại khi container mới khởi động, orchestrator lại thấy healthcheck fail tiếp và rơi vào vòng lặp restart liên tục (CrashLoopBackOff). Việc gộp chung hai probe đã biến một sự cố phụ thuộc tạm thời thành sự cố sập toàn bộ hệ thống.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

- **Khi lưu trên Redis (thực tế bài lab):** Giá trị `history_length` tăng đều đặn qua mỗi lượt tương tác (0 $\rightarrow$ 2 $\rightarrow$ 4 $\rightarrow$ 6...) bất kể request được load balancer điều phối vào container nào trong 3 container, vì cả 3 instance đều cùng đọc/ghi chung một Redis datastore.
- **Nếu lưu trong dict Python (in-memory):** Vì mỗi container là một tiến trình riêng với bộ nhớ RAM tách biệt, khi load balancer phân phối request theo cơ chế round-robin, `history_length` sẽ nhảy lộn xộn và ngắt quãng (ví dụ: lượt 1 vào container A: len=0; lượt 2 vào container B: lại len=0; lượt 3 vào container A: len=2; lượt 4 vào container C: len=0...). Ứng dụng bị mất trạng thái hội thoại và không duy trì được ngữ cảnh trao đổi với người dùng.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

- **Lỗi thực tế gặp phải:** Lỗi khởi động tiến trình do hàm `install` trong `app/lifecycle.py` chưa được cài đặt hoàn thiện.
- **Thông báo lỗi trong log Uvicorn:**
  ```text
  File "app/lifecycle.py", line 59, in install
    raise NotImplementedError("TODO (CP4): cài đặt install")
  ERROR: Application startup failed. Exiting.
  ```
- **Cách tìm ra nguyên nhân:** Đọc traceback lỗi trong terminal khi khởi động Uvicorn, phát hiện khối `lifespan` của FastAPI trong `app/main.py` luôn tự động gọi `lifecycle.install()` lúc app boot; do chưa cài đặt nên hàm ném ngoại lệ làm container dừng ngay lập tức.
- **Cách khắc phục:** Cài đặt hàm `install()` trong `app/lifecycle.py` để đăng ký signal handler cho `SIGTERM` và `SIGINT`, lưu lại handler cũ của Uvicorn và nhường quyền gọi handler cũ trong `request_shutdown()`. Sau khi sửa, app khởi động bình thường, endpoint `/health` phản hồi 200 OK và service deploy lên Render thành công tại `https://day12-agent-otcq.onrender.com`.

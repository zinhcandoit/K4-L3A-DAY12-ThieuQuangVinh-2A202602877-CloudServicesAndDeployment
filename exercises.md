# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: điền câu trả lời trực tiếp bên dưới mỗi câu hỏi.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Thieu Quang Vinh  Mã học viên: 2A202602877

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Khi deploy lên cloud (như Render hay Railway), nếu ta quên cấu hình biến môi trường `AGENT_API_KEY`:
- Nếu có giá trị mặc định `"changeme"`: Service vẫn khởi động thành công và online bình thường. Kẻ xấu hoặc bot quét Internet có thể dùng API key mặc định `"changeme"` để gọi LLM miễn phí hàng ngàn lượt, gây cháy ngân sách và chỉ bị phát hiện khi hóa đơn tiền triệu báo về.
- Với fail-fast (không có mặc định): Service sẽ văng `ValidationError` và crash ngay lúc khởi động (boot time) trong quá trình deploy. Lỗi hiện ngay lập tức trên log dashboard, buộc ta phải cấu hình secret trước khi ứng dụng có thể nhận bất kỳ request nào.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log JSON thu được:
```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T11:47:56.241852+00:00", "user_id": "sv-test", "tokens_in": 3, "tokens_out": 37, "cost_usd": 0.00002265}
```

Hai việc làm được:
1. **Truy vấn và tổng hợp có cấu trúc (Structured Aggregation):** Hệ thống quản lý log (Datadog, Loki, CloudWatch) có thể parse JSON để chạy các query tính toán, ví dụ: `sum(cost_usd) by (user_id)` để tìm user tiêu tốn nhiều chi phí nhất trong ngày, hoặc tính `avg(tokens_out)`.
2. **Thiết lập cảnh báo tự động (Alerting):** Có thể cài đặt rule tự động gửi cảnh báo qua Slack/Telegram khi phát hiện một request có `cost_usd > 0.5` hoặc tỷ lệ log có `level: "error"` vượt ngưỡng 5% trong 5 phút.

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

Phần chênh lệch ~743 MB gồm:
- **Base image:** Bản 1-stage dùng `python:3.11` đầy đủ vốn chứa sẵn toàn bộ hệ điều hành Debian với nhiều gói tiện ích và tài liệu không cần thiết; bản multi-stage dùng `python:3.11-slim` được tối giản tối đa.
- **Bộ công cụ biên dịch (Compilers/Build tools):** Trình biên dịch C/C++ (`gcc`, `g++`, `make`), header files (`glibc-dev`, `python-dev`) phục vụ build bánh xe thư viện chỉ tồn tại ở stage `builder`. Khi sang stage `runtime`, Docker chỉ copy kết quả các thư viện đã biên dịch (`/install` sang `/usr/local`), loại bỏ toàn bộ compiler, cache apt và file rác trung gian.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

- **Với Dockerfile hiện tại:** Các layer từ đầu cho đến trước `COPY . .` (gồm `COPY requirements.txt .`, `RUN pip install...`, `COPY --from=builder /install /usr/local`) đều được **CACHED** và dùng lại 100%. Chỉ từ layer `COPY . .` trở đi (`RUN useradd...`, export manifest) mới phải chạy lại, quá trình build chỉ mất chưa đầy 1 giây.
- **Nếu đặt `COPY . .` lên trước `RUN pip install`:** Mỗi khi sửa dù chỉ một ký tự trong code, layer `COPY . .` thay đổi làm Docker invalidate toàn bộ cache từ bước đó trở đi. Hậu quả là Docker buộc phải chạy lại `RUN pip install`, tải và cài lại toàn bộ thư viện từ đầu sau mỗi lần sửa code, làm chậm quá trình build hàng chục lần.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

1. **Chuỗi sự kiện:**
   - Hacker khai thác lỗ hổng trong code (ví dụ: Command Injection hoặc lỗi deserialization).
   - Vì container chạy bằng root (UID 0), tiến trình bị chiếm quyền sẽ có quyền `root` tuyệt đối trong container.
   - Hacker tiếp tục khai thác lỗ hổng container breakout (lỗ hổng kernel Linux, mount nhầm `docker.sock`, hoặc cấu hình capabilities) để thoát ra máy host. Do tiến trình mang UID 0, khi thoát ra ngoài host nó vẫn mang đặc quyền `root` (UID 0) của máy host, giúp kẻ tấn công chiếm toàn quyền kiểm soát server.
2. **Lệnh `USER appuser` cắt đứt chuỗi ở đâu:**
   - Cắt đứt ngay từ bước đầu tiên: hacker sau khi chiếm quyền thực thi trong container chỉ là user thường `appuser` (UID 10001, unprivileged). User này không thể sửa các file nhạy cảm của hệ thống, không có `sudo`, và không đủ quyền để kích hoạt các kỹ thuật leo thang container breakout.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

- Con số tối đa: **20 request** trong 2 giây.
- Cách đạt được:
  - Người dùng gửi 10 request vào giây `10:00:59` (giây cuối cùng của phút 10) $\rightarrow$ hệ thống ghi nhận đủ 10 request cho phút 10.
  - Sang giây `10:01:00` (giây đầu tiên của phút 11), bộ đếm phút đồng hồ tự động reset về 0.
  - Người dùng lập tức gửi tiếp 10 request nữa vào giây `10:01:00`.
  - Kết quả: trong khoảng thời gian chỉ 2 giây (10:00:59 đến 10:01:00), hệ thống đã cho phép 20 request đi qua, gấp đôi hạn mức 10 req/phút. Cửa sổ trượt 60s (Sliding Window) ghi nhận timestamp của từng request nên sẽ chặn ngay khi phát hiện có 10 request trong bất kỳ khoảng 60s nào.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

- **Sự khác biệt:** Rate limit giới hạn **tần suất / số lượng request theo thời gian** (ví dụ 10 req/phút). Cost guard giới hạn **tổng chi phí / token tích lũy theo ngân sách** (ví dụ 10 USD/tháng).
- **Rate limit cho qua nhưng Cost guard chặn:** User chỉ gửi duy nhất 1 request trong 15 phút (tần suất rất thấp, rate limit cho qua), nhưng request này kèm đoạn tài liệu khổng lồ 100.000 tokens khiến chi phí ước tính vượt quá số dư ngân sách tháng còn lại $\rightarrow$ Cost guard chặn (HTTP 402 Payment Required).
- **Cost guard cho qua nhưng Rate limit chặn:** User mới bắt đầu tháng và còn nguyên ngân sách 10$, nhưng gửi dồn dập 15 câu hỏi ngắn ("xin chào" tốn rất ít token) chỉ trong 5 giây $\rightarrow$ Cost guard thấy chi phí không đáng kể nên cho qua, nhưng Rate limit sẽ chặn từ request thứ 11 (HTTP 429 Too Many Requests).

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Thứ tự sự kiện:
1. Khi Redis mất kết nối 30 giây, cả 3 container đều thực hiện health check và kiểm tra Redis thất bại $\rightarrow$ cả 3 container đồng loạt trả về lỗi (503/fail).
2. Orchestrator (Docker/K8s/Render) thấy liveness probe thất bại nên kết luận rằng tiến trình của cả 3 container đều đã chết $\rightarrow$ tiến hành **kill và restart đồng loạt cả 3 container**.
3. Trong suốt thời gian 3 container bị restart và khởi động lại, cụm service không còn container nào trực chiến $\rightarrow$ toàn bộ người dùng gặp lỗi `502 Bad Gateway`.
4. Nếu sau 30 giây Redis chưa kịp kết nối lại khi container mới khởi động, orchestrator lại thấy health check hỏng và tiếp tục restart liên tục (CrashLoopBackOff). Gộp hai endpoint đã biến một sự cố phụ thuộc tạm thời thành sự cố sập toàn bộ hệ thống.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

- **Khi lưu trên Redis (thực tế bài lab):** `history_length` tăng đều đặn qua mỗi lượt hỏi (0 $\rightarrow$ 2 $\rightarrow$ 4 $\rightarrow$ 6...) bất kể request được load balancer định tuyến vào container nào trong 3 container, vì cả 3 instance cùng đọc và ghi chung vào Redis.
- **Nếu lưu trong dict Python (in-memory):** Vì mỗi container là một tiến trình riêng biệt với vùng nhớ RAM độc lập, khi load balancer phân bổ request ngẫu nhiên hoặc round-robin, `history_length` sẽ nhảy lộn xộn và gián đoạn (ví dụ: lượt 1 vào container 1: len=0; lượt 2 vào container 2: lại len=0; lượt 3 vào container 1: len=2; lượt 4 vào container 3: len=0...). Agent bị "mất trí nhớ" và không thể duy trì ngữ cảnh hội thoại xuyên suốt.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

- **Lỗi gặp phải:** Lỗi khởi động ứng dụng do hàm `install` trong `app/lifecycle.py` chưa được cài đặt.
- **Thông báo lỗi trên log:**
  ```text
  File "app/lifecycle.py", line 59, in install
    raise NotImplementedError("TODO (CP4): cài đặt install")
  ERROR: Application startup failed. Exiting.
  ```
- **Cách tìm ra nguyên nhân:** Đọc traceback lỗi trong log khởi động của Uvicorn, phát hiện `lifespan` của FastAPI trong `app/main.py` luôn tự động gọi `lifecycle.install()` lúc app boot; do chưa cài đặt nên hàm ném ngoại lệ làm container dừng ngay lập tức.
- **Cách khắc phục:** Cài đặt hàm `install()` trong `app/lifecycle.py` để duyệt qua `(signal.SIGTERM, signal.SIGINT)`, lưu handler cũ của uvicorn và gán handler mới `request_shutdown`, đồng thời trong `request_shutdown` gọi lại handler cũ nếu có. Sau khi sửa, app boot thành công, endpoint `/health` trả về 200 OK và service deploy lên Render thành công.

# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization
# ═══════════════════════════════════════════════════════════════════

# Stage 1: builder cài đặt và build dependency
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: runtime chỉ chứa dependency và mã nguồn cần chạy
FROM python:3.11-slim AS runtime

WORKDIR /app

# Copy các gói đã build từ stage builder sang runtime
COPY --from=builder /install /usr/local

# Copy source code sau pip install để tận dụng Docker layer cache
COPY . .

# Tạo user thường UID 10001 và chạy bằng user này
RUN useradd --create-home --uid 10001 appuser
USER appuser

EXPOSE 8000

# Healthcheck kiểm tra endpoint /health
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health').read()" || exit 1

# Khởi động Uvicorn bind 0.0.0.0 và đọc cổng linh hoạt từ ${PORT:-8000}
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

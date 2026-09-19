FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /venv \
 && /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS runtime
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1
RUN groupadd -g 10001 app && useradd -u 10001 -g app -M -s /usr/sbin/nologin app
COPY --from=builder /venv /venv
WORKDIR /app
COPY --chown=app:app worker.py .
USER app
EXPOSE 9200
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; \
urllib.request.urlopen('http://127.0.0.1:9200/',timeout=2)"
CMD ["python", "worker.py"]

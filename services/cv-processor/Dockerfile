# syntax=docker/dockerfile:1
# =============================================================================
# cv-processor — production-grade, hardened multi-stage image.
#   * Multi-stage: build deps in a full image, ship only site-packages + app.
#   * Runtime: distroless (no shell/pkg mgr) -> tiny attack surface; non-root.
#   * Base images buildable by tag; pinned by digest via pin-digests.sh + CI.
#   * Reproducible deps: pinned pip, wheels-only (no arbitrary setup.py exec).
#   * Gunicorn tuned via gunicorn.conf.py (worker recycling, graceful shutdown).
# =============================================================================
ARG PYTHON_VERSION=3.11
ARG BUILDER_IMAGE=python:3.11-slim-bookworm@sha256:a36c24f9cbdf4fd0f52d67f0823eeac19c2028c637cecc392d97f980d4fec56b
ARG RUNTIME_IMAGE=gcr.io/distroless/python3-debian12:nonroot@sha256:7d1042ce588ab97019fe95c24ffca7bc5a82ccdac572511d5e09bda4435c89c5

FROM ${BUILDER_IMAGE} AS builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1
WORKDIR /build
COPY requirements.txt .
RUN python -m pip install --upgrade "pip==24.2" \
 && pip install --prefix=/install --only-binary=:all: -r requirements.txt

FROM ${RUNTIME_IMAGE}
ARG PYTHON_VERSION
ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="cv-processor" \
      org.opencontainers.image.description="CV platform backend: PDF parsing + storage" \
      org.opencontainers.image.source="https://github.com/AnkurDhamija/cv-platform" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.licenses="MIT"
ENV PYTHONPATH=/install/lib/python${PYTHON_VERSION}/site-packages \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8081
WORKDIR /app
COPY --from=builder /install /install
COPY gunicorn.conf.py ./
COPY app/ ./app/
USER 65532:65532
EXPOSE 8081
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python","-c","import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8081/health',timeout=2).status==200 else 1)"]
ENTRYPOINT ["python", "-m", "gunicorn", "-c", "gunicorn.conf.py", "app.main:app"]

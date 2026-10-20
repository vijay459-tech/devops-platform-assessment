# syntax=docker/dockerfile:1
#
# Multi-stage build.
#   build   : full Python image; runs the unit tests so a failing test fails the build.
#   runtime : distroless, non-root, no shell, no package manager.
#
# Base images are build args so CI can pass digest-pinned references
# (e.g. python@sha256:...) without editing this file. Tags below are the
# readable defaults; Dependabot (docker ecosystem) proposes updates.
# The Python minor versions must match: distroless python3-debian12 ships 3.11.
ARG PYTHON_BUILD_IMAGE=python:3.11-slim-bookworm
ARG RUNTIME_IMAGE=gcr.io/distroless/python3-debian12:latest-nonroot

FROM ${PYTHON_BUILD_IMAGE} AS build
WORKDIR /src
ENV PYTHONDONTWRITEBYTECODE=1
COPY app/ ./
RUN python -m unittest discover -s tests -t . \
 && python -m compileall -q service

FROM ${RUNTIME_IMAGE} AS runtime
ARG GIT_SHA=unknown
ARG APP_VERSION=0.0.0-dev
ARG BUILD_TIME=unknown
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    GIT_SHA=${GIT_SHA} \
    APP_VERSION=${APP_VERSION} \
    BUILD_TIME=${BUILD_TIME}
WORKDIR /app
COPY --from=build /src/service /app/service
# 65532 is the distroless "nonroot" user. Numeric so Kubernetes/Cloud Run can
# verify non-root without resolving a name.
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/bin/python3", "-m", "service.server"]

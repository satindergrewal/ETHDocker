FROM ubuntu:latest AS builder

ARG TARGETARCH
ARG LIGHTHOUSE_VERSION=8.1.3

# Known-good SHA256 checksums for official binaries
ARG SHA256_AMD64=a3a74319d3588df60a09eaa2e9c6ccd7b325436ca894739c30d2e71be598f380
ARG SHA256_ARM64=78f0a2476712493a7ac99f9007d42577424ab1f7af6963811f89d3b30e4b10c2

# Map Docker's TARGETARCH to Lighthouse's naming convention
RUN case "${TARGETARCH}" in \
        amd64)  ARCH="x86_64-unknown-linux-gnu"; EXPECTED="${SHA256_AMD64}" ;; \
        arm64)  ARCH="aarch64-unknown-linux-gnu"; EXPECTED="${SHA256_ARM64}" ;; \
        *)      echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "ARCH=${ARCH}" > /tmp/arch.env && \
    echo "EXPECTED=${EXPECTED}" >> /tmp/arch.env

RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Download and verify Lighthouse
RUN . /tmp/arch.env && \
    FILENAME="lighthouse-v${LIGHTHOUSE_VERSION}-${ARCH}.tar.gz" && \
    wget -q "https://github.com/sigp/lighthouse/releases/download/v${LIGHTHOUSE_VERSION}/${FILENAME}" && \
    echo "${EXPECTED}  ${FILENAME}" | sha256sum -c - && \
    tar -xzf "${FILENAME}" && \
    rm -f "${FILENAME}"

# --- Final image ---
FROM ubuntu:latest

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /lighthouse /usr/local/bin/lighthouse

RUN groupadd -r lighthouse && useradd -r -g lighthouse -m lighthouse
USER lighthouse

EXPOSE 5052 9000

ENTRYPOINT ["lighthouse"]

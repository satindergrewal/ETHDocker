FROM ubuntu:latest AS builder

ARG TARGETARCH
ARG GETH_VERSION=1.17.3
ARG GETH_COMMIT=117e067f

# Known-good SHA256 checksums for official binaries
ARG SHA256_AMD64=98d7c066740f33d2be34b6520869c913dffcbdb6d8e17c084b66568050404e53
ARG SHA256_ARM64=417c960091779e910e9748645ec943ae01576c74187cfbcc3c2406a6ffb77ae2

# Map Docker's TARGETARCH to Geth's naming convention
RUN case "${TARGETARCH}" in \
        amd64)  ARCH="amd64"; EXPECTED="${SHA256_AMD64}" ;; \
        arm64)  ARCH="arm64"; EXPECTED="${SHA256_ARM64}" ;; \
        *)      echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "ARCH=${ARCH}" > /tmp/arch.env && \
    echo "EXPECTED=${EXPECTED}" >> /tmp/arch.env

RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Download and verify Geth
RUN . /tmp/arch.env && \
    FILENAME="geth-linux-${ARCH}-${GETH_VERSION}-${GETH_COMMIT}.tar.gz" && \
    wget -q "https://gethstore.blob.core.windows.net/builds/${FILENAME}" && \
    echo "${EXPECTED}  ${FILENAME}" | sha256sum -c - && \
    tar -xzf "${FILENAME}" --strip-components=1 && \
    rm -f "${FILENAME}"

# --- Final image ---
FROM ubuntu:latest

COPY --from=builder /geth /usr/local/bin/geth

RUN groupadd -r geth && useradd -r -g geth -m geth
USER geth

EXPOSE 8545 8546 8551 30303

ENTRYPOINT ["geth"]

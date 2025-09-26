# Golioth Firmware SDK Buildroot Build Environment
# Optimized for external toolchains - minimal dependencies for faster builds
FROM ubuntu:22.04

# Build arguments
ARG BUILDROOT_VERSION=2025.08.x
ARG TARGET_CONFIG=qemu_aarch64_golioth_defconfig
ARG FIRMWARE_VERSION=1.0.0
ARG CREATE_SWU=true

# Avoid interactive prompts during package installation
ARG DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies for external toolchain builds
# Note: No build-essential or heavy dev tools needed since we use pre-built toolchains
# Added tools for A/B partition management and .swu generation
RUN apt-get update && apt-get install -y \
    git \
    wget \
    cpio \
    python3 \
    unzip \
    rsync \
    bc \
    libncurses5-dev \
    file \
    ca-certificates \
    curl \
    ccache \
    make \
    gcc \
    g++ \
    bzip2 \
    gzip \
    xz-utils \
    util-linux \
    dosfstools \
    e2fsprogs \
    parted \
    u-boot-tools \
    mtools \
    xxd \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for building with matching host UID
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN if ! getent group ${GROUP_ID} >/dev/null 2>&1; then \
    groupadd -g ${GROUP_ID} builder; \
    else \
    GROUP_NAME=$(getent group ${GROUP_ID} | cut -d: -f1); \
    echo "Using existing group $GROUP_NAME with GID ${GROUP_ID}"; \
    fi && \
    useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} builder

# Set the working directory and ensure builder user owns it
WORKDIR /build
RUN chown ${USER_ID}:${GROUP_ID} /build

# Copy the build script
COPY build-in-docker.sh /build/
RUN chmod +x /build/build-in-docker.sh && \
    chown ${USER_ID}:${GROUP_ID} /build/build-in-docker.sh

# Switch to the builder user
USER builder

# Set environment variables
ENV BUILDROOT_VERSION=${BUILDROOT_VERSION}
ENV TARGET_CONFIG=${TARGET_CONFIG}
ENV FIRMWARE_VERSION=${FIRMWARE_VERSION}
ENV CREATE_SWU=${CREATE_SWU}

# Build script will be run when container starts
CMD ["/build/build-in-docker.sh"]
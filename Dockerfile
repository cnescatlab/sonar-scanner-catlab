# Builder image for analysis tools
FROM ubuntu:22.04 AS builder

# Install tools from sources
RUN apt update \
    && apt install -y --no-install-recommends \
    curl=7.81.0-* \
    # for C/C++ tools
    make=4.3-* \
    g\+\+=4:11.2.0-* \
    python3=3.10.6-* \
    libpcre3-dev=2:8.39-* \
    unzip=6.0-* \
    xz-utils=5.2.5-* \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# sonar-scanner
RUN curl -ksSLO https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006.zip \
    && unzip sonar-scanner-cli-5.0.1.3006.zip \
    && mv ./sonar-scanner-5.0.1.3006 /sonar-scanner \
    && rm sonar-scanner-cli-5.0.1.3006.zip

# CppCheck
RUN curl -ksSLO https://github.com/danmar/cppcheck/archive/refs/tags/2.14.0.tar.gz \
    && tar -zxvf 2.14.0.tar.gz  \
    && make -C cppcheck-2.14.0/ install \
    MATCHCOMPILER="yes" \
    FILESDIR="/usr/share/cppcheck" \
    HAVE_RULES="yes" \
    CXXFLAGS="-O2 -DNDEBUG -Wall -Wno-sign-compare -Wno-unused-function -Wno-deprecated-declarations" \
    && rm -rf cppcheck-2.14.0 2.14.0.tar.gz

################################################################################

# Final image based on the official sonar-scanner image
FROM ubuntu:22.04

LABEL maintainer="CATLab"

# Set variables for the sonar-scanner
ENV SRC_DIR=/usr/src \
    SONAR_SCANNER_HOME=/opt/sonar-scanner \
    SONAR_USER_HOME=/opt/sonar-scanner/.sonar

# Same workdir as the offical sonar-scanner image
WORKDIR ${SRC_DIR}

# Add an unprivileged user
RUN addgroup sonar-scanner \
    && adduser \
    --home "$SONAR_SCANNER_HOME" \
    --ingroup sonar-scanner \
    --disabled-password \
    --gecos "" \
    sonar-scanner \
    && mkdir -p "$SONAR_SCANNER_HOME/bin" \
    "$SONAR_SCANNER_HOME/lib" \
    "$SONAR_SCANNER_HOME/conf" \
    "$SONAR_SCANNER_HOME/.sonar/cache" \
    "$SONAR_SCANNER_HOME/.pylint.d" \
    && chown -R sonar-scanner:sonar-scanner \
    "$SONAR_SCANNER_HOME" \
    "$SONAR_SCANNER_HOME/.sonar" \
    "$SONAR_SCANNER_HOME/.pylint.d" \
    "$SRC_DIR" \
    && chmod -R 777 \
    "$SONAR_SCANNER_HOME/.sonar" \
    "$SONAR_SCANNER_HOME/.pylint.d" \
    "$SRC_DIR"

# Add sonar-scanner from builder
COPY --from=builder /sonar-scanner/bin/sonar-scanner "$SONAR_SCANNER_HOME/bin"
COPY --from=builder /sonar-scanner/lib "$SONAR_SCANNER_HOME/lib"
# and our default sonar-scanner.properties
COPY conf/sonar-scanner.properties "$SONAR_SCANNER_HOME/conf"

# Add CppCheck from builder stage
COPY --from=builder /usr/share/cppcheck /usr/share/cppcheck
COPY --from=builder /usr/bin/cppcheck /usr/bin
COPY --from=builder /usr/bin/cppcheck-htmlreport /usr/bin

# Add CNES pylintrc A_B, C, D
COPY pylintrc.d/ /opt/python/

# Install tools
RUN apt update \
    && mkdir -p /usr/share/man/man1 \
    && apt install -y --no-install-recommends \
    # Needed by sonar-scanner
    openjdk-17-jre=17.0.* \
    # Needed by Pylint
    python3=3.10.6-* \
    python3-pip=22.0.2* \
    # Shellcheck
    shellcheck=0.8.0-* \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/local/man \
    # Install pylint and CNES pylint extension
    && pip install --no-cache-dir \
    cnes-pylint-extension==7.0.0 \
    pylint-sonarjson-catlab==2.0.0 \
    setuptools-scm==8.0.4 \
    pytest-runner==6.0.1 \
    wrapt==1.16.0 \
    six==1.16.0 \
    lazy-object-proxy==1.10.0 \
    mccabe==0.7.0 \
    isort==5.13.2 \
    typed-ast==1.5.5 \
    astroid==3.1.0 \
    pylint==3.1.0

# Make sonar-scanner, CNES pylint and C/C++ tools executable
ENV PATH="$SONAR_SCANNER_HOME/bin:/usr/local/bin:$PATH" \
    PYLINTHOME="$SONAR_SCANNER_HOME/.pylint.d" \
    JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Switch to an unpriviledged user
USER sonar-scanner

# Set the entrypoint (a SonarSource script) and the default command (sonar-scanner)
COPY --chown=sonar-scanner:sonar-scanner scripts/entrypoint.sh /usr/bin
ENTRYPOINT [ "/usr/bin/entrypoint.sh" ]
CMD [ "sonar-scanner" ]

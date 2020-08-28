# Builder image for other analysis tools
FROM sonarsource/sonar-scanner-cli:4.4 AS builder

# Get CppCheck, Vera++ sources
ADD https://netix.dl.sourceforge.net/project/cppcheck/cppcheck/1.90/cppcheck-1.90.tar.gz \
    https://bitbucket.org/verateam/vera/downloads/vera++-1.2.1.tar.gz \
    /usr/src/

# Compile CppCheck and Vera++ from source as they are not available through alpine's package manager
RUN apk add --no-cache \
        alpine-sdk \
        cmake \
        pcre-dev \
        boost-dev \
        tcl-dev \
    && tar -zxvf cppcheck-1.90.tar.gz \
    && make -C cppcheck-1.90/ install MATCHCOMPILER="yes" FILESDIR="/usr/share/cppcheck" HAVE_RULES="yes" CXXFLAGS="-O2 -DNDEBUG -Wall -Wno-sign-compare -Wno-unused-function -Wno-deprecated-declarations" \
    && tar -zxvf vera++-1.2.1.tar.gz \
    && cmake -S vera++-1.2.1 -B build-vera -D CMAKE_BUILD_TYPE=Release \
    && cmake --build build-vera \
    && cmake --build build-vera --target install

################################################################################

# Final image based on the official sonar-scanner image
FROM sonarsource/sonar-scanner-cli:4.4

LABEL maintainer="CATLab <catlab@cnes.fr>"

# Add CppCheck from builder stage
COPY --from=builder /usr/share/cppcheck /usr/share/cppcheck
COPY --from=builder /usr/bin/cppcheck /usr/bin
COPY --from=builder /usr/bin/cppcheck-htmlreport /usr/bin
# and Vera++
COPY --from=builder /usr/local /usr/local

# Add CNES pylintrc A_B, C, D
COPY --chown=scanner-cli:scanner-cli pylintrc.d/ /opt/python/

# Download CNES pylint extension
ADD https://github.com/cnescatlab/cnes-pylint-extension/archive/v5.0.0.tar.gz \
    /tmp/python/

# Add pylint
RUN apk add --no-cache --virtual .pylint-build-deps \
        gcc=9.3.0-r0 \
        python3-dev=3.8.2-r1 \
        musl-dev=1.1.24-r2 \
    # Download CppCheck and Vera++ runtime dependencies
    && apk add --no-cache \
        pcre \
        libstdc++ \
        boost \
        tcl \
    # Install pylint and CNES pylint extension
    && mkdir -p /opt/python/cnes-pylint-extension-5.0.0 \
    && tar -xvzf /tmp/python/v5.0.0.tar.gz -C /tmp/python \
    && mv /tmp/python/cnes-pylint-extension-5.0.0/checkers /opt/python/cnes-pylint-extension-5.0.0/ \
    && rm -rf /tmp/python \
    && pip install --no-cache-dir \
       setuptools-scm==3.5.0 \
       pytest-runner==5.2 \
       wrapt==1.12.1 \
       six==1.14.0 \
       lazy-object-proxy==1.4.3 \
       mccabe==0.6.1 \
       isort==4.3.21 \
       typed-ast==1.4.1 \
       astroid==2.4.0 \
       pylint==2.5.0 \
    # Remove CNES pylint extension build dependencies
    && apk del --purge .pylint-build-deps \
    # Set default report path for CppCheck, Vera++ and RATS
    && echo '#----- Default report path for C/C++ analysis tools' >> /opt/sonar-scanner/conf/sonar-scanner.properties \
    && echo 'sonar.cxx.cppcheck.reportPath=cppcheck-report.xml' >> /opt/sonar-scanner/conf/sonar-scanner.properties \
    && echo 'sonar.cxx.vera.reportPath=vera-report.xml' >> /opt/sonar-scanner/conf/sonar-scanner.properties \
    && echo 'sonar.cxx.rats.reportPath=rats-report.xml' >> /opt/sonar-scanner/conf/sonar-scanner.properties

# Have CNES pylint and Vera++ executable
ENV PYTHONPATH="$PYTHONPATH:/opt/python/cnes-pylint-extension-5.0.0/checkers/" \
    PATH="/usr/local/bin:$PATH"

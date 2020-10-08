# Builder image for analysis tools
FROM debian:10.5-slim AS builder

# Install tools from sources
RUN echo 'deb http://ftp.fr.debian.org/debian/ bullseye main contrib non-free' >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl=7.72.0-* \
        # for C/C++ tools
        make=4.3-* \
        ## not found##g\+\+=4:10.1.0-* \
        python3=3.8.2-* \
        libpcre3-dev=2:8.39-* \
        unzip=6.0-* \
        xz-utils=5.2.4-* \
        # for Frama-C
        ocaml=4.08.1-* \
        ocaml-findlib=1.8.1-* \
        libfindlib-ocaml-dev=1.8.1-* \
        libocamlgraph-ocaml-dev=1.8.8-* \
        libyojson-ocaml-dev=1.7.0-* \
        ##not found##libzarith-ocaml-dev=1.9.1-* \
        menhir=20200624-* \
    #patch florent to be removed
    && apt-get install -y libzarith-ocaml-dev g\+\+ \
        #for yosys
    && apt-get install -y build-essential clang bison flex \
        libreadline-dev gawk tcl-dev libffi-dev git \
        graphviz xdot pkg-config python3 libboost-system-dev \
        libboost-python-dev libboost-filesystem-dev zlib1g-dev \
    && git clone https://github.com/YosysHQ/yosys.git \
    && cd yosys \
    && make config-gcc \
    && make \
    && make install \
    && cd .. \
    #for ghdl
    #FIXME:  this ghdl install procedure as to be updated to include gcov coverage
    && apt-get install -y gnat git gcc make zlib1g-dev\ 
    && git clone https://github.com/ghdl/ghdl.git \
    && cd ghdl \
    && ./configure --prefix=/usr/local \
    && make \
    && make install \
    && cd .. \
    #for  ghdl-yosys-plugin
    && git clone https://github.com/ghdl/ghdl-yosys-plugin.git \
    && cd ghdl-yosys-plugin \
    && make \
    && make install \
    && cd .. \
    # sonar-scanner
    && curl -ksSLO https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-4.4.0.2170.zip \
    && unzip sonar-scanner-cli-4.4.0.2170.zip \
    && mv /sonar-scanner-4.4.0.2170 /sonar-scanner \
    #Addon for RC scanner
    && curl -ksSLO https://github.com/Linty-Services/VHDL-RC/releases/download/v3.1/rc-scanner-4.0.0.1744-1-linux.tar.gz \
    && tar -zxvf rc-scanner-4.0.0.1744-1-linux.tar.gz \
    && mkdir /sonar-scanner/rc \
    && cp -r /rc-scanner-4.0.0.1744-1-linux/rc/* /sonar-scanner/rc/ \
    # CppCheck
    && curl -ksSLO https://downloads.sourceforge.net/project/cppcheck/cppcheck/1.90/cppcheck-1.90.tar.gz \
    && tar -zxvf cppcheck-1.90.tar.gz \
    && make -C cppcheck-1.90/ install \
            MATCHCOMPILER="yes" \
            FILESDIR="/usr/share/cppcheck" \
            HAVE_RULES="yes" \
            CXXFLAGS="-O2 -DNDEBUG -Wall -Wno-sign-compare -Wno-unused-function -Wno-deprecated-declarations" \
    # RATS (and expat)
    && curl -ksSLO https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/rough-auditing-tool-for-security/rats-2.4.tgz \
    && curl -ksSLO http://downloads.sourceforge.net/project/expat/expat/2.0.1/expat-2.0.1.tar.gz \
    && tar -xvzf expat-2.0.1.tar.gz \
    && cd expat-2.0.1 \
    && ./configure \
    && make \
    && make install \
    && cd .. \
    && tar -xzvf rats-2.4.tgz \
    && cd rats-2.4 \
    && ./configure --with-expat-lib=/usr/local/lib \
    && make \
    && make install \
    && ./rats \
    && cd .. \
    # Frama-C
    && curl -ksSLO https://frama-c.com/download/frama-c-20.0-Calcium.tar.gz \
    && tar -zxvf frama-c-20.0-Calcium.tar.gz \
    && cd frama-c-20.0-Calcium \
    && ./configure --disable-gui --disable-wp \
    && make \
    && make install \
    && cd .. \
    # Infer
    && curl -ksSLO https://github.com/facebook/infer/releases/download/v0.17.0/infer-linux64-v0.17.0.tar.xz \
    && tar -C /opt -Jxvf infer-linux64-v0.17.0.tar.xz

################################################################################

# Final image based on the official sonar-scanner image
FROM debian:10.5-slim

LABEL maintainer="CATLab <catlab@cnes.fr>"

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
            "$SONAR_SCANNER_HOME/rc" \
            "$SONAR_SCANNER_HOME/.sonar/cache" \
            "$SONAR_SCANNER_HOME/.pylint.d" \
    && chown -R sonar-scanner:sonar-scanner \
            "$SONAR_SCANNER_HOME" \
            "$SONAR_SCANNER_HOME/.sonar" \
            "$SONAR_SCANNER_HOME/rc" \
            "$SONAR_SCANNER_HOME/.pylint.d" \
            "$SRC_DIR" \
    && chmod -R 777 \
            "$SONAR_SCANNER_HOME/.sonar" \
            "$SONAR_SCANNER_HOME/rc" \
            "$SONAR_SCANNER_HOME/.pylint.d" \
            "$SRC_DIR"

# Add sonar-scanner from builder
COPY --from=builder /sonar-scanner/bin/sonar-scanner \
    "$SONAR_SCANNER_HOME/bin"
COPY --from=builder /sonar-scanner/lib \
    "$SONAR_SCANNER_HOME/lib"
# and our default sonar-scanner.properties
COPY conf/sonar-scanner.properties "$SONAR_SCANNER_HOME/conf"
#add VHDL RC engine
COPY --from=builder /sonar-scanner/rc/ \
    "$SONAR_SCANNER_HOME/rc"
#give ownership to user (for write and execution) for VHDL RC engine
RUN chown -R sonar-scanner:sonar-scanner "$SONAR_SCANNER_HOME/rc"
RUN chmod -R 777 "$SONAR_SCANNER_HOME/rc" 
# add yosys from builder
COPY --from=builder /usr/local/bin/yosys /usr/local/bin/yosys
COPY --from=builder /usr/local/bin/yosys-abc /usr/local/bin/yosys-abc
COPY --from=builder /usr/local/bin/yosys-config /usr/local/bin/yosys-config
COPY --from=builder /usr/local/bin/yosys-filterlib /usr/local/bin/yosys-filterlib
COPY --from=builder /usr/local/bin/yosys-smtbmc /usr/local/bin/yosys-smtbmc
# add ghdl from builder
COPY --from=builder /usr/local/lib/libghdl.a /usr/local/lib/libghdl.a 
COPY --from=builder /usr/local/lib/libghdl.link /usr/local/lib/libghdl.link 
COPY --from=builder /usr/local/lib/libghdl-1_0_dev.so /usr/local/lib/libghdl-1_0_dev.so 
COPY --from=builder /usr/local/lib/libghdlvpi.so /usr/local/lib/libghdlvpi.so 
COPY --from=builder /usr/local/lib/ghdl /usr/local/lib/ghdl
COPY --from=builder /usr/local/bin/ghdl /usr/local/bin/ghdl 

# Add CppCheck from builder stage
COPY --from=builder /usr/share/cppcheck /usr/share/cppcheck
COPY --from=builder /usr/bin/cppcheck /usr/bin
COPY --from=builder /usr/bin/cppcheck-htmlreport /usr/bin

# Add RATS and Frama-C from builder stage
COPY --from=builder /usr/local /usr/local

# Add Infer from builder stage
COPY --from=builder /opt/infer-linux64-v0.17.0/bin /opt/infer-linux64-v0.17.0/bin
COPY --from=builder /opt/infer-linux64-v0.17.0/lib /opt/infer-linux64-v0.17.0/lib

# Add CNES pylintrc A_B, C, D
COPY pylintrc.d/ /opt/python/

# Download CNES pylint extension
ADD https://github.com/cnescatlab/cnes-pylint-extension/archive/v5.0.0.tar.gz \
    /tmp/python/

# Install tools
RUN echo 'deb http://ftp.fr.debian.org/debian/ bullseye main contrib non-free' >> /etc/apt/sources.list \
    && apt-get update \
    && mkdir -p /usr/share/man/man1 \
    && apt-get install -y --no-install-recommends \
            # Needed by sonar-scanner
            openjdk-11-jre-headless=11.0.8* \
            # Needed by Pylint
            python3=3.8.2-* \
            python3-pip=20.1.1-* \
            # Vera++
            vera\+\+=1.2.1-* \
            # Shellcheck
            shellcheck=0.7.1-* \
            # Needed by Frama-C
            ocaml-findlib=1.8.1-* \
            libocamlgraph-ocaml-dev=1.8.8-* \
            #libzarith-ocaml=1.9.1-* \
            libyojson-ocaml=1.7.0-* \
            # Needed by Infer
            libsqlite3-0=3.33.0-* \
            #libtinfo5=6.2-* \
            python2.7=2.7.18-* \
            # Compilation tools needed by Infer
            #gcc=4:10.1.0-* \
            ##g\+\+=4:10.1.0-* \
            clang=1:9.0-* \
            make=4.3-* \
    ##patch for problem with previous too old version
    && apt-get install -y libzarith-ocaml libtinfo5 gcc  g\+\+\
    ##x needed for elipse
    && apt-get install -y xvfb libswt-gtk-4-jni libswt-gtk-4-java\
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/local/man \
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
    # Infer
    && ln -s "/opt/infer-linux64-v0.17.0/bin/infer" /usr/local/bin/infer 


# Make sonar-scanner, CNES pylint and C/C++ tools executable
ENV PYTHONPATH="$PYTHONPATH:/opt/python/cnes-pylint-extension-5.0.0/checkers" \
    PATH="$SONAR_SCANNER_HOME/bin:/usr/local/bin:$PATH" \
    PYLINTHOME="$SONAR_SCANNER_HOME/.pylint.d" \
    JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64" \
    DISPLAY=":0"

# Switch to an unpriviledged user
USER sonar-scanner
#add fake screen kickstart . this fake screen is needed by eclipse
COPY --chown=sonar-scanner:sonar-scanner scripts/kickstartfakedisplay.sh /usr/bin
# copy the entrypoint (a SonarSource script) and the default command (sonar-scanner)
COPY --chown=sonar-scanner:sonar-scanner scripts/entrypoint.sh /usr/bin
# Set the entrypoint
ENTRYPOINT [ "/usr/bin/kickstartfakedisplay.sh" ]
CMD [ "sonar-scanner" ]

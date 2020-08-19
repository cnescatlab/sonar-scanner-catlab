# This image is based on the official sonar-scanner image
FROM sonarsource/sonar-scanner-cli:4.4

LABEL maintainer="CATLab <catlab@cnes.fr>"

# Add and set up Python tools
# * pylint
# * CNES pylint extension
# * CNES pylintrc A_B, C, D
COPY --chown=scanner-cli:scanner-cli pylintrc.d/ /opt/python/

ADD https://github.com/cnescatlab/cnes-pylint-extension/archive/v5.0.0.tar.gz \
    /tmp/python/

RUN apk add --no-cache --virtual .pylint-build-deps \
        gcc=9.3.0-r0 \
        python3-dev=3.8.2-r1 \
        musl-dev=1.1.24-r2 \
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
    && apk del --purge .pylint-build-deps

ENV PYTHONPATH $PYTHONPATH:/opt/python/cnes-pylint-extension-5.0.0/checkers/

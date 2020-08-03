#!/usr/bin/env bash

# User story:
# As a user of this image, I want to run shellcheck from within a container
# so that it produces a report.

docker run --rm -u "$(id -u):$(id -g)" \
           -e SONAR_HOST_URL="$SONARQUBE_URL" \
           -v "$(pwd):/usr/src" \
           lequal/sonar-scanner \
           shellcheck -s sh \
                      -f checkstyle \
                      tests/shell/src/*.sh \
              > tests/shell/tmp-shellcheck-results.xml

if ! diff tests/shell/tmp-shellcheck-results.xml tests/shell/reference-shellcheck-results.xml;
then
    >&2 echo "Failed: ShellCheck XML reports are different."
    >&2 echo "=== Result ==="
    >&2 cat tests/shell/tmp-shellcheck-results.xml
    >&2 echo "=== Reference ==="
    >&2 cat tests/shell/reference-shellcheck-results.xml
    exit 1
fi

exit 0

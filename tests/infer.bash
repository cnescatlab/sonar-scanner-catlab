#!/usr/bin/env bash

# User story:
# As a user of this image, I want to run Infer from within a container
# so that it produces results.

. tests/functions.bash

cmd="infer -q run -- gcc -c tests/c_cpp/infer/hello.c -o tests/c_cpp/infer/hello.o"
test_analysis_tool "Infer" "$cmd" "tests/c_cpp/reference-infer-results.json" "infer-out/report.json" "no"

exit $?

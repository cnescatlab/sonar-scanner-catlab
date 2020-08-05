#!/usr/bin/env bash

# User story:
# As a user of this image, I want to analyze a fortran project
# so that I can see its level of quality on the SonarQube server.

. tests/functions.bash

sensors=(
    "INFO: Sensor Sonar i-Code \[icode\]"
)
test_language "Fortran 77" "f77" "fortran77" sensors "fortran77-dummy-project" 11

test_language "Fortran 90" "f90" "fortran90" sensors "fortran90-dummy-project" 14

exit $?

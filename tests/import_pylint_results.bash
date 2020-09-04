#!/usr/bin/env bash

# User story:
# As a user of this image, I want to be able to import the results
# of a pylint analysis to SonarQube.

. tests/functions.bash

projectName="Pylint Dummy Project"
projectKey="pylint-dummy-project"

# Get CNES_PYTHON_A key
qpKey=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/qualityprofiles/search?qualityProfile=CNES_PYTHON_A" \
        | jq -r '.profiles[0].key')
if [ "$qpKey" = "null" ]
then
    log "$ERROR" "No quality profile named CNES_PYTHON_A"
    exit 1
fi

# Create a project on SonarQube
res=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
            --data-urlencode "name=$projectName" \
            --data-urlencode "project=$projectKey" \
            "$SONARQUBE_LOCAL_URL/api/projects/create")
if [ -n "$res" ] && [ "$(echo "$res" | jq -r '.errors | length')" -gt 0 ]
then
    log "$ERROR" "Cannot create a project with key $projectKey because: $(echo "$res" | jq -r '.errors[0].msg')"
    exit 1
fi

# Set its Quality Profile for Python to CNES_PYTHON_A
res=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
            --data-urlencode "language=py" \
            --data-urlencode "project=$projectKey" \
            --data-urlencode "qualityProfile=CNES_PYTHON_A" \
            "$SONARQUBE_LOCAL_URL/api/qualityprofiles/add_project")
if [ -n "$res" ] && [ "$(echo "$res" | jq -r '.errors | length')" -gt 0 ]
then
    log "$ERROR" "Cannot set Quality profile of project $projectKey to CNES_PYTHON_A for Python language because: $(echo "$res" | jq -r '.errors[0].msg')"
    exit 1
fi

# Activate any pylint rule in CNES_PYTHON_A
res=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
            --data-urlencode "key=$qpKey" \
            --data-urlencode "rule=Pylint:C0330" \
            "$SONARQUBE_LOCAL_URL/api/qualityprofiles/activate_rule")
if [ -n "$res" ] && [ "$(echo "$res" | jq -r '.errors | length')" -gt 0 ]
then
    log "$ERROR" "Cannot activate a pylint rule in CNES_PYTHON_A because: $(echo "$res" | jq -r '.errors[0].msg')"
    exit 1
fi

# Run pylint and produce a report
docker run --rm -u "$(id -u):$(id -g)" \
                -v "$PWD/tests/python:/usr/src" \
                lequal/sonar-scanner \
                    pylint \
                    --rcfile=/opt/python/pylintrc_RNC_sonar_2017_A_B \
                    -r n \
                    --msg-template='{path}:{line}: [{msg_id}({symbol}), {obj}] {msg}' \
                    src \
                        > tests/python/tmp-pylint-results.txt
if [ ! -e tests/python/tmp-pylint-results.txt ] || [ ! -s tests/python/tmp-pylint-results.txt ]
then
    log "$ERROR" "pylint did not produce any result"
    exit 1
fi

# Analyse the project
analysis_output=$(docker run --rm -u "$(id -u):$(id -g)" \
                            -e SONAR_HOST_URL="$SONARQUBE_URL" \
                            --net "$SONARQUBE_NETWORK" \
                            -v "$PWD:/usr/src" \
                            -v "$PWD/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
                            lequal/sonar-scanner \
                                "-Dsonar.projectBaseDir=/usr/src/tests/python" \
                                "-Dsonar.projectKey=$projectKey" \
                                "-Dsonar.projectName=$projectName" \
                                "-Dsonar.projectVersion=1.0" \
                                "-Dsonar.sources=src" \
                                "-Dsonar.python.pylint.reportPath=tmp-pylint-results.txt" \
                                    2>&1)
echo -e "$analysis_output"
expected_lines=(
    "INFO: Sensor PylintSensor \[python\]"
    "INFO: Sensor PylintImportSensor \[python\]"
    "INFO: EXECUTION SUCCESS"
)
for line in "${expected_lines[@]}"
do
    if ! echo -e "$analysis_output" | grep -q "$line";
    then
        log "$ERROR" "Failed: the output of the scanner miss the line: $line"
        >&2 echo -e "$analysis_output"
        exit 1
    fi
done

# Wait for SonarQube to process the results
sleep 8

# Check that the issue was added to the project
nbPylintIssues=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                        "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=$projectKey" \
                    | jq -r '.issues | map(select(.rule == "Pylint:C0326")) | length')
if [ "$nbPylintIssues" -ne 1 ]
then
    log "$ERROR" "An issue should have been raised by the rule Pylint:C0326"
    curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=$projectKey" | >&2 jq
    exit 1
fi

# Delete the project
res=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
            --data-urlencode "project=$projectKey" \
            "$SONARQUBE_LOCAL_URL/api/projects/delete")
if [ -n "$res" ] && [ "$(echo "$res" | jq -r '.errors | length')" -gt 0 ]
then
    log "$ERROR" "Cannot delete the project $projectKey because: $(echo "$res" | jq -r '.errors[0].msg')"
    exit 1
fi

# Deactivate the rule in CNES_PYTHON_A
res=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
            --data-urlencode "key=$qpKey" \
            --data-urlencode "rule=Pylint:C0330" \
            "$SONARQUBE_LOCAL_URL/api/qualityprofiles/deactivate_rule")
if [ -n "$res" ] && [ "$(echo "$res" | jq -r '.errors | length')" -gt 0 ]
then
    log "$ERROR" "Cannot deactivate the pylint rule in CNES_PYTHON_A because: $(echo "$res" | jq -r '.errors[0].msg')"
    exit 1
fi

log "$INFO" "Pylint analysis results successfully imported in SonarQube."
exit 0

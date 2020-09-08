#!/usr/bin/env bash

# User story:
# As a user of this image, I want to be able to import the results
# of a Frama-C analysis to SonarQube.

. tests/functions.bash

analyzerName="Frama-C"
projectName="Frama-C Dummy Project"
projectKey="framac-dummy-project"
qualityProfile="CNES_CPP_A"
languageKey="c++"
languageFolder="tests/c_cpp"
sourceFolder="framac"
ruleViolated="framac-rules:KERNEL.0"
expected_sensor="INFO: Sensor SonarFrama-C \[framac\]"
expected_import="INFO: Results file frama-c.csv has been found and will be processed."

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

# Set its Quality Profile for the given language to the given one
res=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
            --data-urlencode "language=$languageKey" \
            --data-urlencode "project=$projectKey" \
            --data-urlencode "qualityProfile=$qualityProfile" \
            "$SONARQUBE_LOCAL_URL/api/qualityprofiles/add_project")
if [ -n "$res" ] && [ "$(echo "$res" | jq -r '.errors | length')" -gt 0 ]
then
    log "$ERROR" "Cannot set Quality profile of project $projectKey to $qualityProfile for $languageKey language because: $(echo "$res" | jq -r '.errors[0].msg')"
    exit 1
fi

# Analyse the project and collect the analysis files
analysis_output=$(docker run --rm -u "$(id -u):$(id -g)" \
                            -e SONAR_HOST_URL="$SONARQUBE_URL" \
                            --net "$SONARQUBE_NETWORK" \
                            -v "$PWD/$languageFolder:/usr/src" \
                            lequal/sonar-scanner \
                                "-Dsonar.projectKey=$projectKey" \
                                "-Dsonar.projectName=$projectName" \
                                "-Dsonar.projectVersion=1.0" \
                                "-Dsonar.sources=$sourceFolder" \
                                    2>&1)
if ! echo -e "$analysis_output" | grep -q "$expected_sensor";
then
    log "$ERROR" "Failed: the output of the scanner miss the line: $expected_sensor"
    >&2 echo -e "$analysis_output"
    exit 1
elif ! echo -e "$analysis_output" | grep -q "$expected_import";
then
    log "$ERROR" "Failed: the output of the scanner miss the line: $expected_import"
    >&2 echo -e "$analysis_output"
    exit 1
else
    echo -e "$analysis_output"
fi

# Wait for SonarQube to process the results
sleep 10

# Check that the issue was added to the project
nbIssues=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                        "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=$projectKey" \
                    | jq -r ".issues | map(select(.rule == \"$ruleViolated\")) | length")
if [ "$nbIssues" -ne 1 ]
then
    log "$ERROR" "An issue should have been raised by the rule $ruleViolated"
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

log "$INFO" "$analyzerName analysis results successfully imported in SonarQube."
exit 0

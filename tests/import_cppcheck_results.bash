#!/usr/bin/env bash

# User story:
# As a user of this image, I want to be able to import the results
# of a cppcheck analysis to SonarQube.

. tests/functions.bash

analyzerName="CppCheck"
projectName="CppCheck Dummy Project"
projectKey="cppcheck-dummy-project"
qualityProfile="CNES_C_A"
languageKey="c++"
languageFolder="tests/c_cpp"
sourceFolder="cppcheck"
ruleViolated="cppcheck:arrayIndexOutOfBounds"

# Get a CNES Quality Profile key
qpKey=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/qualityprofiles/search?qualityProfile=$qualityProfile" \
        | jq -r '.profiles[0].key')
if [ "$qpKey" = "null" ]
then
    log "$ERROR" "No quality profile named $qualityProfile"
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

# Set its Quality Profile for this language to a CNES one
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

# Analyse the project and collect the analysis files (that match the default name)
analysis_output=$(docker run --rm -u "$(id -u):$(id -g)" \
                            -e SONAR_HOST_URL="$SONARQUBE_URL" \
                            --net "$SONARQUBE_NETWORK" \
                            -v "$PWD:/usr/src" \
                            -v "$PWD/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
                            lequal/sonar-scanner \
                                "-Dsonar.projectBaseDir=/usr/src/$languageFolder" \
                                "-Dsonar.projectKey=$projectKey" \
                                "-Dsonar.projectName=$projectName" \
                                "-Dsonar.projectVersion=1.0" \
                                "-Dsonar.sources=$sourceFolder" \
                                    2>&1)
echo -e "$analysis_output"
expected_lines=(
    "INFO: Sensor C++ (Community) CppCheckSensor \[cxx\]"
    "INFO: Sensor C++ (Community) VeraxxSensor \[cxx\]"
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

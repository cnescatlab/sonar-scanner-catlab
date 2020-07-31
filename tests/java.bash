#!/usr/bin/env bash

# User story:
# As a user of this image, I want to analyze a java project
# so that I can see its level of quality on the SonarQube server.

# Run analysis with the default QP (Sonar way)
output=$(docker run --rm -u "$(id -u):$(id -g)" \
           -e SONAR_HOST_URL="$SONARQUBE_URL" \
           --network "$SONARQUBE_NETWORK" \
           -v "$(pwd):/usr/src" \
           -v "$(pwd)/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
           lequal/sonar-scanner \
              -Dsonar.projectBaseDir=/usr/src/tests/java \
            2>&1)
echo -e "$output"

# Make sure all non-default Java plugins were executed by the scanner
expected_outputs=(
    "INFO: Sensor CheckstyleSensor \[checkstyle\]"
    "INFO: Sensor FindBugs Sensor \[findbugs\]"
    "INFO: Sensor PmdSensor \[pmd\]"
    "INFO: Sensor CoberturaSensor \[cobertura\]"
)
for line in "${expected_outputs[@]}"
do
    if ! echo -e "$output" | grep -q "$line";
    then
        [[ $line =~ .*\[(.*)\\\] ]]
        >&2 echo "Failed: the scanner did not use ${BASH_REMATCH[1]}."
        exit 1
    fi
done

# Wait for SonarQube to process the results
sleep 5

# Check that the project was added to the server
projectKey="java-dummy-project"
key=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/projects/search?projects=$projectKey" \
    | jq -r '(.components[0].key)')
if [ "$key" != "$projectKey" ]
then
    >&2 echo "Failed: the project is not on the server."
    exit 1
fi

# Get the number of issues of the project, there should be 3
issues=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=${projectKey}" \
        | jq '.issues | map(select(.status == "OPEN")) | length')
if [ "$issues" -ne 3 ]
then
    >&2 echo "Failed: there should be 3 issues on the Java dummy project with the Sonar way QP."
    exit 1
fi

# Switch to a CNES QP
curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
    --data-urlencode "language=java" \
    --data-urlencode "project=${projectKey}" \
    --data-urlencode "qualityProfile=CNES_JAVA_A" \
    "$SONARQUBE_LOCAL_URL/api/qualityprofiles/add_project"

# Rerun the analysis
docker run --rm -u "$(id -u):$(id -g)" \
           -e SONAR_HOST_URL="$SONARQUBE_URL" \
           --network "$SONARQUBE_NETWORK" \
           -v "$(pwd):/usr/src" \
           -v "$(pwd)/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
           lequal/sonar-scanner \
              -Dsonar.projectBaseDir=/usr/src/tests/java \
            2>&1

# Wait for SonarQube to process the results
sleep 5

# Switch back to the Sonar way QP (if the test needs to be rerun)
curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
    --data-urlencode "language=java" \
    --data-urlencode "project=${projectKey}" \
    --data-urlencode "qualityProfile=Sonar way" \
    "$SONARQUBE_LOCAL_URL/api/qualityprofiles/add_project"

# There should be 6 issues
issues=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=${projectKey}" \
        | jq '.issues | map(select(.status == "OPEN")) | length')
if [ "$issues" -ne 6 ]
then
    >&2 echo "Failed: there should be 6 issues on the Java dummy project with the CNES_JAVA_A QP."
    exit 1
fi

echo "Analyses succeeded, Java is supported."
exit 0

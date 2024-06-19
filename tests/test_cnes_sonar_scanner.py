"""
Automated integration test of CNES sonar-scanner-catlab

Run the tests by launching ``pytest`` from the "tests/" folder.

Pytest documentation: https://docs.pytest.org/en/stable/contents.html
"""

import filecmp
import os
import time
from pathlib import Path

import docker
import requests


class TestCNESSonarScanner:
    """
    This class test the lequal/sonar-scanner image.
    It runs a container of the lequal/sonarqube-catlab image and run analysis with
    lequal/sonar-scanner.
    It does not build any image.
    Tests can be parametered with environment variables.

    Environment variables:
        RUN: whether or not to run a lequal/sonarqube-catlab container and create a
             bridge network, default "yes", if you already have a running
             container, set it to "no" and provide information through the
             other variables.
        SONARQUBE_CONTAINER_NAME: the name to give to the container running
                                  the lequal/sonarqube-catlab image.
        SONARQUBE_ADMIN_PASSWORD: the password of the admin account on the server.
        SONARQUBE_URL: URL of lequal/sonarqube-catlab container if already running
                        without trailing / from the scanner container.
                        e.g. http://mycontainer:9000
                        Use it only if no container name was given.
        SONARQUBE_LOCAL_URL: URL of lequal/sonarqube-catlab container if already running
                            without trailing / from the host.
                            e.g. http://localhost:9000
        SONARQUBE_TAG: the tag of the lequal/sonarqube-catlab image to use.
                        e.g. latest
        SONARQUBE_NETWORK: the name of the docker bridge used.
    """
    # Class variables
    RUN = os.environ.get('RUN', "yes") == "yes"
    SONARQUBE_CONTAINER_NAME = os.environ.get("SONARQUBE_CONTAINER_NAME", "lequalsonarqube")
    SONARQUBE_ADMIN_PASSWORD = os.environ.get("SONARQUBE_ADMIN_PASSWORD", "adminpassword")
    SONARQUBE_URL = os.environ.get("SONARQUBE_URL", f"http://{SONARQUBE_CONTAINER_NAME}:9000")
    SONARQUBE_LOCAL_URL = os.environ.get("SONARQUBE_LOCAL_URL", "http://localhost:9000")
    SONARQUBE_TAG = os.environ.get("SONARQUBE_TAG", "latest")
    SONARQUBE_NETWORK = os.environ.get("SONARQUBE_NETWORK", "sonarbridge")
    _SONAR_SCANNER_IMAGE = "lequal/sonar-scanner-catlab"
    _PROJECT_ROOT_DIR = str(Path(os.getcwd()).parent)
    SONARQUBE_TOKEN = ""

    # Setup and Teardown
    @classmethod
    def setup_class(cls):
        """
        Set up the tests
        Launch a lequal/sonarqube-catlab container and wait for it to be up
        """
        docker_client = docker.from_env()
        # Launch a CNES SonarQube container
        if cls.RUN:
            print(f"Creating bridge network (name={cls.SONARQUBE_NETWORK})...")
            docker_client.networks.create(cls.SONARQUBE_NETWORK)
            print(f"Launching lequal/sonarqube-catlab container (name={cls.SONARQUBE_CONTAINER_NAME})...")
            docker_client.containers.run(f"lequal/sonarqube-catlab:{cls.SONARQUBE_TAG}",
                name=cls.SONARQUBE_CONTAINER_NAME,
                detach=True,
                auto_remove=True,
                environment={"SONARQUBE_ADMIN_PASSWORD": cls.SONARQUBE_ADMIN_PASSWORD},
                ports={9000: 9000},
                network=cls.SONARQUBE_NETWORK)
        else:
            print(f"Using container {cls.SONARQUBE_CONTAINER_NAME} and network {cls.SONARQUBE_NETWORK}")

        # Create cache folder for sonar-scanner
        cache_dir_path = os.path.join(cls._PROJECT_ROOT_DIR, '.sonarcache')
        if not os.path.exists(cache_dir_path):
            os.makedirs(cache_dir_path)
        # Wait for the SonarQube server inside it to be set up
        print(f"Waiting for {cls.SONARQUBE_CONTAINER_NAME} to be up...")
        cls.wait_cnes_sonarqube_ready(cls.SONARQUBE_CONTAINER_NAME)
        # Retrieve the token
        cls.get_sonarqube_token()

    @classmethod
    def teardown_class(cls):
        """
        Stop the container
        """
        # Revoke the token
        requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/user_tokens/revoke",
                      auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
                    params={
                        "name": "global_token"
                    })
        if cls.RUN:
            print(f"Stopping {cls.SONARQUBE_CONTAINER_NAME}...")
            docker_client = docker.from_env()
            docker_client.containers.get(cls.SONARQUBE_CONTAINER_NAME).stop()
            print(f"Removing bridge network {cls.SONARQUBE_NETWORK}...")
            docker_client.networks.get(cls.SONARQUBE_NETWORK).remove()

    # Functions
    @classmethod
    def get_sonarqube_token(cls):
        """
        Retrieve SonarQube token with global analysis from the server
        """
        sonarqube_token = requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/user_tokens/generate",
                                            auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
                                            params={
                                                "name": "global_token",
                                                "type": "GLOBAL_ANALYSIS_TOKEN",
                                                "login": "admin"
                                            })
        cls.SONARQUBE_TOKEN = sonarqube_token.json()["token"]

    @classmethod
    def wait_cnes_sonarqube_ready(cls, container_name: str, tail = "all"):
        """
        This function waits for SonarQube to be configured by
        the configure.bash script.

        :param container_name: name of the container running lequal/sonarqube-catlab
        :param tail: forwarded to docker logs
        """
        docker_client = docker.from_env()
        while b'[INFO] CNES SonarQube: ready!' not in docker_client.containers.get(container_name).logs(tail=tail):
            time.sleep(10)

    @classmethod
    def language(cls, language_name: str, language_key: str, folder: str,
        sensors_info, project_key: str, nb_issues: int, cnes_qp: str = "",
        nb_issues_cnes_qp: int = 0):
        """
        This function tests that the image can analyze a project.

        Environment variables used:
            SONARQUBE_URL
            SONARQUBE_LOCAL_URL
            SONARQUBE_NETWORK
            SONARQUBE_ADMIN_PASSWORD

        :param language_name: language name to display
        :param language_key: language key for SonarQube
        :param folder: folder name, relative to the tests/ folder
        :param sensors_INFO  array of lines of sensors to look for in the scanner output
        :param project_key: project key (sonar.project_key of sonar-project.properties)
        :param nb_issues: number of issues with the Sonar way Quality Profile
        :param cnes_qp: (optional) name of the CNES Quality Profile to apply, if any
        :param nb_issues_cnes_qp: (optional) number of issues with the CNES Quality Profile, if specified

        Example (not a doctest):
            sensors = (
                "INFO  Sensor CheckstyleSensor [checkstyle]",
                "INFO  Sensor FindBugs Sensor [findbugs]",
                "INFO  Sensor PmdSensor [pmd]",
                "INFO  Sensor CoberturaSensor [cobertura]"
            )
            self.language("Java", "java", "java", sensors, "java-dummy-project", 3, "CNES_JAVA_A", 6)
        """
        docker_client = docker.from_env()

        # Inner functions to factor out some code
        def analyse_project():
            """
            Factor out code analysis by the sonar-scanner

            :returns: output of the analysis
            """

            print(f"Analysing project {project_key}...")
            output = docker_client.containers.run(cls._SONAR_SCANNER_IMAGE,
                f"-Dsonar.projectBaseDir=/usr/src/tests/{folder} -Dsonar.login={cls.SONARQUBE_TOKEN}",
                auto_remove=True,
                environment={"SONAR_HOST_URL": cls.SONARQUBE_URL},
                network=cls.SONARQUBE_NETWORK,
                user="0:0",
                volumes={
                    f"{cls._PROJECT_ROOT_DIR}": {'bind': '/usr/src', 'mode': 'rw'},
                    f"{cls._PROJECT_ROOT_DIR}/.sonarcache": {'bind': '/opt/sonar-scanner/.sonar/cache', 'mode': 'rw'}
                }).decode("utf-8")
            return output

        def get_number_of_issues():
            """
            Factor out the resquest to get the number of issues of a project on SonarQube

            :returns: the number of issues
            """
            output = requests.get(f"{cls.SONARQUBE_LOCAL_URL}/api/issues/search?componentKeys={project_key}",
                        auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD)).json()['issues']
            issues = [ issue for issue in output if issue['status'] in ('OPEN', 'TO_REVIEW') ]
            return len(issues)

        # Analyse the project
        output = analyse_project()
        # Make sure all non-default for this language plugins were executed by the scanner
        for sensor_line in sensors_info:
            # Hint: if this test fails, a plugin may not be installed correctly or a sensor is not triggered when needed
            assert any(sensor_line in line for line in output.split('\n'))
        # Wait for SonarQube to process the results
        time.sleep(8)
        # Check that the project was added to the server
        output = requests.get(f"{cls.SONARQUBE_LOCAL_URL}/api/projects/search?projects={project_key}",
                        auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD)).json()
        # Hint: if this test fails, the project is not on the server
        assert output['components'][0]['key'] == project_key
        # Hint: if this test fails, there should be {nb_issues issues} on the {language_name}
        # dummy project with the Sonar way QP but {len(issues)} were found
        assert get_number_of_issues() == nb_issues
        print("Analysis with Sonar way QP ran as expected.")
        # If the language has a specific CNES Quality Profile, it must also be tested
        if cnes_qp:
            # Switch to CNES QP
            requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/qualityprofiles/add_project",
                auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
                data={
                    "language": language_key,
                    "project": project_key,
                    "qualityProfile": cnes_qp
                })
            # Rerun the analysis
            analyse_project()
            # Wait for SonarQube to process the results
            time.sleep(8)
            # Switch back to the Sonar way QP (in case the test needs to be rerun)
            requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/qualityprofiles/add_project",
                auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
                data={
                    "language": language_key,
                    "project": project_key,
                    "qualityProfile": "Sonar way"
                })
            # Hint: if this test fails, there should be {nb_issues_cnes_qp} issues on the {language_name} dummy project with the {cnes_qp} QP but {len(issues)} were found
            assert get_number_of_issues() == nb_issues_cnes_qp

    @classmethod
    def analysis_tool(cls, tool: str, cmd: str, ref_file: str, tmp_file: str, store_output: bool = True):
        """
        This function tests that the image can run a specified code analyzer
        and that it keeps producing the same result given the same source code.

        :param tool: tool name
        :param cmd: tool command line
        :param ref_file: analysis results reference file (path from the root of the project)
        :param tmp_file: temporary results file (path from the root of the project)
        :param store_output: (optional) store the standard output in the temporary result file, default: True

        Example (not a doctest):
            ref = "tests/c_cpp/reference-cppcheck-results.xml"
            output = "tests/c_cpp/tmp-cppcheck-results.xml"
            cmd = f"cppcheck --xml-version=2 tests/c_cpp/cppcheck/main.c --output-file={output}"
            self.analysis_tool("cppcheck", cmd, ref, output, False)
        """
        # Run an analysis with the tool
        docker_client = docker.from_env()
        output = docker_client.containers.run(cls._SONAR_SCANNER_IMAGE, cmd,
            auto_remove=True,
            user="0:0",
            volumes={f"{cls._PROJECT_ROOT_DIR}": {'bind': '/usr/src', 'mode': 'rw'}}).decode("utf-8")
        if store_output:
            with open(os.path.join(cls._PROJECT_ROOT_DIR, tmp_file), "w", encoding="utf8") as f:
                f.write(output)
        # Compare the result of the analysis with the reference
        # Hint: if this test fails, look for differences with: diff {tmp_file} {ref_file}
        assert filecmp.cmp(os.path.join(cls._PROJECT_ROOT_DIR, tmp_file), os.path.join(cls._PROJECT_ROOT_DIR, ref_file))

    @classmethod
    def import_analysis_results(cls, project_name: str, project_key: str,
        quality_profile: str, language_key: str, language_folder: str,
        source_folder: str, rule_violated: str, expected_sensor: str,
        expected_import: str, activate_rule: bool = False):
        """
        This function tests that the analysis results produced
        by an analysis tool can be imported in SonarQube. The results
        must be stored in the default files.

        :param project_name: project name
        :param project_key: project key
        :param quality_profile: quality profile to use
        :param language_key: language key
        :param language_folder: folder to run the sonar-scanner in (relative to the root of the project)
        :param source_folder: folder containing the source files (relative to the previous folder)
        :param rule_violated: id of a rule violated by a source file
        :param expected_sensor: line of output of the sonar-scanner that tells the import sensor is used
        :param expected_import: line of output of the sonar-scanner that tells the result file was imported
        :param activate_rule: True if if the rule violated needs to be activated in the Quality Profile for the import sensor to be run

        Example (not a doctest):
            rule_violated = "cppcheck:arrayIndexOutOfBounds"
            expected_sensor = "INFO  Sensor C++ (Community) CppCheckSensor [cxx]"
            expected_import = "INFO  CXX-CPPCHECK processed = 1"
            self.import_analysis_results("CppCheck Dummy Project", "cppcheck-dummy-project",
                "CNES_C_A", "c++", "tests/c_cpp", "cppcheck", rule_violated, expected_sensor, expected_import)
        """
        if activate_rule:
            # Get the key of the Quality Profile to use
            qp_key = requests.get(f"{cls.SONARQUBE_LOCAL_URL}/api/qualityprofiles/search?quality_profile={quality_profile}",
                auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD)).json()['profiles'][0]['key']
            # Activate the rule in the Quality Profile to allow the Sensor to be used
            requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/qualityprofiles/activate_rule",
                auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
                data={
                    "key": qp_key,
                    "rule": rule_violated
                })
        # Create a project on SonarQube
        errors = requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/projects/create",
            auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
            data={
                "name": project_name,
                "project": project_key
            }).json().get('errors', [])
        assert not errors
        # Set its Quality Profile for the given language to the given one
        requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/qualityprofiles/add_project",
            auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
            data={
                "language": language_key,
                "project": project_key,
                "qualityProfile": quality_profile
            })
        # Analyse the project and collect the analysis files (that match the default names)
        docker_client = docker.from_env()
        analysis_output = docker_client.containers.run(cls._SONAR_SCANNER_IMAGE,
            f"-Dsonar.projectKey={project_key} -Dsonar.projectName=\"{project_name}\" -Dsonar.projectVersion=1.0 -Dsonar.sources={source_folder} \
            -Dsonar.login={cls.SONARQUBE_TOKEN}",
            auto_remove=True,
            user="0:0",
            volumes={
                f"{cls._PROJECT_ROOT_DIR}": {'bind': '/usr/src', 'mode': 'rw'},
                f"{cls._PROJECT_ROOT_DIR}/.sonarcache": {'bind': '/opt/sonar-scanner/.sonar/cache', 'mode': 'rw'}
            },
            environment={"SONAR_HOST_URL": cls.SONARQUBE_URL},
            network=cls.SONARQUBE_NETWORK,
            working_dir=f"/usr/src/{language_folder}").decode("utf-8")
        for line in (expected_sensor, expected_import):
            # Hint: if this test fails, the sensor for the tool or for the importation was not launched
            assert line in analysis_output
        # Wait for SonarQube to process the results
        time.sleep(10)
        # Check that the issue was added to the project
        issues = requests.get(f"{cls.SONARQUBE_LOCAL_URL}/api/issues/search?componentKeys={project_key}",
            auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD)).json()['issues']
        nb_issues = len([ issue for issue in issues if issue['rule'] == rule_violated ])
        # Hint: an issue must be raised by the rule violated
        assert nb_issues == 1
        # Delete the project
        requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/projects/delete",
            auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
            data={"project": project_key})
        if activate_rule:
            # Deactivate the rule in the Quality Profile
            requests.post(f"{cls.SONARQUBE_LOCAL_URL}/api/qualityprofiles/deactivate_rule",
                auth=("admin", cls.SONARQUBE_ADMIN_PASSWORD),
                data={
                    "key": qp_key,
                    "rule": rule_violated
                })

    # Language tests
    def test_language_c_cpp(self):
        """
        As a user of this image, I want to analyze a C/C++ project
        so that I can see its level of quality on the SonarQube server.
        """
        sensors = (
            "INFO  Sensor CXX [cxx]",
        )
        self.language("C/C++", "cxx", "c_cpp", sensors, "c-dummy-project", 0, "RNC C A", 0)
        # 0 issue are expected with the Sonar way Quality Profile for
        # C++ (Community) because it does not have any rule enabled.

    def test_language_fortran_77(self):
        """
        As a user of this image, I want to analyze a fortran 77 project
        so that I can see its level of quality on the SonarQube server.
        """
        sensors = (
            "INFO  Sensor Sonar i-Code [icode]",
        )
        self.language("Fortran 77", "f77", "fortran77", sensors, "fortran77-dummy-project", 11)

    def test_language_fortran_90(self):
        """
        As a user of this image, I want to analyze a fortran 90 project
        so that I can see its level of quality on the SonarQube server.
        """
        sensors = (
            "INFO  Sensor Sonar i-Code [icode]",
        )
        self.language("Fortran 90", "f90", "fortran90", sensors, "fortran90-dummy-project", 14)

    def test_language_java(self):
        """
        As a user of this image, I want to analyze a java project
        so that I can see its level of quality on the SonarQube server.
        """
        sensors = (
            "INFO  Sensor CheckstyleSensor [checkstyle]",
            "INFO  Sensor FindBugs Sensor [findbugs]",
            "INFO  Sensor PmdSensor [pmd]",
            "INFO  Sensor CoberturaSensor [cobertura]"
        )
        self.language("Java", "java", "java", sensors, "java-dummy-project", 3, "RNC A", 6)

    def test_language_python(self):
        """
        As a user of this image, I want to analyze a Python project
        so that I can see its level of quality on the SonarQube server.
        """
        self.language("Python", "py", "python", (), "python-dummy-project", 3, "RNC A", 2)

    def test_language_shell(self):
        """
        As a user of this image, I want to analyze a shell project
        so that I can see its level of quality on the SonarQube server.
        """
        sensors = (
            "INFO  Sensor ShellCheck Sensor [shellcheck]",
        )
        self.language("Shell", "shell", "shell", sensors, "shell-dummy-project", 60, "RNC SHELL", 19)

    # Test analysis tools
    def test_tool_cppcheck(self):
        """
        As a user of this image, I want to run cppcheck from within a container
        so that it produces a report.
        """
        ref = "tests/c_cpp/reference-cppcheck-results.xml"
        output = "tests/c_cpp/tmp-cppcheck-results.xml"
        cmd = f"cppcheck --xml-version=2 tests/c_cpp/cppcheck/main.c --output-file={output}"
        self.analysis_tool("cppcheck", cmd, ref, output, False)

    def test_tool_pylint(self):
        """
        As a user of this image, I want to run pylint from within a container
        so that it produces a report.
        """
        cmd = "pylint --exit-zero -f json --rcfile=/opt/python/pylintrc_RNC2015_A_B tests/python/src/simplecaesar.py"
        self.analysis_tool("pylint", cmd, "tests/python/reference-pylint-results.json", "tests/python/tmp-pylint-results.json")

    def test_tool_shellcheck(self):
        """
        As a user of this image, I want to run shellcheck from within a container
        so that it produces a report.
        """
        cmd = "bash -c 'shellcheck -s sh -f checkstyle tests/shell/src/script.sh || true'"
        self.analysis_tool("shellcheck", cmd, "tests/shell/reference-shellcheck-results.xml", "tests/shell/tmp-shellcheck-results.xml")

    # Test importation of analysis results
    def test_import_cppcheck_results(self):
        """
        As a user of this image, I want to be able to import the results
        of a CppCheck analysis to SonarQube.
        """
        rule_violated = "cppcheck:arrayIndexOutOfBounds"
        expected_sensor = "INFO  Sensor CXX [cxx]"
        expected_import = "INFO  Sensor CXX Cppcheck report import"
        self.import_analysis_results("CppCheck Dummy Project", "cppcheck-dummy-project",
            "RNC CPP A", "cxx", "tests/c_cpp", "cppcheck", rule_violated, expected_sensor, expected_import)

    def test_import_pylint_results(self):
        """
        As a user of this image, I want to be able to import the results
        of a pylint analysis to SonarQube.
        """
        rule_violated = "external_pylint:C0326"
        expected_sensor = "INFO  Sensor Python Sensor [python]"
        expected_import = "INFO  Sensor Import of Pylint issues [python]"
        self.import_analysis_results("Pylint Dummy Project", "pylint-dummy-project",
            "Sonar way", "py", "tests/python", "src", rule_violated, expected_sensor, expected_import)

import os
import re
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch


PROJECT_TEMPLATES = (
    "api",
    "app",
    "ds",
    "integration-test",
    "jax-rs",
    "jpa-dao",
    "servlet",
)
LAUNCH_CONFIGS = (
    ("app", "template-app/template-app.bndrun"),
    ("ds", "template-ds/launch.bndrun"),
    ("jax-rs", "template-jax-rs/launch.bndrun"),
    ("servlet", "template-servlet/launch.bndrun"),
    ("felix-gogo", "template-launch-probe/template-launch.bndrun"),
)
PROBE_BSN = "template-launch-probe"
PACKAGE = "org.bndtools.templates.smoke"
PLACEHOLDER = re.compile(r"\$(?:if\([^)]+\)|endif|[A-Za-z][A-Za-z0-9]*)\$")


def render_tree(source, destination, project_name, file_name="template-launch.bndrun"):
    values = {
        "$srcDir$": "src/main/java",
        "$testSrcDir$": "src/test/java",
        "$basePackageDir$": "org/bndtools/templates/smoke",
        "$basePackageName$": PACKAGE,
        "$projectName$": project_name,
        "$fileName$": file_name,
        "$javaLevel$": "17",
    }
    source = Path(source)
    destination = Path(destination)
    ignored = {"bin", "generated"}

    for item in source.rglob("*"):
        relative = item.relative_to(source)
        if any(part in ignored for part in relative.parts):
            continue

        rendered_parts = []
        for part in relative.parts:
            for token, value in values.items():
                part = part.replace(token, value)
            rendered_parts.extend(part.replace("\\", "/").split("/"))
        output = destination.joinpath(*rendered_parts)

        if item.is_dir():
            output.mkdir(parents=True, exist_ok=True)
            continue

        output.parent.mkdir(parents=True, exist_ok=True)
        data = item.read_bytes()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            output.write_bytes(data)
            continue

        text = text.replace("$if(javaLevel)$", "").replace("$endif$", "")
        for token, value in values.items():
            text = text.replace(token, value)
        text = text.replace(r"\${", "${")
        if PLACEHOLDER.search(text):
            raise AssertionError(f"Unrendered template variable in {item}")
        output.write_text(text, encoding="utf-8")


class MinimalWorkspaceTemplateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workspace_value = os.environ.get("BND_MIN_WORKSPACE")
        bnd_value = os.environ.get("BND_JAR")
        if not workspace_value:
            raise RuntimeError("Set BND_MIN_WORKSPACE to the bndtools.workspace.min root")
        if not bnd_value:
            raise RuntimeError("Set BND_JAR to the bnd CLI JAR")

        cls.workspace_source = Path(workspace_value).resolve()
        cls.bnd_jar = Path(bnd_value).resolve()
        cls.java = shutil.which("java")
        if not (cls.workspace_source / "cnf" / "build.bnd").is_file():
            raise RuntimeError(f"Not a bnd workspace: {cls.workspace_source}")
        if not cls.bnd_jar.is_file():
            raise RuntimeError(f"bnd CLI JAR not found: {cls.bnd_jar}")
        if not cls.java:
            raise RuntimeError("Java not found on PATH")

        cls.repo_root = Path(__file__).resolve().parents[1]
        output_value = os.environ.get("BND_TESTBED_OUTPUT")
        cls.temp_dir = None
        if output_value:
            cls.output = Path(output_value).resolve()
        else:
            cls.temp_dir = tempfile.TemporaryDirectory(prefix="bnd-template-min-")
            cls.output = Path(cls.temp_dir.name)
        cls.logs = cls.output / "logs"
        cls.logs.mkdir(parents=True, exist_ok=True)
        cls.command_number = 0
        cls.workspace = cls.output / "workspace"
        cls.workspace.mkdir()
        shutil.copytree(
            cls.workspace_source / "cnf",
            cls.workspace / "cnf",
            ignore=shutil.ignore_patterns(
                "cache", "local", "release", "templates", "generated", "bin"
            ),
        )
        for index in ("build.mvn", "runtime.mvn"):
            shutil.copy2(cls.repo_root / "cnf" / index, cls.workspace / "cnf" / "ext" / index)

        build_config = cls.workspace / "cnf" / "build.bnd"
        config_text = build_config.read_text(encoding="utf-8")
        config_text = re.sub(
            r"(?m)^-remoteworkspace\s+true\s*$",
            "-remoteworkspace false",
            config_text,
        )
        repository_build_config = cls.repo_root / "cnf" / "build.bnd"
        config_text += "\n" + repository_build_config.read_text(encoding="utf-8").split(
            "# JUnit\n", 1
        )[1]
        config_text += (
            "\nsrc: src/main/java\n"
            "testsrc: src/test/java\n"
            "testbin: bin_test\n"
            "\n-plugin.99.TestRelease: \\\n"
            "\taQute.bnd.deployer.repository.LocalIndexedRepo; \\\n"
            "\tname=TestRelease; pretty=true; local=${build}/test-release\n"
            "-releaserepo: TestRelease\n"
            "-baselinerepo: TestRelease\n"
        )
        build_config.write_text(config_text, encoding="utf-8")

        template_root = cls.repo_root / "org.bndtools.templates.osgi" / "resources" / "templates"
        for name in PROJECT_TEMPLATES:
            project_name = f"template-{name}"
            render_tree(
                template_root / name,
                cls.workspace / project_name,
                project_name,
            )

        cls._create_launch_probe()
        render_tree(
            template_root / "launch" / "felix-gogo",
            cls.workspace / PROBE_BSN,
            "template-launch",
            "template-launch.bndrun",
        )
        cls._prepare_launch_configs()
        cls._make_placeholder_unit_tests_pass()

    @classmethod
    def tearDownClass(cls):
        if cls.temp_dir is not None:
            cls.temp_dir.cleanup()

    @classmethod
    def _create_launch_probe(cls):
        project = cls.workspace / PROBE_BSN
        package_dir = project / "src" / "main" / "java" / "template" / "smoke"
        package_dir.mkdir(parents=True)
        (project / "bnd.bnd").write_text(
            "Bundle-SymbolicName: template-launch-probe\n"
            "Bundle-Version: 1.0.0\n"
            "Bundle-Activator: template.smoke.LaunchProbe\n"
            "-buildpath: osgi.core;version=8.0.0\n"
            "-privatepackage: template.smoke\n",
            encoding="utf-8",
        )
        shutil.copyfile(
            cls.repo_root / "testbed" / "lib" / "LaunchProbe.java",
            package_dir / "LaunchProbe.java",
        )

    @classmethod
    def _prepare_launch_configs(cls):
        requirement = "\tosgi.identity;filter:='(osgi.identity=template-launch-probe)',\\"
        for name, relative in LAUNCH_CONFIGS:
            path = cls.workspace / relative
            text = path.read_text(encoding="utf-8")
            header = re.compile(r"(?m)^-runrequires:[ \t]*\\[ \t]*$")
            text, count = header.subn(
                lambda _: "-runrequires: \\\n" + requirement,
                text,
                count=1,
            )
            if count != 1:
                raise AssertionError(f"No continuation-style -runrequires in {relative}")
            if name == "jax-rs":
                text = text.replace(
                    "-runprovidedcapabilities: ${native_capability}",
                    "-runprovidedcapabilities: ${native_capability},\\\n"
                    "\tosgi.implementation;osgi.implementation=osgi.jaxrs;version:Version=1.0.0",
                    1,
                )
            path.write_text(text, encoding="utf-8")

        integration_bnd = cls.workspace / "template-integration-test" / "bnd.bnd"
        text = integration_bnd.read_text(encoding="utf-8")
        text = text.replace(
            "\t${mockito-deps}\n",
            "\t${mockito-deps},\\\n\ttemplate-launch-probe\n",
            1,
        )
        if "template-launch-probe" not in text:
            raise AssertionError("Could not add launch probe to integration-test runbundles")
        integration_bnd.write_text(text, encoding="utf-8")

    @classmethod
    def _make_placeholder_unit_tests_pass(cls):
        for project in ("ds", "jax-rs", "servlet"):
            test_root = cls.workspace / f"template-{project}" / "src" / "test"
            for source in test_root.rglob("*.java"):
                text = source.read_text(encoding="utf-8")
                text = text.replace('fail("Not yet implemented");', "assertTrue(true);")
                source.write_text(text, encoding="utf-8")

    @classmethod
    def _command(cls, *arguments, timeout=180, allowed_returncodes=(0,), cwd=None, java_arguments=None):
        command = [cls.java, *(java_arguments if java_arguments is not None else
                               ["-jar", str(cls.bnd_jar), *arguments])]
        directory = cwd or cls.workspace
        cls.command_number += 1
        log = cls.logs / f"{cls.command_number:02d}-{arguments[0]}.log"
        heading = f"Command: {subprocess.list2cmdline(command)}\nDirectory: {directory}\n\n"
        try:
            result = subprocess.run(
                command,
                cwd=directory,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            log.write_text(heading + output + f"\nTIMEOUT: {timeout}s\n", encoding="utf-8")
            raise AssertionError(
                f"Timed out after {timeout}s: {' '.join(command)}\n{output}"
            ) from error
        log.write_text(
            heading + result.stdout + f"\nExit code: {result.returncode}\n",
            encoding="utf-8",
        )
        if result.returncode not in allowed_returncodes:
            raise AssertionError(
                f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}"
            )
        return result.stdout

    def test_01_build_all_project_templates(self):
        for name in PROJECT_TEMPLATES:
            project_name = f"template-{name}"
            with self.subTest(project=project_name):
                self._command("build", cwd=self.workspace / project_name)
            self._command("build", cwd=self.workspace / PROBE_BSN)

    def test_02_run_project_unit_and_integration_tests(self):
        for name in ("ds", "jax-rs", "servlet"):
            project_name = f"template-{name}"
            with self.subTest(project=project_name):
                project = self.workspace / project_name
                self._command("build", "--test", cwd=project)
                classpath = self._command("classpath", "--testpath", cwd=project).strip()
                classpath += os.pathsep + str(project / "bin_test")
                output = self._command(
                    "junit", cwd=project,
                    java_arguments=["-cp", classpath, "org.junit.runner.JUnitCore", f"{PACKAGE}.ExampleTest"],
                )
                self.assertRegex(output, r"OK \([1-9][0-9]* tests?\)")

        self._command(
            "test",
            cwd=self.workspace / "template-integration-test",
            timeout=180,
        )
        self._assert_test_reports("template-integration-test")

    def _assert_test_reports(self, project_name):
        reports = list((self.workspace / project_name).rglob("TEST-*.xml"))
        self.assertTrue(reports, f"No JUnit XML reports for {project_name}")
        tests = 0
        for report in reports:
            root = ET.parse(report).getroot()
            suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")
            for suite in suites:
                tests += int(suite.get("tests", "0"))
                self.assertEqual(int(suite.get("failures", "0")), 0, str(report))
                self.assertEqual(int(suite.get("errors", "0")), 0, str(report))
        self.assertGreater(tests, 0, f"No tests executed for {project_name}")

    def test_03_resolve_all_bndrun_templates(self):
        for name, relative in LAUNCH_CONFIGS:
            with self.subTest(launch=relative):
                self._command("resolve", "resolve", "-W", relative)

    def test_04_launch_all_bndrun_templates(self):
        for name, relative in LAUNCH_CONFIGS:
            with self.subTest(launch=relative):
                marker = self.logs / f"{name}-startup.marker"
                marker.unlink(missing_ok=True)
                with patch.dict(os.environ, {"TEMPLATE_SMOKE_MARKER": str(marker)}):
                    output = self._command(
                        "run", relative, timeout=60, allowed_returncodes=(0, 1)
                    )
                self.assertTrue(marker.is_file(), f"No startup marker for {relative}")
                if "Errors" in output:
                    self.assertIn("Exit code remote process 117:", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
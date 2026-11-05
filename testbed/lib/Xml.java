import java.nio.file.Path;
import java.util.regex.Pattern;

import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.xpath.XPathFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;

class Xml {
    private static Document parse(String file) throws Exception {
        var factory = DocumentBuilderFactory.newInstance();
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        return factory.newDocumentBuilder().parse(Path.of(file).toFile());
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length < 2) {
            throw new IllegalArgumentException("Expected metadata <file> <release|latest|snapshot> or junit <files...>");
        }
        if (arguments[0].equals("rc")) {
            var xpath = XPathFactory.newInstance().newXPath();
            String release = xpath.evaluate("/metadata/versioning/release", parse(arguments[1])).trim();
            if (!release.matches("[0-9]+\\.[0-9]+\\.[0-9]+")) {
                throw new IllegalArgumentException("Invalid release version: " + release);
            }
            String[] parts = release.split("\\.");
            int[] best = {Integer.parseInt(parts[0]), Integer.parseInt(parts[1]),
                          Integer.parseInt(parts[2]), Integer.MAX_VALUE};
            String selected = "";
            var pattern = Pattern.compile("([0-9]+)\\.([0-9]+)\\.([0-9]+)-RC([0-9]+)");
            var versions = parse(arguments[2]).getElementsByTagName("version");
            for (int index = 0; index < versions.getLength(); index++) {
                String version = versions.item(index).getTextContent().trim();
                var matcher = pattern.matcher(version);
                if (!matcher.matches()) {
                    continue;
                }
                int[] candidate = {Integer.parseInt(matcher.group(1)), Integer.parseInt(matcher.group(2)),
                                   Integer.parseInt(matcher.group(3)), Integer.parseInt(matcher.group(4))};
                for (int component = 0; component < best.length; component++) {
                    if (candidate[component] != best[component]) {
                        if (candidate[component] > best[component]) {
                            best = candidate;
                            selected = version;
                        }
                        break;
                    }
                }
            }
            if (!selected.isEmpty()) {
                System.out.println(selected);
            }
            return;
        }
        if (arguments[0].equals("metadata")) {
            var xpath = XPathFactory.newInstance().newXPath();
            String expression = switch (arguments[2]) {
                case "release" -> "/metadata/versioning/release";
                case "latest" -> "/metadata/versioning/latest";
                case "snapshot" -> "/metadata/versioning/snapshotVersions/snapshotVersion[extension='jar' and not(classifier)]/value";
                default -> throw new IllegalArgumentException("Unknown metadata field");
            };
            String value = xpath.evaluate(expression, parse(arguments[1])).trim();
            if (value.isEmpty()) {
                throw new IllegalArgumentException("Missing metadata field: " + arguments[2]);
            }
            System.out.println(value);
            return;
        }
        if (!arguments[0].equals("junit")) {
            throw new IllegalArgumentException("Unknown XML operation");
        }
        int tests = 0;
        int failures = 0;
        int errors = 0;
        for (int index = 1; index < arguments.length; index++) {
            var suites = parse(arguments[index]).getElementsByTagName("testsuite");
            for (int suiteIndex = 0; suiteIndex < suites.getLength(); suiteIndex++) {
                var suite = (Element) suites.item(suiteIndex);
                tests += count(suite, "tests");
                failures += count(suite, "failures");
                errors += count(suite, "errors");
            }
        }
        if (tests == 0 || failures != 0 || errors != 0) {
            throw new IllegalStateException("JUnit: " + tests + " tests, " + failures + " failures, " + errors + " errors");
        }
        System.out.println("JUnit: " + tests + " tests, no failures or errors");
    }

    private static int count(Element suite, String attribute) {
        String value = suite.getAttribute(attribute);
        return value.isEmpty() ? 0 : Integer.parseInt(value);
    }
}
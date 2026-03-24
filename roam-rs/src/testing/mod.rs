// Test report parsing module.
//
// Parses JUnit XML, Jest JSON, pytest JSON, and Go test JSON output into a
// unified `TestReportSummary`.  The helper reads the report file from disk and
// returns structured results to the iOS client.

use serde::Serialize;
use serde_json::Value;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, PartialEq)]
pub struct TestReportSummary {
    pub total: usize,
    pub passed: usize,
    pub failed: usize,
    pub skipped: usize,
    pub duration_secs: f64,
    pub failures: Vec<TestFailure>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct TestFailure {
    pub name: String,
    pub message: String,
    pub file: Option<String>,
    pub line: Option<u32>,
}

// ---------------------------------------------------------------------------
// XML attribute helper (simple string-based extraction for JUnit)
// ---------------------------------------------------------------------------

fn extract_xml_attr(tag_content: &str, attr_name: &str) -> Option<String> {
    // Match  name="value"  or  name='value'
    let patterns = [format!("{attr_name}=\""), format!("{attr_name}='")];
    for pattern in &patterns {
        if let Some(start) = tag_content.find(pattern.as_str()) {
            let val_start = start + pattern.len();
            let quote = pattern.chars().last().unwrap();
            if let Some(end) = tag_content[val_start..].find(quote) {
                return Some(tag_content[val_start..val_start + end].to_string());
            }
        }
    }
    None
}

fn extract_xml_attr_usize(tag: &str, name: &str) -> usize {
    extract_xml_attr(tag, name)
        .and_then(|v| v.parse().ok())
        .unwrap_or(0)
}

fn extract_xml_attr_f64(tag: &str, name: &str) -> f64 {
    extract_xml_attr(tag, name)
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0)
}

/// Extract `file:line` hints from failure messages or classnames.
fn extract_file_line(classname: &str, message: &str) -> (Option<String>, Option<u32>) {
    // Common patterns: "path/to/file.py:42", "file.rs:123: message"
    for text in [message, classname] {
        for segment in text.split_whitespace() {
            if let Some((file_part, line_part)) = segment.rsplit_once(':') {
                if let Ok(line) = line_part.trim_end_matches(|c: char| !c.is_ascii_digit()).parse::<u32>() {
                    if file_part.contains('.') && !file_part.starts_with("http") {
                        return (Some(file_part.to_string()), Some(line));
                    }
                }
            }
        }
    }
    (None, None)
}

// ---------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------

/// Parse JUnit XML test reports.
///
/// Handles both single `<testsuite>` and wrapped `<testsuites>` formats.
pub fn parse_junit(content: &str) -> Result<TestReportSummary, String> {
    if !content.contains("<testsuite") {
        return Err("no <testsuite> element found".into());
    }

    let mut total = 0usize;
    let mut failures_count = 0usize;
    let mut errors_count = 0usize;
    let mut skipped_count = 0usize;
    let mut time = 0.0f64;
    let mut failures = Vec::new();

    // Aggregate across all <testsuite> elements.
    for chunk in content.split("<testsuite").skip(1) {
        let attrs_end = chunk.find('>').unwrap_or(chunk.len());
        let attrs = &chunk[..attrs_end];

        total += extract_xml_attr_usize(attrs, "tests");
        failures_count += extract_xml_attr_usize(attrs, "failures");
        errors_count += extract_xml_attr_usize(attrs, "errors");
        skipped_count += extract_xml_attr_usize(attrs, "skipped");
        time += extract_xml_attr_f64(attrs, "time");
    }

    // Extract individual failure details from <testcase> elements.
    for chunk in content.split("<testcase").skip(1) {
        let tc_end = chunk
            .find("</testcase>")
            .or_else(|| chunk.find("/>"))
            .unwrap_or(chunk.len());
        let tc_content = &chunk[..tc_end];

        if tc_content.contains("<failure") || tc_content.contains("<error") {
            let attrs_end = tc_content.find('>').unwrap_or(tc_content.len());
            let attrs = &tc_content[..attrs_end];

            let name = extract_xml_attr(attrs, "name").unwrap_or_default();
            let classname = extract_xml_attr(attrs, "classname").unwrap_or_default();

            let message = if let Some(pos) = tc_content.find("<failure") {
                extract_xml_attr(&tc_content[pos..], "message").unwrap_or_default()
            } else if let Some(pos) = tc_content.find("<error") {
                extract_xml_attr(&tc_content[pos..], "message").unwrap_or_default()
            } else {
                String::new()
            };

            let (file, line) = extract_file_line(&classname, &message);

            failures.push(TestFailure {
                name,
                message,
                file,
                line,
            });
        }
    }

    let passed = total.saturating_sub(failures_count + errors_count + skipped_count);

    Ok(TestReportSummary {
        total,
        passed,
        failed: failures_count + errors_count,
        skipped: skipped_count,
        duration_secs: time,
        failures,
    })
}

/// Parse Jest JSON test reports.
pub fn parse_jest(content: &str) -> Result<TestReportSummary, String> {
    let root: Value = serde_json::from_str(content).map_err(|e| format!("invalid JSON: {e}"))?;

    let total = root["numTotalTests"].as_u64().unwrap_or(0) as usize;
    let passed = root["numPassedTests"].as_u64().unwrap_or(0) as usize;
    let failed = root["numFailedTests"].as_u64().unwrap_or(0) as usize;
    let pending = root["numPendingTests"].as_u64().unwrap_or(0) as usize;

    // Duration: Jest provides startTime (epoch ms). Some versions have a
    // top-level `testResults[].perfStats.runtime`. We compute a rough duration
    // from startTime and endTime if available, otherwise fall back to
    // summing suite-level times.
    let start = root["startTime"].as_f64().unwrap_or(0.0);
    let mut max_end = start;
    let mut failures = Vec::new();

    if let Some(suites) = root["testResults"].as_array() {
        for suite in suites {
            // Suite-level endTime
            if let Some(end) = suite["endTime"].as_f64() {
                if end > max_end {
                    max_end = end;
                }
            }

            // Individual test results are in suite.testResults[]
            if let Some(tests) = suite["testResults"].as_array() {
                for test in tests {
                    if test["status"].as_str() == Some("failed") {
                        let ancestors = test["ancestorTitles"]
                            .as_array()
                            .map(|a| {
                                a.iter()
                                    .filter_map(|v| v.as_str())
                                    .collect::<Vec<_>>()
                                    .join(" > ")
                            })
                            .unwrap_or_default();

                        let title = test["title"].as_str().unwrap_or("unknown");
                        let name = if ancestors.is_empty() {
                            title.to_string()
                        } else {
                            format!("{ancestors} > {title}")
                        };

                        let message = test["failureMessages"]
                            .as_array()
                            .and_then(|msgs| msgs.first())
                            .and_then(|m| m.as_str())
                            .unwrap_or("")
                            .to_string();

                        let (file, line) = extract_file_line("", &message);

                        failures.push(TestFailure {
                            name,
                            message,
                            file,
                            line,
                        });
                    }
                }
            }
        }
    }

    let duration_secs = if max_end > start {
        (max_end - start) / 1000.0
    } else {
        0.0
    };

    Ok(TestReportSummary {
        total,
        passed,
        failed,
        skipped: pending,
        duration_secs,
        failures,
    })
}

/// Parse pytest JSON reports (pytest-json-report format).
pub fn parse_pytest(content: &str) -> Result<TestReportSummary, String> {
    let root: Value = serde_json::from_str(content).map_err(|e| format!("invalid JSON: {e}"))?;

    let summary = &root["summary"];
    let total = summary["total"].as_u64().unwrap_or(0) as usize;
    let passed = summary["passed"].as_u64().unwrap_or(0) as usize;
    let failed = summary["failed"].as_u64().unwrap_or(0) as usize;
    let skipped = summary["skipped"].as_u64().unwrap_or(0) as usize;
    let duration_secs = root["duration"].as_f64().unwrap_or(0.0);

    let mut failures = Vec::new();

    if let Some(tests) = root["tests"].as_array() {
        for test in tests {
            let outcome = test["outcome"].as_str().unwrap_or("");
            if outcome == "failed" {
                let nodeid = test["nodeid"].as_str().unwrap_or("unknown");
                let message = test["longrepr"]
                    .as_str()
                    .or_else(|| {
                        test["call"]["longrepr"].as_str()
                    })
                    .unwrap_or("")
                    .to_string();

                // nodeid format: "path/to/test.py::TestClass::test_method"
                let (file, line) = if let Some((file_part, _)) = nodeid.split_once("::") {
                    // Try to find line number in the longrepr
                    let line = extract_file_line(file_part, &message).1;
                    (Some(file_part.to_string()), line)
                } else {
                    (None, None)
                };

                failures.push(TestFailure {
                    name: nodeid.to_string(),
                    message,
                    file,
                    line,
                });
            }
        }
    }

    Ok(TestReportSummary {
        total,
        passed,
        failed,
        skipped,
        duration_secs,
        failures,
    })
}

/// Parse Go test JSON output (`go test -json`).
///
/// Each line is a JSON object with fields: Time, Action, Package, Test, Output, Elapsed.
/// We track test-level pass/fail/skip events (those with a `Test` field).
pub fn parse_go_test(content: &str) -> Result<TestReportSummary, String> {
    let mut passed = 0usize;
    let mut failed = 0usize;
    let mut skipped = 0usize;
    let mut total_elapsed = 0.0f64;
    let mut failures = Vec::new();

    // Collect output lines per (package, test) for failure messages.
    let mut output_buf: std::collections::HashMap<(String, String), Vec<String>> =
        std::collections::HashMap::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let event: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue, // skip non-JSON lines (e.g. build output)
        };

        let action = event["Action"].as_str().unwrap_or("");
        let package = event["Package"].as_str().unwrap_or("");
        let test = event["Test"].as_str();

        match action {
            "output" => {
                if let (Some(test_name), Some(output)) = (test, event["Output"].as_str()) {
                    output_buf
                        .entry((package.to_string(), test_name.to_string()))
                        .or_default()
                        .push(output.to_string());
                }
            }
            "pass" => {
                if test.is_some() {
                    passed += 1;
                } else if let Some(elapsed) = event["Elapsed"].as_f64() {
                    // Package-level pass — use its elapsed time.
                    total_elapsed += elapsed;
                }
            }
            "fail" => {
                if let Some(test_name) = test {
                    failed += 1;

                    let key = (package.to_string(), test_name.to_string());
                    let message = output_buf
                        .remove(&key)
                        .map(|lines| lines.join(""))
                        .unwrap_or_default()
                        .trim()
                        .to_string();

                    let (file, line_no) = extract_file_line("", &message);

                    let name = if package.is_empty() {
                        test_name.to_string()
                    } else {
                        format!("{package}/{test_name}")
                    };

                    failures.push(TestFailure {
                        name,
                        message,
                        file,
                        line: line_no,
                    });
                } else if let Some(elapsed) = event["Elapsed"].as_f64() {
                    total_elapsed += elapsed;
                }
            }
            "skip" => {
                if test.is_some() {
                    skipped += 1;
                }
            }
            _ => {}
        }
    }

    let total = passed + failed + skipped;

    Ok(TestReportSummary {
        total,
        passed,
        failed,
        skipped,
        duration_secs: total_elapsed,
        failures,
    })
}

// ---------------------------------------------------------------------------
// RPC handler
// ---------------------------------------------------------------------------

/// RPC handler: testing.parse_report
pub struct ParseReportHandler;

#[async_trait::async_trait]
impl MethodHandler for ParseReportHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let path = params
            .get("path")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing 'path' parameter".into(),
            })?;

        let format = params
            .get("format")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing 'format' parameter".into(),
            })?;

        let content = tokio::fs::read_to_string(path).await.map_err(|e| RpcError {
            code: -32603,
            message: format!("failed to read {path}: {e}"),
        })?;

        let summary = match format {
            "junit" => parse_junit(&content),
            "jest" => parse_jest(&content),
            "pytest" => parse_pytest(&content),
            "go_test" => parse_go_test(&content),
            other => Err(format!("unknown format: {other} (expected junit|jest|pytest|go_test)")),
        }
        .map_err(|e| RpcError {
            code: -32603,
            message: e,
        })?;

        serde_json::to_value(&summary).map_err(|e| RpcError {
            code: -32603,
            message: format!("serialization error: {e}"),
        })
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -- JUnit ---------------------------------------------------------

    #[test]
    fn junit_basic() {
        let xml = r#"<?xml version="1.0"?>
<testsuite name="Tests" tests="3" failures="1" errors="0" skipped="1" time="0.456">
  <testcase name="test_pass" classname="suite" time="0.1"/>
  <testcase name="test_fail" classname="suite" time="0.2">
    <failure message="expected 1 got 2">assertion failed</failure>
  </testcase>
  <testcase name="test_skip" classname="suite" time="0.0">
    <skipped/>
  </testcase>
</testsuite>"#;

        let summary = parse_junit(xml).unwrap();
        assert_eq!(summary.total, 3);
        assert_eq!(summary.passed, 1);
        assert_eq!(summary.failed, 1);
        assert_eq!(summary.skipped, 1);
        assert!((summary.duration_secs - 0.456).abs() < 0.001);
        assert_eq!(summary.failures.len(), 1);
        assert_eq!(summary.failures[0].name, "test_fail");
        assert_eq!(summary.failures[0].message, "expected 1 got 2");
    }

    #[test]
    fn junit_multiple_suites() {
        let xml = r#"<testsuites>
  <testsuite tests="2" failures="0" errors="0" skipped="0" time="1.0"/>
  <testsuite tests="3" failures="1" errors="1" skipped="0" time="2.0"/>
</testsuites>"#;

        let summary = parse_junit(xml).unwrap();
        assert_eq!(summary.total, 5);
        assert_eq!(summary.failed, 2); // 1 failure + 1 error
        assert_eq!(summary.passed, 3);
        assert!((summary.duration_secs - 3.0).abs() < 0.001);
    }

    #[test]
    fn junit_error_element() {
        let xml = r#"<testsuite tests="1" failures="0" errors="1" time="0.5">
  <testcase name="test_err" classname="suite">
    <error message="null pointer">stack trace</error>
  </testcase>
</testsuite>"#;

        let summary = parse_junit(xml).unwrap();
        assert_eq!(summary.failed, 1);
        assert_eq!(summary.failures.len(), 1);
        assert_eq!(summary.failures[0].name, "test_err");
        assert_eq!(summary.failures[0].message, "null pointer");
    }

    #[test]
    fn junit_no_testsuite_errors() {
        assert!(parse_junit("not xml at all").is_err());
    }

    // -- Jest ----------------------------------------------------------

    #[test]
    fn jest_basic() {
        let json = r#"{
  "numTotalTests": 4,
  "numPassedTests": 2,
  "numFailedTests": 1,
  "numPendingTests": 1,
  "startTime": 1000000,
  "testResults": [
    {
      "endTime": 1002000,
      "testResults": [
        {
          "title": "should add",
          "status": "passed",
          "ancestorTitles": ["MathUtils"]
        },
        {
          "title": "should subtract",
          "status": "failed",
          "ancestorTitles": ["MathUtils"],
          "failureMessages": ["Expected 3 to be 4 at src/math.test.js:10"]
        }
      ]
    }
  ]
}"#;

        let summary = parse_jest(json).unwrap();
        assert_eq!(summary.total, 4);
        assert_eq!(summary.passed, 2);
        assert_eq!(summary.failed, 1);
        assert_eq!(summary.skipped, 1);
        assert!((summary.duration_secs - 2.0).abs() < 0.001);
        assert_eq!(summary.failures.len(), 1);
        assert_eq!(summary.failures[0].name, "MathUtils > should subtract");
    }

    #[test]
    fn jest_invalid_json_errors() {
        assert!(parse_jest("not json").is_err());
    }

    // -- pytest --------------------------------------------------------

    #[test]
    fn pytest_basic() {
        let json = r#"{
  "summary": {
    "total": 5,
    "passed": 3,
    "failed": 1,
    "skipped": 1
  },
  "duration": 1.234,
  "tests": [
    {
      "nodeid": "tests/test_app.py::TestApp::test_login",
      "outcome": "failed",
      "longrepr": "AssertionError: status was 401"
    },
    {
      "nodeid": "tests/test_app.py::TestApp::test_home",
      "outcome": "passed"
    }
  ]
}"#;

        let summary = parse_pytest(json).unwrap();
        assert_eq!(summary.total, 5);
        assert_eq!(summary.passed, 3);
        assert_eq!(summary.failed, 1);
        assert_eq!(summary.skipped, 1);
        assert!((summary.duration_secs - 1.234).abs() < 0.001);
        assert_eq!(summary.failures.len(), 1);
        assert_eq!(
            summary.failures[0].name,
            "tests/test_app.py::TestApp::test_login"
        );
        assert_eq!(
            summary.failures[0].file.as_deref(),
            Some("tests/test_app.py")
        );
    }

    #[test]
    fn pytest_invalid_json_errors() {
        assert!(parse_pytest("{bad}").is_err());
    }

    // -- Go test -------------------------------------------------------

    #[test]
    fn go_test_basic() {
        let json_lines = r#"{"Action":"run","Package":"example","Test":"TestAdd"}
{"Action":"output","Package":"example","Test":"TestAdd","Output":"=== RUN   TestAdd\n"}
{"Action":"pass","Package":"example","Test":"TestAdd","Elapsed":0.01}
{"Action":"run","Package":"example","Test":"TestSub"}
{"Action":"output","Package":"example","Test":"TestSub","Output":"--- FAIL: TestSub\n"}
{"Action":"output","Package":"example","Test":"TestSub","Output":"    sub_test.go:15: expected 1 got 2\n"}
{"Action":"fail","Package":"example","Test":"TestSub","Elapsed":0.02}
{"Action":"run","Package":"example","Test":"TestSkip"}
{"Action":"skip","Package":"example","Test":"TestSkip","Elapsed":0.0}
{"Action":"fail","Package":"example","Elapsed":0.05}"#;

        let summary = parse_go_test(json_lines).unwrap();
        assert_eq!(summary.total, 3);
        assert_eq!(summary.passed, 1);
        assert_eq!(summary.failed, 1);
        assert_eq!(summary.skipped, 1);
        assert!((summary.duration_secs - 0.05).abs() < 0.001);
        assert_eq!(summary.failures.len(), 1);
        assert_eq!(summary.failures[0].name, "example/TestSub");
    }

    #[test]
    fn go_test_empty_input() {
        let summary = parse_go_test("").unwrap();
        assert_eq!(summary.total, 0);
    }

    #[test]
    fn go_test_skips_non_json_lines() {
        let input = "PASS\nok example 0.01s\n";
        let summary = parse_go_test(input).unwrap();
        assert_eq!(summary.total, 0);
    }

    // -- helpers -------------------------------------------------------

    #[test]
    fn xml_attr_extraction() {
        assert_eq!(
            extract_xml_attr(r#"name="hello" time="1.5""#, "name"),
            Some("hello".into())
        );
        assert_eq!(
            extract_xml_attr(r#"name='world'"#, "name"),
            Some("world".into())
        );
        assert_eq!(extract_xml_attr(r#"other="x""#, "name"), None);
    }

    #[test]
    fn file_line_extraction() {
        let (file, line) = extract_file_line("", "at src/foo.rs:42 something");
        assert_eq!(file.as_deref(), Some("src/foo.rs"));
        assert_eq!(line, Some(42));

        let (file, line) = extract_file_line("", "no file reference here");
        assert!(file.is_none());
        assert!(line.is_none());
    }

    #[test]
    fn summary_serializes() {
        let s = TestReportSummary {
            total: 10,
            passed: 8,
            failed: 1,
            skipped: 1,
            duration_secs: 2.5,
            failures: vec![TestFailure {
                name: "test_x".into(),
                message: "boom".into(),
                file: Some("foo.rs".into()),
                line: Some(42),
            }],
        };
        let json = serde_json::to_value(&s).unwrap();
        assert_eq!(json["total"], 10);
        assert_eq!(json["failures"][0]["name"], "test_x");
    }
}

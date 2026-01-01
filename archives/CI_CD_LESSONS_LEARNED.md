# CI/CD and Testing Lessons Learned

This document summarizes key learnings and solutions encountered while setting up a containerized CI pipeline with GitHub Actions, Docker, and Karate.

## 1. Docker Build Arguments and Secrets
**Issue**: Passing secrets as build arguments to `docker build` via shell commands is prone to errors due to quoting and shell expansion.
**Symptoms**: You might see obscure syntax errors in your build log like:
```bash
docker: "build" requires 1 argument.
See 'docker build --help'.
```
Or, if the build succeeds, our application crashes at runtime because the secret variable is empty.
**Solution**: Use the official `docker/build-push-action`. it handles secret injection safely and correctly parsing arguments.

**Example**:
```yaml
- name: Build App Image
  uses: docker/build-push-action@v5
  with:
    context: .
    load: true # Keeps image available for subsequent steps
    build-args: |
      REACT_APP_GOOGLE_API_KEY=${{ secrets.REACT_APP_GOOGLE_API_KEY }}
```

## 2. GitHub Environments
**Issue**: Secrets defined in a specific GitHub Environment (e.g., `CI`) are not accessible to the workflow job unless the job explicitly references that environment.
**Symptoms**: Your workflow runs, but steps that need the secret fail. If you print the secret (be careful!), it is empty. Your app logs might say:
```
Error: GOOGLE_API_KEY is not set
```
**Solution**: Add the `environment` property to the job configuration.

**Example**:
```yaml
jobs:
  test:
    environment: CI
    steps:
      ...
```

## 3. Java Version Compatibility
**Issue**: Tools may have specific Java requirements that differ from the project default. Karate 1.5.0+ requires Java 17, while the project might be on Java 11.
**Symptoms**: The build fails immediately with a class version error:
```
java.lang.UnsupportedClassVersionError: 
com/intuit/karate/Main has been compiled by a more recent version 
of the Java Runtime (class file version 61.0)...
```
**Solution**: Explicitly set the Java version in both the CI environment (`actions/setup-java`) and the Maven configuration (`maven-compiler-plugin`).

**CI Config**:
```yaml
- uses: actions/setup-java@v4
  with:
    java-version: '17'
```

## 4. Testing with Restricted API Keys
**Issue**: Frontend API keys often have "Referrer Restrictions" (e.g., allow `localhost:3000`).
**Symptoms**: Your API tests fail with a **403 Forbidden** status code. The response body explicitly mentions restrictions:
```json
{
  "error_message": "API keys with referer restrictions cannot be used with this API.",
  "status": "REQUEST_DENIED"
}
```
*   **Problem A**: Direct API calls (backend-style) from tests lack the `Referer` header and fail with `REQUEST_DENIED`.
*   **Problem B**: Some Google Web Services (Places/Directions Web Service) strictly reject frontend keys regardless of headers.

**Solutions**:
*   **Add Headers**: For permitted APIs, add the header in the test background: `* header Referer = 'http://localhost:3000/'`.
*   **Ignore Invalid Tests**: If the key is strictly frontend-only, do not run direct backend API tests. Use `@ignore` tags.

## 5. Headless Chrome Stability (UI Tests)
**Issue**: UI tests that pass locally often fail in headless CI environments due to race conditions or rendering differences.
**Symptoms**: The test report shows random failures only in CI. Screenshots taken during failure might show:
*   A blank page (the element hasn't loaded yet).
*   A different element being clicked because the intended one wasn't ready.

Logs often show `js.lang.RuntimeException: js eval failed` or timeout errors.

**Solutions**:
*   **Explicit Waits**: Never assume an element is ready. Use `waitFor('#id')` or `waitFor("//xpath")`.
*   **Robust Selectors**: Material UI and other frameworks often nest text.
    *   *Bad*: `//button[text()='Clear']` (Fails if text is in a `<span>`)
    *   *Good*: `//button[contains(., 'Clear')]` (Checks text content of element and children)
*   **Mock Blocking functions**: `window.alert` can block the execution thread in headless mode. Overwrite it to prevent hangs if an error occurs.
    *   *Karate Example*: `* script("window.alert = function(){}")`

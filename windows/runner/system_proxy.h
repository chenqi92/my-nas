#ifndef RUNNER_SYSTEM_PROXY_H_
#define RUNNER_SYSTEM_PROXY_H_

// Copies the current Windows user's static proxy configuration into the
// process environment before Flutter starts. Existing proxy variables win.
void ApplyWindowsSystemProxyEnvironment();

#endif  // RUNNER_SYSTEM_PROXY_H_

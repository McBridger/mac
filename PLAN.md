# Project Bridge: Development Plan

This document outlines the planned features and improvements for the Bridge application.

## 1. Implement True Two-Way Synchronization via Separate BLE Characteristics

**Goal:** Refactor the Bluetooth communication logic to use two distinct characteristics for sending and receiving data. This improves clarity and aligns with standard BLE practices.

### To-Do List:

## 1. Automate App Building in CI/CD

**Goal:** Streamline the build and release process by integrating automated builds into a Continuous Integration/Continuous Deployment (CI/CD) pipeline.

### To-Do List:

1.  **Choose a CI/CD Platform:**
    *   Select a suitable CI/CD platform (e.g., GitLab CI/CD, GitHub Actions, Jenkins, Azure DevOps).

2.  **Configure Build Environment:**
    *   Set up a macOS runner/agent with Xcode installed.

3.  **Create CI/CD Pipeline Configuration:**
    *   Write a configuration file (e.g., `.gitlab-ci.yml`, `.github/workflows/build.yml`) to define the build steps.
    *   Include steps for:
        *   Checking out the repository.
        *   Installing dependencies (if any).
        *   Building the Xcode project (e.g., `xcodebuild`).
        *   Archiving the application.
        *   Signing the application (if necessary, using certificates and provisioning profiles).
        *   Exporting the application for distribution (e.g., `.app` or `.pkg`).

4.  **Integrate with Version Control:**
    *   Ensure the CI/CD pipeline is triggered automatically on relevant events (e.g., push to `main` branch, tag creation).

5.  **Implement Artifact Storage:**
    *   Configure the pipeline to store the built application as an artifact for easy access and deployment.

# Contributing to Files Utility

Thank you for your interest in contributing to **Files Utility**! We welcome code contributions, documentation improvements, issue reports, and feature proposals.

---

## 🛠️ Development Setup & Environment

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.10.8` or newer, `stable` channel)
- [Dart SDK](https://dart.dev/get-dart) (`^3.0.0`)
- Git (`^2.30`)
- OS-specific build tools:
  - **macOS**: Xcode & Command Line Tools (`xcode-select --install`)
  - **Windows**: Visual Studio 2022 (with C++ Desktop development workload)

### Getting Started
1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/files_utility.git
   cd files_utility
   ```
3. **Install dependencies**:
   ```bash
   flutter pub get
   ```
4. **Run the test suite**:
   ```bash
   flutter test
   ```

---

## 🌿 Branching Strategy & Workflow

We follow standard GitHub flow for contributions:

1. Create a branch off `main` with a descriptive name:
   - `feat/<feature-name>` for new capabilities
   - `fix/<bug-description>` for bug fixes
   - `docs/<topic>` for documentation updates
   - `refactor/<module>` for code cleanups without behavior changes
2. Keep branches focused on a single logical change.

---

## ✍️ Commit Standards (Conventional Commits)

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```text
<type>(<optional scope>): <short summary>

[optional body]

[optional footer(s)]
```

### Common Types
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code (formatting, white-space)
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `perf`: A code change that improves performance
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to build process, release tasks, or auxiliary tools

### Examples
- `feat(transfer): add option to preserve source folder structure`
- `fix(copy): handle UNC paths with whitespace correctly`
- `test(profile): add serialization round-trip tests`

---

## 🧪 Testing & Quality Gates

All contributions must meet our quality standards before merging:

1. **Static Analysis**:
   Must pass with zero warnings or errors:
   ```bash
   flutter analyze --fatal-infos
   ```
2. **Code Formatting**:
   Format all Dart files using `dart format`:
   ```bash
   dart format --output=none --set-exit-if-changed lib test
   ```
3. **Automated Tests**:
   Ensure all existing tests pass, and add unit or widget tests for any new functionality:
   ```bash
   flutter test
   ```

---

## 📬 Pull Request Guidelines

1. Ensure the CI pipeline passes on your pull request.
2. Complete all sections of the [Pull Request Template](.github/pull_request_template.md).
3. Reference relevant issue numbers (e.g., `Closes #42` or `Fixes #15`).
4. Avoid submitting unrelated changes or extraneous refactorings in the same PR.
5. Maintain backward compatibility with existing SQLite schemas (`files_utility.db` and profile databases). Any schema modifications must include migrations.

---

## 💬 Community & Code of Conduct

- Be respectful and constructive in issue discussions and pull request reviews.
- Provide minimal reproduction steps and logs when reporting bugs.
- For questions or support, use the GitHub Discussions or open an issue.

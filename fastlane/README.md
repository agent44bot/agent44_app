fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios push_metadata

```sh
[bundle exec] fastlane ios push_metadata
```

Push metadata only (description, copyright, review notes, etc.)

### ios push_screenshots

```sh
[bundle exec] fastlane ios push_screenshots
```

Push screenshots only

### ios verify_metadata

```sh
[bundle exec] fastlane ios verify_metadata
```

Verify metadata against ASC without pushing

### ios pull_metadata

```sh
[bundle exec] fastlane ios pull_metadata
```

One-time: pull current ASC metadata into fastlane/metadata/

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

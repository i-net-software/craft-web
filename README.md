craft-web
=========

[![Sync](https://github.com/i-net-software/craft-web/actions/workflows/sync.yml/badge.svg)](https://github.com/i-net-software/craft-web/actions/workflows/sync.yml)
[![GridCraft Web](https://img.shields.io/maven-central/v/de.inetsoftware/gridcraft-web.svg?label=gridcraft-web)](https://mvnrepository.com/artifact/de.inetsoftware/gridcraft-web)
[![WordCraft Web](https://img.shields.io/maven-central/v/de.inetsoftware/wordcraft-web.svg?label=wordcraft-web)](https://mvnrepository.com/artifact/de.inetsoftware/wordcraft-web)
[![License](https://img.shields.io/github/license/i-net-software/craft-web.svg)](LICENSE)

Maven Central artifacts for the WebAssembly builds of the [Craft apps](https://github.com/storytold). Java applications can embed the editors and serve them from the classpath.

This repository does not build the apps. It watches their GitHub releases, verifies the published web archive and republishes it unchanged as a signed jar.

Artifacts
----

| Artifact | Upstream | Contents |
| --- | --- | --- |
| [`de.inetsoftware:gridcraft-web`](https://mvnrepository.com/artifact/de.inetsoftware/gridcraft-web) | [storytold/gridcraft](https://github.com/storytold/gridcraft) | spreadsheet editor |
| [`de.inetsoftware:wordcraft-web`](https://mvnrepository.com/artifact/de.inetsoftware/wordcraft-web) | [storytold/wordcraft](https://github.com/storytold/wordcraft) | word processor |

The version is the upstream version: `gridcraft-web-0.11.1.jar` contains `gridcraft-web-0.11.1.zip` from the upstream release `v0.11.1`.

Usage
----

    dependencies {
        implementation 'de.inetsoftware:gridcraft-web:0.11.1'
    }

The jar contains the files of the web archive under `META-INF/resources/craft/<app>/`, for example `META-INF/resources/craft/gridcraft/index.html`. Servlet 3 containers serve `META-INF/resources` automatically. Otherwise read the files with `ClassLoader.getResource`.

Serve `.wasm` files as `application/wasm`. `HOSTING.md` and the `_headers` file from upstream describe the headers the app expects. Both are part of the jar.

The licenses of the app are in `META-INF/licenses/<app>/`.

How it works
----

    upstream release ──► plan ──► download + SHA-256 check ──► jar ──► Maven Central ──► tag here
         (hourly)

1. [`sync.yml`](.github/workflows/sync.yml) runs every hour and on demand.
2. [`scripts/plan.sh`](scripts/plan.sh) reads [`apps.yml`](apps.yml) and lists the final releases of each upstream repository. A release is new if this repository has no tag `<artifact-id>-<version>`.
3. [`scripts/fetch.sh`](scripts/fetch.sh) downloads the web archive and compares it with the `SHA256SUMS.txt` of the same release. A missing entry or a different checksum stops the run.
4. [`build.gradle`](build.gradle) repackages the archive, signs it and uploads it with the [Sonatype Central Portal](https://central.sonatype.org/publish/publish-portal-ossrh-staging-api/) staging API.
5. Only after a successful upload the workflow creates the tag and a GitHub release with the jar attached. If a step fails, the next run starts again with that version.

Releases are processed one at a time and oldest first.

### What is verified

The checksum comes from the same GitHub release as the archive. It protects against a damaged download, not against a compromised upstream release. The upstream repositories do not publish build attestations at the moment. If they do, add `gh attestation verify` to `scripts/fetch.sh`.

The jar adds nothing to the archive. It only moves the files to `META-INF/resources/craft/<app>/` and the license files to `META-INF/licenses/<app>/`.

Add an app
----

Append an entry to [`apps.yml`](apps.yml) and open a pull request. The entry needs a repository that publishes a web archive and a `SHA256SUMS.txt` with every release. Set `since` to the first version you want. Older releases are ignored.

Maven Central versions cannot be changed or deleted. Check the first version in a local run before you merge.

Setup
----

Repository secrets, same as for [JLessC](https://github.com/i-net-software/jlessc):

| Secret | Content |
| --- | --- |
| `SONATYPE_USERNAME`, `SONATYPE_PASSWORD` | token of the Central Portal account that owns the namespace `de.inetsoftware` |
| `SIGNING_KEY`, `SIGNING_PASSWORD` | ASCII-armored private PGP key and its passphrase |

Scheduled workflows run for free in public repositories. GitHub disables them after 60 days without repository activity; start the workflow manually to enable it again.

Run locally
----

Needs JDK 17 or newer, Gradle 8.14, `gh`, `jq` and `yq`. The project has no Gradle wrapper; the workflows install Gradle 8.14.3. This builds one jar into `build/repo` without credentials and without publishing:

    scripts/fetch.sh storytold/gridcraft 0.11.1 gridcraft-web-0.11.1.zip build/input
    gradle \
      -PappId=gridcraft -PappName='GridCraft Web' -PappDescription='Browser build of GridCraft.' \
      -PappUpstream=storytold/gridcraft -PappArtifactId=gridcraft-web \
      -PappVersion=0.11.1 -PappAsset=gridcraft-web-0.11.1.zip -PinputDir=build/input \
      publishAllPublicationsToBuildRepository

To see which releases the next run would publish:

    GITHUB_REPOSITORY=i-net-software/craft-web GH_TOKEN=$(gh auth token) scripts/plan.sh

License
----

The scripts and build files in this repository are under the [MIT License](LICENSE). The republished apps are by their authors, licensed under MIT OR Apache-2.0. Each jar carries the license texts of its app.

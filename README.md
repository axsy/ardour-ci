# Ardour CI for macOS ARM64

`ardour-ci` is a local build pipeline for Ardour on native Apple Silicon. Keep
this repository separate from the Ardour checkout. It resolves the official
macOS ARM64 `build-stack` revision from Ardour nightly information, builds that
stack in an isolated local directory, compiles Ardour, and runs Ardour's normal
macOS packager to create an unsigned public app bundle.

The tool never runs `git pull`, `git rebase`, or `git checkout` in Ardour. You
always choose and update the source revision yourself.

## Prerequisites

This pipeline currently supports **macOS on Apple Silicon (`arm64`) only**.
It requires an administrator account for the Apple developer-tool installation,
an Internet connection, and substantial free disk space. The first dependency
stack build downloads and compiles many projects, so plan for at least 30 GB of
free space and a long initial build.

### 1. Install Apple developer tools

Install the Command Line Tools from Terminal:

```bash
xcode-select --install
```

After the installer completes, verify the selected toolchain:

```bash
xcode-select -p
clang --version
make --version
```

If you use the full Xcode application, open it once or accept its licence from
the command line:

```bash
sudo xcodebuild -license accept
```

The `xcode-select --install` command displays an Apple installer window; it is
not an unattended package installation. Do not continue until `xcode-select -p`
prints a valid developer directory.

### 2. Install host command-line tools

`doctor` requires `git`, `curl`, `make`, `patch`, `perl`, and `python3`.
Recent macOS installations with the Command Line Tools provide most of them.
Check them before building:

```bash
for tool in git curl make patch perl python3; do
  command -v "$tool" || echo "missing: $tool"
done
```

If any tool is missing, Homebrew is suitable for installing these **host
tools**. Install Homebrew only when it is not already available:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the post-installation shell setup printed by Homebrew, open a new
terminal, then install the tools:

```bash
brew install git curl python make patch perl
```

Homebrew's GNU Make command may be named `gmake`; macOS's `/usr/bin/make` is
also acceptable for this pipeline. Verify the environment with:

```bash
./bin/ardour-ci doctor
```

### 3. Keep Homebrew out of Ardour's library stack

Do **not** install Ardour libraries through Homebrew (for example `gtk+`,
`boost`, `libxml2`, `fftw`, `rubberband`, or `pkg-config`) for this pipeline.
Homebrew is used only for missing host executables. `deps build` checks out the
official Ardour `build-stack` revision and builds the patched, versioned library
stack under `ardour-ci/.work/stacks/`; it does not link Ardour against Homebrew
libraries.

The host must be able to reach the official nightly host-info page, the Ardour
build-stack Git repository, dependency download locations, and the video
components downloaded by `osx_build --public`. If your network blocks the
`git://` protocol, set `ARDOUR_CI_BUILD_STACK_URL` to an approved reachable
mirror before running `deps build`.

### 4. Clone both repositories

Use a common parent directory so that the default `../ardour` source location
works:

```bash
mkdir -p "$HOME/src/ardour-workspace"
cd "$HOME/src/ardour-workspace"
git clone https://github.com/Ardour/ardour.git ardour
git clone <your-ardour-ci-repository-url> ardour-ci
```

If your Ardour checkout lives elsewhere, use `config set-source` or pass
`--source /absolute/path/to/ardour` to every pipeline command.

## Quick start

Place both checkouts next to each other:

```text
workspace/
├── ardour/
└── ardour-ci/
```

Choose the Ardour release before running the pipeline:

```bash
cd ../ardour
git pull --rebase
git checkout <tag>

cd ../ardour-ci
./bin/ardour-ci config set-source ../ardour
./bin/ardour-ci deps sync
./bin/ardour-ci all
```

The `.app` and standard unsigned DMG are copied to
`.work/artifacts/<ardour-commit>/`. The application bundle includes the video
components requested by Ardour's `osx_build --public` packager.

## Commands

```bash
./bin/ardour-ci doctor
./bin/ardour-ci config show
./bin/ardour-ci source status
./bin/ardour-ci deps sync
./bin/ardour-ci deps build
./bin/ardour-ci build
./bin/ardour-ci package
./bin/ardour-ci all
```

Use `--source /absolute/path/to/ardour` with any command to override the saved
source directory. `--work-dir /path/to/cache` moves all pipeline state,
downloads, stacks, logs, and artifacts. `--jobs N` sets parallelism;
`--dry-run` prints work without executing it.

Run `./bin/ardour-ci --help` for the complete command synopsis.

## Switching Ardour versions

First inspect the selected source state:

```bash
./bin/ardour-ci source status
cd ../ardour
git tag --list
git checkout <another-tag>
cd ../ardour-ci
./bin/ardour-ci all
```

Every Ardour commit receives a distinct build directory and metadata record.
Switching tags therefore creates a new Waf configuration instead of reusing an
incompatible build. The tool does not replace an existing non-symlink
`ardour/build` directory: move or remove that generated directory yourself if
it belongs to an old manual build.

## Dependency stack updates

`deps sync` is the only command that updates the build-stack revision. It reads
the official ARM64 nightly host information and records the returned commit in
`.work/build-stack.lock`. `deps build`, `build`, `package`, and `all` reuse that
lock, making repeated builds use the same dependency recipes until you explicitly
run `deps sync` again.

Use `--stack-rev <40-hex-commit>` to lock or build a specific upstream
build-stack commit. The stack itself is stored under
`.work/stacks/<build-stack-commit>/`.

## Cleanup and troubleshooting

`./bin/ardour-ci clean` removes only the configured work directory. It never
deletes the Ardour checkout. Run `doctor` first when a tool is missing or the
host architecture is unsupported. For a failed dependency build, retain
`.work/downloads/` to avoid downloading source archives again, then rerun
`deps build` after addressing the failure.

Use `make test` to run the mocked CLI test suite.

## License

This project is licensed under the GNU General Public License, version 2 or
later (`GPL-2.0-or-later`). The complete license text is available in
[COPYING](COPYING).

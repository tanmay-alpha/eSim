# eSim 2.5 on Ubuntu 25.04

Tanmay Mangal | FOSSEE Winter Internship 2026 | Screening Task 4: eSim Upgradation

**Result:** The repaired Ubuntu 25.04 installer dispatches the official 2.5 payload, exposes distro Python GUI dependencies to eSim, and installs KiCad 8 from signed Plucky packages without a PPA. The release's separate NGHDL dispatcher does not support 25.04. This is a verified partial installation, not a working-GUI claim.

## Objective and source identity

Determine what prevents the eSim 2.5 Linux installer from progressing on Ubuntu 25.04, fix a reproducible failure, and separate installer defects from environment limitations. The [official download page](https://esim.fossee.in/downloads) lists 22.04, 23.04 and 24.04 for the 2.5 ZIP; 25.04 is the screening target, not a documented 2.5 platform.

Release input: [eSim-2.5.zip](https://static.fossee.in/esim/installation-files/eSim-2.5.zip), published SHA-256 `b9860ae26f026930bae589520761f4a57b85d593a2e2cd1ac83d5e5db2f281ed`. The v2.5 Git tag points to `b6545bf613347844548a8da098d311eacd305458`. The ZIP, not the tag or current master, is the packaged installation source.

Patch baseline: [FOSSEE/eSim installers](https://github.com/FOSSEE/eSim/tree/a77d6b904c7bab275d819cf4d8cbb594802fe16d), revision `a77d6b904c7bab275d819cf4d8cbb594802fe16d`. The packaging checkout is not the application payload. Its launcher and the released launcher must be tested separately.

## Test environment

Docker Desktop on Windows, Linux/amd64 Ubuntu 25.04 (Plucky Puffin) containers, `ubuntu:25.04` pull digest `sha256:27771fb7b40a58237c98e8d3e6b9ecdd9289cec69a857fccfb85ff36294dac20`; GNU Bash 5.2.37(1). No host APT settings changed. No display server used.

Mirror control: the image's original archive/security endpoints returned package indexes (`apt-get -o APT::Update::Error-Mode=any update`, exit 0). In the same experiment changing the hosts to old-releases.ubuntu.com returned HTTP 404, exit 100. Do not hard-code a mirror migration into eSim: use the endpoint that actually publishes signed Plucky indexes in the test environment.

## Packaging defect: the entry point cannot execute

Before: `bash -n Ubuntu/install-eSim.sh` and real execution with `--install` both failed with exit 2: `line 70: syntax error near unexpected token '}'`. This occurs before APT, LLVM or Python runs. An unclosed file-existence check surrounds an unrelated fragment of the old monolithic installer. Closing the conditional alone would leave configuration writes targeting undefined variables after the child returns.

Change: restore the launcher to dispatch only. Delete the spliced configuration and installation routines, which belong in the version-specific backends; use `exec bash` to preserve the selected backend's exit status. Read the release and point version from `/etc/os-release` without requiring `lsb_release` in the wrapper. Preserve the existing 22.04.4 exception and the 23.04, 24.04 and 25.04 mappings.

After: syntax check exit 0. The same `--install` invocation with closed stdin reached the actual 25.04 proxy prompt and returned the backend's exit 1 on EOF. Declining the real uninstall prompt returned 0 without removing anything. Both cases are covered by `Ubuntu/task4/check-dispatch.sh`; it passed. See `dispatcher.log`. The exit 1 is evidence of delegation, not installation success.

## Reproduce the dispatcher result

Run in the packaging checkout with Docker; the mount is read-only. The baseline and fixed scripts below differ only by the implementation under test. For the baseline the failure occurs before backend lookup.

```bash
git show a77d6b904c7bab275d819cf4d8cbb594802fe16d:Ubuntu/install-eSim.sh | docker run --rm -i ubuntu:25.04 bash -s -- --install
docker run --rm -v "$PWD/Ubuntu:/src:ro" ubuntu:25.04 bash -n /src/install-eSim.sh
docker run --rm -v "$PWD/Ubuntu:/src:ro" ubuntu:25.04 bash /src/task4/check-dispatch.sh
```

To inspect the full code diff against the specified upstream input:

```bash
git diff a77d6b904c7bab275d819cf4d8cbb594802fe16d HEAD -- Ubuntu/install-eSim.sh Ubuntu/install-eSim-scripts
```

## Release baseline and reproduction with the patch

The downloaded ZIP was 100,868,880 bytes; its measured SHA-256 matched the published value. Its VERSION file contains 2.5. On a separate Plucky container, the unmodified release entry point exited 1 with `Unsupported Ubuntu version: 25.04 ()`. This is not the branch's Bash parse failure: the shipped dispatcher has no 25.04 route. To apply the packaging change, copy the launcher and the Plucky backend into the extracted release; do not replace the application or run the backend from the packaging checkout as if it were the release.

```bash
# repo is the absolute path to this checkout. Run inside a disposable guest.
unzip eSim-2.5.zip
cd eSim-2.5
cp "$repo/Ubuntu/install-eSim.sh" .
cp "$repo/Ubuntu/install-eSim-scripts/install-eSim-25.04.sh" install-eSim-scripts/
chmod +x install-eSim.sh
./install-eSim.sh --install
```

## Dependency defect: APT installs modules outside the launcher's Python

The Plucky backend creates an isolated virtualenv, installs psutil, PyQt5 and Matplotlib with APT, then attempts a second installation of Matplotlib and PyQt5 with pip. The launcher activates that virtualenv. On a clean image the isolated interpreter could not import either psutil or Matplotlib immediately after successful APT installation. The duplicate pip steps do not explicitly install psutil. This experiment tests package visibility, not whether a later transitive dependency happens to install another copy.

The fix creates the eSim environment with `--system-site-packages` and removes the duplicate pip requests for the two distro-provided GUI packages. APT remains responsible for their compiled bindings; pip-only tools still install into the environment. Tradeoff: the environment now sees other distro Python packages too. This change applies only to the 25.04 script. It also uses `apt-get install -y` for virtualenv so dependency setup does not require a second interactive confirmation.

From the checkout, start a disposable 25.04 shell and run the same probe before and after. No GUI window or display is needed.

```bash
docker run --rm -it -v "$PWD/Ubuntu/task4:/checks:ro" ubuntu:25.04 bash
apt-get update
apt-get install -y --no-install-recommends python3-virtualenv python3-psutil python3-pyqt5 python3-matplotlib
virtualenv /tmp/esim-env
/tmp/esim-env/bin/python /checks/check-runtime.py
virtualenv --system-site-packages /tmp/esim-env
/tmp/esim-env/bin/python /checks/check-runtime.py
```

Baseline probe exit 1; repaired probe exit 0. Python 3.13.3 loaded Qt 5.15.15, Matplotlib 3.8.3 and psutil 5.9.8 from `/usr/lib/python3/dist-packages`. It rendered a line with Agg, exercised QtGui and read process information. Exact Debian package versions, paths and traceback are in `python-runtime.log`. This proves the dependency step, not a successful Application.py launch.

## NGHDL and LLVM

An independent invocation of `bash install-nghdl.sh --install` inside the unmodified release's bundled nghdl.zip exited 1 with `Unsupported Ubuntu version: 25.04 ()`. The archive contains backend scripts for 22.04, 23.04 and 24.04 only. This blocks that component before an LLVM build. No LLVM compile failure was observed or fixed. See `nghdl.log`.

## KiCad package selection: why the version pin matters

Initial PPA control (`a31aab34ae`): with the signed KiCad 8 PPA enabled, the existing installer pin selected `8.0.8+dfsg-1`. A real APT installation fetched 206 MB, installed 202 packages and exited 0; `kicad-cli version` returned `8.0.8`. Removing only the pin selected PPA version `8.0.9-0~ubuntu25.04.1`, which requires unavailable `libgit2-1.8`; APT exited 100. This control supports keeping the version pin; it does not establish that adding the PPA is necessary. Exact sources, commands and installed versions: `kicad-results.log`; reproducer: `kicad-check.sh`.

## Application boundary

In the dependency-only container, importing the release's actual `src/frontEnd/Application.py` with the repaired interpreter got past PyQt5 and stopped in `src/maker/Maker.py` at `import hdlparse.verilog_parser` (exit 1; `application-import.log`). HDL tools and the user configuration were not installed in that container. This probe distinguishes a working Qt/plotting stack from a complete application environment. It did not start a GUI.

## Checks and scope

`bash -n` accepted the corrected dispatch and Plucky backend. ShellCheck 0.10.0 (`shellcheck -x`) passed on the corrected dispatcher and `check-dispatch.sh`. The other version-specific installers were not executed. The patch is confined to installer packaging; no eSim application code, upstream PR, earlier internship project or host Linux package was changed.

`release-baseline.txt` identifies both inputs with checksums. `installer.diff` contains the implementation changes; `dispatcher.log`, `environment.log`, `mirrors.log`, `python-runtime.log`, `application-import.log`, `kicad-results.log` and `nghdl.log` record the respective experiments. Regression scripts are intended for disposable guests only, particularly the KiCad check, which installs real system packages.

## Initial complete release-overlay attempt (a31aab34ae)

As user `ubuntu` (UID 1000), in a newly extracted release and a fresh home on the same container (APT packages from the earlier run retained), we applied the two files above and ran `printf 'n\ny\n' | timeout 120 ./install-eSim.sh --install`. The launcher selected 25.04, completed the Python dependency phase including hdlparse 1.0.7, then exited 1 at KiCad PPA setup: `sudo: add-apt-repository: command not found`. This is a missing utility in the minimal container, distinct from KiCad's package solver. The run was not timed out. `release-overlay.txt` is its full output.

From that release's `src/frontEnd` directory the actual installer-created interpreter then ran `import Application; print(Application.Application.__name__)` with `QT_QPA_PLATFORM=offscreen`: output `Application`, exit 0 (`final-application-import.log`). The same interpreter passed `check-runtime.py`. The repaired launcher and Python dependency path work together with the official payload. Full installation, GUI interaction and circuit simulation are not verified.

## Executable mode and patch provenance

`direct-invocation.txt` records a Plucky run using files exported from Git blobs with their tracked modes, rather than permissions inherited from a Windows bind mount. `Ubuntu/install-eSim.sh` had mode 0755; `printf 'n\n' | ./Ubuntu/install-eSim.sh --uninstall` invoked the backend through the shebang and returned 0 without uninstalling. Both the upstream and fork Git trees track the launcher as 100755. The patch in `installer.diff` is a commit-to-commit `git diff`, not a diff against a Windows worktree.

## Scope of the library-copy result

The release's `library/kicadLibrary.tar.xz` includes a `template/sym-lib-table` with `${KICAD6_SYMBOL_DIR}` references. The Plucky backend copies it to `~/.config/kicad/6.0/`, despite installing KiCad 8. A successful file copy does not establish that KiCad 8 discovers or loads the libraries. The existing copy function also changes ownership of the system symbol directory recursively; these experiments were restricted to disposable containers.

## KiCad setup repair and measured outcome (67c1019667)

The previous revision always attempted `add-apt-repository` in a minimal guest. Installing `software-properties-common` made that command available, but added a third-party repository when signed Plucky `universe` already supplied the exact pinned binary and all four library packages. The revised 25.04 backend installs these packages from the configured APT indexes without adding or modifying sources. `--no-remove` prevents APT from resolving conflicts by removing installed packages. The installer preserves a compatible installed binary, checks its libraries, and returns to its caller; the old code exited the entire installation on a repeat run. An incompatible installed major is refused rather than purged. That refusal was reviewed, not exercised with another major.

In the fresh-install stage test, `apt-get` installed 201 packages with zero removals, and `kicad-cli version` returned `8.0.8`. A second run installed zero packages and returned to the caller. The real release library-copy function returned 0; the bundled NGHDL dispatcher then returned 1, before LLVM compilation. Exact package versions, control experiments and outputs: `kicad-archive.txt`.

Independent regressions (`final-checks.txt`): dispatcher, Python runtime smoke test, pinned KiCad installation and Bash syntax passed. `shellcheck -x` passed for the dispatcher and both Bash check scripts. The Plucky backend still has pre-existing ShellCheck findings (exit 1); the patch introduced no new diagnostic category or count. Earlier Ubuntu backends remain unchanged and untested. No GUI or circuit simulation was run.

## Final integrated run: first remaining stop

Inside a disposable Plucky guest, the unprivileged `ubuntu` user ran `./install-eSim.sh --install` in the verified 2.5 release with the two packaging files overlaid (standard input: `n` then `y`). All APT sources were signed Ubuntu sources. Downloads were prefetched, not installed with dpkg. The baseline and final runs had separate homes and release copies; the final run retained OS dependencies installed by the baseline, but no preinstalled KiCad. A preliminary concurrent attempt hit a dpkg lock and was discarded; the comparison below was run serially.

With the `a31aab34ae` backend the complete invocation reached KiCad and exited 1 at `add-apt-repository`. With `67c1019667` it installed KiCad, copied the symbols, extracted NGHDL and exited 1 at `Unsupported Ubuntu version: 25.04 ()`. `dpkg-query` confirmed `install ok installed`; `kicad-cli version` printed `8.0.8`. The installer-created Python passed `check-runtime.py` and imported `Application` successfully. `final-overlay.txt` contains the exit status, selected output and file evidence. No NGHDL backend was substituted; LLVM, SKY130, desktop launcher creation, GUI operation and circuit simulation were not verified.

# eSim 2.5 on Ubuntu 25.04

Tanmay Mangal | FOSSEE Winter Internship 2026 | Screening Task 4: eSim Upgradation

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

## KiCad: a control that should not be changed

With the signed KiCad 8 PPA enabled, the existing installer pin selected `8.0.8+dfsg-1`. A real APT installation fetched 206 MB, installed 202 packages and exited 0; `kicad-cli version` returned `8.0.8`. Removing only the pin selected PPA version `8.0.9-0~ubuntu25.04.1`, which requires unavailable `libgit2-1.8`; APT exited 100. The shipped pin protects this path. No KiCad fix is claimed. Exact sources, commands and installed versions: `kicad-results.log`; reproducer: `kicad-check.sh`.

## Application boundary

In the dependency-only container, importing the release's actual `src/frontEnd/Application.py` with the repaired interpreter got past PyQt5 and stopped in `src/maker/Maker.py` at `import hdlparse.verilog_parser` (exit 1; `application-import.log`). HDL tools and the user configuration were not installed in that container. This probe distinguishes a working Qt/plotting stack from a complete application environment. It did not start a GUI.

## Checks and scope

`bash -n` accepted the corrected dispatch and Plucky backend. ShellCheck 0.10.0 (`shellcheck -x`) passed on the corrected dispatcher and `check-dispatch.sh`. The other version-specific installers were not executed. The patch is confined to installer packaging; no eSim application code, upstream PR, earlier internship project or host Linux package was changed.

`release-baseline.txt` identifies both inputs with checksums. `installer.diff` contains the implementation changes; `dispatcher.log`, `environment.log`, `mirrors.log`, `python-runtime.log`, `application-import.log`, `kicad-results.log` and `nghdl.log` record the respective experiments. Regression scripts are intended for disposable guests only, particularly the KiCad check, which installs real system packages.

## Final release-overlay run and conclusion

As user `ubuntu` (UID 1000), in a newly extracted release and a fresh home on the same container (APT packages from the earlier run retained), we applied the two files above and ran `printf 'n\ny\n' | timeout 120 ./install-eSim.sh --install`. The launcher selected 25.04, completed the Python dependency phase including hdlparse 1.0.7, then exited 1 at KiCad PPA setup: `sudo: add-apt-repository: command not found`. This is a missing utility in the minimal container, distinct from KiCad's package solver. The run was not timed out. `release-overlay.txt` is its full output.

From that release's `src/frontEnd` directory the actual installer-created interpreter then ran `import Application; print(Application.Application.__name__)` with `QT_QPA_PLATFORM=offscreen`: output `Application`, exit 0 (`final-application-import.log`). The same interpreter passed `check-runtime.py`. The repaired launcher and Python dependency path work together with the official payload. Full installation, GUI interaction and circuit simulation are not verified.

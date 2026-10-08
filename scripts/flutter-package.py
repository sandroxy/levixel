#!/usr/bin/env python3
"""Build and inspect Flutter packages without rebuilding their native inputs."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


PACKAGE_ROOT = "sandrox_levixel"
MAVEN_MODULE = "io/gitee/sandrox/levixel"
FRAMEWORK_ROOT = "Levixel.xcframework"
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024


class PackageError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise PackageError(message)


def run(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def sha256(contents):
    return hashlib.sha256(contents).hexdigest()


def read_archive(path):
    """Read regular files only; validate every member before using its contents."""
    files = {}
    seen = set()
    total = 0
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            parts = name.rstrip("/").split("/")
            require(
                name and not name.startswith("/") and "\\" not in name
                and all(part not in ("", ".", "..") for part in parts)
                and all(ord(char) >= 32 for char in name)
                and ":" not in name and entry.orig_filename == name,
                f"Unsafe ZIP member: {name!r}",
            )
            canonical = "/".join(parts)
            require(canonical not in seen, f"Duplicate ZIP member: {name}")
            seen.add(canonical)
            kind = stat.S_IFMT(entry.external_attr >> 16)
            allowed = (0, stat.S_IFDIR) if entry.is_dir() else (0, stat.S_IFREG)
            require(kind in allowed, f"Non-regular ZIP member: {name}")
            require(not entry.flag_bits & 1, f"Encrypted ZIP member: {name}")
            total += entry.file_size
            require(total <= MAX_ARCHIVE_BYTES, "ZIP exceeds the unpacked size limit")
            if not entry.is_dir():
                files[name] = archive.read(entry)
    require(files, f"Empty archive: {path}")
    for name in files:
        require(
            not any(str(parent) in files for parent in PurePosixPath(name).parents),
            f"ZIP member has a file as its parent: {name}",
        )
    return files


def write_archive(path, files):
    # Stable ordering, timestamps and permissions make repeated packaging of
    # identical inputs byte-identical on the same Python/zlib toolchain.
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, contents in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            mode = 0o755 if name.endswith("/Levixel.framework/Levixel") else 0o644
            entry.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(entry, contents, compress_type=zipfile.ZIP_DEFLATED,
                             compresslevel=9)


def check_files(actual, expected):
    require(actual.keys() == expected.keys(),
            "Package contents differ: "
            f"missing={sorted(expected.keys() - actual.keys())}, "
            f"unexpected={sorted(actual.keys() - expected.keys())}")
    for name, contents in expected.items():
        require(actual[name] == contents, f"Package bytes differ: {name}")


def check_sidecar(path, contents, name):
    expected = f"{sha256(contents)}  {name}\n".encode()
    require(path.read_bytes() == expected, f"Checksum sidecar differs: {path}")


def source_files(root):
    adapter = root / "adapters/flutter"
    files = {}
    for name in ("pubspec.yaml", "README.md", "android/build.gradle",
                 "ios/sandrox_levixel.podspec", "ios/sandrox_levixel/Package.swift"):
        path = adapter / name
        require(not path.is_symlink(), f"Source must not be a symbolic link: {path}")
        files[name] = path.read_bytes()
    for name in ("lib", "android/src/main", "ios/sandrox_levixel/Sources"):
        directory = adapter / name
        require(directory.is_dir(), f"Missing source directory: {directory}")
        for path in [directory, *sorted(directory.rglob("*"))]:
            require(not path.is_symlink(), f"Source must not be a symbolic link: {path}")
            if path.is_file():
                require(path.suffix in (".dart", ".java", ".xml", ".swift"),
                        f"Unexpected adapter source: {path}")
                files[path.relative_to(adapter).as_posix()] = path.read_bytes()
    for name in ("LICENSE", "CHANGELOG.md", "PROVENANCE.md", "THIRD_PARTY_NOTICES.md"):
        path = root / name
        require(not path.is_symlink(), f"Source must not be a symbolic link: {path}")
        files[name] = path.read_bytes()
    return files


def maven_files(files, aar, version):
    version_root = f"{MAVEN_MODULE}/{version}/"
    publication_pattern = re.escape(version_root + f"levixel-{version}") + (
        r"(?:\.aar|\.pom|\.module|-sources\.jar|-javadoc\.jar)"
        r"(?:\.asc)?(?:\.(?:md5|sha1|sha256|sha512))?"
    )
    for name in files:
        require(re.fullmatch(publication_pattern, name) or
                re.fullmatch(re.escape(MAVEN_MODULE) + r"/maven-metadata\.xml(?:\.(?:md5|sha1|sha256|sha512))?", name),
                f"Unexpected Maven module or version: {name}")
    stem = version_root + f"levixel-{version}"
    for suffix in (".aar", ".pom", ".module", "-sources.jar", "-javadoc.jar"):
        require(stem + suffix in files, f"Maven publication is missing {stem + suffix}")
    require(files[stem + ".aar"] == aar, "Maven AAR differs from the native release AAR")
    pom = ET.fromstring(files[stem + ".pom"])
    namespace = "{http://maven.apache.org/POM/4.0.0}"
    for field, expected in (("groupId", "io.gitee.sandrox"),
                            ("artifactId", "levixel"), ("version", version)):
        require(pom.findtext(namespace + field) == expected,
                f"Unexpected Maven POM {field}")
    return {f"android/maven/{name}": data for name, data in files.items()}


def framework_files(files, version, provenance, legal):
    # ditto may include AppleDouble metadata alongside the framework. These
    # resource forks are not framework payload and are not redistributed.
    for name in files:
        require(name.startswith(FRAMEWORK_ROOT + "/") or
                name.startswith("__MACOSX/"), f"Unexpected XCFramework entry: {name}")
    payload = {name: data for name, data in files.items()
               if name.startswith(FRAMEWORK_ROOT + "/")}
    info = plistlib.loads(payload[f"{FRAMEWORK_ROOT}/Info.plist"])
    libraries = info.get("AvailableLibraries", [])
    require(len(libraries) == 2, "XCFramework must contain device and simulator slices")
    variants = set()
    for library in libraries:
        identifier = library["LibraryIdentifier"]
        require(re.fullmatch(r"[A-Za-z0-9_-]+", identifier), "Invalid XCFramework slice name")
        require(library["LibraryPath"] == "Levixel.framework", "Unexpected framework name")
        require(library["SupportedPlatform"] == "ios", "Unexpected framework platform")
        variant = library.get("SupportedPlatformVariant", "device")
        require(variant in ("device", "simulator") and variant not in variants,
                "XCFramework must contain distinct device and simulator slices")
        variants.add(variant)
        require("arm64" in library["SupportedArchitectures"], "Framework is missing arm64")
        prefix = f"{FRAMEWORK_ROOT}/{identifier}/Levixel.framework/"
        require(payload.get(prefix + "Levixel"), "Framework binary is missing")
        framework_info = plistlib.loads(payload[prefix + "Info.plist"])
        require(framework_info.get("CFBundleShortVersionString") == version,
                "Framework version differs from the Flutter package")
        require(framework_info.get("LevixelSourceCommit") == provenance["sourceCommit"]
                and framework_info.get("LevixelSourceDigest") == provenance["sourceDigest"],
                "Framework provenance differs from the native manifest")
        for name, data in legal.items():
            require(payload.get(prefix + name) == data, f"Framework legal file differs: {name}")
    return {f"ios/sandrox_levixel/Frameworks/{name}": data for name, data in payload.items()}


def source_version(root):
    metadata = json.loads(run("ruby", "-ryaml", "-rjson", "-e", """
      root = ARGV.fetch(0)
      puts JSON.generate({
        "version" => YAML.load_file(File.join(root, "plugin.yaml")).fetch("version"),
        "pubspec" => YAML.load_file(File.join(root, "adapters/flutter/pubspec.yaml"))
      })
    """, str(root)))
    version = metadata["version"]
    require(isinstance(version, str) and re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version),
            "Invalid plugin version")
    pubspec = metadata["pubspec"]
    require(pubspec["name"] == PACKAGE_ROOT and pubspec["version"] == version
            and pubspec["publish_to"] == "none"
            and pubspec["repository"] == "https://github.com/sandroxy/levixel",
            "Flutter package identity differs from the release source")
    require(pubspec["flutter"]["plugin"]["platforms"] == {
        "android": {"package": "com.sandrox.levixel.flutter", "pluginClass": "LevixelPlugin"},
        "ios": {"pluginClass": "LevixelPlugin"},
    }, "Unexpected Flutter plugin platforms")
    podspec = (root / "adapters/flutter/ios/sandrox_levixel.podspec").read_text()
    require(re.search(r"s\.version\s*=\s*'" + re.escape(version) + "'", podspec),
            "Flutter podspec version differs from the release source")
    return version


def release_inputs(root, allow_dirty):
    version = source_version(root)
    commit = run("git", "-C", str(root), "rev-parse", "HEAD")
    dirty = bool(run("git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"))
    require(allow_dirty or not dirty, "Formal Flutter packages require a clean worktree")
    manifest_path = root / f"dist/native-release/levixel-native-{version}.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    run("ruby", "-I", str(root / "scripts"), "-rjson", "-r", "native-release-manifest", "-e", """
      NativeReleaseManifest.validate!(JSON.parse(File.read(ARGV.fetch(0))),
        plugin: "levixel", version: ARGV.fetch(1))
    """, str(manifest_path), version)
    require(manifest["commit"] == commit, "Native manifest commit differs from Flutter source")
    require(allow_dirty or not manifest["dirty"], "Dirty native inputs require --allow-dirty")
    records = {entry["file"]: entry for entry in manifest["artifacts"]}
    inputs = {}
    for platform, name in (("android", f"levixel-{version}.aar"),
                           ("android", f"levixel-{version}-maven.zip"),
                           ("ios", f"levixel-{version}.xcframework.zip")):
        path = root / f"dist/native-{platform}" / name
        contents = path.read_bytes()
        record = records[name]
        require(record["bytes"] == len(contents) and record["sha256"] == sha256(contents),
                f"Native input differs from the manifest: {name}")
        check_sidecar(Path(str(path) + ".sha256"), contents, name)
        inputs[name] = (path, contents)
    files = source_files(root)
    files["native-version.properties"] = f"version={version}\n".encode()
    files["native-release.json"] = manifest_bytes
    files.update(maven_files(read_archive(inputs[f"levixel-{version}-maven.zip"][0]),
                             inputs[f"levixel-{version}.aar"][1], version))
    files.update(framework_files(read_archive(inputs[f"levixel-{version}.xcframework.zip"][0]),
                                 version, manifest["buildProvenance"]["iosXcframework"], {
                                     "LICENSE": files["LICENSE"],
                                     "THIRD_PARTY_NOTICES.md": files["THIRD_PARTY_NOTICES.md"],
                                     "PrivacyInfo.xcprivacy": (root / "native/ios/Levixel/PrivacyInfo.xcprivacy").read_bytes(),
                                 }))
    # Reuse the core's artifact and source-provenance gates. No builds are run.
    subprocess.run(["bash", str(root / "scripts/verify-native-android.sh")], check=True)
    ios_archive = str(inputs[f"levixel-{version}.xcframework.zip"][0])
    subprocess.run(["bash", str(root / "scripts/verify-native-manifest-ios-provenance.sh"),
                    str(manifest_path), ios_archive, version], check=True)
    subprocess.run(["bash", str(root / "scripts/verify-ios-core-adapter-api.sh"), ios_archive], check=True)
    return version, {f"{PACKAGE_ROOT}/{name}": data for name, data in files.items()}


def verify(path, files, version):
    contents = path.read_bytes()
    check_sidecar(Path(str(path) + ".sha256"), contents, f"levixel-flutter-{version}.zip")
    check_files(read_archive(path), files)


def install(candidate, destination, replace):
    pairs = [(candidate, destination),
             (Path(str(candidate) + ".sha256"), Path(str(destination) + ".sha256"))]
    exists = [target.exists() for _, target in pairs]
    require(replace or all(exists) or not any(exists),
            "Incomplete existing candidate; review before using --replace")
    for source, target in pairs:
        require(not target.is_symlink(), f"Output must not be a symbolic link: {target}")
        require(replace or not target.exists() or source.read_bytes() == target.read_bytes(),
                f"Different same-version bytes already exist: {target}. Review before using --replace.")
    for source, target in pairs:
        if not target.exists() or source.read_bytes() != target.read_bytes():
            os.replace(source, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "verify", "check-source"))
    parser.add_argument("artifact", nargs="?", type=Path)
    parser.add_argument("--allow-dirty", action="store_true", help="Allow a local rehearsal")
    parser.add_argument("--replace", action="store_true", help="Replace a rejected local candidate")
    args = parser.parse_args()
    if (args.command != "build" and args.replace) or (args.command != "verify" and args.artifact):
        parser.error("--replace is build-only; an artifact path is verify-only")
    root = Path(__file__).resolve().parent.parent
    if args.command == "check-source":
        version = source_version(root)
        source_files(root)
        print(f"Verified Flutter source package identity: {version}")
        return
    if args.command == "build":
        subprocess.run(["bash", str(root / "scripts/verify-release-readiness.sh")], check=True)
    version, files = release_inputs(root, args.allow_dirty)
    artifact = root / f"dist/flutter/levixel-flutter-{version}.zip"
    if args.command == "verify":
        artifact = args.artifact or artifact
        verify(artifact, files, version)
    else:
        for path in (root / "dist", artifact.parent):
            require(not path.is_symlink(), f"Output must not be a symbolic link: {path}")
        artifact.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".flutter-", dir=artifact.parent) as work:
            candidate = Path(work) / artifact.name
            write_archive(candidate, files)
            Path(str(candidate) + ".sha256").write_text(f"{sha256(candidate.read_bytes())}  {artifact.name}\n")
            # Re-read inputs to reject changes during packaging before installing
            # the candidate. Native builds remain outside this command.
            current_version, current_files = release_inputs(root, args.allow_dirty)
            require(current_version == version, "Source version changed during packaging")
            verify(candidate, current_files, version)
            install(candidate, artifact, args.replace)
    if args.allow_dirty:
        print("Local rehearsal only; clean-commit verification is required before publication.")
    print(f"Verified {artifact}")
    print(f"  sha256: {sha256(artifact.read_bytes())}")


if __name__ == "__main__":
    try:
        main()
    except (PackageError, OSError, KeyError, ValueError, ET.ParseError,
            zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Flutter package verification failed: {error}") from error

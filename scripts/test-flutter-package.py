#!/usr/bin/env python3
"""Archive and native-input boundary tests; these do not accept a release."""

import importlib.util
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
import warnings
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "flutter_package", Path(__file__).with_name("flutter-package.py"))
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)


class FlutterPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / "package.zip"

    def archive_with(self, entries):
        with zipfile.ZipFile(self.archive, "w") as archive:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                for name, contents in entries:
                    archive.writestr(name, contents)

    def test_repeated_packaging_retains_exact_bytes_and_framework_permissions(self):
        files = {"sandrox_levixel/lib/levixel.dart": b"public API",
                 "sandrox_levixel/ios/Levixel.framework/Levixel": b"native binary"}
        package.write_archive(self.archive, files)
        first = self.archive.read_bytes()
        package.write_archive(self.archive, dict(reversed(list(files.items()))))
        self.assertEqual(first, self.archive.read_bytes())
        package.check_files(package.read_archive(self.archive), files)
        with zipfile.ZipFile(self.archive) as archive:
            mode = archive.getinfo("sandrox_levixel/ios/Levixel.framework/Levixel").external_attr >> 16
            self.assertEqual(stat.S_IMODE(mode), 0o755)

    def test_unsafe_paths_are_rejected(self):
        for name in ("../outside", "/absolute", "a/../outside", "a//b",
                     "a/./b", "C:/outside", "a\\outside", "a/\nfile"):
            with self.subTest(name=name):
                self.archive_with([(name, b"payload")])
                with self.assertRaises(package.PackageError):
                    package.read_archive(self.archive)

    def test_duplicate_names_and_file_directory_collisions_are_rejected(self):
        for entries in ([("a", b"one"), ("a", b"two")],
                        [("a", b"file"), ("a/b", b"child")],
                        [("a/", b""), ("a", b"file")]):
            with self.subTest(entries=entries):
                self.archive_with(entries)
                with self.assertRaises(package.PackageError):
                    package.read_archive(self.archive)

    def test_symbolic_links_are_rejected(self):
        entry = zipfile.ZipInfo("link")
        entry.create_system = 3
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.archive_with([(entry, b"../outside")])
        with self.assertRaisesRegex(package.PackageError, "Non-regular"):
            package.read_archive(self.archive)

    def test_missing_extra_and_changed_package_files_are_rejected(self):
        expected = {"package/lib/api.dart": b"reviewed"}
        for actual in ({}, {**expected, "package/.env": b"secret"},
                       {"package/lib/api.dart": b"changed"}):
            with self.subTest(actual=actual):
                with self.assertRaises(package.PackageError):
                    package.check_files(actual, expected)

    def test_checksum_cannot_relabel_or_replace_an_archive(self):
        sidecar = self.root / "package.zip.sha256"
        sidecar.write_text(f"{package.sha256(b'original')}  package.zip\n")
        package.check_sidecar(sidecar, b"original", "package.zip")
        for contents, name in ((b"changed", "package.zip"), (b"original", "other.zip")):
            with self.assertRaises(package.PackageError):
                package.check_sidecar(sidecar, contents, name)

    def candidate(self, name, contents):
        path = self.root / name
        path.write_bytes(contents)
        Path(str(path) + ".sha256").write_text(package.sha256(contents))
        return path

    def test_different_candidate_is_preserved_without_explicit_replace(self):
        destination = self.candidate("installed.zip", b"accepted")
        candidate = self.candidate("new.zip", b"different")
        with self.assertRaisesRegex(package.PackageError, "Different same-version"):
            package.install(candidate, destination, False)
        self.assertEqual(destination.read_bytes(), b"accepted")
        self.assertEqual(candidate.read_bytes(), b"different")
        package.install(candidate, destination, True)
        self.assertEqual(destination.read_bytes(), b"different")

    def test_sidecar_mismatch_does_not_partially_install(self):
        destination = self.candidate("installed.zip", b"same")
        candidate = self.candidate("new.zip", b"same")
        sidecar = Path(str(destination) + ".sha256")
        sidecar.write_bytes(b"unexpected")
        with self.assertRaises(package.PackageError):
            package.install(candidate, destination, False)
        self.assertEqual(destination.read_bytes(), b"same")
        self.assertEqual(sidecar.read_bytes(), b"unexpected")
        sidecar.unlink()
        with self.assertRaisesRegex(package.PackageError, "Incomplete"):
            package.install(candidate, destination, False)

    def maven(self):
        stem = "io/gitee/sandrox/levixel/1.5.0/levixel-1.5.0"
        files = {stem + suffix: b"fixture" for suffix in
                 (".aar", ".module", "-sources.jar", "-javadoc.jar")}
        files[stem + ".pom"] = b'''<project xmlns="http://maven.apache.org/POM/4.0.0">
          <groupId>io.gitee.sandrox</groupId><artifactId>levixel</artifactId>
          <version>1.5.0</version></project>'''
        return files, stem

    def test_maven_retains_metadata_and_requires_the_exact_native_aar(self):
        files, stem = self.maven()
        result = package.maven_files(files, b"fixture", "1.5.0")
        self.assertEqual(result["android/maven/" + stem + ".pom"], files[stem + ".pom"])
        with self.assertRaisesRegex(package.PackageError, "Maven AAR differs"):
            package.maven_files(files, b"different", "1.5.0")
        del files[stem + ".module"]
        with self.assertRaisesRegex(package.PackageError, "missing"):
            package.maven_files(files, b"fixture", "1.5.0")

    def test_other_maven_versions_and_coordinates_are_rejected(self):
        files, stem = self.maven()
        files[stem + ".pom"] = files[stem + ".pom"].replace(b"<version>1.5.0", b"<version>1.4.1")
        with self.assertRaisesRegex(package.PackageError, "POM version"):
            package.maven_files(files, b"fixture", "1.5.0")
        files, _ = self.maven()
        files["io/gitee/sandrox/levixel/1.4.1/levixel-1.4.1.aar"] = b"older"
        with self.assertRaisesRegex(package.PackageError, "Unexpected Maven"):
            package.maven_files(files, b"fixture", "1.5.0")

    def framework(self):
        files = {}
        libraries = []
        provenance = {"sourceCommit": "a" * 40, "sourceDigest": "b" * 64}
        legal = {"LICENSE": b"license", "THIRD_PARTY_NOTICES.md": b"notices",
                 "PrivacyInfo.xcprivacy": b"privacy"}
        for identifier, variant in (("ios-arm64", None), ("ios-arm64-simulator", "simulator")):
            library = {"LibraryIdentifier": identifier, "LibraryPath": "Levixel.framework",
                       "SupportedPlatform": "ios", "SupportedArchitectures": ["arm64"]}
            if variant:
                library["SupportedPlatformVariant"] = variant
            libraries.append(library)
            prefix = f"Levixel.xcframework/{identifier}/Levixel.framework/"
            files[prefix + "Levixel"] = b"fixture binary"
            files[prefix + "Info.plist"] = plistlib.dumps({
                "CFBundleShortVersionString": "1.5.0", "LevixelSourceCommit": provenance["sourceCommit"],
                "LevixelSourceDigest": provenance["sourceDigest"]})
            files.update({prefix + name: data for name, data in legal.items()})
        files["Levixel.xcframework/Info.plist"] = plistlib.dumps({"AvailableLibraries": libraries})
        return files, provenance, legal

    def test_framework_requires_both_slices_and_matching_provenance(self):
        files, provenance, legal = self.framework()
        package.framework_files(files, "1.5.0", provenance, legal)
        with self.assertRaisesRegex(package.PackageError, "provenance"):
            package.framework_files(files, "1.5.0", {**provenance, "sourceCommit": "c" * 40}, legal)
        info = plistlib.loads(files["Levixel.xcframework/Info.plist"])
        info["AvailableLibraries"].pop()
        files["Levixel.xcframework/Info.plist"] = plistlib.dumps(info)
        with self.assertRaisesRegex(package.PackageError, "device and simulator"):
            package.framework_files(files, "1.5.0", provenance, legal)

    def test_framework_version_and_legal_files_cannot_drift(self):
        files, provenance, legal = self.framework()
        with self.assertRaisesRegex(package.PackageError, "version"):
            package.framework_files(files, "1.4.1", provenance, legal)
        with self.assertRaisesRegex(package.PackageError, "legal file"):
            package.framework_files(files, "1.5.0", provenance, {**legal, "LICENSE": b"different"})


if __name__ == "__main__":
    unittest.main()

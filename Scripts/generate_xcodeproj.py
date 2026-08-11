#!/usr/bin/env python3
"""Generate Tensora.xcodeproj from the files on disk.

Run this after adding, renaming or deleting a source file so the project stays
in sync:

    python3 Scripts/generate_xcodeproj.py

Object identifiers are derived from each file's path, so regenerating produces
a stable, diff-friendly project file.
"""

from __future__ import annotations

import hashlib
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Tensora"
PROJECT_NAME = "Tensora"
PROJECT_PATH = ROOT / f"{PROJECT_NAME}.xcodeproj"

BUNDLE_ID = "app.tensora.Tensora"
DEPLOYMENT_TARGET = "17.0"
SWIFT_VERSION = "5.0"
MARKETING_VERSION = "1.0"
BUILD_VERSION = "1"

# Files copied into the bundle rather than compiled.
RESOURCE_SUFFIXES = {".xcassets", ".strings", ".stringsdict", ".json", ".plist"}
SKIP_NAMES = {".DS_Store"}


def uid(*parts: str) -> str:
    """Deterministic 24-character hex identifier."""
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


class Node:
    """A directory in the project navigator."""

    def __init__(self, name: str, path: str):
        self.name = name
        self.path = path
        self.children: list["Node"] = []
        self.files: list[Path] = []

    @property
    def uid(self) -> str:
        return uid("group", self.path)


def collect(directory: Path, relative: str = "") -> Node:
    node = Node(directory.name, relative or directory.name)
    for entry in sorted(directory.iterdir(), key=lambda item: item.name):
        if entry.name in SKIP_NAMES:
            continue
        if entry.is_dir() and entry.suffix not in RESOURCE_SUFFIXES:
            node.children.append(collect(entry, f"{node.path}/{entry.name}"))
        else:
            node.files.append(entry)
    return node


def walk(node: Node):
    yield node
    for child in node.children:
        yield from walk(child)


def is_resource(path: Path) -> bool:
    return path.suffix in RESOURCE_SUFFIXES


def file_type(path: Path) -> str:
    return {
        ".swift": "sourcecode.swift",
        ".xcassets": "folder.assetcatalog",
        ".plist": "text.plist.xml",
        ".entitlements": "text.plist.entitlements",
        ".json": "text.json",
        ".strings": "text.plist.strings",
        ".md": "net.daringfireball.markdown",
    }.get(path.suffix, "text")


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def build_settings_common() -> dict[str, str]:
    return {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
    }


def build_settings_debug() -> dict[str, str]:
    settings = build_settings_common()
    settings.update(
        {
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        }
    )
    return settings


def build_settings_release() -> dict[str, str]:
    settings = build_settings_common()
    settings.update(
        {
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "VALIDATE_PRODUCT": "YES",
        }
    )
    return settings


def target_settings() -> dict[str, str]:
    return {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": BUILD_VERSION,
        "DEVELOPMENT_ASSET_PATHS": '""',
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_NSFaceIDUsageDescription": (
            '"Tensora uses Face ID to unlock your account."'
        ),
        "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": (
            '"Tensora uses your location to find racquet stringers near you."'
        ),
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleDefault",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": (
            '"UIInterfaceOrientationPortrait '
            "UIInterfaceOrientationPortraitUpsideDown "
            "UIInterfaceOrientationLandscapeLeft "
            'UIInterfaceOrientationLandscapeRight"'
        ),
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": (
            '"UIInterfaceOrientationPortrait"'
        ),
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": SWIFT_VERSION,
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }


def render_settings(settings: dict[str, str], indent: str) -> str:
    lines = []
    for key in sorted(settings):
        lines.append(f"{indent}{key} = {settings[key]};")
    return "\n".join(lines)


def generate() -> str:
    root = collect(SOURCE_DIR, PROJECT_NAME)
    all_files: list[Path] = []
    for node in walk(root):
        all_files.extend(node.files)

    sources = [f for f in all_files if f.suffix == ".swift"]
    resources = [f for f in all_files if is_resource(f)]

    project_uid = uid("project", PROJECT_NAME)
    target_uid = uid("target", PROJECT_NAME)
    product_uid = uid("product", PROJECT_NAME)
    main_group_uid = uid("group", "<root>")
    products_group_uid = uid("group", "Products")
    sources_phase_uid = uid("phase", "sources")
    frameworks_phase_uid = uid("phase", "frameworks")
    resources_phase_uid = uid("phase", "resources")
    project_config_list_uid = uid("configlist", "project")
    target_config_list_uid = uid("configlist", "target")
    project_debug_uid = uid("config", "project-debug")
    project_release_uid = uid("config", "project-release")
    target_debug_uid = uid("config", "target-debug")
    target_release_uid = uid("config", "target-release")

    out: list[str] = []
    add = out.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # PBXBuildFile
    add("")
    add("/* Begin PBXBuildFile section */")
    for path in sources + resources:
        phase = "Sources" if path.suffix == ".swift" else "Resources"
        add(
            f"\t\t{uid('buildfile', rel(path))} /* {path.name} in {phase} */ = "
            f"{{isa = PBXBuildFile; fileRef = {uid('fileref', rel(path))} /* {path.name} */; }};"
        )
    add("/* End PBXBuildFile section */")

    # PBXFileReference
    add("")
    add("/* Begin PBXFileReference section */")
    add(
        f"\t\t{product_uid} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    for path in all_files:
        add(
            f"\t\t{uid('fileref', rel(path))} /* {path.name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(path)}; path = {path.name}; sourceTree = \"<group>\"; }};"
        )
    add("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{frameworks_phase_uid} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    add("")
    add("/* Begin PBXGroup section */")
    add(f"\t\t{main_group_uid} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{root.uid} /* {PROJECT_NAME} */,")
    add(f"\t\t\t\t{products_group_uid} /* Products */,")
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{products_group_uid} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{product_uid} /* {PROJECT_NAME}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    for node in walk(root):
        add(f"\t\t{node.uid} /* {node.name} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for child in node.children:
            add(f"\t\t\t\t{child.uid} /* {child.name} */,")
        for path in node.files:
            add(f"\t\t\t\t{uid('fileref', rel(path))} /* {path.name} */,")
        add("\t\t\t);")
        add(f"\t\t\tpath = {node.name};")
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")
    add("/* End PBXGroup section */")

    # PBXNativeTarget
    add("")
    add("/* Begin PBXNativeTarget section */")
    add(f"\t\t{target_uid} /* {PROJECT_NAME} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(
        f"\t\t\tbuildConfigurationList = {target_config_list_uid} "
        f"/* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;"
    )
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{sources_phase_uid} /* Sources */,")
    add(f"\t\t\t\t{frameworks_phase_uid} /* Frameworks */,")
    add(f"\t\t\t\t{resources_phase_uid} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add(f"\t\t\tname = {PROJECT_NAME};")
    add(f"\t\t\tproductName = {PROJECT_NAME};")
    add(f"\t\t\tproductReference = {product_uid} /* {PROJECT_NAME}.app */;")
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # PBXProject
    add("")
    add("/* Begin PBXProject section */")
    add(f"\t\t{project_uid} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1520;")
    add("\t\t\t\tLastUpgradeCheck = 1520;")
    add("\t\t\t\tTargetAttributes = {")
    add(f"\t\t\t\t\t{target_uid} = {{")
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(
        f"\t\t\tbuildConfigurationList = {project_config_list_uid} "
        f"/* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;"
    )
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {main_group_uid};")
    add(f"\t\t\tproductRefGroup = {products_group_uid} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{target_uid} /* {PROJECT_NAME} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{resources_phase_uid} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for path in resources:
        add(f"\t\t\t\t{uid('buildfile', rel(path))} /* {path.name} in Resources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{sources_phase_uid} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for path in sources:
        add(f"\t\t\t\t{uid('buildfile', rel(path))} /* {path.name} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # XCBuildConfiguration
    add("")
    add("/* Begin XCBuildConfiguration section */")
    for config_uid, name, settings in [
        (project_debug_uid, "Debug", build_settings_debug()),
        (project_release_uid, "Release", build_settings_release()),
        (target_debug_uid, "Debug", target_settings()),
        (target_release_uid, "Release", target_settings()),
    ]:
        add(f"\t\t{config_uid} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        add(render_settings(settings, "\t\t\t\t"))
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")
    add("/* End XCBuildConfiguration section */")

    # XCConfigurationList
    add("")
    add("/* Begin XCConfigurationList section */")
    for list_uid, label, debug_uid, release_uid in [
        (project_config_list_uid, f'PBXProject "{PROJECT_NAME}"', project_debug_uid, project_release_uid),
        (target_config_list_uid, f'PBXNativeTarget "{PROJECT_NAME}"', target_debug_uid, target_release_uid),
    ]:
        add(f"\t\t{list_uid} /* Build configuration list for {label} */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{debug_uid} /* Debug */,")
        add(f"\t\t\t\t{release_uid} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {project_uid} /* Project object */;")
    add("}")
    return "\n".join(out) + "\n"


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1520"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_uid}"
               BuildableName = "{name}.app"
               BlueprintName = "{name}"
               ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uid}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uid}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

WORKSPACE_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main() -> None:
    if PROJECT_PATH.exists():
        shutil.rmtree(PROJECT_PATH)

    (PROJECT_PATH / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (PROJECT_PATH / "project.xcworkspace" / "xcshareddata").mkdir(parents=True, exist_ok=True)

    (PROJECT_PATH / "project.pbxproj").write_text(generate(), encoding="utf-8")

    (PROJECT_PATH / "xcshareddata" / "xcschemes" / f"{PROJECT_NAME}.xcscheme").write_text(
        SCHEME_TEMPLATE.format(target_uid=uid("target", PROJECT_NAME), name=PROJECT_NAME),
        encoding="utf-8",
    )

    (PROJECT_PATH / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
        WORKSPACE_TEMPLATE, encoding="utf-8"
    )

    swift_count = sum(1 for path in SOURCE_DIR.rglob("*.swift"))
    print(f"Wrote {os.path.relpath(PROJECT_PATH, ROOT)} ({swift_count} Swift files)")


if __name__ == "__main__":
    main()

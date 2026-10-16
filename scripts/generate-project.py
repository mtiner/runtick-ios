#!/usr/bin/env python3
"""Bootstrap a checked-in Xcode project without requiring macOS. XcodeGen is canonical."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def ref(s): return uid(s)
objects = []
def obj(key, text): objects.append(f'{ref(key)} = {{ {text} }};'); return ref(key)
def array(values): return '(' + ', '.join(values) + ', )' if values else '()'
app_sources = sorted((root/'RunTick').rglob('*.swift'))
test_sources = sorted((root/'RunTickTests').rglob('*.swift'))
resources = sorted((root/'RunTick/Resources').rglob('*.wav')) + sorted((root/'RunTick/Resources').rglob('*.mp3')) + sorted((root/'RunTick/Resources').glob('*.xcassets')) + sorted((root/'RunTick/Resources').glob('*.icon')) + sorted((root/'RunTick').glob('PrivacyInfo.xcprivacy'))
files = []
for p in app_sources + test_sources + resources:
    path = str(p.relative_to(root)); files.append(obj(path, f'isa = PBXFileReference; lastKnownFileType = {"sourcecode.swift" if p.suffix == ".swift" else "folder.assetcatalog" if p.suffix == ".xcassets" else "folder.icon" if p.suffix == ".icon" else "text.plist.xml" if p.suffix == ".xcprivacy" else "audio.mp3" if p.suffix == ".mp3" else "audio.wav"}; path = "{path}"; sourceTree = SOURCE_ROOT;'))
    obj('build:'+path, f'isa = PBXBuildFile; fileRef = {ref(path)};')
obj('appProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = RunTick.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('testProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = RunTickTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; children = ({ref("appProduct")}, {ref("testProduct")}); name = Products; sourceTree = "<group>";')
obj('mainGroup', f'isa = PBXGroup; children = {array(files + [ref("products")])}; sourceTree = "<group>";')
for target, sources, res in [('app', app_sources, resources), ('test', test_sources, [])]:
    for kind, isa, paths in [('sources','PBXSourcesBuildPhase',sources), ('resources','PBXResourcesBuildPhase',res), ('frameworks','PBXFrameworksBuildPhase',[])]:
        obj(target+kind, f'isa = {isa}; buildActionMask = 2147483647; files = {array([ref("build:"+str(p.relative_to(root))) for p in paths])}; runOnlyForDeploymentPostprocessing = 0;')
    for mode in ['Debug', 'Release']:
        settings = {'SWIFT_VERSION':'5.0', 'IPHONEOS_DEPLOYMENT_TARGET':'26.0', 'SDKROOT':'iphoneos', 'TARGETED_DEVICE_FAMILY':'"1,2"', 'GENERATE_INFOPLIST_FILE':'YES', 'CODE_SIGN_STYLE':'Automatic', 'DEVELOPMENT_TEAM':'7D7486BA97', 'MARKETING_VERSION':'1.0', 'CURRENT_PROJECT_VERSION':'1', 'PRODUCT_NAME':'"$(TARGET_NAME)"', 'PRODUCT_BUNDLE_IDENTIFIER': 'cc.runtick.app' + ('.tests' if target=='test' else ''), 'SWIFT_OPTIMIZATION_LEVEL': '"-Onone"' if mode=='Debug' else '"-O"', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if mode=='Debug' else '""', 'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO'}
        if target=='app': settings.update({'ASSETCATALOG_COMPILER_APPICON_NAME':'runtick', 'INFOPLIST_KEY_CFBundleDisplayName':'"RunTick 燃刻"','INFOPLIST_KEY_NSMotionUsageDescription':'"开启起跑反应检测后，使用加速度计和陀螺仪检测起跑器上的手机移动；运动采样仅在本机处理。"', 'INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.sports', 'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents':'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation':'YES', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone':'UIInterfaceOrientationPortrait', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':'"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"', 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption':'NO'})
        else: settings.update({'TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/RunTick.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/RunTick"','BUNDLE_LOADER':'"$(TEST_HOST)"'})
        obj(target+mode, f'isa = XCBuildConfiguration; buildSettings = {{ '+ ' '.join(f'{k} = {v};' for k,v in settings.items()) + f' }}; name = {mode};')
    obj(target+'config', f'isa = XCConfigurationList; buildConfigurations = ({ref(target+"Debug")}, {ref(target+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("appTarget")}; remoteInfo = RunTick;')
obj('dependency', f'isa = PBXTargetDependency; target = {ref("appTarget")}; targetProxy = {ref("proxy")};')
for target, name, typ in [('app','RunTick','application'),('test','RunTickTests','bundle.unit-test')]:
    obj(target+'Target', f'isa = PBXNativeTarget; buildConfigurationList = {ref(target+"config")}; buildPhases = ({ref(target+"sources")}, {ref(target+"frameworks")}, {ref(target+"resources")}); buildRules = (); dependencies = {array([ref("dependency")] if target=="test" else [])}; name = {name}; productName = {name}; productReference = {ref(target+"Product")}; productType = "com.apple.product-type.{typ}";')
for mode in ['Debug','Release']: obj('project'+mode, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; }}; name = {mode};')
obj('projectConfig', f'isa = XCConfigurationList; buildConfigurations = ({ref("projectDebug")}, {ref("projectRelease")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }}; buildConfigurationList = {ref("projectConfig")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; knownRegions = (en, zh_CN, Base); mainGroup = {ref("mainGroup")}; productRefGroup = {ref("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ref("appTarget")}, {ref("testTarget")});')
project = root/'RunTick.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {ref("project")}; }}\n')
scheme_dir = project/'xcshareddata/xcschemes'; scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(target, name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(target+"Target")}" BuildableName="{name}.{ "app" if target=="app" else "xctest" }" BlueprintName="{name}" ReferencedContainer="container:RunTick.xcodeproj"/>'
(scheme_dir/'RunTick.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('app','RunTick')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable('test','RunTickTests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('app','RunTick')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('app','RunTick')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project} with {len(app_sources)} Swift sources and {len(resources)} audio resources')

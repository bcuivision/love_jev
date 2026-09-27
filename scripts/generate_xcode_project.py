from pathlib import Path
import hashlib, plistlib

root = Path(__file__).resolve().parents[1] / 'ios'
project = root / '恋爱吧.xcodeproj'
(project / 'xcshareddata/xcschemes').mkdir(parents=True, exist_ok=True)
objects = {}
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(key, body):
    objects[uid(key)] = body
    return uid(key)
def quoted(value): return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
def seq(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
def settings(values): return '{' + ' '.join(f'{k} = {quoted(v)};' for k, v in values.items()) + '}'

shared = sorted(p.relative_to(root).as_posix() for p in (root/'Shared').glob('*.swift'))
targets = [
    ('LianAiBa', 'App', '$(APP_BUNDLE_ID)', 'com.apple.product-type.application', 'app'),
    ('LianAiBaKeyboard', 'KeyboardExtension', '$(APP_BUNDLE_ID).keyboard', 'com.apple.product-type.app-extension', 'appex'),
    ('LianAiBaBroadcast', 'BroadcastExtension', '$(APP_BUNDLE_ID).broadcast', 'com.apple.product-type.app-extension', 'appex'),
]
all_sources = sorted(shared + [p.relative_to(root).as_posix() for folder in ['App','KeyboardExtension','BroadcastExtension'] for p in (root/folder).glob('*.swift')])
config_ref = add('project-settings', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Project.xcconfig; sourceTree = \"<group>\";')
refs = [config_ref]
resource_paths = sorted(p.relative_to(root).as_posix() for p in (root/'Shared/Resources').glob('*') if p.is_file())
for path in resource_paths:
    refs.append(add('file:'+path, f'isa = PBXFileReference; lastKnownFileType = text; path = {quoted(path)}; sourceTree = "<group>";'))
for path in all_sources:
    refs.append(add('file:'+path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = "<group>";'))
products = []
for name, folder, bundle, producttype, suffix in targets:
    product = add('product:'+name, f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if suffix == "app" else "wrapper.app-extension"}; path = {name}.{suffix}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    target_shared = shared if suffix == 'app' or folder == 'KeyboardExtension' else [p for p in shared if Path(p).name in ['AssistantModels.swift', 'SharedStore.swift', 'ChatScene.swift']]
    sources = target_shared + [p for p in all_sources if p.startswith(folder+'/')]
    builds = []
    for path in sources:
        builds.append(add('build:'+name+':'+path, f'isa = PBXBuildFile; fileRef = {uid("file:"+path)};'))
    source_phase = add('sources:'+name, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {seq(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add('frameworks:'+name, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resource_builds = []
    if folder != 'BroadcastExtension':
        for path in resource_paths:
            resource_builds.append(add('resource:'+name+':'+path, f'isa = PBXBuildFile; fileRef = {uid("file:"+path)};'))
    resources = add('resources:'+name, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {seq(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    phases = [source_phase, frameworks, resources]
    deps = []
    if suffix == 'app':
        embedded = []
        for extension in ['LianAiBaKeyboard', 'LianAiBaBroadcast']:
            embedded.append(add('embed:'+extension, f'isa = PBXBuildFile; fileRef = {uid("product:"+extension)}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy,);}};'))
            proxy = add('proxy:'+extension, f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:"+extension)}; remoteInfo = {extension};')
            deps.append(add('dependency:'+extension, f'isa = PBXTargetDependency; target = {uid("target:"+extension)}; targetProxy = {proxy};'))
        phases.append(add('embedPhase', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {seq(embedded)}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;'))
    configs = []
    for configuration in ['Debug', 'Release']:
        values = {
            'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':bundle,
            'INFOPLIST_FILE':folder+'/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO',
            'SWIFT_VERSION':'5.0', 'IPHONEOS_DEPLOYMENT_TARGET':'17.0', 'TARGETED_DEVICE_FAMILY':'1',
            'CODE_SIGN_STYLE':'Automatic', 'CODE_SIGN_ENTITLEMENTS':'Config/Shared.entitlements', 'CURRENT_PROJECT_VERSION':'1',
            'MARKETING_VERSION':'1.0', 'SWIFT_STRICT_CONCURRENCY':'targeted',
            'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
            'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS':'YES',
        }
        if suffix == 'appex': values.update({'APPLICATION_EXTENSION_API_ONLY':'YES', 'SKIP_INSTALL':'YES'})
        configs.append(add('config:'+name+configuration, f'isa = XCBuildConfiguration; baseConfigurationReference = {config_ref}; buildSettings = {settings(values)}; name = {configuration};'))
    config_list = add('configs:'+name, f'isa = XCConfigurationList; buildConfigurations = {seq(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    add('target:'+name, f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {seq(phases)}; buildRules = (); dependencies = {seq(deps)}; name = {name}; productName = {name}; productReference = {product}; productType = {quoted(producttype)};')

base_info = {'CFBundleDevelopmentRegion':'zh_CN', 'CFBundleExecutable':'$(EXECUTABLE_NAME)', 'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion':'6.0', 'CFBundleName':'$(PRODUCT_NAME)', 'CFBundleShortVersionString':'$(MARKETING_VERSION)', 'CFBundleVersion':'$(CURRENT_PROJECT_VERSION)', 'CFBundleDisplayName':'恋爱吧', 'LianAiAppGroup':'$(APP_GROUP_IDENTIFIER)', 'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSExceptionDomains':{'localhost':{'NSExceptionAllowsInsecureHTTPLoads':True},'127.0.0.1':{'NSExceptionAllowsInsecureHTTPLoads':True}}}}
app_info = dict(base_info, CFBundlePackageType='APPL', LSRequiresIPhoneOS=True, UILaunchScreen={}, UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False}, UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
keyboard_info = dict(base_info, CFBundlePackageType='XPC!', NSExtension={'NSExtensionAttributes':{'IsASCIICapable':True,'PrefersRightToLeft':False,'PrimaryLanguage':'zh-Hans','RequestsOpenAccess':True},'NSExtensionPointIdentifier':'com.apple.keyboard-service','NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).KeyboardViewController'})
broadcast_info = dict(base_info, CFBundlePackageType='XPC!', NSExtension={'RPBroadcastProcessMode':'RPBroadcastProcessModeSampleBuffer','NSExtensionPointIdentifier':'com.apple.broadcast-services-upload','NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).SampleHandler'})
for folder, info in [('App',app_info), ('KeyboardExtension',keyboard_info), ('BroadcastExtension',broadcast_info)]:
    (root/folder/'Info.plist').write_bytes(plistlib.dumps(info))
    refs.append(add('file:'+folder+'/Info.plist', f'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {folder}/Info.plist; sourceTree = "<group>";'))
products_group = add('products', f'isa = PBXGroup; children = {seq(products)}; name = Products; sourceTree = "<group>";')
main_group = add('main', f'isa = PBXGroup; children = {seq(refs+[products_group])}; sourceTree = "<group>";')
project_configs = []
for configuration in ['Debug','Release']:
    values = {'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','ENABLE_USER_SCRIPT_SANDBOXING':'YES','DEBUG_INFORMATION_FORMAT':'dwarf','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O','GCC_PREPROCESSOR_DEFINITIONS':'$(inherited) DEBUG=1' if configuration=='Debug' else '$(inherited)'}
    if configuration=='Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
    project_configs.append(add('projectconfig:'+configuration, f'isa = XCBuildConfiguration; baseConfigurationReference = {config_ref}; buildSettings = {settings(values)}; name = {configuration};'))
pc = add('projectconfigs', f'isa = XCConfigurationList; buildConfigurations = {seq(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
capabilities = ' '.join(f'{uid("target:"+t[0])} = {{SystemCapabilities = {{com.apple.ApplicationGroups.iOS = {{enabled = 1;}};}};}};' for t in targets)
add('project', f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{{capabilities}}};}}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en, Base, zh_CN); mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = {seq([uid("target:"+t[0]) for t in targets])};')
output = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
output += '\n'.join(f'{key} = {{{body}}};' for key,body in objects.items())
output += f'\n}}; rootObject = {uid("project")}; }}\n'
(project/'project.pbxproj').write_text(output)
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:LianAiBa')}" BuildableName="LianAiBa.app" BlueprintName="LianAiBa" ReferencedContainer="container:恋爱吧.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:LianAiBa')}" BuildableName="LianAiBa.app" BlueprintName="LianAiBa" ReferencedContainer="container:恋爱吧.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(project/'xcshareddata/xcschemes/恋爱吧.xcscheme').write_text(scheme)
# Keep the original entry point buildable: both projects compile the same three
# targets and share Config/Project.xcconfig, source membership, and entitlements.
legacy = root / 'LianAiKeyboard.xcodeproj'
(legacy / 'xcshareddata/xcschemes').mkdir(parents=True, exist_ok=True)
(legacy / 'project.pbxproj').write_text(output)
(legacy / 'xcshareddata/xcschemes/LianAi.xcscheme').write_text(
    scheme.replace('container:恋爱吧.xcodeproj', 'container:LianAiKeyboard.xcodeproj')
)
print(project)

import os
import hashlib

def gen_id(name):
    # Generates a stable 24-character hexadecimal Xcode identifier
    h = hashlib.sha1(name.encode('utf-8')).hexdigest().upper()
    return h[:24]

# Files list: (relativePath, isResource)
files = [
    # App
    ("SpendDrop/App/SpendDropApp.swift", False),
    # Models
    ("SpendDrop/Models/Expense.swift", False),
    ("SpendDrop/Models/ExpenseCategory.swift", False),
    ("SpendDrop/Models/PaymentSource.swift", False),
    ("SpendDrop/Models/ExpenseSourceType.swift", False),
    # Data
    ("SpendDrop/Data/ExpenseDataContainer.swift", False),
    ("SpendDrop/Data/SampleData.swift", False),
    # Utils
    ("SpendDrop/Utils/CurrencyFormatter.swift", False),
    ("SpendDrop/Utils/HapticFeedback.swift", False),
    # OCR (Milestone 2)
    ("SpendDrop/OCR/OCRService.swift", False),
    ("SpendDrop/OCR/ParsedTransaction.swift", False),
    ("SpendDrop/OCR/MerchantDetector.swift", False),
    ("SpendDrop/OCR/CategoryDetector.swift", False),
    ("SpendDrop/OCR/TransactionParser.swift", False),
    ("SpendDrop/OCR/ImageStorageService.swift", False),
    ("SpendDrop/OCR/TransactionParserTests.swift", False),
    # Views
    ("SpendDrop/Views/MainTabView.swift", False),
    ("SpendDrop/Views/Dashboard/DashboardView.swift", False),
    ("SpendDrop/Views/Dashboard/Components/SpendingSummaryCard.swift", False),
    ("SpendDrop/Views/Dashboard/Components/QuickCashButton.swift", False),
    ("SpendDrop/Views/Expenses/ExpensesView.swift", False),
    ("SpendDrop/Views/Expenses/ExpenseDetailView.swift", False),
    ("SpendDrop/Views/Expenses/EditExpenseView.swift", False),
    ("SpendDrop/Views/Expenses/Components/ExpenseRowView.swift", False),
    ("SpendDrop/Views/Expenses/Components/FilterBarView.swift", False),
    ("SpendDrop/Views/AddExpense/AddExpenseView.swift", False),
    ("SpendDrop/Views/Review/ExpenseReviewView.swift", False),
    ("SpendDrop/Views/Analytics/AnalyticsView.swift", False),
    ("SpendDrop/Views/Settings/SettingsView.swift", False),
    ("SpendDrop/Views/Settings/Components/ParserSelfTestView.swift", False),
    # Resources
    ("SpendDrop/Resources/Assets.xcassets", True),
    ("SpendDrop/Resources/Info.plist", False),
    ("SpendDrop/Resources/SpendDrop.entitlements", False),
]

proj_id = gen_id("SpendDrop_Project")
target_id = gen_id("SpendDrop_NativeTarget")
sources_phase_id = gen_id("SpendDrop_SourcesPhase")
resources_phase_id = gen_id("SpendDrop_ResourcesPhase")
frameworks_phase_id = gen_id("SpendDrop_FrameworksPhase")
app_product_id = gen_id("SpendDrop_AppProduct")

debug_config_target_id = gen_id("SpendDrop_Debug_Target")
release_config_target_id = gen_id("SpendDrop_Release_Target")
config_list_target_id = gen_id("SpendDrop_ConfigList_Target")

debug_config_proj_id = gen_id("SpendDrop_Debug_Proj")
release_config_proj_id = gen_id("SpendDrop_Release_Proj")
config_list_proj_id = gen_id("SpendDrop_ConfigList_Proj")

main_group_id = gen_id("SpendDrop_MainGroup")
products_group_id = gen_id("SpendDrop_ProductsGroup")

# Build File Ref and Build File IDs
file_refs = {}
build_files = {}

for path, is_res in files:
    fref_id = gen_id(f"FREF_{path}")
    file_refs[path] = fref_id
    if path.endswith(".swift") or is_res:
        bf_id = gen_id(f"BF_{path}")
        build_files[path] = bf_id

pbx = []
pbx.append("// !$*UTF8*$!")
pbx.append("{")
pbx.append("\tarchiveVersion = 1;")
pbx.append("\tclasses = {")
pbx.append("\t};")
pbx.append("\tobjectVersion = 56;")
pbx.append("\tobjects = {")

# PBXBuildFile
pbx.append("\n/* Begin PBXBuildFile section */")
for path, bf_id in build_files.items():
    fref_id = file_refs[path]
    filename = os.path.basename(path)
    pbx.append(f"\t\t{bf_id} /* {filename} in Build */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {filename} */; }};")
pbx.append("/* End PBXBuildFile section */")

# PBXFileReference
pbx.append("\n/* Begin PBXFileReference section */")
pbx.append(f"\t\t{app_product_id} /* SpendDrop.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SpendDrop.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for path, fref_id in file_refs.items():
    filename = os.path.basename(path)
    if path.endswith(".swift"):
        ft = "sourcecode.swift"
    elif path.endswith(".xcassets"):
        ft = "folder.assetcatalog"
    elif path.endswith(".plist"):
        ft = "text.plist.xml"
    elif path.endswith(".entitlements"):
        ft = "text.plist.entitlements"
    else:
        ft = "text"
    pbx.append(f"\t\t{fref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = \"{filename}\"; sourceTree = \"<group>\"; }};")
pbx.append("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
pbx.append("\n/* Begin PBXFrameworksBuildPhase section */")
pbx.append(f"\t\t{frameworks_phase_id} /* Frameworks */ = {{")
pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXFrameworksBuildPhase section */")

# PBXGroup hierarchy
groups = {}

def add_group(gid, name, path, children):
    groups[gid] = (name, path, children)

# Components groups
dash_comp_id = gen_id("GROUP_Views_Dashboard_Components")
add_group(dash_comp_id, "Components", "Components", [
    file_refs["SpendDrop/Views/Dashboard/Components/SpendingSummaryCard.swift"],
    file_refs["SpendDrop/Views/Dashboard/Components/QuickCashButton.swift"]
])

exp_comp_id = gen_id("GROUP_Views_Expenses_Components")
add_group(exp_comp_id, "Components", "Components", [
    file_refs["SpendDrop/Views/Expenses/Components/ExpenseRowView.swift"],
    file_refs["SpendDrop/Views/Expenses/Components/FilterBarView.swift"]
])

settings_comp_id = gen_id("GROUP_Views_Settings_Components")
add_group(settings_comp_id, "Components", "Components", [
    file_refs["SpendDrop/Views/Settings/Components/ParserSelfTestView.swift"]
])

# Dashboard group
dash_group_id = gen_id("GROUP_Views_Dashboard")
add_group(dash_group_id, "Dashboard", "Dashboard", [
    dash_comp_id,
    file_refs["SpendDrop/Views/Dashboard/DashboardView.swift"]
])

# Expenses group
exp_group_id = gen_id("GROUP_Views_Expenses")
add_group(exp_group_id, "Expenses", "Expenses", [
    exp_comp_id,
    file_refs["SpendDrop/Views/Expenses/ExpensesView.swift"],
    file_refs["SpendDrop/Views/Expenses/ExpenseDetailView.swift"],
    file_refs["SpendDrop/Views/Expenses/EditExpenseView.swift"]
])

# AddExpense group
addexp_group_id = gen_id("GROUP_Views_AddExpense")
add_group(addexp_group_id, "AddExpense", "AddExpense", [
    file_refs["SpendDrop/Views/AddExpense/AddExpenseView.swift"]
])

# Review group (Milestone 2)
review_group_id = gen_id("GROUP_Views_Review")
add_group(review_group_id, "Review", "Review", [
    file_refs["SpendDrop/Views/Review/ExpenseReviewView.swift"]
])

# Analytics group
analytics_group_id = gen_id("GROUP_Views_Analytics")
add_group(analytics_group_id, "Analytics", "Analytics", [
    file_refs["SpendDrop/Views/Analytics/AnalyticsView.swift"]
])

# Settings group
settings_group_id = gen_id("GROUP_Views_Settings")
add_group(settings_group_id, "Settings", "Settings", [
    settings_comp_id,
    file_refs["SpendDrop/Views/Settings/SettingsView.swift"]
])

# Views group
views_group_id = gen_id("GROUP_Views")
add_group(views_group_id, "Views", "Views", [
    dash_group_id,
    exp_group_id,
    addexp_group_id,
    review_group_id,
    analytics_group_id,
    settings_group_id,
    file_refs["SpendDrop/Views/MainTabView.swift"]
])

# OCR group (Milestone 2)
ocr_group_id = gen_id("GROUP_OCR")
add_group(ocr_group_id, "OCR", "OCR", [
    file_refs["SpendDrop/OCR/OCRService.swift"],
    file_refs["SpendDrop/OCR/ParsedTransaction.swift"],
    file_refs["SpendDrop/OCR/MerchantDetector.swift"],
    file_refs["SpendDrop/OCR/CategoryDetector.swift"],
    file_refs["SpendDrop/OCR/TransactionParser.swift"],
    file_refs["SpendDrop/OCR/ImageStorageService.swift"],
    file_refs["SpendDrop/OCR/TransactionParserTests.swift"]
])

# App group
app_group_id = gen_id("GROUP_App")
add_group(app_group_id, "App", "App", [
    file_refs["SpendDrop/App/SpendDropApp.swift"]
])

# Models group
models_group_id = gen_id("GROUP_Models")
add_group(models_group_id, "Models", "Models", [
    file_refs["SpendDrop/Models/Expense.swift"],
    file_refs["SpendDrop/Models/ExpenseCategory.swift"],
    file_refs["SpendDrop/Models/PaymentSource.swift"],
    file_refs["SpendDrop/Models/ExpenseSourceType.swift"]
])

# Data group
data_group_id = gen_id("GROUP_Data")
add_group(data_group_id, "Data", "Data", [
    file_refs["SpendDrop/Data/ExpenseDataContainer.swift"],
    file_refs["SpendDrop/Data/SampleData.swift"]
])

# Utils group
utils_group_id = gen_id("GROUP_Utils")
add_group(utils_group_id, "Utils", "Utils", [
    file_refs["SpendDrop/Utils/CurrencyFormatter.swift"],
    file_refs["SpendDrop/Utils/HapticFeedback.swift"]
])

# Resources group
res_group_id = gen_id("GROUP_Resources")
add_group(res_group_id, "Resources", "Resources", [
    file_refs["SpendDrop/Resources/Assets.xcassets"],
    file_refs["SpendDrop/Resources/Info.plist"],
    file_refs["SpendDrop/Resources/SpendDrop.entitlements"]
])

# SpendDrop folder group
spenddrop_group_id = gen_id("GROUP_SpendDrop_Folder")
add_group(spenddrop_group_id, "SpendDrop", "SpendDrop", [
    app_group_id,
    models_group_id,
    data_group_id,
    views_group_id,
    ocr_group_id,
    utils_group_id,
    res_group_id
])

# Products group
add_group(products_group_id, "Products", None, [app_product_id])

# Main group
add_group(main_group_id, None, None, [spenddrop_group_id, products_group_id])

pbx.append("\n/* Begin PBXGroup section */")
for gid, (name, path, children) in groups.items():
    pbx.append(f"\t\t{gid} = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    for child in children:
        pbx.append(f"\t\t\t\t{child},")
    pbx.append("\t\t\t);")
    if name:
        pbx.append(f"\t\t\tname = \"{name}\";")
    if path:
        pbx.append(f"\t\t\tpath = \"{path}\";")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")
pbx.append("/* End PBXGroup section */")

# PBXNativeTarget
pbx.append("\n/* Begin PBXNativeTarget section */")
pbx.append(f"\t\t{target_id} /* SpendDrop */ = {{")
pbx.append("\t\t\tisa = PBXNativeTarget;")
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_target_id} /* Build configuration list for PBXNativeTarget \"SpendDrop\" */;")
pbx.append("\t\t\tbuildPhases = (")
pbx.append(f"\t\t\t\t{sources_phase_id} /* Sources */,")
pbx.append(f"\t\t\t\t{frameworks_phase_id} /* Frameworks */,")
pbx.append(f"\t\t\t\t{resources_phase_id} /* Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tbuildRules = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdependencies = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = SpendDrop;")
pbx.append("\t\t\tproductName = SpendDrop;")
pbx.append(f"\t\t\tproductReference = {app_product_id} /* SpendDrop.app */;")
pbx.append("\t\t\tproductType = \"com.apple.product-type.application\";")
pbx.append("\t\t};")
pbx.append("/* End PBXNativeTarget section */")

# PBXProject
pbx.append("\n/* Begin PBXProject section */")
pbx.append(f"\t\t{proj_id} /* Project object */ = {{")
pbx.append("\t\t\tisa = PBXProject;")
pbx.append("\t\t\tattributes = {")
pbx.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
pbx.append("\t\t\t\tLastUpgradeCheck = 1600;")
pbx.append("\t\t\t\tTargetAttributes = {")
pbx.append(f"\t\t\t\t\t{target_id} = {{")
pbx.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
pbx.append("\t\t\t\t\t};")
pbx.append("\t\t\t\t};")
pbx.append("\t\t\t};")
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_proj_id} /* Build configuration list for PBXProject \"SpendDrop\" */;")
pbx.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
pbx.append("\t\t\tdevelopmentRegion = en;")
pbx.append("\t\t\thasScannedForEncodings = 0;")
pbx.append("\t\t\tknownRegions = (")
pbx.append("\t\t\t\ten,")
pbx.append("\t\t\t\tBase,")
pbx.append("\t\t\t);")
pbx.append(f"\t\t\tmainGroup = {main_group_id};")
pbx.append(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
pbx.append("\t\t\tprojectDirPath = \"\";")
pbx.append("\t\t\tprojectRoot = \"\";")
pbx.append("\t\t\ttargets = (")
pbx.append(f"\t\t\t\t{target_id} /* SpendDrop */,")
pbx.append("\t\t\t);")
pbx.append("\t\t};")
pbx.append("/* End PBXProject section */")

# PBXResourcesBuildPhase
pbx.append("\n/* Begin PBXResourcesBuildPhase section */")
pbx.append(f"\t\t{resources_phase_id} /* Resources */ = {{")
pbx.append("\t\t\tisa = PBXResourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for path, is_res in files:
    if is_res and path in build_files:
        bf_id = build_files[path]
        pbx.append(f"\t\t\t\t{bf_id} /* {os.path.basename(path)} in Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
pbx.append("\n/* Begin PBXSourcesBuildPhase section */")
pbx.append(f"\t\t{sources_phase_id} /* Sources */ = {{")
pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for path, is_res in files:
    if path.endswith(".swift") and path in build_files:
        bf_id = build_files[path]
        pbx.append(f"\t\t\t\t{bf_id} /* {os.path.basename(path)} in Sources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
pbx.append("\n/* Begin XCBuildConfiguration section */")
# Project Debug
pbx.append(f"\t\t{debug_config_proj_id} /* Debug */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
pbx.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
pbx.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
pbx.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
pbx.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
pbx.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
pbx.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
pbx.append("\t\t\t\tENABLE_TESTABILITY = YES;")
pbx.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
pbx.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
pbx.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
pbx.append("\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
pbx.append("\t\t\t\t\t\"DEBUG=1\",")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
pbx.append("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
pbx.append("\t\t\t\tGCC_WARN_UNDEFINED_VARIABLES = YES;")
pbx.append("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
pbx.append("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
pbx.append("\t\t\t\tMTL_FAST_MATH = YES;")
pbx.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
pbx.append("\t\t\t\tSDKROOT = iphoneos;")
pbx.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
pbx.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Debug;")
pbx.append("\t\t};")

# Project Release
pbx.append(f"\t\t{release_config_proj_id} /* Release */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
pbx.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
pbx.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
pbx.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
pbx.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
pbx.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
pbx.append("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
pbx.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
pbx.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
pbx.append("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
pbx.append("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
pbx.append("\t\t\t\tGCC_WARN_UNDEFINED_VARIABLES = YES;")
pbx.append("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
pbx.append("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
pbx.append("\t\t\t\tMTL_FAST_MATH = YES;")
pbx.append("\t\t\t\tSDKROOT = iphoneos;")
pbx.append("\t\t\t\tSWIFT_COMPILATION_MODE = \"wholemodule\";")
pbx.append("\t\t\t\tVALIDATE_PRODUCT = YES;")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Release;")
pbx.append("\t\t};")

# Target Debug
pbx.append(f"\t\t{debug_config_target_id} /* Debug */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpendDrop/Resources/SpendDrop.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
pbx.append("\t\t\t\tENABLE_PREVIEWS = YES;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpendDrop/Resources/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.1.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spenddrop.SpendDrop;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Debug;")
pbx.append("\t\t};")

# Target Release
pbx.append(f"\t\t{release_config_target_id} /* Release */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpendDrop/Resources/SpendDrop.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
pbx.append("\t\t\t\tENABLE_PREVIEWS = YES;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpendDrop/Resources/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.1.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spenddrop.SpendDrop;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Release;")
pbx.append("\t\t};")
pbx.append("/* End XCBuildConfiguration section */")

# XCConfigurationList
pbx.append("\n/* Begin XCConfigurationList section */")
pbx.append(f"\t\t{config_list_proj_id} /* Build configuration list for PBXProject \"SpendDrop\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_proj_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_proj_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")

pbx.append(f"\t\t{config_list_target_id} /* Build configuration list for PBXNativeTarget \"SpendDrop\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_target_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_target_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")
pbx.append("/* End XCConfigurationList section */")

pbx.append("\t};")
pbx.append(f"\trootObject = {proj_id} /* Project object */;")
pbx.append("}")

output_dir = "SpendDrop.xcodeproj"
os.makedirs(output_dir, exist_ok=True)
pbx_path = os.path.join(output_dir, "project.pbxproj")
with open(pbx_path, "w", encoding="utf-8") as f:
    f.write("\n".join(pbx) + "\n")

print(f"Generated {pbx_path} successfully for Milestone 2!")

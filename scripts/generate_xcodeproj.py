import os
import hashlib

def gen_id(name):
    # Generates a stable 24-character hexadecimal Xcode identifier
    h = hashlib.sha1(name.encode('utf-8')).hexdigest().upper()
    return h[:24]

# All project files
all_files = [
    # App
    ("SpendDrop/App/SpendDropApp.swift", False),
    # Models
    ("SpendDrop/Models/Expense.swift", False),
    ("SpendDrop/Models/ExpenseCategory.swift", False),
    ("SpendDrop/Models/PaymentSource.swift", False),
    ("SpendDrop/Models/ExpenseSourceType.swift", False),
    ("SpendDrop/Models/PayBookContact.swift", False),
    # Data
    ("SpendDrop/Data/ExpenseDataContainer.swift", False),
    ("SpendDrop/Data/DuplicateDetector.swift", False),
    ("SpendDrop/Data/SampleData.swift", False),
    # Utils
    ("SpendDrop/Utils/CurrencyFormatter.swift", False),
    ("SpendDrop/Utils/HapticFeedback.swift", False),
    # OCR (Milestone 2)
    ("SpendDrop/OCR/OCRService.swift", False),
    ("SpendDrop/OCR/ParsedTransaction.swift", False),
    ("SpendDrop/OCR/MonetaryCandidate.swift", False),
    ("SpendDrop/OCR/PaymentProviderDetector.swift", False),
    ("SpendDrop/OCR/MerchantDetector.swift", False),
    ("SpendDrop/OCR/CategoryDetector.swift", False),
    ("SpendDrop/OCR/TransactionParser.swift", False),
    ("SpendDrop/OCR/ImageStorageService.swift", False),
    ("SpendDrop/OCR/ImagePipelineDiagnostics.swift", False),
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
    ("SpendDrop/Views/Expenses/Components/PaymentLogoView.swift", False),
    ("SpendDrop/Views/Expenses/Components/FilterBarView.swift", False),
    ("SpendDrop/Views/PayBook/PayBookView.swift", False),
    ("SpendDrop/Views/PayBook/PayBookDetailView.swift", False),
    ("SpendDrop/Views/PayBook/AddPayBookContactView.swift", False),
    ("SpendDrop/Views/PayBook/EditPayBookContactView.swift", False),
    ("SpendDrop/Views/AddExpense/AddExpenseView.swift", False),
    ("SpendDrop/Views/Review/ExpenseReviewView.swift", False),
    ("SpendDrop/Views/Analytics/AnalyticsView.swift", False),
    ("SpendDrop/Views/Settings/SettingsView.swift", False),
    ("SpendDrop/Views/Settings/Components/ParserSelfTestView.swift", False),
    # Share Extension (Milestone 3)
    ("SpendDrop/ShareExtension/ShareViewController.swift", False),
    ("SpendDrop/ShareExtension/ShareExtensionView.swift", False),
    ("SpendDrop/ShareExtension/Info.plist", False),
    ("SpendDrop/ShareExtension/ShareExtension.entitlements", False),
    # Resources
    ("SpendDrop/Resources/Assets.xcassets", True),
    ("SpendDrop/Resources/Info.plist", False),
    ("SpendDrop/Resources/SpendDrop.entitlements", False),
    ("SpendDrop/Resources/DiagnosticSamples/sample_screenshot.png", True),
    ("SpendDrop/Resources/DiagnosticSamples/sample_photo.jpg", True),
    ("SpendDrop/Resources/DiagnosticSamples/sample_camera.heic", True),
]

# Files compiled by main app target
app_source_paths = [path for path, is_res in all_files if path.endswith(".swift") and not path.startswith("SpendDrop/ShareExtension/")]

# Resources copied by main app target
app_res_paths = [path for path, is_res in all_files if is_res]

# Files compiled by Share Extension target
share_source_paths = [
    "SpendDrop/ShareExtension/ShareViewController.swift",
    "SpendDrop/ShareExtension/ShareExtensionView.swift",
    "SpendDrop/Models/Expense.swift",
    "SpendDrop/Models/ExpenseCategory.swift",
    "SpendDrop/Models/PaymentSource.swift",
    "SpendDrop/Models/ExpenseSourceType.swift",
    "SpendDrop/Models/PayBookContact.swift",
    "SpendDrop/Data/ExpenseDataContainer.swift",
    "SpendDrop/Data/DuplicateDetector.swift",
    "SpendDrop/Data/SampleData.swift",
    "SpendDrop/OCR/OCRService.swift",
    "SpendDrop/OCR/ParsedTransaction.swift",
    "SpendDrop/OCR/MonetaryCandidate.swift",
    "SpendDrop/OCR/PaymentProviderDetector.swift",
    "SpendDrop/OCR/MerchantDetector.swift",
    "SpendDrop/OCR/CategoryDetector.swift",
    "SpendDrop/OCR/TransactionParser.swift",
    "SpendDrop/OCR/ImageStorageService.swift",
    "SpendDrop/Utils/CurrencyFormatter.swift",
    "SpendDrop/Utils/HapticFeedback.swift",
]

# IDs for Main App Target
proj_id = gen_id("SpendDrop_Project")
target_id = gen_id("SpendDrop_NativeTarget")
sources_phase_id = gen_id("SpendDrop_SourcesPhase")
resources_phase_id = gen_id("SpendDrop_ResourcesPhase")
frameworks_phase_id = gen_id("SpendDrop_FrameworksPhase")
embed_extensions_phase_id = gen_id("SpendDrop_EmbedExtensionsPhase")
app_product_id = gen_id("SpendDrop_AppProduct")

debug_config_target_id = gen_id("SpendDrop_Debug_Target")
release_config_target_id = gen_id("SpendDrop_Release_Target")
config_list_target_id = gen_id("SpendDrop_ConfigList_Target")

debug_config_proj_id = gen_id("SpendDrop_Debug_Proj")
release_config_proj_id = gen_id("SpendDrop_Release_Proj")
config_list_proj_id = gen_id("SpendDrop_ConfigList_Proj")

# IDs for Share Extension Target
share_target_id = gen_id("SpendDropShare_NativeTarget")
share_sources_phase_id = gen_id("SpendDropShare_SourcesPhase")
share_resources_phase_id = gen_id("SpendDropShare_ResourcesPhase")
share_frameworks_phase_id = gen_id("SpendDropShare_FrameworksPhase")
share_product_id = gen_id("SpendDropShare_Product")

debug_config_share_id = gen_id("SpendDropShare_Debug_Target")
release_config_share_id = gen_id("SpendDropShare_Release_Target")
config_list_share_id = gen_id("SpendDropShare_ConfigList_Target")

# Dependency IDs
container_proxy_id = gen_id("SpendDrop_ContainerItemProxy_Share")
target_dependency_id = gen_id("SpendDrop_TargetDependency_Share")
embed_appex_build_file_id = gen_id("SpendDrop_EmbedAppexBuildFile")

main_group_id = gen_id("SpendDrop_MainGroup")
products_group_id = gen_id("SpendDrop_ProductsGroup")

# PBXFileReference IDs
file_refs = {}
for path, _ in all_files:
    file_refs[path] = gen_id(f"FREF_{path}")

# PBXBuildFile IDs for App target
app_build_files = {}
for path in app_source_paths:
    app_build_files[path] = gen_id(f"BF_APP_{path}")
app_res_build_files = {}
for path in app_res_paths:
    app_res_build_files[path] = gen_id(f"BF_APP_RES_{path}")

# PBXBuildFile IDs for Share target
share_build_files = {}
for path in share_source_paths:
    share_build_files[path] = gen_id(f"BF_SHARE_{path}")

pbx = []
pbx.append("// !$*UTF8*$!")
pbx.append("{")
pbx.append("\tarchiveVersion = 1;")
pbx.append("\tclasses = {")
pbx.append("\t};")
pbx.append("\tobjectVersion = 56;")
pbx.append("\tobjects = {")

# PBXBuildFile section
pbx.append("\n/* Begin PBXBuildFile section */")
# App sources
for path, bf_id in app_build_files.items():
    fref_id = file_refs[path]
    filename = os.path.basename(path)
    pbx.append(f"\t\t{bf_id} /* {filename} in App Sources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {filename} */; }};")

# App resources
for path, bf_id in app_res_build_files.items():
    fref_id = file_refs[path]
    filename = os.path.basename(path)
    pbx.append(f"\t\t{bf_id} /* {filename} in App Resources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {filename} */; }};")

# Share extension sources
for path, bf_id in share_build_files.items():
    fref_id = file_refs[path]
    filename = os.path.basename(path)
    pbx.append(f"\t\t{bf_id} /* {filename} in Share Sources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {filename} */; }};")

# Embed Appex in App
pbx.append(f"\t\t{embed_appex_build_file_id} /* SpendDropShare.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {share_product_id} /* SpendDropShare.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
pbx.append("/* End PBXBuildFile section */")

# PBXContainerItemProxy section
pbx.append("\n/* Begin PBXContainerItemProxy section */")
pbx.append(f"\t\t{container_proxy_id} /* PBXContainerItemProxy */ = {{")
pbx.append("\t\t\tisa = PBXContainerItemProxy;")
pbx.append(f"\t\t\tcontainerPortal = {proj_id} /* Project object */;")
pbx.append("\t\t\tproxyType = 1;")
pbx.append(f"\t\t\tremoteGlobalIDString = {share_target_id};")
pbx.append("\t\t\tremoteInfo = SpendDropShare;")
pbx.append("\t\t};")
pbx.append("/* End PBXContainerItemProxy section */")

# PBXCopyFilesBuildPhase section
pbx.append("\n/* Begin PBXCopyFilesBuildPhase section */")
pbx.append(f"\t\t{embed_extensions_phase_id} /* Embed Foundation Extensions */ = {{")
pbx.append("\t\t\tisa = PBXCopyFilesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tdstPath = \"\";")
pbx.append("\t\t\tdstSubfolderSpec = 13;")
pbx.append("\t\t\tfiles = (")
pbx.append(f"\t\t\t\t{embed_appex_build_file_id} /* SpendDropShare.appex in Embed Foundation Extensions */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = \"Embed Foundation Extensions\";")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXCopyFilesBuildPhase section */")

# PBXFileReference section
pbx.append("\n/* Begin PBXFileReference section */")
pbx.append(f"\t\t{app_product_id} /* SpendDrop.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SpendDrop.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
pbx.append(f"\t\t{share_product_id} /* SpendDropShare.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = SpendDropShare.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")

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
    elif path.endswith(".png"):
        ft = "image.png"
    elif path.endswith(".jpg") or path.endswith(".jpeg"):
        ft = "image.jpeg"
    elif path.endswith(".heic"):
        ft = "image.heic"
    else:
        ft = "text"
    pbx.append(f"\t\t{fref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = \"{filename}\"; sourceTree = \"<group>\"; }};")
pbx.append("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase section
pbx.append("\n/* Begin PBXFrameworksBuildPhase section */")
pbx.append(f"\t\t{frameworks_phase_id} /* Frameworks */ = {{")
pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append(f"\t\t{share_frameworks_phase_id} /* Frameworks */ = {{")
pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXFrameworksBuildPhase section */")

# PBXGroup section
groups = {}
def add_group(gid, name, path, children):
    groups[gid] = (name, path, children)

dash_comp_id = gen_id("GROUP_Views_Dashboard_Components")
add_group(dash_comp_id, "Components", "Components", [
    file_refs["SpendDrop/Views/Dashboard/Components/SpendingSummaryCard.swift"],
    file_refs["SpendDrop/Views/Dashboard/Components/QuickCashButton.swift"]
])

exp_comp_id = gen_id("GROUP_Views_Expenses_Components")
add_group(exp_comp_id, "Components", "Components", [
    file_refs["SpendDrop/Views/Expenses/Components/ExpenseRowView.swift"],
    file_refs["SpendDrop/Views/Expenses/Components/PaymentLogoView.swift"],
    file_refs["SpendDrop/Views/Expenses/Components/FilterBarView.swift"]
])

settings_comp_id = gen_id("GROUP_Views_Settings_Components")
add_group(settings_comp_id, "Components", "Components", [
    file_refs["SpendDrop/Views/Settings/Components/ParserSelfTestView.swift"]
])

dash_group_id = gen_id("GROUP_Views_Dashboard")
add_group(dash_group_id, "Dashboard", "Dashboard", [
    dash_comp_id,
    file_refs["SpendDrop/Views/Dashboard/DashboardView.swift"]
])

exp_group_id = gen_id("GROUP_Views_Expenses")
add_group(exp_group_id, "Expenses", "Expenses", [
    exp_comp_id,
    file_refs["SpendDrop/Views/Expenses/ExpensesView.swift"],
    file_refs["SpendDrop/Views/Expenses/ExpenseDetailView.swift"],
    file_refs["SpendDrop/Views/Expenses/EditExpenseView.swift"]
])

addexp_group_id = gen_id("GROUP_Views_AddExpense")
add_group(addexp_group_id, "AddExpense", "AddExpense", [
    file_refs["SpendDrop/Views/AddExpense/AddExpenseView.swift"]
])

review_group_id = gen_id("GROUP_Views_Review")
add_group(review_group_id, "Review", "Review", [
    file_refs["SpendDrop/Views/Review/ExpenseReviewView.swift"]
])

analytics_group_id = gen_id("GROUP_Views_Analytics")
add_group(analytics_group_id, "Analytics", "Analytics", [
    file_refs["SpendDrop/Views/Analytics/AnalyticsView.swift"]
])

settings_group_id = gen_id("GROUP_Views_Settings")
add_group(settings_group_id, "Settings", "Settings", [
    settings_comp_id,
    file_refs["SpendDrop/Views/Settings/SettingsView.swift"]
])

paybook_group_id = gen_id("GROUP_Views_PayBook")
add_group(paybook_group_id, "PayBook", "PayBook", [
    file_refs["SpendDrop/Views/PayBook/PayBookView.swift"],
    file_refs["SpendDrop/Views/PayBook/PayBookDetailView.swift"],
    file_refs["SpendDrop/Views/PayBook/AddPayBookContactView.swift"],
    file_refs["SpendDrop/Views/PayBook/EditPayBookContactView.swift"]
])

views_group_id = gen_id("GROUP_Views")
add_group(views_group_id, "Views", "Views", [
    dash_group_id,
    exp_group_id,
    paybook_group_id,
    addexp_group_id,
    review_group_id,
    analytics_group_id,
    settings_group_id,
    file_refs["SpendDrop/Views/MainTabView.swift"]
])

ocr_group_id = gen_id("GROUP_OCR")
add_group(ocr_group_id, "OCR", "OCR", [
    file_refs["SpendDrop/OCR/OCRService.swift"],
    file_refs["SpendDrop/OCR/ParsedTransaction.swift"],
    file_refs["SpendDrop/OCR/MonetaryCandidate.swift"],
    file_refs["SpendDrop/OCR/PaymentProviderDetector.swift"],
    file_refs["SpendDrop/OCR/MerchantDetector.swift"],
    file_refs["SpendDrop/OCR/CategoryDetector.swift"],
    file_refs["SpendDrop/OCR/TransactionParser.swift"],
    file_refs["SpendDrop/OCR/ImageStorageService.swift"],
    file_refs["SpendDrop/OCR/ImagePipelineDiagnostics.swift"],
    file_refs["SpendDrop/OCR/TransactionParserTests.swift"]
])

app_group_id = gen_id("GROUP_App")
add_group(app_group_id, "App", "App", [
    file_refs["SpendDrop/App/SpendDropApp.swift"]
])

models_group_id = gen_id("GROUP_Models")
add_group(models_group_id, "Models", "Models", [
    file_refs["SpendDrop/Models/Expense.swift"],
    file_refs["SpendDrop/Models/ExpenseCategory.swift"],
    file_refs["SpendDrop/Models/PaymentSource.swift"],
    file_refs["SpendDrop/Models/ExpenseSourceType.swift"],
    file_refs["SpendDrop/Models/PayBookContact.swift"]
])

data_group_id = gen_id("GROUP_Data")
add_group(data_group_id, "Data", "Data", [
    file_refs["SpendDrop/Data/ExpenseDataContainer.swift"],
    file_refs["SpendDrop/Data/DuplicateDetector.swift"],
    file_refs["SpendDrop/Data/SampleData.swift"]
])

utils_group_id = gen_id("GROUP_Utils")
add_group(utils_group_id, "Utils", "Utils", [
    file_refs["SpendDrop/Utils/CurrencyFormatter.swift"],
    file_refs["SpendDrop/Utils/HapticFeedback.swift"]
])

diag_samples_group_id = gen_id("GROUP_DiagnosticSamples")
add_group(diag_samples_group_id, "DiagnosticSamples", "DiagnosticSamples", [
    file_refs["SpendDrop/Resources/DiagnosticSamples/sample_screenshot.png"],
    file_refs["SpendDrop/Resources/DiagnosticSamples/sample_photo.jpg"],
    file_refs["SpendDrop/Resources/DiagnosticSamples/sample_camera.heic"]
])

res_group_id = gen_id("GROUP_Resources")
add_group(res_group_id, "Resources", "Resources", [
    file_refs["SpendDrop/Resources/Assets.xcassets"],
    file_refs["SpendDrop/Resources/Info.plist"],
    file_refs["SpendDrop/Resources/SpendDrop.entitlements"],
    diag_samples_group_id
])

share_ext_group_id = gen_id("GROUP_ShareExtension")
add_group(share_ext_group_id, "ShareExtension", "ShareExtension", [
    file_refs["SpendDrop/ShareExtension/ShareViewController.swift"],
    file_refs["SpendDrop/ShareExtension/ShareExtensionView.swift"],
    file_refs["SpendDrop/ShareExtension/Info.plist"],
    file_refs["SpendDrop/ShareExtension/ShareExtension.entitlements"]
])

spenddrop_group_id = gen_id("GROUP_SpendDrop_Folder")
add_group(spenddrop_group_id, "SpendDrop", "SpendDrop", [
    app_group_id,
    models_group_id,
    data_group_id,
    views_group_id,
    ocr_group_id,
    share_ext_group_id,
    utils_group_id,
    res_group_id
])

products_group_id = gen_id("GROUP_Products")
add_group(products_group_id, "Products", None, [app_product_id, share_product_id])

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

# PBXNativeTarget section
pbx.append("\n/* Begin PBXNativeTarget section */")
# Main App Target
pbx.append(f"\t\t{target_id} /* SpendDrop */ = {{")
pbx.append("\t\t\tisa = PBXNativeTarget;")
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_target_id} /* Build configuration list for PBXNativeTarget \"SpendDrop\" */;")
pbx.append("\t\t\tbuildPhases = (")
pbx.append(f"\t\t\t\t{sources_phase_id} /* Sources */,")
pbx.append(f"\t\t\t\t{frameworks_phase_id} /* Frameworks */,")
pbx.append(f"\t\t\t\t{resources_phase_id} /* Resources */,")
pbx.append(f"\t\t\t\t{embed_extensions_phase_id} /* Embed Foundation Extensions */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tbuildRules = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdependencies = (")
pbx.append(f"\t\t\t\t{target_dependency_id} /* PBXTargetDependency */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = SpendDrop;")
pbx.append("\t\t\tproductName = SpendDrop;")
pbx.append(f"\t\t\tproductReference = {app_product_id} /* SpendDrop.app */;")
pbx.append("\t\t\tproductType = \"com.apple.product-type.application\";")
pbx.append("\t\t};")

# Share Extension Target
pbx.append(f"\t\t{share_target_id} /* SpendDropShare */ = {{")
pbx.append("\t\t\tisa = PBXNativeTarget;")
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_share_id} /* Build configuration list for PBXNativeTarget \"SpendDropShare\" */;")
pbx.append("\t\t\tbuildPhases = (")
pbx.append(f"\t\t\t\t{share_sources_phase_id} /* Sources */,")
pbx.append(f"\t\t\t\t{share_frameworks_phase_id} /* Frameworks */,")
pbx.append(f"\t\t\t\t{share_resources_phase_id} /* Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tbuildRules = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdependencies = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = SpendDropShare;")
pbx.append("\t\t\tproductName = SpendDropShare;")
pbx.append(f"\t\t\tproductReference = {share_product_id} /* SpendDropShare.appex */;")
pbx.append("\t\t\tproductType = \"com.apple.product-type.app-extension\";")
pbx.append("\t\t};")
pbx.append("/* End PBXNativeTarget section */")

# PBXProject section
pbx.append("\n/* Begin PBXProject section */")
pbx.append(f"\t\t{proj_id} /* Project object */ = {{")
pbx.append("\t\t\tisa = PBXProject;")
pbx.append("\t\t\tattributes = {")
pbx.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
pbx.append("\t\t\t\tLastUpgradeCheck = 1600;")
pbx.append("\t\t\t\tTargetAttributes = {")
pbx.append(f"\t\t\t\t\t{target_id} = {{")
pbx.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
pbx.append("\t\t\t\t\t\tProvisioningStyle = Automatic;")
pbx.append("\t\t\t\t\t};")
pbx.append(f"\t\t\t\t\t{share_target_id} = {{")
pbx.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
pbx.append("\t\t\t\t\t\tProvisioningStyle = Automatic;")
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
pbx.append(f"\t\t\t\t{share_target_id} /* SpendDropShare */,")
pbx.append("\t\t\t);")
pbx.append("\t\t};")
pbx.append("/* End PBXProject section */")

# PBXResourcesBuildPhase section
pbx.append("\n/* Begin PBXResourcesBuildPhase section */")
pbx.append(f"\t\t{resources_phase_id} /* Resources */ = {{")
pbx.append("\t\t\tisa = PBXResourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for path, bf_id in app_res_build_files.items():
    filename = os.path.basename(path)
    pbx.append(f"\t\t\t\t{bf_id} /* {filename} in Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")

pbx.append(f"\t\t{share_resources_phase_id} /* Resources */ = {{")
pbx.append("\t\t\tisa = PBXResourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase section
pbx.append("\n/* Begin PBXSourcesBuildPhase section */")
# App sources phase
pbx.append(f"\t\t{sources_phase_id} /* Sources */ = {{")
pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for path in app_source_paths:
    bf_id = app_build_files[path]
    pbx.append(f"\t\t\t\t{bf_id} /* {os.path.basename(path)} in Sources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")

# Share sources phase
pbx.append(f"\t\t{share_sources_phase_id} /* Sources */ = {{")
pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for path in share_source_paths:
    bf_id = share_build_files[path]
    pbx.append(f"\t\t\t\t{bf_id} /* {os.path.basename(path)} in Sources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXSourcesBuildPhase section */")

# PBXTargetDependency section
pbx.append("\n/* Begin PBXTargetDependency section */")
pbx.append(f"\t\t{target_dependency_id} /* PBXTargetDependency */ = {{")
pbx.append("\t\t\tisa = PBXTargetDependency;")
pbx.append(f"\t\t\ttarget = {share_target_id} /* SpendDropShare */;")
pbx.append(f"\t\t\ttargetProxy = {container_proxy_id} /* PBXContainerItemProxy */;")
pbx.append("\t\t};")
pbx.append("/* End PBXTargetDependency section */")

# XCBuildConfiguration section
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
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
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
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
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

# Target App Debug
pbx.append(f"\t\t{debug_config_target_id} /* Debug */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpendDrop/Resources/SpendDrop.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tENABLE_PREVIEWS = YES;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpendDrop/Resources/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spenddrop.SpendDrop;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Debug;")
pbx.append("\t\t};")

# Target App Release
pbx.append(f"\t\t{release_config_target_id} /* Release */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpendDrop/Resources/SpendDrop.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tENABLE_PREVIEWS = YES;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpendDrop/Resources/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spenddrop.SpendDrop;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Release;")
pbx.append("\t\t};")

# Target Share Debug
pbx.append(f"\t\t{debug_config_share_id} /* Debug */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpendDrop/ShareExtension/ShareExtension.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpendDrop/ShareExtension/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t\t\"@executable_path/../../Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spenddrop.SpendDrop.ShareExtension;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSKIP_INSTALL = YES;")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Debug;")
pbx.append("\t\t};")

# Target Share Release
pbx.append(f"\t\t{release_config_share_id} /* Release */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpendDrop/ShareExtension/ShareExtension.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpendDrop/ShareExtension/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t\t\"@executable_path/../../Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spenddrop.SpendDrop.ShareExtension;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSKIP_INSTALL = YES;")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Release;")
pbx.append("\t\t};")
pbx.append("/* End XCBuildConfiguration section */")

# XCConfigurationList section
pbx.append("\n/* Begin XCConfigurationList section */")
# Project config list
pbx.append(f"\t\t{config_list_proj_id} /* Build configuration list for PBXProject \"SpendDrop\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_proj_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_proj_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")

# App target config list
pbx.append(f"\t\t{config_list_target_id} /* Build configuration list for PBXNativeTarget \"SpendDrop\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_target_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_target_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")

# Share target config list
pbx.append(f"\t\t{config_list_share_id} /* Build configuration list for PBXNativeTarget \"SpendDropShare\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_share_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_share_id} /* Release */,")
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

print(f"Generated {pbx_path} successfully with Share Extension target!")

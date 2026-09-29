import os
import hashlib

def gen_id(name):
    # Generates a stable 24-character hexadecimal Xcode identifier
    h = hashlib.sha1(name.encode('utf-8')).hexdigest().upper()
    return h[:24]

# All project files
all_files = [
    # App
    ("SpenDrop/App/SpenDropApp.swift", False),
    # Models
    ("SpenDrop/Models/Expense.swift", False),
    ("SpenDrop/Models/ExpenseCategory.swift", False),
    ("SpenDrop/Models/PaymentSource.swift", False),
    ("SpenDrop/Models/PaymentChannel.swift", False),
    ("SpenDrop/Models/ExpenseSourceType.swift", False),
    ("SpenDrop/Models/PayBookProfile.swift", False),
    ("SpenDrop/Models/PayBookPaymentMethod.swift", False),
    ("SpenDrop/Models/PayBookContact.swift", False),
    ("SpenDrop/Models/Account.swift", False),
    ("SpenDrop/Models/ExpenseShare.swift", False),
    ("SpenDrop/Models/MoneyMovement.swift", False),
    # Data
    ("SpenDrop/Data/ExpenseDataContainer.swift", False),
    ("SpenDrop/Data/DuplicateDetector.swift", False),
    ("SpenDrop/Data/TransactionFilterEngine.swift", False),
    ("SpenDrop/Data/TransactionReconciliationEngine.swift", False),
    ("SpenDrop/Data/SampleData.swift", False),
    ("SpenDrop/Data/UserDataBackupService.swift", False),
    ("SpenDrop/Data/DataSafetyTests.swift", False),
    ("SpenDrop/Data/SchemaVersions.swift", False),
    ("SpenDrop/Data/AccountLinker.swift", False),
    ("SpenDrop/Data/Money.swift", False),
    ("SpenDrop/Data/SplitCalculator.swift", False),
    ("SpenDrop/Data/FinancialCalculator.swift", False),
    ("SpenDrop/Data/FinancialModelTests.swift", False),
    ("SpenDrop/Data/MoneyMovementDraft.swift", False),
    ("SpenDrop/Data/AccountFeatureTests.swift", False),
    # Utils
    ("SpenDrop/Utils/CurrencyFormatter.swift", False),
    ("SpenDrop/Utils/HapticFeedback.swift", False),
    # OCR (Milestone 2)
    ("SpenDrop/OCR/OCRService.swift", False),
    ("SpenDrop/OCR/ParsedTransaction.swift", False),
    ("SpenDrop/OCR/MonetaryCandidate.swift", False),
    ("SpenDrop/OCR/PaymentProviderDetector.swift", False),
    ("SpenDrop/OCR/MerchantDetector.swift", False),
    ("SpenDrop/OCR/CategoryDetector.swift", False),
    ("SpenDrop/OCR/TransactionParser.swift", False),
    ("SpenDrop/OCR/ImageStorageService.swift", False),
    ("SpenDrop/OCR/ImagePipelineDiagnostics.swift", False),
    ("SpenDrop/OCR/TransactionParserTests.swift", False),
    # Views
    ("SpenDrop/Views/MainTabView.swift", False),
    ("SpenDrop/Views/Dashboard/DashboardView.swift", False),
    ("SpenDrop/Views/Dashboard/Components/SpendingSummaryCard.swift", False),
    ("SpenDrop/Views/Dashboard/Components/QuickCashButton.swift", False),
    ("SpenDrop/Views/Expenses/ExpensesView.swift", False),
    ("SpenDrop/Views/Expenses/ExpenseDetailView.swift", False),
    ("SpenDrop/Views/Expenses/EditExpenseView.swift", False),
    ("SpenDrop/Views/Expenses/Components/ExpenseRowView.swift", False),
    ("SpenDrop/Views/Expenses/Components/PaymentLogoView.swift", False),
    ("SpenDrop/Views/Expenses/Components/FilterBarView.swift", False),
    ("SpenDrop/Views/PayBook/PayBookView.swift", False),
    ("SpenDrop/Views/PayBook/PayBookDetailView.swift", False),
    ("SpenDrop/Views/PayBook/AddPayBookProfileView.swift", False),
    ("SpenDrop/Views/PayBook/EditPayBookProfileView.swift", False),
    ("SpenDrop/Views/PayBook/AddPaymentMethodView.swift", False),
    ("SpenDrop/Views/PayBook/EditPaymentMethodView.swift", False),
    ("SpenDrop/Views/PayBook/PayBookPickerSheet.swift", False),
    ("SpenDrop/Views/AddExpense/AddExpenseView.swift", False),
    ("SpenDrop/Views/Review/ExpenseReviewView.swift", False),
    ("SpenDrop/Views/Analytics/AnalyticsView.swift", False),
    ("SpenDrop/Views/Settings/SettingsView.swift", False),
    ("SpenDrop/Views/Settings/Components/ParserSelfTestView.swift", False),
    ("SpenDrop/Views/More/MoreView.swift", False),
    ("SpenDrop/Views/Accounts/AccountsView.swift", False),
    ("SpenDrop/Views/Money/MoneyMovementFormView.swift", False),
    # Share Extension (Milestone 3)
    ("SpenDrop/ShareExtension/ShareViewController.swift", False),
    ("SpenDrop/ShareExtension/ShareExtensionView.swift", False),
    ("SpenDrop/ShareExtension/Info.plist", False),
    ("SpenDrop/ShareExtension/ShareExtension.entitlements", False),
    ("SpenDrop/Data/SplitDraft.swift", False),
    ("SpenDrop/Data/Tests/TestKit.swift", False),
    ("SpenDrop/Data/Tests/SplitFeatureTests.swift", False),
    ("SpenDrop/Views/Split/SplitEditorView.swift", False),
    ("SpenDrop/Data/PersonLedger.swift", False),
    ("SpenDrop/Data/Tests/PeopleBalanceTests.swift", False),
    ("SpenDrop/Data/ActivityFeed.swift", False),
    ("SpenDrop/Data/Tests/ActivityFeedTests.swift", False),
    ("SpenDrop/Models/ClassificationRule.swift", False),
    ("SpenDrop/Data/TransactionClassifier.swift", False),
    ("SpenDrop/Data/MovementDuplicateDetector.swift", False),
    ("SpenDrop/OCR/DirectionDetector.swift", False),
    ("SpenDrop/Data/ApplePayAutomation.swift", False),
    ("SpenDrop/App/ApplePayIntent.swift", False),
    ("SpenDrop/Data/PeriodGrouping.swift", False),
    ("SpenDrop/Data/Tests/Phase7Tests.swift", False),
    ("SpenDrop/Data/Cloud/CloudCore.swift", False),
    ("SpenDrop/Data/Cloud/AuthService.swift", False),
    ("SpenDrop/Data/Cloud/CloudBackupService.swift", False),
    ("SpenDrop/Views/Account/AccountView.swift", False),
    ("SpenDrop/Data/Tests/CloudTests.swift", False),
    ("SpenDrop/Data/Tests/HardeningTests.swift", False),
    # Resources
    ("SpenDrop/Resources/Assets.xcassets", True),
    ("SpenDrop/Resources/CloudConfig", True),
    ("SpenDrop/Resources/Info.plist", False),
    ("SpenDrop/Resources/SpenDrop.entitlements", False),
    ("SpenDrop/Resources/DiagnosticSamples/sample_screenshot.png", True),
    ("SpenDrop/Resources/DiagnosticSamples/sample_photo.jpg", True),
    ("SpenDrop/Resources/DiagnosticSamples/sample_camera.heic", True),
]

# Files compiled by main app target
app_source_paths = [path for path, is_res in all_files if path.endswith(".swift") and not path.startswith("SpenDrop/ShareExtension/")]

# Resources copied by main app target
app_res_paths = [path for path, is_res in all_files if is_res]

# Files compiled by Share Extension target
share_source_paths = [
    "SpenDrop/ShareExtension/ShareViewController.swift",
    "SpenDrop/ShareExtension/ShareExtensionView.swift",
    "SpenDrop/Models/Expense.swift",
    "SpenDrop/Models/ExpenseCategory.swift",
    "SpenDrop/Models/PaymentSource.swift",
    "SpenDrop/Models/PaymentChannel.swift",
    "SpenDrop/Models/ExpenseSourceType.swift",
    "SpenDrop/Models/PayBookProfile.swift",
    "SpenDrop/Models/PayBookPaymentMethod.swift",
    "SpenDrop/Models/PayBookContact.swift",
    "SpenDrop/Models/Account.swift",
    "SpenDrop/Models/ExpenseShare.swift",
    "SpenDrop/Models/MoneyMovement.swift",
    "SpenDrop/Data/ExpenseDataContainer.swift",
    "SpenDrop/Data/SchemaVersions.swift",
    "SpenDrop/Data/AccountLinker.swift",
    "SpenDrop/Data/DuplicateDetector.swift",
    "SpenDrop/Data/TransactionReconciliationEngine.swift",
    "SpenDrop/Data/SampleData.swift",
    "SpenDrop/Data/UserDataBackupService.swift",
    "SpenDrop/OCR/OCRService.swift",
    "SpenDrop/OCR/ParsedTransaction.swift",
    "SpenDrop/OCR/MonetaryCandidate.swift",
    "SpenDrop/OCR/PaymentProviderDetector.swift",
    "SpenDrop/OCR/MerchantDetector.swift",
    "SpenDrop/OCR/CategoryDetector.swift",
    "SpenDrop/OCR/TransactionParser.swift",
    "SpenDrop/OCR/ImageStorageService.swift",
    "SpenDrop/Utils/CurrencyFormatter.swift",
    "SpenDrop/Utils/HapticFeedback.swift",
    "SpenDrop/Models/ClassificationRule.swift",
    "SpenDrop/Data/TransactionClassifier.swift",
    "SpenDrop/Data/MovementDuplicateDetector.swift",
    "SpenDrop/OCR/DirectionDetector.swift",
    "SpenDrop/Data/Money.swift",
]

# IDs for Main App Target
proj_id = gen_id("SpenDrop_Project")
target_id = gen_id("SpenDrop_NativeTarget")
sources_phase_id = gen_id("SpenDrop_SourcesPhase")
resources_phase_id = gen_id("SpenDrop_ResourcesPhase")
frameworks_phase_id = gen_id("SpenDrop_FrameworksPhase")
embed_extensions_phase_id = gen_id("SpenDrop_EmbedExtensionsPhase")
app_product_id = gen_id("SpenDrop_AppProduct")

debug_config_target_id = gen_id("SpenDrop_Debug_Target")
release_config_target_id = gen_id("SpenDrop_Release_Target")
config_list_target_id = gen_id("SpenDrop_ConfigList_Target")

debug_config_proj_id = gen_id("SpenDrop_Debug_Proj")
release_config_proj_id = gen_id("SpenDrop_Release_Proj")
config_list_proj_id = gen_id("SpenDrop_ConfigList_Proj")

# IDs for Share Extension Target
share_target_id = gen_id("SpenDropShare_NativeTarget")
share_sources_phase_id = gen_id("SpenDropShare_SourcesPhase")
share_resources_phase_id = gen_id("SpenDropShare_ResourcesPhase")
share_frameworks_phase_id = gen_id("SpenDropShare_FrameworksPhase")
share_product_id = gen_id("SpenDropShare_Product")

debug_config_share_id = gen_id("SpenDropShare_Debug_Target")
release_config_share_id = gen_id("SpenDropShare_Release_Target")
config_list_share_id = gen_id("SpenDropShare_ConfigList_Target")

# Dependency IDs
container_proxy_id = gen_id("SpenDrop_ContainerItemProxy_Share")
target_dependency_id = gen_id("SpenDrop_TargetDependency_Share")
embed_appex_build_file_id = gen_id("SpenDrop_EmbedAppexBuildFile")

main_group_id = gen_id("SpenDrop_MainGroup")
products_group_id = gen_id("SpenDrop_ProductsGroup")

# PBXFileReference IDs
file_refs = {}
for path, _ in all_files:
    file_refs[path] = gen_id(f"FREF_{path}")

# UI test target (SpenDropUITests): launches the app with --ui-testing (fresh temporary database)
# and drives it like a user. Not part of the app or the Share Extension.
uit_source_paths = ["SpenDropUITests/SpenDropUITests.swift"]
for path in uit_source_paths:
    file_refs[path] = gen_id(f"FREF_{path}")
uit_build_files = {path: gen_id(f"BF_UIT_{path}") for path in uit_source_paths}
uit_target_id = gen_id("SpenDropUITests_NativeTarget")
uit_product_id = gen_id("SpenDropUITests_Product")
uit_sources_phase_id = gen_id("SpenDropUITests_SourcesPhase")
uit_frameworks_phase_id = gen_id("SpenDropUITests_FrameworksPhase")
uit_resources_phase_id = gen_id("SpenDropUITests_ResourcesPhase")
uit_debug_id = gen_id("SpenDropUITests_Debug")
uit_release_id = gen_id("SpenDropUITests_Release")
uit_config_list_id = gen_id("SpenDropUITests_ConfigList")
uit_proxy_id = gen_id("SpenDropUITests_ContainerItemProxy_App")
uit_dependency_id = gen_id("SpenDropUITests_TargetDependency_App")
uit_group_id = gen_id("GROUP_SpenDropUITests")

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
pbx.append(f"\t\t{embed_appex_build_file_id} /* SpenDropShare.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {share_product_id} /* SpenDropShare.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
pbx.append("/* End PBXBuildFile section */")

# PBXContainerItemProxy section
pbx.append("\n/* Begin PBXContainerItemProxy section */")
pbx.append(f"\t\t{container_proxy_id} /* PBXContainerItemProxy */ = {{")
pbx.append("\t\t\tisa = PBXContainerItemProxy;")
pbx.append(f"\t\t\tcontainerPortal = {proj_id} /* Project object */;")
pbx.append("\t\t\tproxyType = 1;")
pbx.append(f"\t\t\tremoteGlobalIDString = {share_target_id};")
pbx.append("\t\t\tremoteInfo = SpenDropShare;")
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
pbx.append(f"\t\t\t\t{embed_appex_build_file_id} /* SpenDropShare.appex in Embed Foundation Extensions */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = \"Embed Foundation Extensions\";")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXCopyFilesBuildPhase section */")

# PBXFileReference section
pbx.append("\n/* Begin PBXFileReference section */")
pbx.append(f"\t\t{app_product_id} /* SpenDrop.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SpenDrop.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
pbx.append(f"\t\t{share_product_id} /* SpenDropShare.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = SpenDropShare.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")

for path, fref_id in file_refs.items():
    filename = os.path.basename(path)
    if path.endswith(".swift"):
        ft = "sourcecode.swift"
    elif path.endswith(".xcassets"):
        ft = "folder.assetcatalog"
    elif path.endswith("/CloudConfig"):
        # Folder reference: its contents (e.g. the git-ignored SupabaseConfig.plist) are copied when present.
        ft = "folder"
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
    file_refs["SpenDrop/Views/Dashboard/Components/SpendingSummaryCard.swift"],
    file_refs["SpenDrop/Views/Dashboard/Components/QuickCashButton.swift"]
])

exp_comp_id = gen_id("GROUP_Views_Expenses_Components")
add_group(exp_comp_id, "Components", "Components", [
    file_refs["SpenDrop/Views/Expenses/Components/ExpenseRowView.swift"],
    file_refs["SpenDrop/Views/Expenses/Components/PaymentLogoView.swift"],
    file_refs["SpenDrop/Views/Expenses/Components/FilterBarView.swift"]
])

settings_comp_id = gen_id("GROUP_Views_Settings_Components")
add_group(settings_comp_id, "Components", "Components", [
    file_refs["SpenDrop/Views/Settings/Components/ParserSelfTestView.swift"]
])

dash_group_id = gen_id("GROUP_Views_Dashboard")
add_group(dash_group_id, "Dashboard", "Dashboard", [
    dash_comp_id,
    file_refs["SpenDrop/Views/Dashboard/DashboardView.swift"]
])

exp_group_id = gen_id("GROUP_Views_Expenses")
add_group(exp_group_id, "Expenses", "Expenses", [
    exp_comp_id,
    file_refs["SpenDrop/Views/Expenses/ExpensesView.swift"],
    file_refs["SpenDrop/Views/Expenses/ExpenseDetailView.swift"],
    file_refs["SpenDrop/Views/Expenses/EditExpenseView.swift"]
])

addexp_group_id = gen_id("GROUP_Views_AddExpense")
add_group(addexp_group_id, "AddExpense", "AddExpense", [
    file_refs["SpenDrop/Views/AddExpense/AddExpenseView.swift"]
])

review_group_id = gen_id("GROUP_Views_Review")
add_group(review_group_id, "Review", "Review", [
    file_refs["SpenDrop/Views/Review/ExpenseReviewView.swift"]
])

analytics_group_id = gen_id("GROUP_Views_Analytics")
add_group(analytics_group_id, "Analytics", "Analytics", [
    file_refs["SpenDrop/Views/Analytics/AnalyticsView.swift"]
])

settings_group_id = gen_id("GROUP_Views_Settings")
add_group(settings_group_id, "Settings", "Settings", [
    settings_comp_id,
    file_refs["SpenDrop/Views/Settings/SettingsView.swift"]
])

paybook_group_id = gen_id("GROUP_Views_PayBook")
add_group(paybook_group_id, "PayBook", "PayBook", [
    file_refs["SpenDrop/Views/PayBook/PayBookView.swift"],
    file_refs["SpenDrop/Views/PayBook/PayBookDetailView.swift"],
    file_refs["SpenDrop/Views/PayBook/AddPayBookProfileView.swift"],
    file_refs["SpenDrop/Views/PayBook/EditPayBookProfileView.swift"],
    file_refs["SpenDrop/Views/PayBook/AddPaymentMethodView.swift"],
    file_refs["SpenDrop/Views/PayBook/EditPaymentMethodView.swift"],
    file_refs["SpenDrop/Views/PayBook/PayBookPickerSheet.swift"]
])

more_group_id = gen_id("GROUP_Views_More")
add_group(more_group_id, "More", "More", [
    file_refs["SpenDrop/Views/More/MoreView.swift"]
])

accounts_group_id = gen_id("GROUP_Views_Accounts")
add_group(accounts_group_id, "Accounts", "Accounts", [
    file_refs["SpenDrop/Views/Accounts/AccountsView.swift"]
])

money_group_id = gen_id("GROUP_Views_Money")
add_group(money_group_id, "Money", "Money", [
    file_refs["SpenDrop/Views/Money/MoneyMovementFormView.swift"]
])

split_group_id = gen_id("GROUP_split_group_id")
add_group(split_group_id, "Split", "Split", [
    file_refs["SpenDrop/Views/Split/SplitEditorView.swift"]
])

account_views_group_id = gen_id("GROUP_account_views_group_id")
add_group(account_views_group_id, "Account", "Account", [
    file_refs["SpenDrop/Views/Account/AccountView.swift"]
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
    more_group_id,
    accounts_group_id,
    money_group_id,
    file_refs["SpenDrop/Views/MainTabView.swift"],
    split_group_id,
    account_views_group_id
])

ocr_group_id = gen_id("GROUP_OCR")
add_group(ocr_group_id, "OCR", "OCR", [
    file_refs["SpenDrop/OCR/OCRService.swift"],
    file_refs["SpenDrop/OCR/ParsedTransaction.swift"],
    file_refs["SpenDrop/OCR/MonetaryCandidate.swift"],
    file_refs["SpenDrop/OCR/PaymentProviderDetector.swift"],
    file_refs["SpenDrop/OCR/MerchantDetector.swift"],
    file_refs["SpenDrop/OCR/CategoryDetector.swift"],
    file_refs["SpenDrop/OCR/TransactionParser.swift"],
    file_refs["SpenDrop/OCR/ImageStorageService.swift"],
    file_refs["SpenDrop/OCR/ImagePipelineDiagnostics.swift"],
    file_refs["SpenDrop/OCR/TransactionParserTests.swift"],
    file_refs["SpenDrop/OCR/DirectionDetector.swift"]
])

app_group_id = gen_id("GROUP_App")
add_group(app_group_id, "App", "App", [
    file_refs["SpenDrop/App/SpenDropApp.swift"],
    file_refs["SpenDrop/App/ApplePayIntent.swift"]
])

models_group_id = gen_id("GROUP_Models")
add_group(models_group_id, "Models", "Models", [
    file_refs["SpenDrop/Models/Expense.swift"],
    file_refs["SpenDrop/Models/ExpenseCategory.swift"],
    file_refs["SpenDrop/Models/PaymentSource.swift"],
    file_refs["SpenDrop/Models/PaymentChannel.swift"],
    file_refs["SpenDrop/Models/ExpenseSourceType.swift"],
    file_refs["SpenDrop/Models/PayBookProfile.swift"],
    file_refs["SpenDrop/Models/PayBookPaymentMethod.swift"],
    file_refs["SpenDrop/Models/PayBookContact.swift"],
    file_refs["SpenDrop/Models/Account.swift"],
    file_refs["SpenDrop/Models/ExpenseShare.swift"],
    file_refs["SpenDrop/Models/MoneyMovement.swift"],
    file_refs["SpenDrop/Models/ClassificationRule.swift"]
])

data_tests_group_id = gen_id("GROUP_data_tests_group_id")
add_group(data_tests_group_id, "Tests", "Tests", [
    file_refs["SpenDrop/Data/Tests/TestKit.swift"],
    file_refs["SpenDrop/Data/Tests/SplitFeatureTests.swift"],
    file_refs["SpenDrop/Data/Tests/PeopleBalanceTests.swift"],
    file_refs["SpenDrop/Data/Tests/ActivityFeedTests.swift"],
    file_refs["SpenDrop/Data/Tests/Phase7Tests.swift"],
    file_refs["SpenDrop/Data/Tests/CloudTests.swift"],
    file_refs["SpenDrop/Data/Tests/HardeningTests.swift"]
])

data_cloud_group_id = gen_id("GROUP_data_cloud_group_id")
add_group(data_cloud_group_id, "Cloud", "Cloud", [
    file_refs["SpenDrop/Data/Cloud/CloudCore.swift"],
    file_refs["SpenDrop/Data/Cloud/AuthService.swift"],
    file_refs["SpenDrop/Data/Cloud/CloudBackupService.swift"]
])

data_group_id = gen_id("GROUP_Data")
add_group(data_group_id, "Data", "Data", [
    file_refs["SpenDrop/Data/ExpenseDataContainer.swift"],
    file_refs["SpenDrop/Data/DuplicateDetector.swift"],
    file_refs["SpenDrop/Data/TransactionFilterEngine.swift"],
    file_refs["SpenDrop/Data/TransactionReconciliationEngine.swift"],
    file_refs["SpenDrop/Data/SampleData.swift"],
    file_refs["SpenDrop/Data/UserDataBackupService.swift"],
    file_refs["SpenDrop/Data/DataSafetyTests.swift"],
    file_refs["SpenDrop/Data/SchemaVersions.swift"],
    file_refs["SpenDrop/Data/AccountLinker.swift"],
    file_refs["SpenDrop/Data/Money.swift"],
    file_refs["SpenDrop/Data/SplitCalculator.swift"],
    file_refs["SpenDrop/Data/FinancialCalculator.swift"],
    file_refs["SpenDrop/Data/FinancialModelTests.swift"],
    file_refs["SpenDrop/Data/MoneyMovementDraft.swift"],
    file_refs["SpenDrop/Data/AccountFeatureTests.swift"],
    file_refs["SpenDrop/Data/SplitDraft.swift"],
    data_tests_group_id,
    file_refs["SpenDrop/Data/PersonLedger.swift"],
    file_refs["SpenDrop/Data/ActivityFeed.swift"],
    file_refs["SpenDrop/Data/TransactionClassifier.swift"],
    file_refs["SpenDrop/Data/MovementDuplicateDetector.swift"],
    file_refs["SpenDrop/Data/ApplePayAutomation.swift"],
    file_refs["SpenDrop/Data/PeriodGrouping.swift"],
    data_cloud_group_id
])

utils_group_id = gen_id("GROUP_Utils")
add_group(utils_group_id, "Utils", "Utils", [
    file_refs["SpenDrop/Utils/CurrencyFormatter.swift"],
    file_refs["SpenDrop/Utils/HapticFeedback.swift"]
])

diag_samples_group_id = gen_id("GROUP_DiagnosticSamples")
add_group(diag_samples_group_id, "DiagnosticSamples", "DiagnosticSamples", [
    file_refs["SpenDrop/Resources/DiagnosticSamples/sample_screenshot.png"],
    file_refs["SpenDrop/Resources/DiagnosticSamples/sample_photo.jpg"],
    file_refs["SpenDrop/Resources/DiagnosticSamples/sample_camera.heic"]
])

res_group_id = gen_id("GROUP_Resources")
add_group(res_group_id, "Resources", "Resources", [
    file_refs["SpenDrop/Resources/Assets.xcassets"],
    file_refs["SpenDrop/Resources/CloudConfig"],
    file_refs["SpenDrop/Resources/Info.plist"],
    file_refs["SpenDrop/Resources/SpenDrop.entitlements"],
    diag_samples_group_id
])

share_ext_group_id = gen_id("GROUP_ShareExtension")
add_group(share_ext_group_id, "ShareExtension", "ShareExtension", [
    file_refs["SpenDrop/ShareExtension/ShareViewController.swift"],
    file_refs["SpenDrop/ShareExtension/ShareExtensionView.swift"],
    file_refs["SpenDrop/ShareExtension/Info.plist"],
    file_refs["SpenDrop/ShareExtension/ShareExtension.entitlements"]
])

spendrop_group_id = gen_id("GROUP_SpenDrop_Folder")
add_group(spendrop_group_id, "SpenDrop", "SpenDrop", [
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
add_group(products_group_id, "Products", None, [app_product_id, share_product_id, uit_product_id])
add_group(uit_group_id, "SpenDropUITests", "SpenDropUITests", [file_refs[p] for p in uit_source_paths])

add_group(main_group_id, None, None, [spendrop_group_id, uit_group_id, products_group_id])

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
pbx.append(f"\t\t{target_id} /* SpenDrop */ = {{")
pbx.append("\t\t\tisa = PBXNativeTarget;")
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_target_id} /* Build configuration list for PBXNativeTarget \"SpenDrop\" */;")
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
pbx.append("\t\t\tname = SpenDrop;")
pbx.append("\t\t\tproductName = SpenDrop;")
pbx.append(f"\t\t\tproductReference = {app_product_id} /* SpenDrop.app */;")
pbx.append("\t\t\tproductType = \"com.apple.product-type.application\";")
pbx.append("\t\t};")

# Share Extension Target
pbx.append(f"\t\t{share_target_id} /* SpenDropShare */ = {{")
pbx.append("\t\t\tisa = PBXNativeTarget;")
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_share_id} /* Build configuration list for PBXNativeTarget \"SpenDropShare\" */;")
pbx.append("\t\t\tbuildPhases = (")
pbx.append(f"\t\t\t\t{share_sources_phase_id} /* Sources */,")
pbx.append(f"\t\t\t\t{share_frameworks_phase_id} /* Frameworks */,")
pbx.append(f"\t\t\t\t{share_resources_phase_id} /* Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tbuildRules = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdependencies = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = SpenDropShare;")
pbx.append("\t\t\tproductName = SpenDropShare;")
pbx.append(f"\t\t\tproductReference = {share_product_id} /* SpenDropShare.appex */;")
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
pbx.append(f"\t\t\tbuildConfigurationList = {config_list_proj_id} /* Build configuration list for PBXProject \"SpenDrop\" */;")
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
pbx.append(f"\t\t\t\t{target_id} /* SpenDrop */,")
pbx.append(f"\t\t\t\t{share_target_id} /* SpenDropShare */,")
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
pbx.append(f"\t\t\ttarget = {share_target_id} /* SpenDropShare */;")
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
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpenDrop/Resources/SpenDrop.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tENABLE_PREVIEWS = YES;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpenDrop/Resources/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spendrop.SpenDrop;")
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
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpenDrop/Resources/SpenDrop.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_ASSET_PATHS = \"\";")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tENABLE_PREVIEWS = YES;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpenDrop/Resources/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spendrop.SpenDrop;")
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
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpenDrop/ShareExtension/ShareExtension.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpenDrop/ShareExtension/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t\t\"@executable_path/../../Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spendrop.SpenDrop.ShareExtension;")
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
pbx.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"SpenDrop/ShareExtension/ShareExtension.entitlements\";")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = \"SpenDrop/ShareExtension/Info.plist\";")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
pbx.append("\t\t\t\t\t\"$(inherited)\",")
pbx.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
pbx.append("\t\t\t\t\t\"@executable_path/../../Frameworks\",")
pbx.append("\t\t\t\t);")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.3.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spendrop.SpenDrop.ShareExtension;")
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
pbx.append(f"\t\t{config_list_proj_id} /* Build configuration list for PBXProject \"SpenDrop\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_proj_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_proj_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")

# App target config list
pbx.append(f"\t\t{config_list_target_id} /* Build configuration list for PBXNativeTarget \"SpenDrop\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{debug_config_target_id} /* Debug */,")
pbx.append(f"\t\t\t\t{release_config_target_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")

# Share target config list
pbx.append(f"\t\t{config_list_share_id} /* Build configuration list for PBXNativeTarget \"SpenDropShare\" */ = {{")
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

# ---- UI test target entries, inserted into their sections ----
def insert_before(marker, lines):
    i = pbx.index(marker)
    pbx[i:i] = lines

def insert_after(anchor, lines):
    i = pbx.index(anchor) + 1
    pbx[i:i] = lines

insert_before("/* End PBXBuildFile section */",
    [f"\t\t{bf} /* {os.path.basename(p)} in UITest Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[p]} /* {os.path.basename(p)} */; }};" for p, bf in uit_build_files.items()])
insert_before("/* End PBXContainerItemProxy section */", [
    f"\t\t{uit_proxy_id} /* PBXContainerItemProxy */ = {{",
    "\t\t\tisa = PBXContainerItemProxy;",
    f"\t\t\tcontainerPortal = {proj_id} /* Project object */;",
    "\t\t\tproxyType = 1;",
    f"\t\t\tremoteGlobalIDString = {target_id};",
    "\t\t\tremoteInfo = SpenDrop;",
    "\t\t};"])
insert_before("/* End PBXFileReference section */", [
    f"\t\t{uit_product_id} /* SpenDropUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SpenDropUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"])
insert_before("/* End PBXFrameworksBuildPhase section */", [
    f"\t\t{uit_frameworks_phase_id} /* Frameworks */ = {{",
    "\t\t\tisa = PBXFrameworksBuildPhase;",
    "\t\t\tbuildActionMask = 2147483647;",
    "\t\t\tfiles = (",
    "\t\t\t);",
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
    "\t\t};"])
insert_before("/* End PBXNativeTarget section */", [
    f"\t\t{uit_target_id} /* SpenDropUITests */ = {{",
    "\t\t\tisa = PBXNativeTarget;",
    f"\t\t\tbuildConfigurationList = {uit_config_list_id} /* Build configuration list for PBXNativeTarget \"SpenDropUITests\" */;",
    "\t\t\tbuildPhases = (",
    f"\t\t\t\t{uit_sources_phase_id} /* Sources */,",
    f"\t\t\t\t{uit_frameworks_phase_id} /* Frameworks */,",
    f"\t\t\t\t{uit_resources_phase_id} /* Resources */,",
    "\t\t\t);",
    "\t\t\tbuildRules = (",
    "\t\t\t);",
    "\t\t\tdependencies = (",
    f"\t\t\t\t{uit_dependency_id} /* PBXTargetDependency */,",
    "\t\t\t);",
    "\t\t\tname = SpenDropUITests;",
    "\t\t\tproductName = SpenDropUITests;",
    f"\t\t\tproductReference = {uit_product_id} /* SpenDropUITests.xctest */;",
    "\t\t\tproductType = \"com.apple.product-type.bundle.ui-testing\";",
    "\t\t};"])
insert_before(f"\t\t\t\t\t{share_target_id} = {{", [
    f"\t\t\t\t\t{uit_target_id} = {{",
    "\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;",
    "\t\t\t\t\t\tProvisioningStyle = Automatic;",
    f"\t\t\t\t\t\tTestTargetID = {target_id};",
    "\t\t\t\t\t};"])
insert_after(f"\t\t\t\t{share_target_id} /* SpenDropShare */,", [f"\t\t\t\t{uit_target_id} /* SpenDropUITests */,"])
insert_before("/* End PBXResourcesBuildPhase section */", [
    f"\t\t{uit_resources_phase_id} /* Resources */ = {{",
    "\t\t\tisa = PBXResourcesBuildPhase;",
    "\t\t\tbuildActionMask = 2147483647;",
    "\t\t\tfiles = (",
    "\t\t\t);",
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
    "\t\t};"])
insert_before("/* End PBXSourcesBuildPhase section */",
    [f"\t\t{uit_sources_phase_id} /* Sources */ = {{",
     "\t\t\tisa = PBXSourcesBuildPhase;",
     "\t\t\tbuildActionMask = 2147483647;",
     "\t\t\tfiles = ("] +
    [f"\t\t\t\t{bf} /* {os.path.basename(p)} in Sources */," for p, bf in uit_build_files.items()] +
    ["\t\t\t);",
     "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
     "\t\t};"])
insert_before("/* End PBXTargetDependency section */", [
    f"\t\t{uit_dependency_id} /* PBXTargetDependency */ = {{",
    "\t\t\tisa = PBXTargetDependency;",
    f"\t\t\ttarget = {target_id} /* SpenDrop */;",
    f"\t\t\ttargetProxy = {uit_proxy_id} /* PBXContainerItemProxy */;",
    "\t\t};"])
def uit_config(cid, name):
    return [f"\t\t{cid} /* {name} */ = {{",
            "\t\t\tisa = XCBuildConfiguration;",
            "\t\t\tbuildSettings = {",
            "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
            "\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
            "\t\t\t\tDEVELOPMENT_TEAM = 772ZMVR7WF;",
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;",
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;",
            "\t\t\t\tMARKETING_VERSION = 1.0;",
            "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.spendrop.SpenDropUITests;",
            "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";",
            "\t\t\t\tSWIFT_VERSION = 5.0;",
            "\t\t\t\tTARGETED_DEVICE_FAMILY = \"1\";",
            "\t\t\t\tTEST_TARGET_NAME = SpenDrop;",
            "\t\t\t};",
            f"\t\t\tname = {name};",
            "\t\t};"]
insert_before("/* End XCBuildConfiguration section */", uit_config(uit_debug_id, "Debug") + uit_config(uit_release_id, "Release"))
insert_before("/* End XCConfigurationList section */", [
    f"\t\t{uit_config_list_id} /* Build configuration list for PBXNativeTarget \"SpenDropUITests\" */ = {{",
    "\t\t\tisa = XCConfigurationList;",
    "\t\t\tbuildConfigurations = (",
    f"\t\t\t\t{uit_debug_id} /* Debug */,",
    f"\t\t\t\t{uit_release_id} /* Release */,",
    "\t\t\t);",
    "\t\t\tdefaultConfigurationIsVisible = 0;",
    "\t\t\tdefaultConfigurationName = Release;",
    "\t\t};"])

output_dir = "SpenDrop.xcodeproj"
os.makedirs(output_dir, exist_ok=True)
pbx_path = os.path.join(output_dir, "project.pbxproj")
with open(pbx_path, "w", encoding="utf-8") as f:
    f.write("\n".join(pbx) + "\n")

print(f"Generated {pbx_path} successfully with Share Extension target!")

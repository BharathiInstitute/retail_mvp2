# 📁 Project File Renaming Plan for Better Understanding

This document provides a comprehensive plan to rename files in the retail_mvp2 project for better clarity and understanding. The project is a **Retail POS (Point of Sale) Management System** with modules for sales, inventory, customers, accounting, and more.

---

## ⚠️ SAFETY RULES FOR FILE RENAMING

**IMPORTANT: Follow these rules to avoid breaking Firebase/backend functionality:**

### ❌ NEVER Do:
1. **Never rename files to match Firebase collection names** - Avoid confusion with Firestore paths like `stores`, `products`, `customers`, `invoices`, `inventory`
2. **Never modify Firebase-related files**:
   - `firebase.json`
   - `firestore.rules`
   - `firestore.indexes.json`
   - `storage.rules`
   - `functions/*.js` (backend JavaScript)
3. **Never change string literals** that reference:
   - Firestore collection paths (`'stores'`, `'products'`, `'customers'`, `'invoices'`, etc.)
   - Storage bucket paths
   - Cloud Function names

### ✅ SAFE to Rename:
- Pure UI widgets/screens (layout, styling)
- Theme/styling utilities
- Navigation helpers
- State management files (providers)
- Utility/helper files

### 🔍 Always Verify After Renaming:
1. Run `flutter analyze` to check for broken imports
2. Test CRUD operations still work
3. Confirm backend functions remain untouched

---

## 📋 Summary of Project Structure

The project is organized as follows:
- **lib/** - Main Flutter application code
  - **core/** - Shared utilities, theme, widgets, authentication
  - **modules/** - Feature-specific modules (POS, Inventory, CRM, etc.)

---

## 🔄 RENAMING PLAN

### 📂 **lib/ (Root Level Files)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `main.dart` | `main.dart` ✅ (Keep) | App entry point - initializes Firebase and runs app |
| `app_shell.dart` | `app_router_and_shell.dart` | Main app container with GoRouter navigation, side menu, and route definitions |
| `firebase_options.dart` | `firebase_options.dart` ✅ (Keep) | Firebase configuration (auto-generated) |

---

### 📂 **lib/core/ (Core Utilities)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `app_keys.dart` | `global_navigator_keys.dart` | Global navigator and scaffold messenger keys for cross-context access |
| `data_layout.dart` | `database_migration_mode.dart` | Defines database layout mode (top-level, subcollections, dual) for migration |
| `logging.dart` | `debug_logger_helper.dart` | Structured logging utility for debugging async operations |
| `permissions.dart` | `user_permissions_provider.dart` | User role/permission system with screen-level access control |
| `store_scoped_refs.dart` | `firestore_store_collections.dart` | Store-scoped Firestore collection references helper |

---

### 📂 **lib/core/auth/ (Authentication)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `auth.dart` | `auth_repository_and_provider.dart` | Firebase auth repository and Riverpod state management |
| `login_screen.dart` | `login_page.dart` | User login UI screen |
| `register_screen.dart` | `register_page.dart` | New user registration UI screen |
| `forgot_password_screen.dart` | `forgot_password_page.dart` | Password reset email request UI |

---

### 📂 **lib/core/firebase/ (Firebase Utilities)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `firestore_paging.dart` | `firestore_pagination_helper.dart` | Paginated Firestore query utility function |

---

### 📂 **lib/core/loading/ (Loading States)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `loading.dart` | `loading_exports.dart` | Barrel export file for all loading utilities |
| `async_action.dart` | `async_action_runner.dart` | Helper to run async actions with error handling and snackbars |
| `global_loading_overlay.dart` | `fullscreen_loading_overlay.dart` | App-wide blocking loading overlay with progress |
| `page_loader_overlay.dart` | `page_loading_state_widget.dart` | Per-page loading/error state wrapper widget |
| `skeleton_loaders.dart` | `shimmer_skeleton_widgets.dart` | Shimmer animation placeholders for loading states |

---

### 📂 **lib/core/navigation/**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `app_menu.dart` | `side_menu_config.dart` | Side menu configuration (currently empty - can be removed or populated) |

---

### 📂 **lib/core/paging/ (Pagination)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `paged_list_controller.dart` | `infinite_scroll_controller.dart` | Generic ChangeNotifier for infinite scroll pagination |

---

### 📂 **lib/core/theme/ (Theming)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `app_theme.dart` | `theme_config_and_providers.dart` | Theme mode, density, colors, sizes with SharedPreferences persistence |
| `font_controller.dart` | `font_preference_controller.dart` | User's selected font persistence |
| `theme_utils.dart` | `theme_extension_helpers.dart` | BuildContext extensions for easy theme/size/color access |
| `typography.dart` | `google_fonts_typography.dart` | Google Fonts text theme configuration |

---

### 📂 **lib/core/widgets/ (Reusable UI Components)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `widgets.dart` | `widgets_exports.dart` | Barrel export file for all reusable widgets |
| `app_button.dart` | `styled_button_widget.dart` | Themed button with variants (primary, secondary, danger, etc.) |
| `app_card.dart` | `styled_card_widget.dart` | Themed card with size variants and tap handlers |
| `app_chip.dart` | `styled_chip_badge_widget.dart` | Themed chip/badge for status labels |
| `app_dialog.dart` | `styled_dialog_widget.dart` | Themed modal dialog with size variants |
| `app_empty_state.dart` | `empty_state_placeholder_widget.dart` | Empty state widget with icon, title, subtitle, action |
| `app_text_field.dart` | `styled_text_input_widget.dart` | Themed text input field with size variants |
| `settings_dialog.dart` | `display_settings_dialog.dart` | Theme/density/font settings popup |

---

### 📂 **lib/modules/dashboard/ (Dashboard)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `dashboard.dart` | `dashboard_home_screen.dart` | Main dashboard with sales summary, charts, quick links |
| `dashboard_providers.dart` | `dashboard_data_providers.dart` | Riverpod providers for dashboard analytics (sales, top products, alerts) |

---

### 📂 **lib/modules/pos/ (Point of Sale)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `pos.dart` | `pos_models.dart` | Product, Customer, CartItem models (no UI) |
| `pos_ui.dart` | `pos_main_screen.dart` | Main POS screen with products, cart, checkout |
| `pos_two_section_tab.dart` | `pos_desktop_two_panel_screen.dart` | Desktop layout: left products, right cart+checkout |
| `pos_mobile.dart` | `pos_mobile_screen.dart` | Mobile-optimized POS layout |
| `pos_cashier.dart` | `pos_shift_and_drawer_screen.dart` | Cashier shift management (open/close, cash drawer) |
| `pos_checkout.dart` | `checkout_panel_widget.dart` | Checkout panel with customer, payment, totals |
| `pos_search_scan_fav.dart` | ⚠️ **DELETE** (legacy, commented out) | Old search/scan widget - superseded by _fixed version |
| `pos_search_scan_fav_fixed.dart` | `pos_search_barcode_widget.dart` | Product search, barcode scan, favorites filter widget |
| `simple_checkout_tab.dart` | `quick_checkout_button_widget.dart` | Minimal checkout button with payment mode sheet |
| `credit_service.dart` | `customer_credit_ledger_service.dart` | Add/repay customer credit with ledger tracking |
| `device_class_icon.dart` | ⚠️ **DELETE** (empty/hidden) | Was device size indicator badge - now returns SizedBox.shrink() |
| `file_saver_io.dart` | `pdf_file_saver_mobile.dart` | Save/share PDF on mobile (path_provider + share_plus) |
| `file_saver_web.dart` | `pdf_file_saver_web.dart` | Download PDF on web via dart:html blob |
| `backend_launcher_desktop.dart` | `printer_backend_launcher_windows.dart` | Auto-start Node printer backend on Windows |
| `backend_launcher_stub.dart` | `printer_backend_launcher_stub.dart` | No-op stub for non-Windows platforms |

---

### 📂 **lib/modules/pos/pos_invoices/ (Invoice Generation)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `invoice_models.dart` | `invoice_data_model.dart` | InvoiceData, InvoiceLine immutable models |
| `invoice_pdf.dart` | `invoice_pdf_builder.dart` | Generate PDF document from InvoiceData |
| `invoice_email_service.dart` | `invoice_email_sender_service.dart` | Send invoice via Firebase Cloud Function |
| `pdf_theme.dart` | `pdf_styling_constants.dart` | PDF colors, fonts, styles constants |

---

### 📂 **lib/modules/pos/printing/ (Printing)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `print_service.dart` | `local_printer_backend_client.dart` | HTTP client for local Node printer backend |
| `print_settings.dart` | `print_format_settings_model.dart` | Paper size, orientation, font size settings |
| `invoice_printer.dart` | `unified_invoice_printer.dart` | Cross-platform invoice printing dispatcher |
| `invoice_printer_io.dart` | `invoice_printer_desktop.dart` | Desktop printing via PowerShell/lpr |
| `invoice_printer_web.dart` | `invoice_printer_web.dart` ✅ (Keep) | Web printing via browser print dialog |
| `invoice_printer_stub.dart` | `invoice_printer_stub.dart` ✅ (Keep) | Stub for unsupported platforms |
| `cloud_printer_settings.dart` | `cloud_print_config_model.dart` | PrintNode + local backend config stored in Firestore |
| `printnode_service.dart` | `printnode_api_client.dart` | PrintNode cloud printing API client |
| `printer_settings_screen.dart` | `printer_config_admin_screen.dart` | Admin UI to configure printing settings |
| `receipt_settings.dart` | `receipt_format_settings_model.dart` | Receipt header/footer, paper size, char width settings |
| `receipt_settings_screen.dart` | `receipt_format_admin_screen.dart` | Admin UI to customize receipt format |
| `web_url_launcher.dart` | `url_launcher_web.dart` | Web-only URL launcher (dart:html) |
| `web_url_launcher_stub.dart` | `url_launcher_stub.dart` | URL launcher stub for non-web |

---

### 📂 **lib/modules/inventory/ (Inventory Management)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `alerts_screen.dart` | `low_stock_expiry_alerts_screen.dart` | View products with low stock or expiring soon |
| `audit_screen.dart` | `inventory_audit_screen.dart` | Audit tool to verify and update stock counts |
| `category_screen.dart` | `category_management_screen.dart` | Manage product categories and subcategories |
| `import_products_screen.dart` | `product_csv_import_screen.dart` | Import products from CSV/Excel with preview |
| `stock_movements_screen.dart` | `stock_transfer_history_screen.dart` | View/add stock transfers between locations |
| `suppliers_screen.dart` | `supplier_management_screen.dart` | CRUD for supplier contacts |
| `download_helper_stub.dart` | `file_download_stub.dart` | Non-web file download stub (returns false) |
| `download_helper_web.dart` | `file_download_web.dart` | Web blob download via dart:html |
| `web_image_picker.dart` | `camera_image_picker_web.dart` | Pick/capture image on web |
| `web_image_picker_stub.dart` | `camera_image_picker_stub.dart` | Non-web image picker stub |
| `file_pick_helper_stub.dart` | `file_picker_stub.dart` | (If exists) File picker stub |
| `file_pick_helper_web.dart` | `file_picker_web.dart` | (If exists) File picker web |

---

### 📂 **lib/modules/inventory/Products/ (Product Management)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `inventory.dart` | `products_list_screen.dart` | Main products listing with add/edit/delete |
| `inventory_repository.dart` | `product_firestore_repository.dart` | CRUD operations for products in Firestore |
| `csv_utils.dart` | `csv_parser_utility.dart` | Simple CSV parse/generate utility |
| `generate_barcode.dart` | `barcode_label_pdf_generator.dart` | Generate printable barcode label PDFs |
| `import_service.dart` | ⚠️ **DELETE or rename** | Legacy placeholder - minimal content |
| `inventory_sheet_page.dart` | `products_spreadsheet_editor.dart` | Excel-like product editing with PlutoGrid |
| `invoice_analysis_page.dart` | `ai_invoice_analyzer_screen.dart` | Upload invoice image/PDF for AI extraction |
| `product_image_uploader.dart` | `product_image_upload_service.dart` | Upload product images to Firebase Storage |

---

### 📂 **lib/modules/invoices/ (Invoice Records)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `sales_invoices.dart` | `sales_invoice_list_screen.dart` | List/search/filter sales invoices |
| `purchse_invoice.dart` | `purchase_invoice_list_screen.dart` | List/create purchase invoices (typo in current name!) |

---

### 📂 **lib/modules/crm/ (Customer Relationship Management)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `crm.dart` | `customer_list_screen.dart` | List/search/add/edit customers |

---

### 📂 **lib/modules/accounting/ (Accounting)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `accounting.dart` | `accounting_ledger_screen.dart` | Combined sales/purchases ledger view with stock value |

---

### 📂 **lib/modules/loyalty/ (Loyalty Program)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `loyalty.dart` | `loyalty_customer_browser_screen.dart` | Browse customers by loyalty tier, change status |
| `loyalty_settings.dart` | `loyalty_program_settings_screen.dart` | Configure points rules and tier definitions |

---

### 📂 **lib/modules/admin/ (Admin Panel)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `permissions_overview_tab.dart` | `admin_overview_screen.dart` | Admin home with store switching, appearance settings |
| `permissions_tab.dart` | `user_permissions_editor_screen.dart` | Edit individual user's module permissions |
| `users_tab.dart` | `store_users_management_screen.dart` | Manage store team members (invite, remove, promote) |
| `migration_tools.dart` | `data_migration_placeholder_screen.dart` | Placeholder for future migration tools |

---

### 📂 **lib/modules/stores/ (Multi-Store Support)**

| Current Name | Suggested Name | Purpose |
|-------------|----------------|---------|
| `models.dart` | `store_and_membership_models.dart` | StoreDoc and StoreMembership data classes |
| `providers.dart` | `store_selection_providers.dart` | Selected store state, memberships stream providers |
| `my_stores_screen.dart` | `store_picker_screen.dart` | User's stores list with selection and logout |
| `create_store_screen.dart` | `create_new_store_screen.dart` | Form to create a new store |

---

## 📊 Files to DELETE (Dead/Empty/Legacy Code)

| File | Reason |
|------|--------|
| `lib/modules/pos/pos_search_scan_fav.dart` | Commented out, replaced by `_fixed` version |
| `lib/modules/pos/device_class_icon.dart` | Returns empty widget, no longer useful |
| `lib/modules/inventory/Products/import_service.dart` | Legacy placeholder with no real logic |
| `lib/core/navigation/app_menu.dart` | Empty file |

---

## 🎯 Folder Structure Changes (Optional)

Consider reorganizing for clarity:

```
lib/
├── main.dart
├── app_router.dart  (renamed from app_shell.dart)
├── firebase_options.dart
│
├── core/
│   ├── auth/
│   ├── database/  (renamed from firebase/)
│   ├── loading/
│   ├── navigation/
│   ├── pagination/  (renamed from paging/)
│   ├── theme/
│   ├── widgets/
│   └── utils/  (move logging.dart, app_keys.dart here)
│
├── modules/
│   ├── dashboard/
│   ├── pos/
│   │   ├── models/
│   │   ├── screens/
│   │   ├── widgets/
│   │   ├── services/
│   │   └── printing/
│   ├── inventory/
│   │   ├── products/  (lowercase)
│   │   ├── stock/
│   │   └── suppliers/
│   ├── invoices/
│   │   ├── sales/
│   │   └── purchases/
│   ├── customers/  (renamed from crm/)
│   ├── accounting/
│   ├── loyalty/
│   ├── admin/
│   └── stores/
```

---

## ⚠️ Important Notes Before Renaming

1. **Backup your code** or ensure you have a clean git state
2. **Use IDE refactoring** (VS Code: Right-click → Rename Symbol/Rename File) to auto-update imports
3. **Test thoroughly** after each batch of renames
4. **Update any hardcoded paths** in:
   - `app_shell.dart` (route imports)
   - `pubspec.yaml` (if any paths mentioned)
   - Firebase configurations

---

## 🚀 Implementation Priority

1. **Phase 1 (Low Risk):** Rename files in `core/` - these are utilities with clear purposes
2. **Phase 2 (Medium Risk):** Rename model/service files in `modules/` 
3. **Phase 3 (Higher Risk):** Rename main screen files - many import dependencies
4. **Phase 4 (Optional):** Folder restructuring

---

## 📝 Example Rename Command (PowerShell)

```powershell
# Rename a single file using git mv (preserves history)
git mv lib/core/app_keys.dart lib/core/global_navigator_keys.dart
```

---

*Document generated: December 2, 2025*
*Total files analyzed: ~80+ Dart files*

# 🧪 Retail ERP MVP - Manual Testing Checklist

> **Goal:** Complete manual testing of all features  
> **Estimated Time:** 4-6 hours  
> **Date Started:** _______________

---

## ✅ Quick Status

| Phase | Tests | Passed | Failed | Status |
|-------|-------|--------|--------|--------|
| 1. Smoke Tests | 8 | 8 | 0 | ✅ DONE |
| 2. POS Module | 20 | _ | _ | ☐ |
| 3. Inventory | 15 | _ | _ | ☐ |
| 4. CRM/Customers | 10 | _ | _ | ☐ |
| 5. Loyalty | 6 | _ | _ | ☐ |
| 6. Invoices | 10 | _ | _ | ☐ |
| 7. Suppliers | 6 | _ | _ | ☐ |
| 8. Accounting | 6 | _ | _ | ☐ |
| 9. Admin/Users | 8 | _ | _ | ☐ |
| 10. Stores | 5 | _ | _ | ☐ |
| **TOTAL** | **94** | _ | _ | _ |

---

## 🔴 Phase 1: Smoke Tests (COMPLETED ✅)

| # | Test | Status |
|---|------|--------|
| 1.1 | App launches without crash | ✅ |
| 1.2 | Login screen appears | ✅ |
| 1.3 | Can log in | ✅ |
| 1.4 | Dashboard loads | ✅ |
| 1.5 | Navigate to POS | ✅ |
| 1.6 | Navigate to Inventory | ✅ |
| 1.7 | Navigate to all modules | ✅ |
| 1.8 | Logout works | ✅ |

---

## 🛒 Phase 2: POS Module (20 tests)

### 2.1 Product Search & Cart

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 2.1.1 | Search product by name | Type product name | Products filter | ☐ |
| 2.1.2 | Search product by barcode | Type/scan barcode | Product found | ☐ |
| 2.1.3 | Add product to cart | Click product | Added to cart | ☐ |
| 2.1.4 | Increase quantity | Click + or edit qty | Qty increases | ☐ |
| 2.1.5 | Decrease quantity | Click - | Qty decreases | ☐ |
| 2.1.6 | Remove item | Click delete/remove | Item removed | ☐ |
| 2.1.7 | Cart total updates | Add/remove items | Total correct | ☐ |
| 2.1.8 | Empty cart message | Clear all items | Shows empty state | ☐ |

### 2.2 Discounts

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 2.2.1 | Apply % discount | Enter 10% discount | Price reduced 10% | ☐ |
| 2.2.2 | Apply fixed discount | Enter ₹50 off | Price reduced ₹50 | ☐ |
| 2.2.3 | Remove discount | Clear discount | Original price | ☐ |

### 2.3 Customer Selection

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 2.3.1 | Select customer | Search & select | Customer attached | ☐ |
| 2.3.2 | Clear customer | Remove selection | Walk-in sale | ☐ |
| 2.3.3 | Add new customer | Create from POS | New customer saved | ☐ |

### 2.4 Payment & Checkout

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 2.4.1 | Cash payment (exact) | Pay exact amount | Sale completes | ☐ |
| 2.4.2 | Cash payment (change) | Pay more than total | Change shown | ☐ |
| 2.4.3 | Card payment | Select card | Sale completes | ☐ |
| 2.4.4 | Credit payment | Pay on credit | Credit recorded | ☐ |
| 2.4.5 | Split payment | Cash + Card | Sale completes | ☐ |
| 2.4.6 | Print receipt | After checkout | Receipt prints | ☐ |

### 2.5 Hold Orders

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 2.5.1 | Hold order | Click Hold | Order saved | ☐ |
| 2.5.2 | Recall held order | Select from list | Order loaded | ☐ |

---

## 📦 Phase 3: Inventory Module (15 tests)

### 3.1 Products

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 3.1.1 | View products list | Go to Inventory | Products display | ☐ |
| 3.1.2 | Search product | Type in search | Filters work | ☐ |
| 3.1.3 | Add new product | Fill form → Save | Product created | ☐ |
| 3.1.4 | Edit product | Select → Edit → Save | Changes saved | ☐ |
| 3.1.5 | Delete product | Select → Delete | Product removed | ☐ |
| 3.1.6 | Add product image | Upload image | Image shows | ☐ |
| 3.1.7 | Set product price | Enter price | Price saved | ☐ |
| 3.1.8 | Set cost price | Enter cost | Cost saved | ☐ |

### 3.2 Categories

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 3.2.1 | Add category | Create new | Category created | ☐ |
| 3.2.2 | Assign product | Edit product → Select | Product categorized | ☐ |
| 3.2.3 | Filter by category | Select category | Products filter | ☐ |

### 3.3 Stock Management

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 3.3.1 | Stock adjustment (+) | Add stock | Stock increases | ☐ |
| 3.3.2 | Stock adjustment (-) | Remove stock | Stock decreases | ☐ |
| 3.3.3 | Stock transfer | Transfer to another store | Both stores update | ☐ |
| 3.3.4 | Low stock alert | Reduce below threshold | Alert shows | ☐ |

---

## 👥 Phase 4: CRM/Customers Module (10 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 4.1 | View customers list | Go to CRM | Customers display | ☐ |
| 4.2 | Search customer | Type name/phone | Filters work | ☐ |
| 4.3 | Add new customer | Fill form → Save | Customer created | ☐ |
| 4.4 | Edit customer | Select → Edit → Save | Changes saved | ☐ |
| 4.5 | Delete customer | Select → Delete | Customer removed | ☐ |
| 4.6 | View purchase history | Select customer | History shows | ☐ |
| 4.7 | Check credit balance | After credit sale | Balance correct | ☐ |
| 4.8 | Record credit payment | Pay balance | Balance reduces | ☐ |
| 4.9 | Customer phone required | Try blank phone | Validation error | ☐ |
| 4.10 | Duplicate phone check | Same phone twice | Warning shown | ☐ |

---

## ⭐ Phase 5: Loyalty Module (6 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 5.1 | Enable loyalty | Turn on for customer | Loyalty active | ☐ |
| 5.2 | Earn points on sale | Complete purchase | Points added | ☐ |
| 5.3 | View points balance | Check customer | Balance shown | ☐ |
| 5.4 | Redeem points | Apply at checkout | Discount applied | ☐ |
| 5.5 | Points deducted | After redemption | Balance reduced | ☐ |
| 5.6 | Points history | View transactions | History shows | ☐ |

---

## 🧾 Phase 6: Invoices Module (10 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 6.1 | View invoices list | Go to Invoices | List displays | ☐ |
| 6.2 | Filter by date | Select range | Filters work | ☐ |
| 6.3 | Filter by customer | Select customer | Filters work | ☐ |
| 6.4 | Search invoice | Type invoice # | Found | ☐ |
| 6.5 | View invoice details | Click invoice | Details show | ☐ |
| 6.6 | Print invoice | Click print | Prints correctly | ☐ |
| 6.7 | Email invoice | Send email | Email sent | ☐ |
| 6.8 | Void invoice | Cancel sale | Marked void | ☐ |
| 6.9 | Stock restores on void | After void | Stock back | ☐ |
| 6.10 | Process return | Return item | Refund recorded | ☐ |

---

## 🚚 Phase 7: Suppliers Module (6 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 7.1 | View suppliers list | Go to Suppliers | List displays | ☐ |
| 7.2 | Add supplier | Fill form → Save | Supplier created | ☐ |
| 7.3 | Edit supplier | Select → Edit | Changes saved | ☐ |
| 7.4 | Delete supplier | Select → Delete | Supplier removed | ☐ |
| 7.5 | Create purchase order | Add items → Submit | PO created | ☐ |
| 7.6 | Receive goods | Mark received | Stock updated | ☐ |

---

## 💰 Phase 8: Accounting Module (6 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 8.1 | View daily summary | Check dashboard | Totals shown | ☐ |
| 8.2 | Sales match | Compare with POS | Numbers match | ☐ |
| 8.3 | Add expense | Enter expense | Recorded | ☐ |
| 8.4 | Expense categories | Select category | Categorized | ☐ |
| 8.5 | Cash drawer balance | Open/close drawer | Balance tracks | ☐ |
| 8.6 | End of day report | Run EOD | Summary correct | ☐ |

---

## 👨‍💼 Phase 9: Admin/Users Module (8 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 9.1 | View users list | Go to Admin | Users display | ☐ |
| 9.2 | Add new user | Create user | User created | ☐ |
| 9.3 | New user can login | Login as new user | Success | ☐ |
| 9.4 | Assign role | Set cashier/manager | Role saved | ☐ |
| 9.5 | Permissions apply | Test restricted access | Blocked | ☐ |
| 9.6 | Edit user | Change details | Saved | ☐ |
| 9.7 | Deactivate user | Disable account | Can't login | ☐ |
| 9.8 | Owner transfer | Change owner | Owner updated | ☐ |

---

## 🏪 Phase 10: Stores Module (5 tests)

| # | Test | Steps | Expected | ✓/✗ |
|---|------|-------|----------|-----|
| 10.1 | View stores | Go to Stores | List displays | ☐ |
| 10.2 | Add store | Create new | Store created | ☐ |
| 10.3 | Switch store | Select different | Data changes | ☐ |
| 10.4 | Store isolation | Check inventory | Per-store data | ☐ |
| 10.5 | Edit store | Update details | Changes saved | ☐ |

---

## 🔴 Bug Tracking

| # | Module | Description | Severity | Status |
|---|--------|-------------|----------|--------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

**Severity:** 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low

---

## ✅ Final Checklist

Before Go-Live:

| # | Requirement | Status |
|---|-------------|--------|
| 1 | All smoke tests pass | ✅ |
| 2 | All POS tests pass | ☐ |
| 3 | All Inventory tests pass | ☐ |
| 4 | All CRM tests pass | ☐ |
| 5 | No critical bugs open | ☐ |
| 6 | Data backup configured | ☐ |
| 7 | User training done | ☐ |

---

## 📝 Testing Notes

Write any observations here:

```
_______________________________________
_______________________________________
_______________________________________
_______________________________________
_______________________________________
```

---

**Tester:** _______________  
**Date Completed:** _______________  
**Overall Result:** ☐ PASS / ☐ FAIL

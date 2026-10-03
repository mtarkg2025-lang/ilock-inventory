# SIDRA → Odoo Online — Reverse Engineering Blueprint

## الهدف

إعادة بناء منطق مشروع I-Lock/SIDRA داخل Odoo Online باستخدام وظائف Odoo الأصلية والتخصيصات التي يسمح بها Odoo Online، بدل تحويل ملف HTML/JavaScript الحالي إلى Custom Python Module.

> قاعدة مهمة: ملف index.html الحالي هو **Business Specification / نموذج أولي للمنطق** وليس هو قاعدة البيانات النهائية.

## قيد المنصة

Odoo Online لا يدعم تثبيت Custom Modules التي تحتوي Python server-side code. لذلك لا نعتمد على `__manifest__.py` أو `models/*.py` كحل مباشر لـ Odoo Online.

إذا احتجنا لاحقًا إلى Custom Python Module كامل، يكون الانتقال إلى Odoo.sh هو المسار المناسب.

## مبدأ التصميم

Odoo = System of Record (مصدر البيانات الأساسي)

SIDRA = Management & Analysis Layer (طبقة الإدارة والتحليل)

لا ننشئ جدول مخزون مكرر إذا كان Odoo لديه سجل أصلي يؤدي نفس الوظيفة.

---

## 1. الأصناف والأكواد

### المشروع الحالي
- code
- name
- type
- unit
- opening
- unitCost
- sellPrice
- completionCost
- sellingCost
- costMethod

### Odoo Online
نستخدم Product / Product Variant / Units of Measure والحقول الأصلية.

### تخصيص SIDRA المقترح
حقول إضافية عند الحاجة:
- SIDRA Item Type
- SIDRA Item Family Role
- Completion Cost
- Necessary Selling Cost
- Analysis Flag

لا نكرر Item Master كاملًا كجدول مستقل إذا كان Product هو مصدر الحقيقة.

---

## 2. حركة المخزون

### المشروع الحالي
purchase / production / issue / return / supplierReturn / transferOut / transferIn / adjustment

### Odoo
نستخدم Inventory Operations وStock Moves وPickings والعمليات الأصلية المناسبة.

الهدف:
- الاستلام
- صرف
- التحويل
- التسوية
- الإنتاج

كلها تُسجل في Odoo، وتحليل SIDRA يقرأ منها.

---

## 3. الرصيد

### المشروع الحالي
الرصيد = الرصيد الافتتاحي + صافي الحركات

### التصميم الجديد
لا نحسب رصيدًا مستقلًا داخل SIDRA.

نستخدم رصيد Odoo كمصدر أساسي، ثم نعرضه في تقارير SIDRA.

---

## 4. الجرد والانحراف

### المشروع الحالي
Deviation = Physical Count - Book Balance

### التصميم الجديد
نستخدم Inventory Adjustment / Count في Odoo.

ثم تقرير SIDRA يعرض:
- Book Balance
- Physical Count
- Deviation
- Deviation Value
- Status: مطابق / نقص / زيادة

ولا يتم تعديل الرصيد الدفتري تلقائيًا من تقرير التحليل.

---

## 5. عائلات المنتجات وقدرة التجميع

### المشروع الحالي
Family:
- code
- name
- components[]
- component quantity

Capacity:

min(floor(component stock / required quantity))

### التصميم الجديد
نربط العائلة بمنطق Product/BOM حيث يكون ذلك مناسبًا.

مثال:

فيشة دكر
- جسم × 1
- قلب × 1
- غطاء × 1

إذا كانت الأرصدة:
- جسم = 1000
- قلب = 900
- غطاء = 1200

فالقدرة = 900.

المكون الذي يعطي أقل قدرة هو Limiting Component (المكوّن المحدِّد).

> ملاحظة: إذا كان المطلوب تقرير Capacity خاص بـ SIDRA ولا توفره أدوات Odoo Online مباشرة، نبحث عن تنفيذه عبر Spreadsheet/Studio/Automation بدل إنشاء Python module.

---

## 6. الخطط والاستهلاك

### المشروع الحالي
Plan:
- from
- to
- item
- planned quantity

Actual consumption = Issue movements داخل الفترة.

### التصميم الجديد
نستخدم بيانات Odoo للحركات الفعلية، ثم نضيف طبقة تخطيط وتحليل مناسبة من الأدوات المتاحة في Odoo Online.

التقرير:
- Planned
- Actual
- Variance
- Execution %

---

## 7. تحليل المخزون

تقارير SIDRA الأساسية:

1. ملخص المخزون
2. الخامات
3. المنتجات التامة
4. العائلات وقدرة التجميع
5. الجرد والانحراف
6. الخطة مقابل الاستهلاك
7. IAS 2 / NRV

---

## 8. IAS 2 / NRV

### المنطق الحالي

NRV = Estimated Selling Price
      - Completion Costs
      - Necessary Selling Costs

Inventory carrying amount is compared with NRV.

### Odoo Online

هذا جزء تحليلي وليس بديلًا عن القيود المحاسبية.

يجب الفصل بين:
- التقرير الإداري
- القيد المحاسبي

في المرحلة الأولى نُبقيه Management Analysis فقط.

---

## 9. Excel

نحتفظ باستخدام Excel في نقطتين:

### Import
استيراد:
- Items
- Families/Components عند إمكانية ذلك
- Plans
- بيانات تحليلية

### Export
إخراج:
- Current Stock
- Inventory Analysis
- Variance
- Family Capacity
- Plan vs Actual
- IAS 2 / NRV analysis

---

## 10. Dashboard

لوحة SIDRA المقترحة:

### KPIs
- عدد الأصناف
- قيمة المخزون
- أصناف برصيد سالب
- قيمة الانحراف
- عدد الأصناف التي تحتاج مراجعة NRV
- قدرة التجميع للعائلات الرئيسية

### Filters
- Warehouse
- Product
- Product Category
- Product Family
- Date
- Item Type

Odoo Dashboards/Spreadsheets يمكن استخدامها لعرض وتحليل بيانات Odoo.

---

# قرار معماري نهائي للمرحلة الحالية

## لا نفعل
HTML → Python conversion → محاولة رفع Custom Module إلى Odoo Online

## نفعل
HTML/JS الحالي
→ استخراج Business Rules
→ مطابقة كل Rule مع Odoo Native Feature
→ Studio customization عند الحاجة
→ Odoo Spreadsheet/Dashboard للتحليل
→ Automation/Webhooks حيث تكون مناسبة
→ اختبار على بيانات تجريبية
→ اعتماد Odoo كمصدر الحقيقة

---

# المرحلة التالية

قبل بناء أي تخصيص فعلي يجب تثبيت **إصدار Odoo Online** الموجود عند المستخدم، لأن أسماء النماذج والواجهات والخصائص تختلف حسب الإصدار.

بعد تحديد الإصدار، يتم إعداد:

1. SIDRA Data Map
2. Odoo Model Map
3. Studio Fields
4. Views
5. Automations
6. Reports
7. Dashboard
8. Import Templates

ثم نبدأ التنفيذ من **Item Master + Inventory + Family Capacity**، لأنها قاعدة باقي التحليلات.

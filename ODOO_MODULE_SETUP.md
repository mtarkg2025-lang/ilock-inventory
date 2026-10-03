# وحدة I LOCK لمخزون Odoo

هذه وحدة إضافية لـ **Odoo 19** تربط نموذج I LOCK مباشرة مع تطبيق **Inventory / stock**؛ لذلك لا تنشئ مخزونًا موازيًا أو تعتمد على Google Sheets. تستخدم أصناف Odoo ومواقعه وتحويلاته وكمياته الفعلية كمصدر الحقيقة.

## ما تضيفه الوحدة

* بيانات تتبع صناعية في أوامر الاستلام والصرف والتحويل (`stock.picking`): مرجع I LOCK، الوردية، طالب الحركة، وملاحظة تشغيلية.
* حقول تحكم تشغيلي في بطاقة الصنف: حد تنبيه I LOCK وملاحظة تخزين. قواعد إعادة الطلب القياسية في Odoo تبقى الخيار الصحيح للتوريد الآلي حسب المخزن.
* دورة جرد: إنشاء جلسة جرد، تحميل الكميات النظرية من مواقع Odoo الداخلية، إدخال الكمية الفعلية، ثم اعتمادها لإنشاء تسويات Odoo القياسية.
* مجموعتا صلاحيات منفصلتان: مستخدم I LOCK ومدير I LOCK.

## التثبيت (Odoo.sh أو Odoo On-premise)

1. انسخ مجلد `odoo_addons/ilock_inventory_erp` إلى مسار `addons_path` المخصص، مثل `~/src/user/ilock_inventory_erp` في Odoo.sh أو `/opt/odoo/custom-addons/` على الخادم.
2. أعد تشغيل خدمة Odoo أو حدّث البناء في Odoo.sh.
3. فعّل وضع المطوّر، ثم افتح **Apps → Update Apps List** وابحث عن `I LOCK Industrial Inventory Control` وثبّته.
4. من **Settings → Users** امنح أمناء المخزن دور **I LOCK Inventory User**، وامنح مسؤولي المخزون دور **I LOCK Inventory Manager**.
5. من Inventory ستجد قائمة **I LOCK Controls → Inventory Counts**. افتح جلسة، اختر المخزن والموقع، ثم **Load Theoretical Stock**، أدخل الأرقام الفعلية، وبعد المراجعة اضغط **Validate and Apply**.

## ملاحظات التوافق والأمان

* الوحدة تستهدف Odoo 19، وتحتاج تطويعًا بسيطًا إذا كان لديك إصدار أقدم. لا يمكن تثبيت وحدات Python مخصصة على Odoo Online/SaaS العادي؛ استخدم Odoo.sh أو خادمك الخاص.
* الاعتماد ينفذ تعديلًا فعليًا لكميات Odoo عند **Validate and Apply**. اختبر أولاً على قاعدة staging وامنح حق المدير فقط لمن يعتمد الجرد.
* صلاحيات الوصول معرفة في `security/ir.model.access.csv` ومربوطة بمجموعات؛ لا تمنح حقًا عامًا للزوار.

## مراجع رسمية

* [Building a Module — Odoo 19](https://www.odoo.com/documentation/19.0/developer/tutorials/backend.html)
* [Security in Odoo — Odoo 19](https://www.odoo.com/documentation/19.0/developer/reference/backend/security.html)
* [Creating a module on Odoo.sh](https://www.odoo.com/documentation/19.0/administration/odoo_sh/first_module.html)

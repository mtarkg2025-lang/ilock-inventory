/** I LOCK ERP for Google Sheets and Google Workspace. */
const ERP = {
  sheets: {
    Items: ['Item Code', 'Item Name', 'Type', 'Unit', 'Warehouse', 'Reorder Point', 'Opening Balance', 'Unit Cost', 'Active'],
    Movements: ['Transaction ID', 'Date', 'Time', 'Item Code', 'Movement Type', 'Quantity', 'Unit Cost', 'Reference', 'Partner', 'Requested By', 'Notes', 'Status', 'Created At'],
    Counts: ['Count ID', 'Count Date', 'Item Code', 'Counted Quantity', 'Warehouse', 'Counter', 'Reason', 'Notes', 'Created At'],
    BOM: ['BOM Code', 'Product Name', 'Component Code', 'Quantity Per Unit'],
    Plans: ['Plan ID', 'From Date', 'To Date', 'Item Code', 'Planned Quantity', 'Created At']
  },
  positive: ['purchase', 'production', 'customerReturn', 'transferIn', 'adjustmentIn']
};

function onOpen() {
  SpreadsheetApp.getUi().createMenu('I LOCK ERP')
    .addItem('تهيئة نموذج ERP', 'setupErpWorkbook')
    .addItem('فتح مركز العمليات', 'showOperationsSidebar')
    .addSeparator()
    .addItem('تحديث لوحة المؤشرات', 'refreshDashboard')
    .addItem('إنشاء بيانات تجريبية', 'loadDemoData')
    .addToUi();
}

function doGet() {
  return HtmlService.createHtmlOutputFromFile('Index')
    .setTitle('I LOCK ERP | Operations Center')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function showOperationsSidebar() {
  const html = HtmlService.createHtmlOutputFromFile('Index').setTitle('I LOCK ERP').setWidth(430);
  SpreadsheetApp.getUi().showSidebar(html);
}

function setupErpWorkbook() {
  const ss = SpreadsheetApp.getActive();
  PropertiesService.getScriptProperties().setProperty('ERP_SPREADSHEET_ID', ss.getId());
  Object.keys(ERP.sheets).forEach(name => ensureSheet_(ss, name, ERP.sheets[name]));
  refreshDashboard();
  SpreadsheetApp.getActive().toast('تم تجهيز نموذج I LOCK ERP.', 'I LOCK ERP', 5);
}

function ensureSheet_(ss, name, headers) {
  let sh = ss.getSheetByName(name);
  if (!sh) sh = ss.insertSheet(name);
  if (sh.getLastRow() === 0) sh.getRange(1, 1, 1, headers.length).setValues([headers]);
  sh.setFrozenRows(1);
  sh.getRange(1, 1, 1, headers.length).setBackground('#163b62').setFontColor('#ffffff').setFontWeight('bold');
  sh.autoResizeColumns(1, headers.length);
  return sh;
}

function getDashboardData() {
  setupSilent_();
  const items = getRows_('Items');
  const movements = getRows_('Movements');
  const stock = stockMap_(items, movements);
  const today = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd');
  const risks = items.filter(i => Number(stock[i['Item Code']] || 0) <= Number(i['Reorder Point'] || 0))
    .map(i => ({code:i['Item Code'], name:i['Item Name'], warehouse:i.Warehouse, unit:i.Unit, balance:Number(stock[i['Item Code']] || 0), reorderPoint:Number(i['Reorder Point'] || 0)}));
  const totalValue = items.reduce((sum, i) => sum + Math.max(0, Number(stock[i['Item Code']] || 0)) * Number(i['Unit Cost'] || 0), 0);
  return {
    kpis: {totalValue, activeItems: items.filter(i => String(i.Active).toLowerCase() !== 'false').length, alerts: risks.length, todayMoves: movements.filter(m => dateKey_(m.Date) === today && m.Status !== 'Cancelled').length},
    risks: risks.slice(0, 10),
    items: items.map(i => ({code:i['Item Code'], name:i['Item Name'], unit:i.Unit, warehouse:i.Warehouse, balance:Number(stock[i['Item Code']] || 0)}))
  };
}

function saveMovement(form) {
  setupSilent_();
  required_(form, ['date', 'itemCode', 'movementType', 'quantity']);
  if (Number(form.quantity) <= 0) throw new Error('الكمية يجب أن تكون أكبر من صفر.');
  const item = getRows_('Items').find(i => i['Item Code'] === form.itemCode);
  if (!item) throw new Error('كود الصنف غير موجود في دليل الأصناف.');
  appendObject_('Movements', {
    'Transaction ID': 'TX-' + Utilities.getUuid().slice(0, 8).toUpperCase(), Date: new Date(form.date), Time: form.time || '',
    'Item Code': form.itemCode, 'Movement Type': form.movementType, Quantity: Number(form.quantity), 'Unit Cost': Number(form.unitCost || item['Unit Cost'] || 0),
    Reference: form.reference || '', Partner: form.partner || '', 'Requested By': form.requestedBy || '', Notes: form.notes || '', Status: 'Active', 'Created At': new Date()
  });
  refreshDashboard();
  return {message: 'تم حفظ مستند الحركة بنجاح.'};
}

function saveCount(form) {
  setupSilent_();
  required_(form, ['date', 'itemCode', 'quantity']);
  if (Number(form.quantity) < 0) throw new Error('كمية الجرد لا يمكن أن تكون سالبة.');
  appendObject_('Counts', {'Count ID':'CNT-' + Utilities.getUuid().slice(0, 8).toUpperCase(), 'Count Date':new Date(form.date), 'Item Code':form.itemCode, 'Counted Quantity':Number(form.quantity), Warehouse:form.warehouse || '', Counter:form.counter || '', Reason:form.reason || 'دوري', Notes:form.notes || '', 'Created At':new Date()});
  return {message: 'تم حفظ محضر الجرد.'};
}

function refreshDashboard() {
  setupSilent_();
  const ss = getSpreadsheet_(), sh = ss.getSheetByName('Dashboard') || ss.insertSheet('Dashboard');
  sh.clear(); sh.setRightToLeft(true); sh.setColumnWidths(1, 8, 145);
  const data = getDashboardData();
  sh.getRange('A1:H1').merge().setValue('I LOCK ERP — لوحة العمليات').setBackground('#163b62').setFontColor('#fff').setFontSize(16).setFontWeight('bold').setHorizontalAlignment('center');
  sh.getRange('A3:H3').setValues([['قيمة المخزون', 'الأصناف النشطة', 'تنبيهات إعادة الطلب', 'حركات اليوم', '', '', '', '']]);
  sh.getRange('A4:D4').setValues([[data.kpis.totalValue, data.kpis.activeItems, data.kpis.alerts, data.kpis.todayMoves]]).setFontSize(16).setFontWeight('bold').setBackground('#eaf2fb');
  sh.getRange('A6:F6').setValues([['الصنف', 'الكود', 'المخزن', 'الرصيد', 'حد الطلب', 'الحالة']]).setBackground('#163b62').setFontColor('#fff').setFontWeight('bold');
  const values = data.risks.map(r => [r.name, r.code, r.warehouse, r.balance, r.reorderPoint, r.balance < 0 ? 'رصيد سالب' : 'إعادة طلب']);
  if (values.length) sh.getRange(7, 1, values.length, 6).setValues(values);
  else sh.getRange('A7').setValue('لا توجد تنبيهات مخزون حالياً.');
  sh.getRange('A1:H20').setVerticalAlignment('middle'); sh.setFrozenRows(1);
}

function loadDemoData() {
  setupErpWorkbook();
  const sh = getSpreadsheet_().getSheetByName('Items');
  if (sh.getLastRow() > 1) throw new Error('لن يتم استبدال بيانات موجودة. أنشئ ملفاً جديداً للبيانات التجريبية.');
  sh.getRange(2, 1, 5, 9).setValues([
    ['RM-001','حبيبات بلاستيك ABS','Raw Material','كجم','المخزن الرئيسي',150,500,80,true],
    ['CP-101','جسم فيشة','Component','قطعة','خط الحقن',400,1000,2.2,true],
    ['CP-102','قلب فيشة','Component','قطعة','خط الحقن',350,900,1.8,true],
    ['CP-103','غطاء فيشة','Component','قطعة','خط التجميع',500,1200,1.2,true],
    ['FG-001','فيشة ذكر كاملة','Finished Good','قطعة','مخزن المنتج التام',100,200,7,true]
  ]);
  appendObject_('Movements', {'Transaction ID':'DEMO-001',Date:new Date(),Time:'08:00','Item Code':'RM-001','Movement Type':'issue',Quantity:70,'Unit Cost':80,Reference:'WO-1001',Partner:'الإنتاج','Requested By':'مشرف الوردية',Notes:'صرف تشغيلي',Status:'Active','Created At':new Date()});
  refreshDashboard();
}

function getRows_(sheetName) { const sh = getSpreadsheet_().getSheetByName(sheetName); const values = sh.getDataRange().getValues(); const headers = values.shift(); return values.filter(r => r.some(v => v !== '')).map(r => headers.reduce((o, h, n) => (o[h] = r[n], o), {})); }
function appendObject_(sheetName, row) { const sh = getSpreadsheet_().getSheetByName(sheetName), headers = sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0]; sh.appendRow(headers.map(h => row[h] === undefined ? '' : row[h])); }
function stockMap_(items, movements) { const map = {}; items.forEach(i => map[i['Item Code']] = Number(i['Opening Balance'] || 0)); movements.filter(m => m.Status !== 'Cancelled').forEach(m => { const q = Number(m.Quantity || 0) * (ERP.positive.includes(m['Movement Type']) ? 1 : -1); map[m['Item Code']] = Number(map[m['Item Code']] || 0) + q; }); return map; }
function required_(object, fields) { fields.forEach(f => { if (object[f] === undefined || object[f] === null || object[f] === '') throw new Error('الحقل مطلوب: ' + f); }); }
function dateKey_(value) { return value instanceof Date ? Utilities.formatDate(value, Session.getScriptTimeZone(), 'yyyy-MM-dd') : String(value).slice(0, 10); }
function setupSilent_() { const ss = getSpreadsheet_(); Object.keys(ERP.sheets).forEach(name => ensureSheet_(ss, name, ERP.sheets[name])); }
function getSpreadsheet_() { const id = PropertiesService.getScriptProperties().getProperty('ERP_SPREADSHEET_ID'); return id ? SpreadsheetApp.openById(id) : SpreadsheetApp.getActive(); }
